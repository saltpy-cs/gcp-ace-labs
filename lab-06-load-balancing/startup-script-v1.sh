#!/bin/bash
apt-get update -y
apt-get install -y nginx
INSTANCE_NAME=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/name" -H "Metadata-Flavor: Google")
ZONE=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/zone" -H "Metadata-Flavor: Google" | awk -F/ '{print $NF}')
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head><title>Lab 06 - Load Balancing</title></head>
<body>
<h1>Hello from ${INSTANCE_NAME}</h1>
<p>Zone: ${ZONE}</p>
<p>Served by: nginx on Compute Engine (MIG)</p>
</body>
</html>
EOF
systemctl enable nginx
systemctl start nginx
