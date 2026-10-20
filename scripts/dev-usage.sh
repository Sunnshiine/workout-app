#!/bin/bash
# The entry point for scripts/dev-usage.py; scripts/dev-usage.sh --help explains it.
exec python3 -I -S "$(dirname "$0")/dev-usage.py" "$@"
