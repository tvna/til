#!/bin/bash
docker run --rm guacamole/guacamole /opt/guacamole/bin/initdb.sh --postgres > initdb-postgres.sql
