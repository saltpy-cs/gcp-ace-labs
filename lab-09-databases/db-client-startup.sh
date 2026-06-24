#!/bin/bash
# Startup script for lab09-db-client VM.
# Installs postgresql-client (psql) and the Cloud SQL Auth Proxy binary.

set -euo pipefail

apt-get update -y
apt-get install -y postgresql-client redis-tools

curl -o /usr/local/bin/cloud-sql-proxy \
  https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.11.0/cloud-sql-proxy.linux.amd64
chmod +x /usr/local/bin/cloud-sql-proxy

touch /tmp/startup-complete
