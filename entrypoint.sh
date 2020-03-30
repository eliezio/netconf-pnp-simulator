#!/bin/ash
# shellcheck disable=SC2086

# ============LICENSE_START=======================================================
#  Copyright (C) 2020 Nordix Foundation.
# ================================================================================
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0
# ============LICENSE_END=========================================================

set -o errexit
set -o pipefail
set -o nounset
[ "${SHELL_XTRACE:-false}" = "true" ] && set -o xtrace

export PATH=/opt/bin:/usr/local/bin:/usr/bin:/bin

CONFIG=/config
SSH_CONFIG=$CONFIG/ssh
TLS_CONFIG=$CONFIG/tls
MODELS_CONFIG=$CONFIG/modules
TEMPLATES=/templates
KEY_PATH=/opt/etc/keystored/keys
BASE_VIRTUALENVS=$HOME/.local/share/virtualenvs

find_file() {
  local dir=$1
  shift
  for app in "$@"; do
    if [ -f $dir/$app ]; then
      echo -n $dir/$app
      break
    fi
  done
}

configure_ssh()
{
  ssh_pubkey=$(find_file $SSH_CONFIG id_ecdsa.pub id_dsa.pub id_rsa.pub)
  test -n "$ssh_pubkey"
  name=${ssh_pubkey##*/}
  name=${name%%.pub}
  set -- $(cat $ssh_pubkey)
  xmlstarlet ed --pf --omit-decl \
      --update '//_:name[text()="netconf"]/following-sibling::_:authorized-key/_:name' --value "$name" \
      --update '//_:name[text()="netconf"]/following-sibling::_:authorized-key/_:algorithm' --value "$1" \
      --update '//_:name[text()="netconf"]/following-sibling::_:authorized-key/_:key-data' --value "$2" \
      $TEMPLATES/load_auth_pubkey.xml | \
  sysrepocfg --datastore=startup --format=xml ietf-system --import=-
}

configure_tls()
{
  cp $TLS_CONFIG/server_key.pem $KEY_PATH
  ca_cert=$(grep -Fv -- ----- $TLS_CONFIG/ca.pem)
  server_cert=$(grep -Fv -- ----- $TLS_CONFIG/server_cert.pem)
  xmlstarlet ed --pf --omit-decl \
      --update '//_:name[text()="server_cert"]/following-sibling::_:certificate' --value "$server_cert" \
      --update '//_:name[text()="ca"]/following-sibling::_:certificate' --value "$ca_cert" \
      $TEMPLATES/load_server_certs.xml | \
  sysrepocfg --datastore=startup --format=xml ietf-keystore --merge=-

  ca_fingerprint=$(openssl x509 -noout -fingerprint -in $TLS_CONFIG/ca.pem | cut -d= -f2)
  xmlstarlet ed --pf --omit-decl \
      --update '//_:name[text()="netconf"]/preceding-sibling::_:fingerprint' --value "02:$ca_fingerprint" \
      $TEMPLATES/tls_listen.xml | \
  sysrepocfg --datastore=startup --format=xml ietf-netconf-server --merge=-
}

configure_modules()
{
  for dir in "$MODELS_CONFIG"/*; do
    if [ -d $dir ]; then
      model=${dir##*/}
      install_and_configure_yang_model $dir $model
      app="$dir/subscriber.py"
      if [ -x "$app" ]; then
        configure_subscriber_execution $dir $model $app
      fi
    fi
  done
}

install_and_configure_yang_model()
{
    local dir=$1
    local model=$2

    yang=$(find_file $dir $model.yang model.yang)
    sysrepoctl --install --yang=$yang
    data=$(find_file $dir startup.json startup.xml data.json data.xml)
    if [ -n "$data" ]; then
      sysrepocfg --datastore=startup --import=$data $model
    fi
}

configure_subscriber_execution()
{
  local dir=$1
  local model=$2
  local app=$3

  APP_PATH=$PATH
  if [ -r "$dir/requirements.txt" ]; then
    env_dir=$(create_python_venv $dir)
    APP_PATH=$env_dir/bin:$APP_PATH
  fi
  cat > /etc/supervisord.d/$model.conf <<EOF
[program:subs-$model]
command=$app $model
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
redirect_stderr=true
autorestart=true
environment=PATH=$APP_PATH,PYTHONUNBUFFERED="1"
EOF
}

create_python_venv()
{
  local dir=$1

  mkdir -p $BASE_VIRTUALENVS
  env_dir=$BASE_VIRTUALENVS/$model
  (
    virtualenv --system-site-packages $env_dir
    cd $env_dir
    # shellcheck disable=SC1091
    . ./bin/activate
    pip install --requirement "$dir"/requirements.txt
  ) 1>&2
  echo $env_dir
}

configure_ssh
configure_tls
configure_modules

exec /usr/local/bin/supervisord -c /etc/supervisord.conf
