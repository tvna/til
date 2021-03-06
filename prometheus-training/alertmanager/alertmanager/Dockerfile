FROM golang:1.10-alpine as buildstage

ENV PROMETHEUS_ALERTMANAGER_VERSION=v0.13.0
ARG PROMETHEUS_ALERTMANAGER_GIT=https://github.com/prometheus/alertmanager.git

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
    git clone --depth=1 -b $PROMETHEUS_ALERTMANAGER_VERSION $PROMETHEUS_ALERTMANAGER_GIT && \
    cd alertmanager && \
    git checkout -b $PROMETHEUS_ALERTMANAGER_VERSION && \
    make build -j4 && \
    mkdir -p /etc/alertmanager && \
    mv $GOPATH/src/github.com/prometheus/alertmanager/alertmanager /bin/alertmanager && \
    mv $GOPATH/src/github.com/prometheus/alertmanager/amtool /bin/amtool && \
    mv $GOPATH/src/github.com/prometheus/alertmanager/doc/examples/simple.yml \
        /etc/alertmanager/config.yml && \
    apk del .build-deps && \
    rm -rf $GOPATH/src/* /var/cache/apk/* /var/tmp/* /tmp/*

FROM busybox
COPY --from=buildstage /usr/bin/dumb-init /usr/bin/dumb-init
COPY --from=buildstage /bin/alertmanager /bin/alertmanager
COPY --from=buildstage /etc/alertmanager/config.yml /etc/alertmanager/config.yml

VOLUME     ["/alertmanager"]
EXPOSE     9093
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD        ["/bin/alertmanager", \
            "--config.file=/etc/alertmanager/config.yml", \
            "--storage.path=/alertmanager" ]
