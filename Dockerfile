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
