#!/usr/bin/env python3
"""Run the app's in-process native integration check, without touching user windows."""
import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent
result = subprocess.run([str(root / '.build/debug/Sisyphus'), '--verify-native'], capture_output=True, text=True, timeout=20)
try:
    report = json.loads(result.stdout)
except json.JSONDecodeError:
    raise SystemExit('FAIL: native application integration report is missing: ' + result.stdout + result.stderr)
assert result.returncode == 0, report
assert report['checks'] and all(report['checks'].values()), report
if report.get('screenCapturePermission'):
    assert report['checks'].get('screenTerrainReadback'), 'FAIL: ScreenCaptureKit path has not been verified'
print(json.dumps(report, ensure_ascii=False, indent=2))
