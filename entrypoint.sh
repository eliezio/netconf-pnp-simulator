#!/bin/bash
# shellcheck disable=SC2086

set -o errexit
set -o nounset
set -o pipefail
set -o xtrace

export PATH=/opt/bin:/usr/local/bin:/usr/bin:/bin

CONFIG=/config
TLS_CONFIG=$CONFIG/tls
MODELS_CONFIG=$CONFIG/models
KEY_PATH=/opt/etc/keystored/keys
BASE_VIRTUALENVS=$HOME/.local/share/virtualenvs

find_file() {
  dir=$1
  shift
  for prog in "$@"; do
    if [ -f $dir/$prog ]; then
      echo -n $dir/$prog
      break
    fi
  done
  echo -n ""
}

find_executable() {
  dir=$1
  shift
  for prog in "$@"; do
    if [ -x $dir/$prog ]; then
      echo -n $dir/$prog
      break
    fi
  done
  echo -n ""
}

configure_tls()
{
  cp $TLS_CONFIG/server_key.pem $KEY_PATH
  cp $TLS_CONFIG/server_key.pem.pub $KEY_PATH
  sysrepocfg --datastore=startup --format=xml ietf-keystore --merge=$TLS_CONFIG/load_server_certs.xml
  sysrepocfg --datastore=startup --format=xml ietf-netconf-server --merge=$TLS_CONFIG/tls_listen.xml
}

configure_modules()
{
  for dir in "$MODELS_CONFIG"/*; do
    if [ -d $dir ]; then
      model=${dir##*/}
      install_and_configure_yang_model $dir $model
      prog=$(find_executable $dir subscriber subscriber.py)
      if [ -n "$prog" ]; then
        configure_subscriber_execution $dir $model $prog
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
  local prog=$3

  PROG_PATH=$PATH
  if [ -r "$dir/requirements.txt" ]; then
    mkdir -p $BASE_VIRTUALENVS
    env_dir=$BASE_VIRTUALENVS/$model
    python3 -m venv --system-site-packages $env_dir
    cd $env_dir
    . ./bin/activate
    pip install -r "$dir"/requirements.txt
    deactivate
    PROG_PATH=$env_dir/bin:$PROG_PATH
  fi
  cat > /etc/supervisord.d/$model.conf <<EOF
[program:subs-$model]
command=$prog $model
redirect_stderr=true
autorestart=true
environment=PATH=$PROG_PATH,PYTHONPATH=/opt/lib/python3.7/site-packages,PYTHONUNBUFFERED="1"
EOF
}

configure_tls
configure_modules

exec /usr/local/bin/supervisord -c /etc/supervisord.conf
