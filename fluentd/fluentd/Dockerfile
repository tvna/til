FROM alpine as timezone
RUN apk --update add tzdata && \
    cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    apk del tzdata && rm -rf /var/cache/apk/*

FROM fluent/fluentd:v1.1

RUN set -ex && \
    apk update && \
    apk add --no-cache --virtual .build-deps \
      build-base \
    && \
    apk add --no-cache --virtual .run-deps \
      ruby-dev \
    && \
    fluent-gem install fluent-plugin-forest --version=0.3.3 && \
    fluent-gem install fluent-plugin-flowcounter --version=1.3.0 && \
    fluent-gem install fluent-plugin-prometheus --version=1.0.1 && \
    fluent-gem install fluent-plugin-mongo --version=1.1.0 && \
    fluent-gem sources --clear-all && \
    apk del .build-deps && \
    rm -rf /var/cache/apk/* /var/tmp/* /tmp/*

COPY --from=timezone /etc/localtime /etc/localtime
