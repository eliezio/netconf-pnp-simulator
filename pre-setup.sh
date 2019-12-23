#!/bin/dash

set -eux

MODELS_CONFIG=/config/models
BASE_VIRTUALENVS=$HOME/.local/share/virtualenvs

# create include script for common definitions between pre- and setup
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
        PROG_PATH="/usr/local/bin:/usr/bin:/bin"
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
autostart=false
autorestart=true
environment=PATH=$PROG_PATH,PYTHONUNBUFFERED="1"
EOF
      fi
    fi
  done
}

config_subscribers

exec /usr/local/bin/supervisord -c /etc/supervisord.conf
