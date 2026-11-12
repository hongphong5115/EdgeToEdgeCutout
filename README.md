tui vai code bang gemini 3.8 flash
# EdgeToEdgeCutout

An open-source, minimal LSPosed/Xposed module (`dev.phong.edgetoedge`) that eliminates the black status bar band on Android 11+ (`minSdk 30`, `targetSdk 33`) devices by enforcing transparent edge-to-edge rendering and `shortEdges` display cutout mode for scoped applications.

Built with a **zero-Gradle, reproducible PowerShell + lockfile toolchain** (`aapt2`, `javac`, `R8/D8`, `zipalign`, `apksigner`) with SHA-256 verification and GitHub Actions CI.

## Features

- **Type A Edge-to-Edge Cutout Fix**: Sets `LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES`, makes the status bar transparent, and sets `decorFitsSystemWindows(false)` while keeping status bar icons visible.
- **IME & Navigation Bar Safe**: Strips top `statusBars()` / `displayCutout()` insets on `android:id/content` while preserving bottom `ime()` and `navigationBars()` padding so keyboards and gesture bars do not overlap UI controls.
- **Scoped by Default**: Targets `com.facebook.katana` via [`res/values/arrays.xml`](res/values/arrays.xml) (`@array/xposed_scope`) and skips `android` and `com.android.systemui` in code.
- **Transparent A-to-Z Build**: No Gradle wrapper, no hidden IDE config — every compiler step and pinned dependency hash is inspected in [`tools.lock.json`](tools.lock.json), [`bootstrap.ps1`](bootstrap.ps1), and [`build.ps1`](build.ps1).

## Repository Layout

```text
EdgeToEdgeCutout/
├── .github/workflows/build.yml   # Windows CI pipeline (verify -> bootstrap -> build -> verify APK)
├── assets/xposed_init            # Xposed entry point declaration
├── docs/
│   ├── ARCHITECTURE.md           # Window/inset hooking design & device findings
│   └── BUILD.md                  # Full A-to-Z manual build & install walkthrough
├── res/values/arrays.xml         # Default LSPosed scope (@array/xposed_scope)
├── scripts/verify.py             # Source & output APK verification script
├── src/dev/phong/edgetoedge/
│   └── HookEntry.java            # Core LSPosed hook implementation
├── .gitignore
├── AndroidManifest.xml
├── CONTRIBUTING.md               # Contribution & PR verification guidelines
├── LICENSE                       # MIT License
├── README.md
├── SECURITY.md                   # Security policy & scope isolation notes
├── bootstrap.ps1                 # Downloads & SHA-256-verifies pinned Android/Xposed tools
├── build.ps1                     # Compiles, dexes, aligns, signs, and verifies APK
└── tools.lock.json               # Pinned tool URLs + SHA-256 checksums
```

## Quick Start (A to Z)

### 1. Verify Source

```powershell
python .\scripts\verify.py
```

### 2. Download & Verify Toolchain

```powershell
./bootstrap.ps1
```

(If you already have the locked zip/jar files cached in `..\tools`, you can pass `./bootstrap.ps1 -CacheDirectory ..\tools`, or skip directly to `./build.ps1` which auto-detects `.\tools` or `..\tools`.)

### 3. Build & Sign APK

```powershell
./build.ps1
```

Output: `build/EdgeToEdgeCutout.apk` (signed with a persistent local keystore created in `.local/build-signing.jks` and verified via `apksigner.jar verify --verbose`).

### 4. Verify Built APK

```powershell
python .\scripts\verify.py --apk .\build\EdgeToEdgeCutout.apk
```

### 5. Install & Enable in LSPosed

1. Install `build/EdgeToEdgeCutout.apk` (`adb install -r` or `su -c "pm install -r ..."` on ColorOS — see [docs/BUILD.md](docs/BUILD.md)).
2. Open **LSPosed Manager** -> **Modules** -> enable **EdgeToEdge Cutout**.
3. Ensure target apps (e.g., Facebook `com.facebook.katana`) are checked in scope.
4. Force-stop and relaunch the target app.

## Customizing Target Scope

You can toggle additional apps directly inside LSPosed Manager's module scope UI, or edit [`res/values/arrays.xml`](res/values/arrays.xml) to change the default recommended scope list before building.

## Documentation

- [docs/BUILD.md](docs/BUILD.md) — Step-by-step toolchain breakdown, keystore persistence, and troubleshooting.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Root-cause analysis on Android 13 / ColorOS (`RMX3370`) and how `HookEntry.java` handles `PhoneWindow` and `WindowInsets`.

## License

[MIT](LICENSE)
