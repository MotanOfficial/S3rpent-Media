# Startup Performance Plan (Open Fast, Load Later)

This app already starts successfully, but startup does too much work before the first frame:

- heavy optional QML/effects initialize immediately
- `BadApple` assets load on startup
- many background systems initialize eagerly
- main scene is fully constructed up-front

Goal: show window *immediately*, then finish non-critical work in the background.

---

## 1) Fast-start strategy

Use a 2-phase startup:

1. **Phase A (instant):** show a minimal shell UI (window + basic controls).
2. **Phase B (deferred):** load optional systems with `Loader`, `Timer`, `Qt.callLater()`.

This removes startup stalls from the critical path.

---

## 2) Highest-impact fixes first

### A. Do not load `BadApple` frames on app startup

Your logs show:

- `[BadApple] Loaded 2523648 bytes...`
- texture creation runs during startup

That should happen only when the effect is used.

#### Patch idea (`src/qml/BadAppleEffect.qml`)

Move frame loading from `Component.onCompleted` to `startPlayback()`:

```qml
// Before: loads on component creation
Component.onCompleted: {
    // loadBadAppleFrames(...)
}

function ensureFramesLoaded() {
    if (framesLoaded || typeof ColorUtils === "undefined")
        return
    const appDir = ColorUtils.getAppDirectory()
    const normalizedDir = appDir.replace(/\\/g, "/")
    const binaryPath = "file:///" + normalizedDir + "/badapple_frames.bin"
    if (ColorUtils.loadBadAppleFrames(binaryPath)) {
        frameTextureUrl = ColorUtils.createBadAppleTexture()
        framesLoaded = (frameTextureUrl !== "")
    }
}

function startPlayback() {
    ensureFramesLoaded()
    if (!framesLoaded) {
        console.log("[BadApple] Frames unavailable, aborting playback")
        return
    }
    enabled = true
    frameIndex = 0.0
    time = 0.0
    badAppleAudioPlayer.stop()
    badAppleAudioPlayer.position = 0
    Qt.callLater(function() {
        badAppleAudioPlayer.play()
        playing = true
    })
}
```

Expected gain: **large** (removes file IO + texture prep from cold start).

---

### B. Lazy-load heavy viewers/components

Some QML trees are huge (video stack, model viewer, effects). Keep them unloaded until needed.

#### Patch idea (`src/qml/MainContentArea.qml` / `MediaViewerLoaders.qml`)

Use `Loader` + `active` by mode:

```qml
Loader {
    id: videoPageLoader
    anchors.fill: parent
    active: appState.currentView === "video"
    asynchronous: true
    sourceComponent: videoPageComponent
}
```

Apply same pattern for:

- model viewer
- PDF viewer
- optional shader/effect layers

Expected gain: **medium to large**, depending on inactive features.

---

### C. Defer optional visual effects until after first frame

Effects like backdrop blur, ambient gradient, snow, etc. can start after UI appears.

#### Patch idea (`src/qml/Main.qml`)

```qml
property bool postStartupEffectsReady: false

Timer {
    interval: 300
    running: true
    repeat: false
    onTriggered: postStartupEffectsReady = true
}

AmbientGradient {
    enabled: postStartupEffectsReady && userSettings.ambientGradientEnabled
}
SnowEffect {
    enabled: postStartupEffectsReady && userSettings.snowEnabled
}
BackdropBlur {
    enabled: postStartupEffectsReady && userSettings.blurEnabled
}
```

Expected gain: **medium**, plus better perceived startup speed.

---

### D. Delay non-essential C++ initialization

Keep only required startup actions before `engine.load(...)`.
Move optional setup after window is shown.

Examples to defer:

- diagnostic hooks
- expensive scans
- optional backend probing

#### Patch idea (`src/cpp/main.cpp`)

```cpp
engine.load(mainQmlUrl);
if (engine.rootObjects().isEmpty()) return -1;

QObject* root = engine.rootObjects().first();
QTimer::singleShot(0, [root]() {
    QMetaObject::invokeMethod(root, "postStartupInit", Qt::QueuedConnection);
});
```

In QML:

```qml
function postStartupInit() {
    // warmups, optional checks, prefetches
}
```

Expected gain: **small to medium**, depending on moved tasks.

---

## 3) Build-level improvements (for perceived startup)

- Keep using `RelWithDebInfo` (`FastDebug`) for near-release performance.
- For release builds, ensure deployment does not copy unnecessary plugins.
- Consider **splash/min-shell window** while heavy modules initialize.

---

## 4) Measurement checklist (must do)

Add timestamps around startup phases to prove impact:

- app process start
- first window shown
- first interactive input accepted
- optional systems ready

Track:

- cold start (after reboot or cleared caches)
- warm start

Target:

- first frame in under ~300-600 ms (warm)
- full ready in background within 1-3 s

---

## 5) Recommended implementation order

1. **BadApple lazy load** (highest impact, lowest risk)
2. **Effect defer timer** (quick win)
3. **Loader-based lazy pages** (bigger change, high payoff)
4. **Post-startup C++ deferral** (cleanup/perf polish)

---

## 6) Optional next step

If you want, the next patch pass can implement steps 1 + 2 directly now (minimal risk), then we profile again before touching larger Loader refactors.
