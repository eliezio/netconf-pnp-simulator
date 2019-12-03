#!/bin/dash

set -eux

MODELS_CONFIG=/config/models

# create include script for common definitions between pre- and post-setup
# function to infer SV program ID from model

find_executable() {
  dir=$1
  shift
  for prog in $*; do
    if [ -x $dir/$prog ]; then
      echo -n $dir/$prog
    fi
  done
  echo -n ""
}

config_subscribers() {
  for dir in $MODELS_CONFIG/*; do
    if [ -d $dir ]; then
      model=${dir##*/}
      prog=$(find_executable $dir subscriber subscriber.py)
      if [ -n "$prog" ]; then
        cat > /etc/supervisord.d/$model.conf <<EOF
[program:subs-$model]
command=$prog $model
redirect_stderr=true
autostart=false
autorestart=true
environment=PYTHONUNBUFFERED="1"
EOF
      fi
    fi
  done
}

config_subscribers

exec /usr/bin/supervisord -c /etc/supervisord.conf
