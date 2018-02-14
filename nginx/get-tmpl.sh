#!/bin/bash
docker run --rm jwilder/nginx-proxy cat nginx.tmpl > nginx.tmpl
echo [RESULT] $(pwd)/nginx.tmpl
cat $(pwd)/nginx.tmpl
