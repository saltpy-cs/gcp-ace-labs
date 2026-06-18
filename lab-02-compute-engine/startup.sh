#!/bin/bash
set -euxo pipefail

apt-get update -y
apt-get install -y nginx jq

# Write a custom index page that identifies this instance
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
