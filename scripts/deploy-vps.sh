#!/usr/bin/env bash
# Legacy alias — ranked profile
exec bash "$(dirname "$0")/deploy-unified.sh" --profile=ranked "$@"
