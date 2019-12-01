#!/bin/dash

set -eux

CONFIG=/config

TLS_CONFIG=$CONFIG/tls
KEY_PATH=/usr/local/etc/keystored/keys
SR_SUBSCRIPTIONS_SOCKET_DIR=/var/run/sysrepo-subscriptions

# This function configures server/trusted certificates into Netopeer
configure_tls()
{
  wait-for 127.0.0.1:830 -t 60 -- echo SSH Server is Up

  cp $TLS_CONFIG/server_key.pem $KEY_PATH
  cp $TLS_CONFIG/server_key.pem.pub $KEY_PATH
  sysrepocfg --datastore=running --format=xml ietf-keystore --merge=$TLS_CONFIG/load_server_certs.xml
  sysrepocfg --datastore=running --format=xml ietf-netconf-server --merge=$TLS_CONFIG/tls_listen.xml
}

MODELS_CONFIG=$CONFIG/models

# This function uploads all models under $CONFIG/yang-models
configure_yang_models()
{
  for dir in $MODELS_CONFIG/*; do
    if [ -d $dir ]; then
      model=${dir##*/}
      rm -vf $SR_SUBSCRIPTIONS_SOCKET_DIR/$model/*.sock
      # install the Yang model
      sysrepoctl --install --yang=$dir/model.yang
      if [ -f $dir/data.json ]; then
        echo initializing data for $model model
        sysrepocfg --datastore=startup --format=json $model --import=$dir/data.json
      elif [ -f $dir/data.xml ]; then
        echo initializing data for $model model
        sysrepocfg --datastore=startup --format=xml $model --import=$dir/data.xml
      fi
      # activate the subscriber
      supervisorctl start subs-$model
    fi
  done
}

configure_tls
configure_yang_models mynetconf
