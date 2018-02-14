FROM alpine as timezone
RUN apk --update add tzdata && \
    cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    apk del tzdata && rm -rf /var/cache/apk/*

FROM networkmgmt/dumb-init as initproc
COPY --from=timezone /etc/localtime /etc/localtime

FROM golang:alpine as blackbox-exporter
RUN set -ex && \
    apk update && apk add --no-cache git build-base
ARG BLACKBOX_EXPORTER_VERSION=v0.11.0
RUN mkdir -p $GOPATH/src/github.com/prometheus && \
    cd $GOPATH/src/github.com/prometheus && \
    git clone --depth=1 -b $BLACKBOX_EXPORTER_VERSION https://github.com/prometheus/blackbox_exporter.git && \
    cd blackbox_exporter && \
    git checkout -b $BLACKBOX_EXPORTER_VERSION && \
    make build && \
    mkdir -p /etc/blackbox_exporter && \
    mv $GOPATH/src/github.com/prometheus/blackbox_exporter/blackbox_exporter \
        /bin/blackbox_exporter && \
    rm -rf $GOPATH/src/* && \
    rm -rf /var/cache/apk/*

FROM busybox
COPY --from=initproc dumb-init /sbin/dumb-init
COPY --from=initproc /etc/localtime /etc/localtime
COPY --from=blackbox-exporter /bin/blackbox_exporter /bin/blackbox_exporter

EXPOSE     9115
ENTRYPOINT ["/sbin/dumb-init", "--"]
CMD        ["/bin/blackbox_exporter", \
            "--config.file=/etc/blackbox_exporter/config.yml"]
