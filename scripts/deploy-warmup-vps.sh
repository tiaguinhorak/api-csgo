#!/usr/bin/env bash
# Legacy alias — public/warmup stack
exec bash "$(dirname "$0")/deploy-unified.sh" --profile=warmup "$@"
