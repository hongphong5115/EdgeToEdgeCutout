#!/usr/bin/env python3
"""Static and APK artifact verification script for EdgeToEdgeCutout."""

from __future__ import annotations

import argparse
import json
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
ROOT = Path(__file__).resolve().parent.parent


def require_file(rel_path: str) -> Path:
    path = ROOT / rel_path
    if not path.is_file():
        raise AssertionError(f"Missing required file: {rel_path}")
    return path


def verify_source() -> None:
    manifest_path = require_file("AndroidManifest.xml")
    arrays_path = require_file("res/values/arrays.xml")
    xposed_init_path = require_file("assets/xposed_init")
    hook_path = require_file("src/dev/phong/edgetoedge/HookEntry.java")
    lock_path = require_file("tools.lock.json")
    require_file("bootstrap.ps1")
    require_file("build.ps1")

    manifest_root = ET.parse(manifest_path).getroot()
    package_name = manifest_root.attrib.get("package")
    if package_name != "dev.phong.edgetoedge":
        raise AssertionError(f"Unexpected manifest package: {package_name!r}")

    uses_sdk = manifest_root.find("uses-sdk")
    if uses_sdk is None:
        raise AssertionError("AndroidManifest.xml is missing <uses-sdk>")
    min_sdk = uses_sdk.attrib.get(f"{ANDROID_NS}minSdkVersion")
    target_sdk = uses_sdk.attrib.get(f"{ANDROID_NS}targetSdkVersion")
    if min_sdk != "30" or target_sdk != "33":
        raise AssertionError(f"Expected minSdk=30, targetSdk=33; got {min_sdk}/{target_sdk}")

    app = manifest_root.find("application")
    if app is None:
        raise AssertionError("AndroidManifest.xml is missing <application>")
    meta = {
        elem.attrib.get(f"{ANDROID_NS}name"): (
            elem.attrib.get(f"{ANDROID_NS}value") or elem.attrib.get(f"{ANDROID_NS}resource")
        )
        for elem in app.findall("meta-data")
    }
    if meta.get("xposedmodule") != "true":
        raise AssertionError("Missing xposedmodule=true meta-data")
    if meta.get("xposedminversion") != "93":
        raise AssertionError(f"Expected xposedminversion=93, got {meta.get('xposedminversion')!r}")
    if meta.get("xposedscope") != "@array/xposed_scope":
        raise AssertionError(f"Expected xposedscope=@array/xposed_scope, got {meta.get('xposedscope')!r}")

    arrays_root = ET.parse(arrays_path).getroot()
    scope_arrays = [
        elem for elem in arrays_root.findall("string-array") if elem.attrib.get("name") == "xposed_scope"
    ]
    if not scope_arrays:
        raise AssertionError("res/values/arrays.xml is missing string-array name='xposed_scope'")
    scope_items = [item.text.strip() for item in scope_arrays[0].findall("item") if item.text]
    if not scope_items:
        raise AssertionError("xposed_scope must contain at least one target package")

    entry_class = xposed_init_path.read_text(encoding="utf-8").strip()
    if entry_class != "dev.phong.edgetoedge.HookEntry":
        raise AssertionError(f"Unexpected assets/xposed_init entry: {entry_class!r}")

    hook_source = hook_path.read_text(encoding="utf-8")
    for required_token in (
        "package dev.phong.edgetoedge;",
        "public class HookEntry implements IXposedHookLoadPackage",
        "LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES",
        "setDecorFitsSystemWindows",
    ):
        if required_token not in hook_source:
            raise AssertionError(f"HookEntry.java missing expected token: {required_token}")

    lock_data = json.loads(lock_path.read_text(encoding="utf-8"))
    if not isinstance(lock_data, list) or len(lock_data) != 4:
        raise AssertionError(f"Expected 4 artifacts in tools.lock.json list, got {type(lock_data).__name__}")
    for artifact in lock_data:
        sha = artifact.get("sha256", "")
        if len(sha) != 64 or any(c not in "0123456789abcdef" for c in sha.lower()):
            raise AssertionError(f"Invalid SHA-256 for {artifact.get('file')!r}: {sha!r}")

    print(
        f"[OK] Source verified: package={package_name}, minSdk={min_sdk}, "
        f"targetSdk={target_sdk}, scope={scope_items}, lock_artifacts={len(lock_data)}"
    )


def verify_apk(apk_path: Path) -> None:
    if not apk_path.is_file():
        raise AssertionError(f"APK not found: {apk_path}")

    with zipfile.ZipFile(apk_path, "r") as zf:
        names = set(zf.namelist())
        for required_entry in ("AndroidManifest.xml", "resources.arsc", "assets/xposed_init", "classes.dex"):
            if required_entry not in names:
                raise AssertionError(f"APK missing required entry: {required_entry}")

        xposed_init = zf.read("assets/xposed_init").decode("utf-8").strip()
        if xposed_init != "dev.phong.edgetoedge.HookEntry":
            raise AssertionError(f"APK assets/xposed_init mismatch: {xposed_init!r}")

        dex_bytes = zf.read("classes.dex")
        if b"Ldev/phong/edgetoedge/HookEntry;" not in dex_bytes:
            raise AssertionError("classes.dex does not contain Ldev/phong/edgetoedge/HookEntry;")

        has_v1_sig = any(name.startswith("META-INF/") and name.endswith(".SF") for name in names)
        raw_apk = apk_path.read_bytes()
        has_v2_v3_sig = b"APK Sig Block 42" in raw_apk
        if not (has_v1_sig or has_v2_v3_sig):
            raise AssertionError("APK does not appear to contain a v1/v2/v3 signature")

    print(f"[OK] APK verified: {apk_path} ({apk_path.stat().st_size} bytes)")


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify EdgeToEdgeCutout source and APK outputs.")
    parser.add_argument("--apk", type=Path, help="Optional path to built APK to inspect.")
    args = parser.parse_args()

    verify_source()
    if args.apk is not None:
        if args.apk.is_absolute():
            apk_resolved = args.apk
        elif (Path.cwd() / args.apk).exists():
            apk_resolved = Path.cwd() / args.apk
        else:
            apk_resolved = ROOT / args.apk
        verify_apk(apk_resolved)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"[FAIL] {exc}", file=sys.stderr)
        raise SystemExit(1)
