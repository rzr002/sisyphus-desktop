#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ -d /Applications/Sisyphus.app ]; then
  open /Applications/Sisyphus.app
else
  if [ ! -d dist/Sisyphus.app ]; then bash scripts/build-app.sh; fi
  open dist/Sisyphus.app
fi
