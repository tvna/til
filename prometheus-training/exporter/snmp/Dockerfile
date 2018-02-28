FROM golang:1.10-alpine as buildstage

ENV SNMP_EXPORTER_VERSION=v0.8.0
ARG SNMP_EXPORTER_GIT=https://github.com/prometheus/snmp_exporter.git

RUN set -ex && \
    apk update && \
    apk add --no-cache --virtual .build-deps \
      git \
      build-base \
    && \
    apk add --no-cache --virtual .run-deps \
      dumb-init \
    && \
    mkdir -p $GOPATH/src/github.com/prometheus && \
    cd $GOPATH/src/github.com/prometheus && \
    git clone --depth=1 -b $SNMP_EXPORTER_VERSION $SNMP_EXPORTER_GIT && \
    cd snmp_exporter && \
    git checkout -b $SNMP_EXPORTER_VERSION && \
    make build -j4 && \
    mkdir -p /etc/snmp_exporter && \
    mv $GOPATH/src/github.com/prometheus/snmp_exporter/snmp_exporter /bin/snmp_exporter && \
    mv $GOPATH/src/github.com/prometheus/snmp_exporter/snmp.yml /etc/snmp_exporter/config.yml && \
    apk del .build-deps && \
    rm -rf $GOPATH/src/* /var/cache/apk/* /var/tmp/* /tmp/*

FROM busybox
COPY --from=buildstage /usr/bin/dumb-init /usr/bin/dumb-init
COPY --from=buildstage /bin/snmp_exporter /bin/snmp_exporter
COPY --from=buildstage /etc/snmp_exporter/config.yml /etc/snmp_exporter/config.yml

EXPOSE     9116
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD        ["/bin/snmp_exporter" \
            "--config.file=/etc/snmp_exporter/config.yml"]
