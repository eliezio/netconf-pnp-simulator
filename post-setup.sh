#!/bin/sh

set -eux

CONFIG=/config

TLS_CONFIG=$CONFIG/tls
KEY_PATH=/usr/local/etc/keystored/keys

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

wait_for_subscription() {
  local model=$1
  local secs=$2
  local i=0
  while [ $i -le $secs ]; do
    if [ -S /var/run/sysrepo-subscriptions/$model/*.sock ]; then
      return 0
    fi
    sleep 1
    i=$(($i+1))
  done
  return 1
}

# This function uploads all models under $CONFIG/yang-models
configure_yang_models()
{
  for dir in $MODELS_CONFIG/*; do
    if [ -d $dir ]; then
      model=${dir##*/}
      rm -vf /var/run/sysrepo-subscriptions/$model/*.sock
      # install the Yang model
      sysrepoctl --install --yang=$dir/model.yang
      # activate the subscriber
      supervisorctl start subs-$model
      wait_for_subscription $model 10
      if [ -f $dir/data.json ]; then
        echo creating data for $model model
        sysrepocfg --datastore=running --format=json $model --import=$dir/data.json
      elif [ -f $dir/data.xml ]; then
        echo creating data for $model model
        sysrepocfg --datastore=running --format=xml $model --import=$dir/data.xml
      fi
    fi
  done
}

configure_tls
configure_yang_models mynetconf
