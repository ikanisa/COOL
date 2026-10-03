FROM ubuntu@sha256:496754492fb28b4d3049432f2ca787449331e23fb14f0dd3fffea86bf5a93eb4
LABEL com.collect.arc01.owner="collect-arc01-ubuntu-resolved-20261002-35c1bc3c8800"
RUN apt-get -o Acquire::Retries=0 -o Acquire::http::Timeout=25 update && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=0 -o Acquire::http::Timeout=25 install -y --no-install-recommends ca-certificates curl git make ruby unzip xz-utils zip libglu1-mesa && rm -rf /var/lib/apt/lists/*
RUN groupadd --gid 1001 arc01 && useradd --uid 501 --gid 1001 --create-home --shell /bin/bash arc01
USER arc01
WORKDIR /work/checkout
ENV PATH=/opt/flutter/flutter/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
