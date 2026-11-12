#!/usr/bin/env python3
"""Check the downloadable Release source folder and a packaged matching ZIP."""
import base64
import hashlib
import json
from pathlib import Path
import plistlib
import sys
import zipfile

root = Path(__file__).resolve().parent.parent
source = root / 'Bridge/extension'
identities = json.loads((root / 'Config/BridgeIdentities.json').read_text())

def check(files, variant):
    identity = identities[variant]
    manifest = json.loads(files['manifest.json'])
    expected_id = ''.join(chr(97 + (b >> 4)) + chr(97 + (b & 15)) for b in hashlib.sha256(base64.b64decode(manifest['key'], validate=True)).digest()[:16])
    assert expected_id == identity['extensionID']
    assert manifest['manifest_version'] == 3
    assert set(manifest['permissions']) == {'bookmarks', 'nativeMessaging', 'storage'}
    assert not any(key in manifest for key in ['host_permissions', 'content_scripts', 'externally_connectable', 'background'])
    assert manifest['action']['default_popup'] in files and manifest['options_ui']['page'] in files
    config = files['config.js'].decode()
    assert config.startswith('export const configuration = ') and config.endswith(';\n')
    assert json.loads(config.removeprefix('export const configuration = ').removesuffix(';\n')) == {'host': identity['nativeHost'], 'variant': variant}
    assert all(key in files for key in ['client.mjs', 'api-client.mjs', 'bookmarks.mjs', 'README.md', 'LICENSE'])

files = {p.name: p.read_bytes() for p in source.iterdir() if p.is_file() and not p.is_symlink()}
assert len(files) == len(list(source.iterdir()))
check(files, 'release')
if len(sys.argv) == 2:
    app = Path(sys.argv[1])
    variant = plistlib.loads((app / 'Contents/Info.plist').read_bytes())['GalmuriBuildConfiguration']
    with zipfile.ZipFile(app / 'Contents/Resources/Galmuri-Chrome-Extension.zip') as archive:
        expected = {'Galmuri-Chrome-Extension/' + name for name in files}
        assert set(archive.namelist()) == expected and len(archive.namelist()) == len(expected)
        packed = {name: archive.read('Galmuri-Chrome-Extension/' + name) for name in files}
    check(packed, variant)
    for name in files.keys() - {'manifest.json', 'config.js'}:
        assert packed[name] == files[name], name
    if variant == 'release': assert packed == files
    print(f'{variant} packaged ZIP matches source and isolated identity; no profile data or site permissions')
print('Standalone Release extension folder is ready to load; no build step required')
