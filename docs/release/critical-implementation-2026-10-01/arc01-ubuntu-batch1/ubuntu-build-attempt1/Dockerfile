FROM ubuntu@sha256:11dc1ccb427f0464a2369e645454c272bb0baece7357c892ba69d313b3a332cf
LABEL com.collect.arc01.owner="collect-arc01-ubuntu-20261002-deabfee579f3"
RUN apt-get -o Acquire::Retries=0 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 update
RUN DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=0 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 install -y --no-install-recommends ca-certificates git make ruby
RUN rm -rf /var/lib/apt/lists/*
ENV PATH="/opt/dart/dart-sdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
WORKDIR /work/checkout
CMD ["/bin/bash"]
