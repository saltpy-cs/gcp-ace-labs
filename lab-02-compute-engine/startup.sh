#!/bin/bash
set -euxo pipefail

apt-get update -y
apt-get install -y nginx jq

# Stop nginx while we update the index page so it doesn't serve stale content
systemctl stop nginx || true

INSTANCE_NAME=$(curl -sf -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/name)
ZONE=$(curl -sf -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/zone | awk -F/ '{print $NF}')

cat > /var/www/html/index.html << HTML
<html><body>
<h1>Hello from $INSTANCE_NAME in $ZONE</h1>
</body></html>
HTML

systemctl enable nginx
systemctl start nginx
