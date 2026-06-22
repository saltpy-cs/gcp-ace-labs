#!/bin/bash
apt-get update -y
apt-get install -y nginx
INSTANCE_NAME=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/name" -H "Metadata-Flavor: Google")
ZONE=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/zone" -H "Metadata-Flavor: Google" | awk -F/ '{print $NF}')
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head><title>Lab 06 - v2</title></head>
<body style="background-color:#e8f5e9">
<h1>Hello from ${INSTANCE_NAME} [v2]</h1>
<p>Zone: ${ZONE}</p>
<p>Version: 2.0 - Green deployment</p>
</body>
</html>
EOF
systemctl enable nginx
systemctl start nginx
