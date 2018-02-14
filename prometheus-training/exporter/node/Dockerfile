FROM alpine as timezone
RUN apk --update add tzdata && \
    cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    apk del tzdata && rm -rf /var/cache/apk/*

FROM networkmgmt/dumb-init as initproc
COPY --from=timezone /etc/localtime /etc/localtime

FROM golang:alpine as node-exporter
RUN set -ex && \
    apk update && apk add --no-cache git build-base
ARG NODE_EXPORTER_VERSION=v0.15.2
RUN mkdir -p $GOPATH/src/github.com/prometheus && \
    cd $GOPATH/src/github.com/prometheus && \
    git clone --depth=1 -b $NODE_EXPORTER_VERSION https://github.com/prometheus/node_exporter.git && \
    cd node_exporter && \
    git checkout -b $NODE_EXPORTER_VERSION && \
    make build && \
    mv $GOPATH/src/github.com/prometheus/node_exporter/node_exporter /bin/node_exporter && \
    rm -rf $GOPATH/src/* && \
    rm -rf /var/cache/apk/*

FROM busybox
COPY --from=initproc dumb-init /sbin/dumb-init
COPY --from=initproc /etc/localtime /etc/localtime
COPY --from=node-exporter /bin/node_exporter /bin/node_exporter

EXPOSE     9100
ENTRYPOINT ["/sbin/dumb-init", "--"]
CMD        ["/bin/node_exporter"]
