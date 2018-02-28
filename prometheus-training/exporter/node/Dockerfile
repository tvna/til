FROM golang:1.10-alpine as buildstage

ENV NODE_EXPORTER_VERSION=v0.15.2
ARG NODE_EXPORTER_GIT=https://github.com/prometheus/node_exporter.git

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
    git clone --depth=1 -b $NODE_EXPORTER_VERSION $NODE_EXPORTER_GIT && \
    cd node_exporter && \
    git checkout -b $NODE_EXPORTER_VERSION && \
    make build && \
    mv $GOPATH/src/github.com/prometheus/node_exporter/node_exporter /bin/node_exporter && \
    apk del .build-deps && \
    rm -rf $GOPATH/src/* /var/cache/apk/* /var/tmp/* /tmp/*

FROM busybox
COPY --from=buildstage /usr/bin/dumb-init /usr/bin/dumb-init
COPY --from=buildstage /bin/node_exporter /bin/node_exporter

EXPOSE     9100
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD        ["/bin/node_exporter"]
