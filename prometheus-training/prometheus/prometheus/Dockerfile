FROM golang:1.10-alpine as buildstage

ENV PROMETHEUS_VERSION=v2.1.0
ARG PROMETHEUS_GIT=https://github.com/prometheus/prometheus.git

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
    git clone --depth=1 -b $PROMETHEUS_VERSION $PROMETHEUS_GIT && \
    cd prometheus && \
    git checkout -b $PROMETHEUS_VERSION && \
    make build -j4 && \
    mkdir -p /etc/prometheus && \
    mv $GOPATH/src/github.com/prometheus/prometheus/prometheus /bin/prometheus && \
    mv $GOPATH/src/github.com/prometheus/prometheus/promtool /bin/promtool && \
    apk del .build-deps && \
    rm -rf $GOPATH/src/* /var/cache/apk/* /var/tmp/* /tmp/*

FROM busybox
COPY --from=buildstage /usr/bin/dumb-init /usr/bin/dumb-init
COPY --from=buildstage /bin/prometheus /bin/prometheus

VOLUME     ["/prometheus"]
EXPOSE     9090
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD        ["/bin/prometheus", \
            "--config.file=/etc/prometheus/config.yml", \
            "--storage.tsdb.path=/prometheus", \
            "--web.console.libraries=/etc/prometheus/console_libraries", \
            "--web.console.templates=/etc/prometheus/consoles" ]
