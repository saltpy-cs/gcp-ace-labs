#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx

# Install Ops Agent
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
bash add-google-cloud-ops-agent-repo.sh --also-install

# Configure Ops Agent:
#   - journald receiver: captures logger/syslog output (Debian 12 default; rsyslog not bridging)
#   - nginx receivers: read access and error log files into separate Cloud Logging log names
cat > /etc/google-cloud-ops-agent/config.yaml << 'EOF'
logging:
  receivers:
    journald:
      type: systemd_journald
    nginx_access:
      type: files
      include_paths:
        - /var/log/nginx/access.log
    nginx_error:
      type: files
      include_paths:
        - /var/log/nginx/error.log
  service:
    pipelines:
      default_pipeline:
        receivers: [journald, nginx_access, nginx_error]
EOF

systemctl restart google-cloud-ops-agent
sleep 5

systemctl enable nginx 2>/dev/null
systemctl start nginx

logger -p user.info    -t lab10-app "INFO: nginx started successfully"
logger -p user.warning -t lab10-app "WARNING: high memory threshold approaching"
logger -p user.err     -t lab10-app "ERROR: simulated application error for lab exercise"

touch /tmp/startup-complete
