FROM alpine as timezone
RUN apk --update add tzdata && \
    cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    apk del tzdata && rm -rf /var/cache/apk/*

FROM networkmgmt/dumb-init as initproc
COPY --from=timezone /etc/localtime /etc/localtime

FROM golang:alpine as prometheus
RUN set -ex && \
    apk update && apk add --no-cache git build-base
ARG PROMETHEUS_VERSION=v2.1.0
RUN mkdir -p $GOPATH/src/github.com/prometheus && \
    cd $GOPATH/src/github.com/prometheus && \
    git clone --depth=1 -b $PROMETHEUS_VERSION https://github.com/prometheus/prometheus.git && \
    cd prometheus && \
    git checkout -b $PROMETHEUS_VERSION && \
## make build for rasberry pi ##
#   export GOARCH=arm && \
#   sed -i "91d" Makefile && \
    make build && \
    mkdir -p /etc/prometheus && \
    mv $GOPATH/src/github.com/prometheus/prometheus/prometheus /bin/prometheus && \
    mv $GOPATH/src/github.com/prometheus/prometheus/promtool /bin/promtool && \
    rm -rf $GOPATH/src/* && \
    rm -rf /var/cache/apk/*

FROM busybox
COPY --from=initproc dumb-init /sbin/dumb-init
COPY --from=initproc /etc/localtime /etc/localtime
COPY --from=prometheus /bin/prometheus /bin/prometheus

VOLUME     ["/prometheus"]
EXPOSE     9090
ENTRYPOINT ["/sbin/dumb-init", "--"]
CMD        ["/bin/prometheus", \
            "--config.file=/etc/prometheus/config.yml", \
            "--storage.tsdb.path=/prometheus", \
            "--web.console.libraries=/etc/prometheus/console_libraries", \
            "--web.console.templates=/etc/prometheus/consoles" ]
