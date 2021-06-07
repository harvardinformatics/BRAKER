FROM ubuntu:20.04 AS spaln_boundary_scorer

RUN apt update && apt install -y --no-install-recommends \
  ca-certificates \
  g++ \
  make \
  wget \
  && rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# 2021-02-22
RUN wget -O - https://github.com/gatech-genemark/spaln-boundary-scorer/archive/b48977154a75a8559ff0398b8858dc2a51768632.tar.gz | tar -xzf - \
  && cd spaln-boundary-scorer-* \
  && make -j CC='g++ -O2' \
  && mv spaln_boundary_scorer /usr/local/bin \
  && cd / \
  && rm -rf spaln-boundary-scorer-*

FROM ubuntu:20.04 AS augustus

# Install required packages
RUN apt update && DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
  ca-certificates \
  curl \
  gcc \
  g++ \
  libc6-dev \
  make \
  libbamtools-dev \
  libboost-iostreams-dev \
  libboost-serialization-dev \
  libjsoncpp-dev \
  libgsl-dev \
  libhts-dev \
  libseqlib-dev \
  liblpsolve55-dev \
  libsqlite3-dev \
  libsuitesparse-dev \
  pkg-config \
  zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

# 2021-05-21 snapshot + filterBam optimizations
# https://github.com/Gaius-Augustus/Augustus/pull/297
RUN mkdir /src && cd /src \
  && curl -L https://github.com/harvardinformatics/Augustus/archive/849d9939b58fd67666317f070bdbe344dc0923b3.tar.gz \
    | tar --strip-components=1 -xzf - \
  && make -j INSTALLDIR=/opt/augustus MYSQL=false HTSLIBS='-lhts' \
  && make install \
  && rm -rf /src
