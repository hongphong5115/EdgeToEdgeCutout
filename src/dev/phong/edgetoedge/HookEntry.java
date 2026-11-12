package dev.phong.edgetoedge;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Insets;
import android.os.Bundle;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowManager;

import java.util.Collections;
import java.util.Set;
import java.util.WeakHashMap;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/**
 * LSPosed entry point forcing Type A (transparent edge-to-edge) status bar display
 * into the display cutout while keeping bottom IME/navigation insets intact.
 */
public class HookEntry implements IXposedHookLoadPackage {

    private static final String TAG = "EdgeToEdgeCutout";
    private static final Set<View> HOOKED_CONTENT_VIEWS =
            Collections.synchronizedSet(Collections.newSetFromMap(new WeakHashMap<>()));
    private static volatile boolean sHooksInstalled = false;

    @Override
    public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lpparam) {
        String pkg = lpparam.packageName;
        if (pkg == null || "android".equals(pkg) || "com.android.systemui".equals(pkg)) {
            return;
        }
        if (sHooksInstalled) {
            return;
        }
        sHooksInstalled = true;

        hookActivityLifecycle();
        hookPhoneWindow(lpparam.classLoader);
    }

    private void hookActivityLifecycle() {
        XC_MethodHook applyHook = new XC_MethodHook() {
            @Override
            protected void afterHookedMethod(MethodHookParam param) {
                Activity activity = (Activity) param.thisObject;
                if (activity != null && !activity.isFinishing()) {
                    applyEdgeToEdge(activity);
                }
            }
        };

        try {
            XposedHelpers.findAndHookMethod(Activity.class, "onCreate", Bundle.class, applyHook);
            XposedHelpers.findAndHookMethod(Activity.class, "onPostResume", applyHook);
        } catch (Throwable t) {
            XposedBridge.log(TAG + ": failed hooking Activity lifecycle: " + t);
        }
    }

    private void hookPhoneWindow(ClassLoader classLoader) {
        Class<?> phoneWindowClass = XposedHelpers.findClassIfExists(
                "com.android.internal.policy.PhoneWindow", classLoader);
        if (phoneWindowClass == null) {
            return;
        }

        try {
            XposedHelpers.findAndHookMethod(phoneWindowClass, "setStatusBarColor", int.class,
                    new XC_MethodHook() {
                        @Override
                        protected void beforeHookedMethod(MethodHookParam param) {
                            Window window = (Window) param.thisObject;
                            if (window != null && !window.isFloating()) {
                                param.args[0] = Color.TRANSPARENT;
                            }
                        }
                    });
        } catch (Throwable t) {
            XposedBridge.log(TAG + ": failed hooking setStatusBarColor: " + t);
        }

        try {
            XposedHelpers.findAndHookMethod(phoneWindowClass, "setDecorFitsSystemWindows", boolean.class,
                    new XC_MethodHook() {
                        @Override
                        protected void beforeHookedMethod(MethodHookParam param) {
                            Window window = (Window) param.thisObject;
                            if (window != null && !window.isFloating()) {
                                param.args[0] = false;
                            }
                        }
                    });
        } catch (Throwable t) {
            XposedBridge.log(TAG + ": failed hooking setDecorFitsSystemWindows: " + t);
        }
    }

    private static void applyEdgeToEdge(Activity activity) {
        Window window = activity.getWindow();
        if (window == null || window.isFloating()) {
            return;
        }

        WindowManager.LayoutParams lp = window.getAttributes();
        if (lp != null && lp.layoutInDisplayCutoutMode
                != WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES) {
            lp.layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
            window.setAttributes(lp);
        }

        window.setStatusBarColor(Color.TRANSPARENT);
        window.setDecorFitsSystemWindows(false);

        View content = window.findViewById(android.R.id.content);
        if (content != null && HOOKED_CONTENT_VIEWS.add(content)) {
            content.setOnApplyWindowInsetsListener((v, insets) -> {
                Insets bottomAndNav = insets.getInsets(
                        WindowInsets.Type.ime() | WindowInsets.Type.navigationBars());
                v.setPadding(bottomAndNav.left, 0, bottomAndNav.right, bottomAndNav.bottom);

                WindowInsets stripped = new WindowInsets.Builder(insets)
                        .setInsets(WindowInsets.Type.statusBars(), Insets.NONE)
                        .setInsets(WindowInsets.Type.displayCutout(), Insets.NONE)
                        .setInsets(WindowInsets.Type.navigationBars(), Insets.NONE)
                        .setInsets(WindowInsets.Type.ime(), Insets.NONE)
                        .setInsetsIgnoringVisibility(WindowInsets.Type.statusBars(), Insets.NONE)
                        .setInsetsIgnoringVisibility(WindowInsets.Type.navigationBars(), Insets.NONE)
                        .setDisplayCutout(null)
                        .build();
                return v.onApplyWindowInsets(stripped);
            });
            content.requestApplyInsets();
        }
    }
}
