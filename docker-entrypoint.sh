#!/bin/sh

set -eux

MODELS_CONFIG=/config/models

config_subscribers() {
  for dir in $MODELS_CONFIG/*; do
    if [ -d $dir ]; then
      model=${dir##*/}
      if [ -x $dir/subscriber ]; then
        cat > /etc/supervisord.d/$model.conf <<EOF
[program:subs-$model]
command=$dir/subscriber $model
redirect_stderr=true
autostart=false
environment=PYTHONUNBUFFERED="1"
EOF
      fi
    fi
  done
}

config_subscribers

exec /usr/bin/supervisord -c /etc/supervisord.conf
