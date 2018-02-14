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
COPY --from=prometheus /bin/promtool /bin/promtool

CMD ["promtool","check","config","/etc/prometheus/config.yml"]
