FROM ubuntu:20.04 AS spaln_boundary_scorer

RUN apt update && apt install -y --no-install-recommends \
  ca-certificates \
  g++ \
  make \
  wget \
  && rm -rf /var/lib/apt/lists/*

# Shouldn't be strictly necessary to build our own spaln_boundary_scorer, as
# latest version of ProtHint bundles it, but at least we know how just in case...
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

# 2021-05-21 snapshot (for bam2hints optimization) + filterBam optimizations
# https://github.com/Gaius-Augustus/Augustus/pull/297
RUN mkdir /src && cd /src \
  && curl -L https://github.com/harvardinformatics/Augustus/archive/849d9939b58fd67666317f070bdbe344dc0923b3.tar.gz \
    | tar --strip-components=1 -xzf - \
  && make -j CXX='g++ -O3' MYSQL=false \
  && make install INSTALLDIR=/opt/augustus \
  && rm -rf /src

FROM ubuntu:20.04 AS braker

RUN apt update && DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
  ca-certificates \
  cdbfasta \
  diamond-aligner \
  libbamtools2.5.1 \
  libboost-iostreams1.71.0 \
  libboost-serialization1.71.0 \
  libdbd-mysql-perl \
  libfile-which-perl \
  libgsl23 \
  libcamd2 \
  libparallel-forkmanager-perl \
  libseqlib1 \
  libsqlite3-0 \
  libsuitesparseconfig5 \
  libyaml-perl \
  python3-biopython \
  samtools \
  spaln \
  wget

COPY --from=spaln_boundary_scorer /usr/local/bin/spaln_boundary_scorer /usr/local/bin/
COPY --from=augustus /opt/augustus /opt/augustus

# Register for GeneMark-ES/ET/EP at http://exon.gatech.edu/GeneMark/license_download.cgi (tested with ver 4.65)
# NOTE: the bundled license key expires after 200 days
ADD ./gmes_linux_64.tar.gz /opt

# Use more recnet ProtHint for https://github.com/gatech-genemark/ProtHint/pull/31
# Using ubuntu package versions of diamond & spaln instead of stale static builds
RUN mkdir /opt/gm_key \
  && mv /opt/gmes_linux_64/gm_key /opt/gm_key/.gm_key \
  && cd /opt/gmes_linux_64 \
  && perl change_path_in_perl_scripts.pl "/usr/bin/env perl" \
  && rm -rf ProtHint \
  && wget -O - https://github.com/gatech-genemark/ProtHint/archive/524c27f4d62b7b4314b32c50c45cedabf688be98.tar.gz | tar -xzf - \
  && mv ProtHint-* ProtHint \
  && rm -rf ProtHint/examples ProtHint/tests ProtHint/dependencies/diamond ProtHint/dependencies/spaln*

# a la https://github.com/bioconda/bioconda-recipes/pull/28922
RUN wget -O - https://github.com/Gaius-Augustus/TSEBRA/archive/refs/tags/v1.0.1.tar.gz | tar -xzf - \
  && sed -i.bak -e 's#from \([^ ]*\) import#from tsebra_mod.\1 import#' TSEBRA-1.0.1/bin/*.py \
  && mv TSEBRA-1.0.1/bin/tsebra.py TSEBRA-1.0.1/bin/fix_gtf_ids.py /usr/local/bin \
  && mv TSEBRA-1.0.1/bin/ $(python3 -c 'import site; print(site.getsitepackages()[0])')/tsebra_mod

ENV ALIGNMENT_TOOL_PATH=/usr/local/bin/
ENV AUGUSTUS_BIN_PATH=/usr/local/bin
ENV AUGUSTUS_SCRIPTS_PATH=/usr/local/bin
ENV GENEMARK_PATH=/opt/gmes_linux_64
ENV PATH=/opt/augustus/bin:/opt/augustus/scripts:/opt/gmes_linux_64/ProtHint/bin:${PATH}
