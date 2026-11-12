#!/usr/bin/env python3
"""Package a SwiftPM product without selecting an Apple team or installing it."""
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

root = Path(__file__).resolve().parent.parent
configuration, executable = sys.argv[1:]
identities = json.loads((root / "Config/BuildIdentities.json").read_text())
def require(condition, message):
    if not condition:
        raise ValueError(message)

require(set(identities) == {"debug", "release"}, "Unexpected build configurations")
identifiers = [item["bundleIdentifier"] for item in identities.values()]
require(len(set(identifiers)) == len(identifiers), "Bundle IDs must differ")
for identifier in identifiers:
    require(re.fullmatch(r"[A-Za-z0-9.-]+", identifier) and (identifier == "forked.galmuri.local" or identifier.startswith("forked.galmuri.local.")), "Only validated sacrificial identities are allowed")
identity = identities[configuration]
require(identity["displayName"] in ("Galmuri", "Galmuri Dev"), "Unexpected product name")
output = root / "build" / configuration / (identity["displayName"] + ".app")
output.parent.mkdir(parents=True, exist_ok=True)
require(output.parent.resolve() == output.parent and not output.is_symlink(), "Unexpected output redirection")
if output.exists():
    old_info = plistlib.loads((output / "Contents/Info.plist").read_bytes())
    require(old_info["CFBundleIdentifier"] == identity["bundleIdentifier"] and old_info["GalmuriBuildConfiguration"] == configuration, "Unrecognized existing build output")
    processes = subprocess.run(["/bin/ps", "-axww", "-o", "comm="], check=True, capture_output=True, text=True).stdout.splitlines()
    if any(line.strip().startswith(str(output) + "/") for line in processes):
        raise SystemExit("Build output is running. Normally quit that exact app before repackaging.")
stage = Path(tempfile.mkdtemp(prefix=".package-", dir=output.parent))
candidate = stage / output.name
resources = candidate / "Contents/Resources"
resources.mkdir(parents=True)
(candidate / "Contents/MacOS").mkdir()
shutil.copy2(executable, candidate / "Contents/MacOS/Galmuri")
asset_info = stage / "asset-info.plist"
try:
    bridge = json.loads((root / "Config/BridgeIdentities.json").read_text())[configuration]
    helper_source = Path(executable).resolve().parent / "GalmuriBridgeHost"
    require(helper_source.is_file(), "Build GalmuriBridgeHost before packaging")
    helpers = candidate / "Contents/Helpers"
    helpers.mkdir()
    shutil.copy2(helper_source, helpers / "GalmuriBridgeHost")
    # Ship only the explicitly built extension files, never browser/profile data.
    subprocess.run([sys.executable, str(root / "scripts/build-bridge.py"), configuration], check=True)
    extension = root / "build/bridge" / configuration
    names = {p.name for p in (root / "Bridge/extension").iterdir()} | {"manifest.json", "config.js"}
    with zipfile.ZipFile(resources / "Galmuri-Chrome-Extension.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(names):
            archive.write(extension / name, "Galmuri-Chrome-Extension/" + name)
    (resources / "BridgeConfiguration.json").write_text(json.dumps({"variant": configuration, "bundleIdentifier": identity["bundleIdentifier"], "extensionID": bridge["extensionID"]}) + "\n")
    subprocess.run(["codesign", "--force", "--sign", "-", "--identifier", bridge["nativeHost"], str(helpers / "GalmuriBridgeHost")], check=True)
    subprocess.run(["xcrun", "actool", str(root / "Assets/Assets.xcassets"), "--compile", str(resources), "--platform", "macosx", "--minimum-deployment-target", "14.0", "--target-device", "mac", "--app-icon", identity["appIcon"], "--output-partial-info-plist", str(asset_info), "--warnings", "--errors", "--notices"], check=True)
    info = plistlib.loads((root / "Config/Info.plist").read_bytes())
    info.update(plistlib.loads(asset_info.read_bytes()))
    info.update(CFBundleIdentifier=identity["bundleIdentifier"], CFBundleName=identity["displayName"], CFBundleDisplayName=identity["displayName"], GalmuriBuildConfiguration=configuration)
    (candidate / "Contents/Info.plist").write_bytes(plistlib.dumps(info, sort_keys=False))
    subprocess.run(["xcrun", "xcstringstool", "compile", str(root / "localization/Localizable.xcstrings"), "--output-directory", str(resources)], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", "--identifier", identity["bundleIdentifier"], str(candidate)], check=True)
    subprocess.run(["codesign", "--verify", "--strict", str(candidate)], check=True)
    previous = stage / "previous.app"
    if output.exists():
        os.rename(output, previous)
    try:
        require(not output.exists() and not output.is_symlink(), "Output appeared during packaging")
        os.rename(candidate, output)
    except BaseException:
        if previous.exists() and not output.exists():
            os.rename(previous, output)
        raise
    shutil.rmtree(stage)
except BaseException:
    print(f"Packaging failed; review staging/recovery files at {stage}", file=sys.stderr)
    raise
print(output)
