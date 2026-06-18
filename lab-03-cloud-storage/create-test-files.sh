#!/bin/bash
set -euo pipefail

LAB_DIR="$(cd "$(dirname "$0")" && pwd)/work"

echo "Hello from Lab 03" > "$LAB_DIR/hello.txt"
echo "Config file content" > "$LAB_DIR/config.json"
dd if=/dev/urandom bs=1024 count=100 2>/dev/null | base64 > "$LAB_DIR/binary-data.txt"
echo "This file will be deleted" > "$LAB_DIR/temp.txt"

echo "Created test files in $LAB_DIR:"
ls -lh "$LAB_DIR"
