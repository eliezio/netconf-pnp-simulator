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

set -eu

HERE=${0%/*}
source $HERE/common.sh

TLS_CONFIG=$CONFIG/tls
KEY_PATH=/opt/etc/keystored/keys

log INFO Update server private key
cp $TLS_CONFIG/server_key.pem $KEY_PATH
ca_cert=$(pem_body $TLS_CONFIG/ca.pem)
server_cert=$(pem_body $TLS_CONFIG/server_cert.pem)
log INFO Load CA and server certificates
xmlstarlet ed --pf --omit-decl \
    --update '//_:name[text()="server_cert"]/following-sibling::_:certificate' --value "$server_cert" \
    --update '//_:name[text()="ca"]/following-sibling::_:certificate' --value "$ca_cert" \
    $TEMPLATES/load_server_certs.xml | \
sysrepocfg --datastore=startup --format=xml ietf-keystore --merge=-

ca_fingerprint=$(openssl x509 -noout -fingerprint -in $TLS_CONFIG/ca.pem | cut -d= -f2)
log INFO Configure TLS ingress service
xmlstarlet ed --pf --omit-decl \
    --update '//_:name[text()="netconf"]/preceding-sibling::_:fingerprint' --value "02:$ca_fingerprint" \
    $TEMPLATES/tls_listen.xml | \
sysrepocfg --datastore=startup --format=xml ietf-netconf-server --merge=-
