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

find_file() {
  dir=$1
  shift
  for prog in $*; do
    if [ -f $dir/$prog ]; then
      echo -n $dir/$prog
    fi
  done
  echo -n ""
}

# This function uploads all models under $CONFIG/yang-models
configure_yang_models()
{
  for dir in $MODELS_CONFIG/*; do
    if [ -d $dir ]; then
      model=${dir##*/}
      rm -vf $SR_SUBSCRIPTIONS_SOCKET_DIR/$model/*.sock
      # install the Yang model
      yang=$(find_file $dir $model.yang model.yang)
      sysrepoctl --install --yang=$yang
      data=$(find_file $dir startup.json startup.xml data.json data.xml)
      if [ -n "$data" ]; then
        echo importing $data into startup datastore
        sysrepocfg --datastore=startup --format=${data##*.} $model --import=$data
      fi
      # activate the subscriber
      supervisorctl start subs-$model
    fi
  done
}

configure_tls
configure_yang_models mynetconf
