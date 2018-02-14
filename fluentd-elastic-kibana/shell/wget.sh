#!/bin/sh

apk --no-cache update
apk --no-cache add wget

while :; \
    do RND=$((20000 * (RANDOM % 10) )); \
    usleep $RND; \
    echo $RND; \
    wget -l 9 http://portal/web/; \
done
