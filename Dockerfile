FROM python:3.7.6-slim-buster as build

ARG libyang_version=v1.0-r5
ARG sysrepo_version=v0.7.9
ARG libnetconf2_version=v0.12-r2
ARG netopeer2_version=v0.7-r2

WORKDIR /usr/src

COPY bindep.txt .
RUN set -eux \
      && pip install --upgrade pip \
      && pip install bindep \
      && apt-get update -yq \
      && apt-get install -yq $(bindep -b compile)

RUN git config --global advice.detachedHead false

COPY patches/ ./patches/

ENV PKG_CONFIG_PATH=/opt/lib/pkgconfig
RUN echo /opt/lib > /etc/ld.so.conf.d/opt.conf


# libyang
RUN set -eux \
      && git clone --branch $libyang_version --depth 1 https://github.com/CESNET/libyang.git \
      && cd libyang && mkdir build && cd build \
      && cmake -DCMAKE_BUILD_TYPE:String="Release" -DENABLE_BUILD_TESTS=OFF \
         -DCMAKE_INSTALL_PREFIX:PATH=/opt \
         .. \
      && make -j2 \
      && make install \
      && ldconfig

# sysrepo
RUN set -eux \
      && git clone --branch $sysrepo_version --depth 1 https://github.com/sysrepo/sysrepo.git \
      && cd sysrepo && for p in ../patches/sysrepo/*.patch; do patch -p1 -i $p; done \
      && mkdir build && cd build \
      && cmake -DCMAKE_BUILD_TYPE:String="Release" -DENABLE_TESTS=OFF -DREPOSITORY_LOC:PATH=/opt/etc/sysrepo \
         -DCMAKE_INSTALL_PREFIX:PATH=/opt \
         -DPYTHON_MODULE_PATH:PATH=/opt/lib/python3.7/site-packages \
         -DGEN_PYTHON_VERSION=3 .. \
      && make -j2 \
      && make install \
      && ldconfig

# libnetconf2
RUN set -eux \
      && git clone --branch $libnetconf2_version --depth 1 https://github.com/CESNET/libnetconf2.git \
      && cd libnetconf2 && mkdir build && cd build \
      && cmake -DCMAKE_BUILD_TYPE:String="Release" -DENABLE_BUILD_TESTS=OFF \
         -DCMAKE_INSTALL_PREFIX:PATH=/opt \
         .. \
      && make -j2 \
      && make install \
      && ldconfig

# keystore
RUN set -eux \
      && git clone --branch $netopeer2_version --depth 1 https://github.com/CESNET/Netopeer2.git \
      && cd Netopeer2/keystored && mkdir build && cd build \
      && cmake -DCMAKE_BUILD_TYPE:String="Release" \
         -DCMAKE_INSTALL_PREFIX:PATH=/opt \
         .. \
      && make -j2 \
      && make install \
      && ldconfig

# netopeer2
RUN set -eux \
      && cd Netopeer2/server && mkdir build && cd build \
      && cmake -DCMAKE_BUILD_TYPE:String="Release" \
         -DCMAKE_INSTALL_PREFIX:PATH=/opt \
         .. \
      && make -j2 \
      && make install

FROM python:3.7.6-slim-buster
LABEL authors="eliezio.oliveira@est.tech"

COPY bindep.txt .
RUN set -eux \
      && pip install --upgrade pip \
      && pip install bindep \
      && apt-get update -yq \
      && apt-get install -yq $(bindep -b setup runtime) \
      && rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/ /opt/
RUN echo /opt/lib > /etc/ld.so.conf.d/opt.conf \
      && ldconfig

COPY config/ /config
VOLUME /config

RUN set -eux \
      && pip3 install --upgrade pip \
      && pip3 install supervisor

# finish setup and add netconf user
RUN \
      ldconfig \
      && adduser --system --disabled-password --gecos 'Netconf User' netconf

ENV HOME=/home/netconf
VOLUME $HOME/.local/share/virtualenvs

# generate ssh keys for netconf user
RUN set -eux \
      && mkdir -p $HOME/.ssh \
      && ssh-keygen -t dsa -P '' -f $HOME/.ssh/id_dsa \
      && cat $HOME/.ssh/id_dsa.pub > $HOME/.ssh/authorized_keys

EXPOSE 830

COPY supervisord.conf /etc/supervisord.conf
RUN mkdir /etc/supervisord.d

COPY entrypoint.sh /opt/bin/

CMD /opt/bin/entrypoint.sh
