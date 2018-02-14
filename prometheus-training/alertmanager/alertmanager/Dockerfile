FROM alpine as timezone
RUN apk --update add tzdata && \
    cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    apk del tzdata && rm -rf /var/cache/apk/*

FROM networkmgmt/dumb-init as initproc
COPY --from=timezone /etc/localtime /etc/localtime

FROM golang:alpine as alertmanager
RUN set -ex && \
    apk update && apk add --no-cache git build-base
ARG ALERTMANAGER_VERSION=v0.13.0
RUN mkdir -p $GOPATH/src/github.com/prometheus && \
    cd $GOPATH/src/github.com/prometheus && \
    git clone --depth=1 -b $ALERTMANAGER_VERSION https://github.com/prometheus/alertmanager.git && \
    cd alertmanager && \
    git checkout -b $ALERTMANAGER_VERSION && \
## make build for rasberry pi ##
#   export GOARCH=arm && \
#   sed -i "85d" Makefile && \
    make build && \
    mkdir -p /etc/alertmanager && \
    mv $GOPATH/src/github.com/prometheus/alertmanager/alertmanager /bin/alertmanager && \
    mv $GOPATH/src/github.com/prometheus/alertmanager/amtool /bin/amtool && \
    mv $GOPATH/src/github.com/prometheus/alertmanager/doc/examples/simple.yml \
        /etc/alertmanager/config.yml && \
    rm -rf $GOPATH/src/* && \
    rm -rf /var/cache/apk/*

FROM busybox
COPY --from=initproc dumb-init /sbin/dumb-init
COPY --from=initproc /etc/localtime /etc/localtime
COPY --from=alertmanager /bin/alertmanager /bin/alertmanager

VOLUME     ["/alertmanager"]
EXPOSE     9093
ENTRYPOINT ["/sbin/dumb-init", "--"]
CMD        ["/bin/alertmanager", \
            "--config.file=/etc/alertmanager/config.yml", \
            "--storage.path=/alertmanager" ]
