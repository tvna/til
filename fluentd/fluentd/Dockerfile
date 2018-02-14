FROM alpine as timezone
RUN apk --update add tzdata && \
    cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    apk del tzdata && rm -rf /var/cache/apk/*

FROM fluent/fluentd

RUN set -ex \
    && gem install \
        fluent-plugin-prometheus \
    && gem sources --clear-all

COPY --from=timezone /etc/localtime /etc/localtime
