FROM python:3.7.6-slim-buster as build

ARG libyang_version=v1.0-r5
ARG sysrepo_version=v0.7.9
ARG libnetconf2_version=v0.12-r2
ARG netopeer2_version=v0.7-r2

RUN \
      apt-get update -q && apt-get install -y \
      # general tools
      git \
      cmake \
      build-essential \
      # libyang
      libpcre3-dev \
      pkg-config \
      # sysrepo
      libavl-dev \
      libev-dev \
      libprotobuf-c-dev \
      protobuf-c-compiler \
      # netopeer2
      libssh-dev \
      libssl-dev \
      # bindings
      swig \
      python3-dev

# use /opt/dev as working directory
RUN mkdir /opt/dev
WORKDIR /opt/dev

COPY patches/ /opt/dev/patches/

RUN git config --global advice.detachedHead false

# libyang
RUN \
      git clone --branch $libyang_version --depth 1 https://github.com/CESNET/libyang.git && \
      cd libyang && mkdir build && cd build && \
      cmake -DCMAKE_BUILD_TYPE:String="Release" -DENABLE_BUILD_TESTS=OFF .. && \
      make -j2 && \
      make install && \
      ldconfig

# sysrepo
RUN \
      git clone --branch $sysrepo_version --depth 1 https://github.com/sysrepo/sysrepo.git && \
      cd sysrepo && for p in ../patches/sysrepo/*.patch; do patch -p1 -i $p; done && \
      mkdir build && cd build && \
      cmake -DCMAKE_BUILD_TYPE:String="Release" -DENABLE_TESTS=OFF -DREPOSITORY_LOC:PATH=/usr/local/etc/sysrepo \
      -DGEN_PYTHON_VERSION=3 \
      -DPYTHON_MODULE_PATH:PATH=/usr/local/lib/python3.7/site-packages .. && \
      make -j2 && \
      make install && \
      ldconfig

# libnetconf2
RUN \
      git clone --branch $libnetconf2_version --depth 1 https://github.com/CESNET/libnetconf2.git && \
      cd libnetconf2 && mkdir build && cd build && \
      cmake -DCMAKE_BUILD_TYPE:String="Release" -DENABLE_BUILD_TESTS=OFF .. && \
      make -j2 && \
      make install && \
      ldconfig

# keystore
RUN \
      cd /opt/dev && \
      git clone --branch $netopeer2_version --depth 1 https://github.com/CESNET/Netopeer2.git && \
      cd Netopeer2 && \
      cd keystored && mkdir build && cd build && \
      cmake -DCMAKE_BUILD_TYPE:String="Release" .. && \
      make -j2 && \
      make install && \
      ldconfig

# netopeer2
RUN \
      cd /opt/dev && \
      cd Netopeer2/server && mkdir build && cd build && \
      cmake -DCMAKE_BUILD_TYPE:String="Release" .. && \
      make -j2 && \
      make install && \
      cd ../../cli && mkdir build && cd build && \
      cmake -DCMAKE_BUILD_TYPE:String="Release" .. && \
      make -j2 && \
      make install

FROM python:3.7.6-slim-buster
LABEL authors="mislav.novakovic@sartura.hr, eliezio.oliveira@est.tech"

RUN apt-get update -q && apt-get upgrade -yq && apt-get install -y \
      # general RT tools
      openssh-client \
      # libyang
      libpcre3 \
      # sysrepo
      libavl1 \
      libev4 \
      libprotobuf-c1 \
      # netopeer2
      libssh-4 \
      libssl1.1 \
      # bindings
      libpython3.7 \
      && rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local/ /usr/local/

COPY config/ /config
VOLUME /config

RUN pip3 install --upgrade pip \
    && pip3 install supervisor

# finish setup and add netconf user
RUN \
      ldconfig \
      && adduser --system --disabled-password --gecos 'Netconf User' netconf

ENV HOME=/home/netconf
VOLUME $HOME/.local/share/virtualenvs

# generate ssh keys for netconf user
RUN \
      mkdir -p $HOME/.ssh && \
      ssh-keygen -t dsa -P '' -f $HOME/.ssh/id_dsa && \
      cat $HOME/.ssh/id_dsa.pub > $HOME/.ssh/authorized_keys

EXPOSE 830

COPY supervisord.conf /etc/supervisord.conf
RUN mkdir /etc/supervisord.d

COPY entrypoint.sh /usr/local/bin/

CMD /usr/local/bin/entrypoint.sh
