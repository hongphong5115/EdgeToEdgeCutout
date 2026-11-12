# Build Guide (A to Z, No Gradle)

This project compiles directly with standard JDK + Android SDK command-line tools (`aapt2`, `javac`, `jar`, `D8/R8`, `zipalign`, `apksigner`) without needing Gradle or Android Studio.

## Prerequisites

1. **Windows PowerShell 5.1+** or **PowerShell 7+** (`pwsh`).
2. **JDK 25** (or another JDK supporting `--release 11`, `javac`, `jar`, `keytool`, and `java` on `PATH` or installed under `Eclipse Adoptium` / `Java`).
3. **Python 3** (optional, for running `scripts/verify.py`).
4. Internet access on first run of `bootstrap.ps1` (unless tools are already cached locally or placed in `./tools` or `../tools`).

## Step 1: Verify Source Metadata

```powershell
python .\scripts\verify.py
```

This checks `AndroidManifest.xml`, `res/values/arrays.xml`, `assets/xposed_init`, `HookEntry.java`, and `tools.lock.json`.

## Step 2: Fetch & Verify Toolchain (`bootstrap.ps1`)

All pinned artifacts and SHA-256 checksums live in [`tools.lock.json`](../tools.lock.json):

| Artifact | Purpose |
| :--- | :--- |
| `platform33.zip` | Provides `android.jar` (Android API 33 compile/D8 library stub) |
| `buildtools34.zip` | Provides `aapt2.exe`, `zipalign.exe`, and `apksigner.jar` |
| `r8-current.jar` | R8/D8 `9.5.29` compiler (`com.android.tools.r8.D8`) |
| `xposed-api82.jar` | Compile-only Xposed API 82 jar (`IXposedHookLoadPackage`, `XC_MethodHook`) |

Run:

```powershell
./bootstrap.ps1
```

If you already store downloaded archives in another folder (for example `..\tools`), pass `-CacheDirectory ..\tools`:

```powershell
./bootstrap.ps1 -CacheDirectory ..\tools
```

`bootstrap.ps1` validates every archive/jar against its SHA-256 digest in `tools.lock.json` before extracting into `tools/`.

## Step 3: Build & Sign (`build.ps1`)

Run:

```powershell
./build.ps1
```

Or point to an existing tools directory explicitly:

```powershell
./build.ps1 -ToolsDir ..\tools
```

### What `build.ps1` Does Under the Hood

1. **Tool resolution**: Uses `-ToolsDir` if given, otherwise checks `.\tools` and falls back to `..\tools`. Fails early with a clear message telling you to run `./bootstrap.ps1` if any required tool is missing.
2. **Resource compilation (`aapt2 compile` & `aapt2 link`)**:
   - Compiles `res/` into `build/res.zip`.
   - Links `AndroidManifest.xml`, `assets/`, and `build/res.zip` against `android.jar` into `build/unsigned.apk`, generating `R.java` under `build/gen`.
3. **Java compilation (`javac`)**:
   - Compiles `src/**/*.java` and `build/gen/**/*.java` with `--release 11 -encoding UTF-8` against `android.jar` and `xposed-api82.jar`.
   - Packages `.class` files into `build/classes.jar` via `jar cf`.
4. **DEX compilation (`D8` via `r8-current.jar`)**:
   - Runs `java -cp <r8-current.jar> com.android.tools.r8.D8 --min-api 30 --lib <android.jar> --classpath <xposed-api82.jar> --output build\dex build\classes.jar`.
   - Inserts `classes.dex` into `build/unsigned.apk` via `jar uf`.
5. **Alignment (`zipalign`)**:
   - Aligns APK boundaries (`zipalign -f -p 4`) into `build/aligned.apk`.
6. **Persistent signing & verification (`keytool` + `apksigner.jar`)**:
   - Uses `EDGETOEDGE_SIGNING_PASSWORD` if set; otherwise reads or generates a random password in `.local/signing-password.txt` (gitignored) and creates `.local/build-signing.jks` (RSA-2048, validity 3,650 days) on first run.
   - Signs into `build/EdgeToEdgeCutout.apk` and runs `apksigner.jar verify --verbose`.

## Why `r8-current.jar` Instead of `buildtools34\d8.bat`?

When compiling Java sources with JDK 25 (even with `--release 11`), `build-tools` 34's bundled `d8.bat` (R8 `8.2.2-dev`) throws a `NullPointerException` on nested/anonymous classes (`HookEntry$1.class`). Running `D8` from `r8-current.jar` (`9.5.29`) avoids this crash cleanly.

## Step 4: Verify Output APK

```powershell
python .\scripts\verify.py --apk .\build\EdgeToEdgeCutout.apk
```

Checks that `AndroidManifest.xml`, `resources.arsc`, `assets/xposed_init`, `classes.dex` (containing `Ldev/phong/edgetoedge/HookEntry;`), and an APK signature are all present.

## Step 5: Install on Device

Standard ADB install:

```powershell
adb install -r .\build\EdgeToEdgeCutout.apk
```

On ColorOS / Realme UI devices where USB-ADB installation is blocked by `INSTALL_FAILED_USER_RESTRICTED` or similar OEM restrictions, push and install via root shell:

```powershell
adb push .\build\EdgeToEdgeCutout.apk /data/local/tmp/EdgeToEdgeCutout.apk
adb shell su -c "pm install -r /data/local/tmp/EdgeToEdgeCutout.apk"
```

> **Note:** If you previously installed an APK signed with a different temporary keystore, uninstall the existing package (`adb uninstall dev.phong.edgetoedge`) before installing the `.local/build-signing.jks`-signed APK. Subsequent rebuilds reuse `.local/build-signing.jks` automatically.
