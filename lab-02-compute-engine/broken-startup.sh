#!/bin/bash
set -euxo pipefail

apt-get update -y

# Intentional error: package does not exist
apt-get install -y totally-fake-package-that-does-not-exist

# This line will never be reached
apt-get install -y nginx
systemctl start nginx
