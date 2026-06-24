#!/bin/bash
apt-get update -y
apt-get install -y nginx
systemctl enable nginx
systemctl start nginx
# Write structured log lines to syslog for the lab logging exercises
logger -t lab10-app "INFO: nginx started successfully"
logger -t lab10-app "WARNING: high memory threshold approaching"
logger -t lab10-app "ERROR: simulated application error for lab exercise"
