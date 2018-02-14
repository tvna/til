FROM fluent/fluentd

RUN set -ex \
    && gem install \
        fluent-plugin-elasticsearch --no-rdoc --no-ri --version 1.9.2 \
    && gem sources --clear-all
