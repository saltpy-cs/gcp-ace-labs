#!/bin/bash
# Delegates to the top-level status script
exec "$(dirname "$0")/../status.sh" "$@"
