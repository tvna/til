FROM alpine as timezone
RUN apk --update add tzdata && \
    cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    apk del tzdata && rm -rf /var/cache/apk/*

FROM networkmgmt/dumb-init as initproc
COPY --from=timezone /etc/localtime /etc/localtime

FROM golang:alpine as snmp-exporter
RUN set -ex && \
    apk update && apk add --no-cache git build-base
ARG SNMP_EXPORTER_VERSION=v0.8.0
RUN mkdir -p $GOPATH/src/github.com/prometheus && \
    cd $GOPATH/src/github.com/prometheus && \
    git clone --depth=1 -b $SNMP_EXPORTER_VERSION https://github.com/prometheus/snmp_exporter.git && \
    cd snmp_exporter && \
    git checkout -b $SNMP_EXPORTER_VERSION && \
    make build && \
    mkdir -p /etc/snmp_exporter && \
    mv $GOPATH/src/github.com/prometheus/snmp_exporter/snmp_exporter /bin/snmp_exporter && \
    mv $GOPATH/src/github.com/prometheus/snmp_exporter/snmp.yml /etc/snmp_exporter/config.yml && \
    rm -rf $GOPATH/src/* && \
    rm -rf /var/cache/apk/*

FROM busybox
COPY --from=initproc dumb-init /sbin/dumb-init
COPY --from=initproc /etc/localtime /etc/localtime
COPY --from=snmp-exporter /bin/snmp_exporter /bin/snmp_exporter
COPY --from=snmp-exporter /etc/snmp_exporter/config.yml /etc/snmp_exporter/config.yml

EXPOSE     9116
ENTRYPOINT ["/sbin/dumb-init", "--"]
CMD        ["/bin/snmp_exporter" \
            "--config.file=/etc/snmp_exporter/config.yml"]
