FROM golang:1.10-alpine as buildstage

ENV BLACKBOX_EXPORTER_VERSION=v0.11.0
ARG BLACKBOX_EXPORTER_GIT=https://github.com/prometheus/blackbox_exporter.git

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
    git clone --depth=1 -b $BLACKBOX_EXPORTER_VERSION $BLACKBOX_EXPORTER_GIT && \
    cd blackbox_exporter && \
    git checkout -b $BLACKBOX_EXPORTER_VERSION && \
    make build -j4 && \
    mkdir -p /etc/blackbox_exporter && \
    mv $GOPATH/src/github.com/prometheus/blackbox_exporter/blackbox_exporter \
        /bin/blackbox_exporter && \
    apk del .build-deps && \
    rm -rf $GOPATH/src/* /var/cache/apk/* /var/tmp/* /tmp/*

FROM busybox
COPY --from=buildstage /usr/bin/dumb-init /usr/bin/dumb-init
COPY --from=buildstage /bin/blackbox_exporter /bin/blackbox_exporter

EXPOSE     9115
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD        ["/bin/blackbox_exporter", \
            "--config.file=/etc/blackbox_exporter/config.yml"]
