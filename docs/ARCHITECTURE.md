# Architecture: EdgeToEdgeCutout

`EdgeToEdgeCutout` is a minimal LSPosed/Xposed module that enforces a transparent edge-to-edge status bar and `shortEdges` cutout rendering for scoped Android apps without installing custom system overlays or rewriting APK files.

## Problem Background

On devices such as `RMX3370` (Android 13 / ColorOS `RMX3370_13.1.0.601(CN01)`), apps that do not opt into full edge-to-edge cutout flags—or encounter OEM top-bar compatibility behavior—can end up with an opaque black status bar band (observed at `0..110 px` on `com.facebook.katana` v586.0.0.52.53). When `DecorView` places `android:id/content` below the status bar (`0,110-1080,2400`), the camera cutout region renders as a solid black bar instead of letting app content draw underneath a transparent status bar.

## Why Type A (Edge-to-Edge Transparent Status Bar)?

There are two ways to handle a black cutout band:

1. **Type A — Transparent Edge-to-Edge (implemented):** Allow the window to extend into `LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES`, make the status bar transparent, disable `decorFitsSystemWindows`, and selectively strip top system/cutout insets from `android:id/content` while keeping bottom `ime` and `navigationBars` insets intact.
2. **Type B — Fullscreen Immersive / Hide Status Bar:** Hides status bar icons completely, which requires swipe gestures to peek at time/battery/notifications.

Type A removes the black band while preserving status bar icons (clock, battery, network) and avoiding keyboard (`IME`) overlap.

## How the Hook Works

Entry point: [`HookEntry.java`](../src/dev/phong/edgetoedge/HookEntry.java) registered via [`assets/xposed_init`](../assets/xposed_init).

### 1. Package Filtering
In `handleLoadPackage(XC_LoadPackage.LoadPackageParam lpparam)`:
- Skips `android` and `com.android.systemui` defensively so system processes are never altered even if misconfigured.
- Relies on [`xposedscope`](../res/values/arrays.xml) in [`AndroidManifest.xml`](../AndroidManifest.xml) (default: `com.facebook.katana`) so LSPosed only injects into user-selected apps.

### 2. Lifecycle & Window Setter Hooks
- **`Activity.onCreate(Bundle)`** (`afterHookedMethod`): applies edge-to-edge configuration as soon as the activity window is initialized.
- **`Activity.onPostResume()`** (`afterHookedMethod`): re-applies settings after resume transitions in case the app or OEM theme resets flags.
- **`com.android.internal.policy.PhoneWindow.setStatusBarColor(int)`** (`beforeHookedMethod`): overrides non-floating window status bar color arguments back to `Color.TRANSPARENT`.
- **`com.android.internal.policy.PhoneWindow.setDecorFitsSystemWindows(boolean)`** (`beforeHookedMethod`): forces `decorFitsSystemWindows` to `false` on non-floating windows so the app cannot re-enable top system-bar padding at the decor layer.

### 3. `WindowInsets` Filtering on `android:id/content`
In `applyEdgeToEdge(Activity)`:
1. Ignores dialogs/floating overlays (`window == null || window.isFloating()`).
2. Sets `WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES` on `window.getAttributes()` (Android 11+ / `minSdk 30`).
3. Calls `window.setStatusBarColor(Color.TRANSPARENT)` and `window.setDecorFitsSystemWindows(false)`.
4. Attaches a `View.OnApplyWindowInsetsListener` to `window.findViewById(android.R.id.content)`, tracked per-view in a synchronized `WeakHashMap<View, Boolean>` (`HOOKED_CONTENT_VIEWS`) to avoid duplicate listeners or memory leaks:
   - Reads `Insets ime = insets.getInsets(WindowInsets.Type.ime())` and `Insets nav = insets.getInsets(WindowInsets.Type.navigationBars())`.
   - Applies content padding `(Math.max(ime.left, nav.left), 0, Math.max(ime.right, nav.right), Math.max(ime.bottom, nav.bottom))` so top is `0` while navigation bar and keyboard (`IME`) remain respected.
   - Builds a stripped `WindowInsets` via `WindowInsets.Builder(insets)` with `Insets.NONE` for `statusBars()`, `displayCutout()`, `navigationBars()`, and `ime()` before calling `v.onApplyWindowInsets(stripped)`.
   - Requests initial dispatch via `content.requestApplyInsets()`.

## Verified Behavior on Target Device

Tested on `RMX3370` (`com.facebook.katana`) with LSPosed active:
- `layoutInDisplayCutoutMode` confirmed as `shortEdges`.
- `android:id/content` top bound shifted from `110 px` to `0` (`0,0-1080,2400`), rendering app content behind the transparent status bar without a black band.
