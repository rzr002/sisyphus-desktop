#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/cache .build/clang
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang"
command="$1"
shift
exec swift "$command" --cache-path "$PWD/.build/cache" --disable-sandbox "$@"
