FROM google/cadvisor as buildstage

RUN set -ex && \
    apk update && \
    apk add --no-cache tini && \
    rm -rf $GOPATH/src/* /var/cache/apk/* /var/tmp/* /tmp/*

FROM busybox
COPY --from=buildstage /usr/bin/tini /usr/bin/tini
COPY --from=buildstage /usr/bin/cadvisor /usr/bin/cadvisor

EXPOSE     8080
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD        ["/usr/bin/cadvisor", "-logtostderr"]
