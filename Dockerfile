FROM ubuntu:20.04 AS builder

RUN apt update && DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
  ca-certificates \
  curl \
  g++ \
  gcc \
  libbamtools-dev \
  libboost-iostreams-dev \
  libboost-serialization-dev \
  libc6-dev \
  libgsl-dev \
  libhts-dev \
  libjsoncpp-dev \
  liblpsolve55-dev \
  libmysqlclient-dev \
  libpng-dev \
  libseqlib-dev \
  libsqlite3-dev \
  libsuitesparse-dev \
  make \
  pkg-config \
  uuid-dev \
  zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

FROM builder AS spaln_boundary_scorer

# Shouldn't be strictly necessary to build our own spaln_boundary_scorer, as
# latest version of ProtHint bundles it, but at least we know how just in case...
# 2021-02-22
RUN curl -L https://github.com/gatech-genemark/spaln-boundary-scorer/archive/b48977154a75a8559ff0398b8858dc2a51768632.tar.gz | tar -xzf - \
  && cd spaln-boundary-scorer-* \
  && make -j CC='g++ -O2' \
  && mv spaln_boundary_scorer /usr/local/bin \
  && cd / \
  && rm -rf spaln-boundary-scorer-*

FROM builder AS augustus

# 2021-05-21 snapshot (for bam2hints optimization) + filterBam optimizations
# https://github.com/Gaius-Augustus/Augustus/pull/297
RUN mkdir /src && cd /src \
  && curl -L https://github.com/harvardinformatics/Augustus/archive/849d9939b58fd67666317f070bdbe344dc0923b3.tar.gz \
    | tar --strip-components=1 -xzf - \
  && make -j CXX='g++ -O3' MYSQL=false \
  && make install INSTALLDIR=/opt/augustus \
  && rm -rf /src

FROM builder AS ucsc

RUN curl https://hgdownload.cse.ucsc.edu/admin/exe/userApps.archive/userApps.v415.src.tgz | tar -xzf - \
  && export BINDIR=/usr/local/bin \
  && for dir in jkOwnLib lib htslib \
                utils/faToTwoBit \
                utils/twoBitInfo; \
     do cd /userApps/kent/src/${dir} && make -j MYSQLLIBS=''; done

FROM ubuntu:20.04 AS braker

RUN apt update && DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
  bamtools \
  ca-certificates \
  cdbfasta \
  diamond-aligner \
  libbamtools2.5.1 \
  libboost-iostreams1.71.0 \
  libboost-serialization1.71.0 \
  libcolamd2 \
  libdbd-mysql-perl \
  libfile-which-perl \
  libgsl23 \
  libhash-merge-perl \
  libmath-utils-perl \
  libmce-perl \
  libparallel-forkmanager-perl \
  libscalar-util-numeric-perl \
  libseqlib1 \
  libsqlite3-0 \
  libsuitesparseconfig5 \
  libyaml-perl \
  openjdk-8-jre-headless \
  python3-biopython \
  samtools \
  spaln \
  unzip \
  wget

COPY --from=spaln_boundary_scorer /usr/local/bin/spaln_boundary_scorer /usr/local/bin/
COPY --from=ucsc /usr/local/bin/ /usr/local/bin/
COPY --from=augustus /opt/augustus /opt/augustus

# Register for GeneMark-ES/ET/EP at http://exon.gatech.edu/GeneMark/license_download.cgi (tested with ver 4.65)
# NOTE: the bundled license key expires after 200 days
ADD ./gmes_linux_64.tar.gz /opt

# Use more recent ProtHint for https://github.com/gatech-genemark/ProtHint/pull/31
# Using ubuntu package versions of diamond & spaln instead of stale static builds
RUN mkdir /opt/gm_key \
  && mv /opt/gmes_linux_64/gm_key /opt/gm_key/.gm_key \
  && cd /opt/gmes_linux_64 \
  && perl change_path_in_perl_scripts.pl "/usr/bin/env perl" \
  && rm -rf ProtHint \
  && wget -O - https://github.com/gatech-genemark/ProtHint/archive/524c27f4d62b7b4314b32c50c45cedabf688be98.tar.gz | tar -xzf - \
  && mv ProtHint-* ProtHint \
  && rm -rf ProtHint/examples ProtHint/tests ProtHint/dependencies/diamond \
  && ln -sf /usr/bin/spaln /opt/gmes_linux_64/ProtHint/dependencies/ \
  && ln -sf /usr/local/bin/spaln_boundary_scorer /opt/gmes_linux_64/ProtHint/dependencies/

# a la https://github.com/bioconda/bioconda-recipes/pull/28922
RUN wget -O - https://github.com/Gaius-Augustus/TSEBRA/archive/refs/tags/v1.0.1.tar.gz | tar -xzf - \
  && sed -i.bak -e 's#from \([^ ]*\) import#from tsebra_mod.\1 import#' TSEBRA-1.0.1/bin/*.py \
  && mv TSEBRA-1.0.1/bin/tsebra.py TSEBRA-1.0.1/bin/fix_gtf_ids.py /usr/local/bin \
  && mv TSEBRA-1.0.1/bin/ $(python3 -c 'import site; print(site.getsitepackages()[0])')/tsebra_mod

# Install GUSHR & dependency GeMoMa
# https://github.com/Gaius-Augustus/GUSHR/issues/1
RUN wget -O /usr/local/bin/gushr.py https://raw.githubusercontent.com/harvardinformatics/GUSHR/8aafe23/gushr.py \
  && chmod +x /usr/local/bin/gushr.py
# work around https://github.com/Jstacs/Jstacs/issues/12 by creating a GeMoMa.ini.xml with the defaults
RUN mkdir /tmp/GeMoMa \
  && cd /tmp/GeMoMa \
  && wget http://www.jstacs.de/downloads/GeMoMa-1.6.4.zip \
  && unzip GeMoMa-1.6.4.zip \
  && mv GeMoMa-1.6.4.jar /usr/local/bin \
  && rm -rf /tmp/GeMoMa \
  && printf '%s\n' '<maxSize><className>java.lang.Integer</className>-1</maxSize>\n' \
                   '<timeOut><className>java.lang.Long</className>3600</timeOut>\n' \
                   '<maxTimeOut><className>java.lang.Long</className>604800</maxTimeOut>\n' > /usr/local/bin/GeMoMa.ini.xml

COPY scripts/ /usr/local/bin/

ENV AUGUSTUS_BIN_PATH=/opt/augustus/bin
ENV AUGUSTUS_CONFIG_PATH=/opt/augustus/config
ENV AUGUSTUS_SCRIPTS_PATH=/opt/augustus/scripts
ENV GENEMARK_PATH=/opt/gmes_linux_64
ENV PATH=/opt/augustus/bin:/opt/augustus/scripts:/opt/gmes_linux_64/ProtHint/bin:${PATH}
