FROM alpine as timezone
RUN apk --update add tzdata && \
    cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    apk del tzdata && rm -rf /var/cache/apk/*

FROM networkmgmt/dumb-init as initproc
COPY --from=timezone /etc/localtime /etc/localtime

FROM google/cadvisor
COPY --from=initproc dumb-init /sbin/dumb-init
COPY --from=initproc /etc/localtime /etc/localtime

EXPOSE     8080
ENTRYPOINT ["/sbin/dumb-init", "--"]
CMD        ["/usr/bin/cadvisor", "-logtostderr"]
