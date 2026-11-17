#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
project_app="$PWD/dist/Sisyphus.app"
installed_app=/Applications/Sisyphus.app

if [[ ! -d "$project_app" ]]; then
  if [[ -d "$installed_app" ]]; then
    exec open "$installed_app"
  fi
  bash scripts/build-app.sh
fi

# The game is single-instance. An older running installation would keep the
# lock and receive the reopen, even when we pass the project bundle to open.
if [[ -d "$installed_app" ]] && ! cmp -s "$project_app/Contents/MacOS/Sisyphus" "$installed_app/Contents/MacOS/Sisyphus"; then
  /usr/bin/osascript -l JavaScript - "$installed_app" <<'JXA'
ObjC.import('AppKit')
function run(argv) {
  const games = $.NSRunningApplication.runningApplicationsWithBundleIdentifier('studio.leosnow.sisyphus')
  for (let i = 0; i < games.count; i++) {
    const game = games.objectAtIndex(i)
    if (ObjC.unwrap(game.bundleURL.path) !== argv[0]) continue
    game.terminate
    const deadline = Date.now() + 5000
    while (!game.terminated && Date.now() < deadline) {
      $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.1))
    }
    if (!game.terminated) throw Error('请先右键退出旧版 Sisyphus，再打开项目版。')
  }
}
JXA
fi

exec open "$project_app"
