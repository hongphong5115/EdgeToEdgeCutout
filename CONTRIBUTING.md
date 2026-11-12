# Contributing to EdgeToEdgeCutout

Contributions, bug reports, and pull requests are welcome!

## Scope & Design Guidelines

- **Type A only by default:** Keep status bar icons visible (`Color.TRANSPARENT` + `LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES` + `setDecorFitsSystemWindows(false)`). Do not force fullscreen status-bar hiding unless strictly opt-in.
- **Protect system processes:** `HookEntry.java` explicitly ignores `android` and `com.android.systemui`. Preserve those guards.
- **Respect floating windows & IME:** Do not strip `ime()` or `navigationBars()` bottom/side padding from `android:id/content`, and skip `window.isFloating()` dialogs/overlays.
- **Zero-Gradle toolchain:** Keep builds runnable via `./bootstrap.ps1` and `./build.ps1` using pinned hashes in `tools.lock.json`.

## Before Opening a Pull Request

Run the verification suite and build locally:

```powershell
python .\scripts\verify.py
./build.ps1
python .\scripts\verify.py --apk .\build\EdgeToEdgeCutout.apk
```

Do not commit `build/`, `tools/`, `.local/`, keystores (`*.jks`, `*.keystore`), or signing passwords.

## Reporting Device Compatibility Issues

When opening an issue for a specific app or ROM, include:
1. Device model & Android / OEM skin version (e.g., `RMX3370`, Android 13 / ColorOS).
2. LSPosed version & target app package/version.
3. Relevant window bounds from `dumpsys window windows` or `uiautomator dump` plus LSPosed log lines.
