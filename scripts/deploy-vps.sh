#!/usr/bin/env bash
# Legacy alias — ranked profile
exec "$(dirname "$0")/deploy-unified.sh" --profile=ranked "$@"
