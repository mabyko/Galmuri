#!/usr/bin/env python3
"""Build the profile-paired experimental extension; never install into a browser profile."""
import base64
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys

root = Path(__file__).resolve().parent.parent
variant = sys.argv[1] if len(sys.argv) == 2 else ''
if variant not in ('debug', 'release'):
    raise SystemExit('Use debug or release')
identities = json.loads((root / 'Config/BridgeIdentities.json').read_text())
identity = identities[variant]
expected = ''.join(chr(97 + (b >> 4)) + chr(97 + (b & 15)) for b in hashlib.sha256(base64.b64decode(identity['extensionKey'], validate=True)).digest()[:16])
if expected != identity['extensionID'] or not re.fullmatch(r'[a-p]{32}', expected):
    raise SystemExit('Extension key/ID mismatch')
if len({x['extensionID'] for x in identities.values()}) != 2 or identity['nativeHost'] != ('forked.galmuri.local.bridge' if variant == 'debug' else 'forked.galmuri.local.release.bridge'):
    raise SystemExit('Bridge identities must remain isolated')
output = root / 'build/bridge' / variant
output.mkdir(parents=True, exist_ok=True)
if output.resolve() != output:
    raise SystemExit('Redirected extension output')
for name in ['manifest.json', 'config.js'] + [p.name for p in (root / 'Bridge/extension').iterdir()]:
    if (output / name).is_symlink():
        raise SystemExit('Redirected extension file')
for path in (root / 'Bridge/extension').iterdir():
    if not path.is_file() or path.is_symlink():
        raise SystemExit('Unexpected extension source')
    shutil.copy2(path, output / path.name)
manifest = {'manifest_version': 3, 'name': 'Galmuri Chrome Bridge' + (' Dev' if variant == 'debug' else ''), 'version': '0.1.0', 'minimum_chrome_version': '134', 'key': identity['extensionKey'], 'permissions': ['nativeMessaging', 'storage', 'bookmarks'], 'action': {'default_popup': 'launcher.html'}, 'options_ui': {'page': 'popup.html', 'open_in_tab': True}}
# API calls remain behind explicit pairing; no content scripts or host-site permissions.
(output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
(output / 'config.js').write_text('export const configuration = ' + json.dumps({'host': identity['nativeHost'], 'variant': variant}) + ';\n')
print(output)
