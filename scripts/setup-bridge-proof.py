#!/usr/bin/env python3
"""Register a read-only or explicitly write-enabled API host in a dedicated QA root."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shlex
import stat
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--variant', choices=['debug','release'], required=True)
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--browser-root', type=Path, required=True)
parser.add_argument('--workspace', type=Path, required=True)
parser.add_argument('--enable-api-test-writes', action='store_true')
args = parser.parse_args()
root=Path(__file__).resolve().parent.parent
for folder in [args.browser_root,args.workspace,args.app]:
    if not folder.is_absolute() or folder.resolve()!=folder or folder.is_symlink() or not folder.is_dir():
        raise SystemExit('Use existing canonical directories')
for folder, marker in [(args.browser_root,'Galmuri dedicated Chrome proof v1\n'), (args.workspace,'Galmuri pairing-only proof v1\n')]:
    folder_info=folder.stat()
    if folder_info.st_uid!=os.geteuid() or folder_info.st_mode & 0o077:
        raise SystemExit('Dedicated proof directories must be private and owned by this user')
    path=folder/'.galmuri-bridge-proof'; info=path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid!=os.geteuid() or info.st_nlink!=1 or info.st_mode & 0o077 or path.read_text()!=marker:
        raise SystemExit('Dedicated private proof marker required')
identity=json.loads((root/'Config/BridgeIdentities.json').read_text())[args.variant]
if args.enable_api_test_writes:
    for folder in [args.browser_root,args.workspace]:
        marker=folder/'.galmuri-api-write';info=marker.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_uid!=os.geteuid() or info.st_nlink!=1 or info.st_mode & 0o077 or marker.read_text()!='Galmuri dedicated API write proof v1\n':
            raise SystemExit('Explicit dedicated API-write markers required')
build=json.loads((root/'Config/BuildIdentities.json').read_text())[args.variant]
info=plistlib.loads((args.app/'Contents/Info.plist').read_bytes())
if info['CFBundleIdentifier']!=build['bundleIdentifier'] or info['GalmuriBuildConfiguration']!=args.variant:
    raise SystemExit('Wrong app variant')
subprocess.run(['codesign','--verify','--strict',str(args.app)],check=True)
helper=args.app/'Contents/Helpers/GalmuriBridgeHost'
if not helper.is_file(): raise SystemExit('Native host is not packaged')
configuration=json.loads((args.app/'Contents/Resources/BridgeConfiguration.json').read_text())
if configuration!={'variant':args.variant,'bundleIdentifier':build['bundleIdentifier'],'extensionID':identity['extensionID']}:
    raise SystemExit('Native host configuration mismatch')
launcher=args.workspace/('launch-'+args.variant+'.sh')
text='#!/bin/sh\nexec '+shlex.quote(str(helper))+' "$@" --proof-workspace '+shlex.quote(str(args.workspace))+'\n'
if args.enable_api_test_writes: text=text.rstrip()+' --api-test-writes\n'
folder=args.browser_root/'NativeMessagingHosts'
folder.mkdir(mode=0o700,exist_ok=True)
if folder.resolve()!=folder or folder.is_symlink(): raise SystemExit('Redirected host directory')
manifest=folder/(identity['nativeHost']+'.json')
body=json.dumps({'name':identity['nativeHost'],'description':'Galmuri dedicated API bridge proof','path':str(launcher),'type':'stdio','allowed_origins':['chrome-extension://'+identity['extensionID']+'/']},indent=2)+'\n'
if any(path.exists() or path.is_symlink() for path in (launcher,manifest)): raise SystemExit('Proof setup already exists; inspect it instead of overwriting')
for path,value,mode in [(launcher,text,0o700),(manifest,body,0o600)]:
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,mode)
    with os.fdopen(fd,'w') as output: output.write(value)
print(json.dumps({'nativeHost':identity['nativeHost'],'extensionID':identity['extensionID'],'registeredOnlyInDedicatedRoot':True}))
