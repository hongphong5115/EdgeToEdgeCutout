# Security Policy

## Supported Versions

| Version | Supported |
| :--- | :--- |
| `1.0` (`main`) | Yes |

## Runtime Scope & Isolation

`EdgeToEdgeCutout` is designed with minimal privilege and narrow process scope:

- Declared `xposedscope` in `AndroidManifest.xml` (`@array/xposed_scope`) defaults only to `com.facebook.katana`.
- `HookEntry.java` defensively skips `android` and `com.android.systemui` at runtime.
- No network permissions, file I/O hooks, IPC services, or telemetry are included in the module.

## Signing Keys & Local Secrets

- Release and local test APKs are signed with `build.ps1`, which stores local signing keystores and passwords exclusively inside `.local/` (gitignored).
- Never commit `.local/`, `*.jks`, `*.keystore`, or `signing-password.txt`.
- Release artifacts include `SHA256SUMS.txt` so downloads can be verified before installation.

## Reporting a Vulnerability

If you discover a security or stability vulnerability (for example, an unsafe hook, unintended process injection, or build-pipeline integrity issue), please report it via GitHub Security Advisories or open an issue without posting private credentials or device logs containing sensitive tokens.
