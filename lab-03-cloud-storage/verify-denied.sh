#!/bin/bash
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Usage: $0 <url>"
  echo "Example: $0 \"https://storage.googleapis.com/my-bucket/index.html\""
  exit 1
fi

URL=$1
TIMEOUT=120
ELAPSED=0

echo "Waiting for access to be denied on: $URL"

until [ "$(curl -s -o /dev/null -w "%{http_code}" "$URL")" = "403" ]; do
  if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "Timed out after ${TIMEOUT}s — URL is still accessible."
    exit 1
  fi
  echo "Still accessible... (${ELAPSED}s elapsed)"
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

echo "Access denied (403) confirmed."
