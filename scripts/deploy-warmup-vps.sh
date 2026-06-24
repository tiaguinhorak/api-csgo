#!/usr/bin/env bash
# Legacy alias — public/warmup stack
exec "$(dirname "$0")/deploy-unified.sh" --profile=warmup "$@"
