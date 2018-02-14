#!/bin/bash
# $1 = usrname
# $2 = password
# $3 = VIRTUAL_HOST
docker run --rm httpd:alpine htpasswd -nb -s $1 $2 >> ~/.htpasswd/$3
echo [RESULT] $HOME/.htpasswd/$3
cat ~/.htpasswd/$3
