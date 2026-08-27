# OldGuida Branding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename every user-visible app surface to `OldGuida` and replace the default Flutter mark with a crisp steering-wheel-and-open-book icon across supported platforms.

**Architecture:** Keep internal package and application identifiers unchanged, and update only display metadata and visible titles. Generate a deterministic high-resolution raster master and all platform derivatives from one Pillow drawing script so icon sizing, safe areas, transparency, and future regeneration remain auditable.

**Tech Stack:** Flutter platform projects, Python 3 with Pillow 11.3.0 available in the workspace, XML/plist/JSON/RC configuration, Flutter builds and visual inspection.

**Spec:** `docs/superpowers/specs/2026-08-27-keyword-translation-and-branding-design.md`

## Global Constraints

- The exact user-visible name is `OldGuida`.
- Keep Dart package name `italian_driving_app`, Android `applicationId`, Android namespace, Kotlin package, iOS/macOS bundle identifiers, Linux application id, and Windows binary name unchanged.
- The icon contains no text, watermark, Flutter logo, thin decorative detail, or stock imagery.
- Icon subject is a steering wheel combined with an open book.
- Primary color follows the app's teal theme; Italian red, white, and green are restrained accents.
- The icon must survive square, rounded-square, circle, and Android adaptive masks without clipping.
- iOS icons must be opaque; Android adaptive foregrounds must preserve transparency.
- Do not add an image-generation API dependency or require a network service.
- Do not stage unrelated generated plugin file changes.

---

## File Map

- Create `tools/branding/generate_app_icons.py`: deterministic master artwork and platform export.
- Create `tools/branding/verify_branding.py`: dimension, alpha, color, display-name, and identifier checks.
- Create `tools/branding/tests/test_generate_app_icons.py`: generator tests in a temporary directory.
- Create `assets/branding/app_icon_master.png`: opaque 2048x2048 reference master.
- Create `assets/branding/app_icon_foreground.png`: transparent 2048x2048 adaptive foreground reference.
- Replace Android `mipmap-*/ic_launcher.png` and add adaptive foreground/XML resources.
- Replace all iOS `Runner/Assets.xcassets/AppIcon.appiconset/*.png` files.
- Replace all macOS `Runner/Assets.xcassets/AppIcon.appiconset/*.png` files.
- Replace Web favicon and the four existing manifest icon PNGs.
- Replace `windows/runner/resources/app_icon.ico`.
- Modify platform display-name metadata, `lib/main.dart`, and `lib/Screen/Homepage.dart`.

### Task 1: Build a Deterministic Icon Generator

**Files:**
- Create: `tools/branding/generate_app_icons.py`
- Create: `tools/branding/tests/test_generate_app_icons.py`

**Interfaces:**
- Produces: `draw_foreground(size: int) -> PIL.Image.Image` in RGBA mode.
- Produces: `draw_composite(size: int, rounded: bool = False) -> PIL.Image.Image`.
- Produces: `generate(root: Path) -> list[Path]` containing every written icon.

- [ ] **Step 1: Write generator tests for master geometry and output sizes**

```python
class AppIconGeneratorTest(unittest.TestCase):
    def test_foreground_is_transparent_and_composite_is_opaque(self):
        foreground = draw_foreground(1024)
        composite = draw_composite(1024)
        self.assertEqual(foreground.mode, "RGBA")
        self.assertEqual(foreground.getpixel((0, 0))[3], 0)
        self.assertEqual(composite.mode, "RGB")

    def test_generate_writes_expected_platform_dimensions(self):
        paths = generate(self.root)
        self.assertIn(self.root / "assets/branding/app_icon_master.png", paths)
        expected = {
            "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": (48, 48),
            "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png": (432, 432),
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png": (1024, 1024),
            "web/icons/Icon-512.png": (512, 512),
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png": (16, 16),
        }
        for relative_path, size in expected.items():
            with Image.open(self.root / relative_path) as image:
                self.assertEqual(image.size, size)
```

- [ ] **Step 2: Run tests and observe failure**

Run: `python -m unittest tools.branding.tests.test_generate_app_icons -v`

Expected: FAIL because the generator is missing.

- [ ] **Step 3: Implement the supersampled icon artwork**

Use a 4x supersampled canvas and `Image.Resampling.LANCZOS` for final reduction. Define colors once:

```python
TEAL = "#138A83"
TEAL_DARK = "#075E59"
INK = "#163A3A"
WHITE = "#FFFFFF"
ITALY_GREEN = "#159447"
ITALY_RED = "#D83A3A"


def draw_foreground(size: int) -> Image.Image:
    scale = 4
    canvas = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    s = size * scale

    # Steering wheel: centered above the book and contained within 66% safe area.
    wheel_box = (int(.25*s), int(.16*s), int(.75*s), int(.66*s))
    draw.ellipse(wheel_box, outline=WHITE, width=int(.065*s))
    center = (int(.50*s), int(.43*s))
    for endpoint in ((int(.31*s), int(.31*s)), (int(.69*s), int(.31*s)), (int(.50*s), int(.62*s))):
        draw.line((center, endpoint), fill=WHITE, width=int(.055*s))
    draw.ellipse((int(.43*s), int(.36*s), int(.57*s), int(.50*s)), fill=TEAL_DARK)

    # Open book: two bold pages with a dark center seam.
    left_page = [(int(.20*s), int(.59*s)), (int(.48*s), int(.53*s)), (int(.48*s), int(.82*s)), (int(.20*s), int(.75*s))]
    right_page = [(int(.52*s), int(.53*s)), (int(.80*s), int(.59*s)), (int(.80*s), int(.75*s)), (int(.52*s), int(.82*s))]
    draw.polygon(left_page, fill=WHITE)
    draw.polygon(right_page, fill=WHITE)
    draw.line((int(.50*s), int(.54*s), int(.50*s), int(.82*s)), fill=INK, width=int(.025*s))

    # Three broad page markers provide a restrained Italian accent.
    marker_y = int(.72*s)
    for x, color in ((.38, ITALY_GREEN), (.48, WHITE), (.58, ITALY_RED)):
        draw.rounded_rectangle(
            (int(x*s), marker_y, int((x+.06)*s), int(.79*s)),
            radius=int(.012*s),
            fill=color,
            outline=TEAL_DARK,
            width=max(1, int(.006*s)),
        )

    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def draw_composite(size: int, rounded: bool = False) -> Image.Image:
    if rounded:
        base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        inset = int(size * .05)
        ImageDraw.Draw(base).rounded_rectangle(
            (inset, inset, size - inset, size - inset),
            radius=int(size * .20),
            fill=TEAL,
        )
        base.alpha_composite(draw_foreground(size))
        return base
    base = Image.new("RGBA", (size, size), TEAL)
    base.alpha_composite(draw_foreground(size))
    return base.convert("RGB")
```

For macOS only, call `draw_composite(size, rounded=True)`; all iOS, Android legacy, and Web normal icons use the opaque default.

- [ ] **Step 4: Implement every platform export map**

Use these exact maps:

```python
ANDROID_LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ANDROID_FOREGROUND = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
MACOS = [16, 32, 64, 128, 256, 512, 1024]
WEB = {"Icon-192.png": 192, "Icon-512.png": 512, "Icon-maskable-192.png": 192, "Icon-maskable-512.png": 512}
IOS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}
```

Save a multi-resolution Windows ICO containing 16, 24, 32, 48, 64, 128, and 256 pixel frames. Generate `web/favicon.png` at 32x32. Maskable Web icons must use a reduced foreground contained within the central 60% safe zone.

Implement the export loops from the maps above with this structure:

```python
def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def draw_maskable(size: int) -> Image.Image:
    base = Image.new("RGBA", (size, size), TEAL)
    glyph_size = int(size * .60)
    glyph = draw_foreground(glyph_size)
    offset = (size - glyph_size) // 2
    base.alpha_composite(glyph, (offset, offset))
    return base.convert("RGB")


def generate(root: Path) -> list[Path]:
    written = []
    master = draw_composite(2048)
    foreground = draw_foreground(2048)
    master_path = root / "assets/branding/app_icon_master.png"
    foreground_path = root / "assets/branding/app_icon_foreground.png"
    save_png(master, master_path)
    save_png(foreground, foreground_path)
    written.extend([master_path, foreground_path])

    for density, size in ANDROID_LEGACY.items():
        path = root / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png"
        save_png(draw_composite(size), path)
        written.append(path)
    for density, size in ANDROID_FOREGROUND.items():
        path = root / f"android/app/src/main/res/mipmap-{density}/ic_launcher_foreground.png"
        save_png(draw_foreground(size), path)
        written.append(path)
    for filename, size in IOS.items():
        path = root / "ios/Runner/Assets.xcassets/AppIcon.appiconset" / filename
        save_png(draw_composite(size), path)
        written.append(path)
    for size in MACOS:
        path = root / "macos/Runner/Assets.xcassets/AppIcon.appiconset" / f"app_icon_{size}.png"
        save_png(draw_composite(size, rounded=True), path)
        written.append(path)
    for filename, size in WEB.items():
        path = root / "web/icons" / filename
        image = draw_maskable(size) if "maskable" in filename else draw_composite(size)
        save_png(image, path)
        written.append(path)
    favicon = root / "web/favicon.png"
    save_png(draw_composite(32), favicon)
    written.append(favicon)
    ico = root / "windows/runner/resources/app_icon.ico"
    ico.parent.mkdir(parents=True, exist_ok=True)
    draw_composite(256).save(
        ico,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    written.append(ico)
    return written
```

- [ ] **Step 5: Run generator tests**

Run: `python -m unittest tools.branding.tests.test_generate_app_icons -v`

Expected: PASS.

- [ ] **Step 6: Commit the generator and tests**

```powershell
git add -- tools/branding/generate_app_icons.py tools/branding/tests/test_generate_app_icons.py
git commit -m "feat: add deterministic OldGuida icon generator"
```

### Task 2: Generate and Wire All Platform Icon Assets

**Files:**
- Create: `assets/branding/app_icon_master.png`
- Create: `assets/branding/app_icon_foreground.png`
- Modify: `android/app/src/main/res/mipmap-*/ic_launcher.png`
- Create: `android/app/src/main/res/mipmap-*/ic_launcher_foreground.png`
- Create: `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- Create: `android/app/src/main/res/values/colors.xml`
- Modify: `ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png`
- Modify: `macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png`
- Modify: `web/favicon.png`
- Modify: `web/icons/*.png`
- Modify: `windows/runner/resources/app_icon.ico`

**Interfaces:**
- Consumes: `generate(root)`.
- Produces: complete mobile, desktop, and Web icon assets from one master.

- [ ] **Step 1: Generate the real icon assets**

Run: `python tools\branding\generate_app_icons.py --root .`

Expected: the command lists every written file and exits 0.

- [ ] **Step 2: Add Android adaptive icon metadata**

Create `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
```

Create `android/app/src/main/res/values/colors.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#138A83</color>
</resources>
```

- [ ] **Step 3: Inspect the master and small-size outputs**

Use image inspection on:

- `assets/branding/app_icon_master.png`
- `assets/branding/app_icon_foreground.png`
- `android/app/src/main/res/mipmap-mdpi/ic_launcher.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png`
- `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png`

Expected: steering wheel and open book are recognizable; Italian accents remain secondary; no white border, text, watermark, clipped stroke, or transparent iOS corner exists.

- [ ] **Step 4: Commit generated icon assets**

```powershell
git add -- assets/branding android/app/src/main/res ios/Runner/Assets.xcassets/AppIcon.appiconset macos/Runner/Assets.xcassets/AppIcon.appiconset web/favicon.png web/icons windows/runner/resources/app_icon.ico
git commit -m "feat: replace Flutter icon with OldGuida branding"
```

### Task 3: Rename Every User-Visible App Surface

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/Screen/Homepage.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `ios/Runner/Info.plist`
- Modify: `macos/Runner/Configs/AppInfo.xcconfig`
- Modify: `macos/Runner.xcodeproj/project.pbxproj`
- Modify: `windows/runner/main.cpp`
- Modify: `windows/runner/Runner.rc`
- Modify: `linux/runner/my_application.cc`
- Modify: `web/manifest.json`
- Modify: `web/index.html`
- Modify: `README.md`
- Create: `tools/branding/verify_branding.py`

**Interfaces:**
- Produces exact visible name `OldGuida` on Flutter, Android, iOS, macOS, Windows, Linux, and Web.
- Preserves all internal ids and package imports.

- [ ] **Step 1: Write the branding verifier before changing metadata**

```python
VISIBLE_NAME_FILES = {
    "lib/main.dart": "title: 'OldGuida'",
    "lib/Screen/Homepage.dart": "OldGuida",
    "android/app/src/main/AndroidManifest.xml": 'android:label="OldGuida"',
    "ios/Runner/Info.plist": "<string>OldGuida</string>",
    "macos/Runner/Configs/AppInfo.xcconfig": "PRODUCT_NAME = OldGuida",
    "windows/runner/main.cpp": 'window.Create(L"OldGuida"',
    "windows/runner/Runner.rc": 'VALUE "ProductName", "OldGuida"',
    "linux/runner/my_application.cc": 'gtk_header_bar_set_title(header_bar, "OldGuida")',
    "web/manifest.json": '"name": "OldGuida"',
    "web/index.html": "<title>OldGuida</title>",
}

PRESERVED_IDENTIFIERS = {
    "pubspec.yaml": "name: italian_driving_app",
    "android/app/build.gradle.kts": 'applicationId = "com.example.italian_driving_app"',
    "ios/Runner.xcodeproj/project.pbxproj": "PRODUCT_BUNDLE_IDENTIFIER = com.example.italianDrivingApp;",
    "macos/Runner/Configs/AppInfo.xcconfig": "PRODUCT_BUNDLE_IDENTIFIER = com.example.italianDrivingApp",
    "linux/CMakeLists.txt": 'set(APPLICATION_ID "com.example.italian_driving_app")',
    "windows/CMakeLists.txt": 'set(BINARY_NAME "italian_driving_app")',
}
```

The CLI reads each UTF-8 file, reports missing expected strings, and exits nonzero on any mismatch.

- [ ] **Step 2: Run the verifier and observe visible-name failures**

Run: `python tools\branding\verify_branding.py --root .`

Expected: FAIL for current visible names while preserved identifiers pass.

- [ ] **Step 3: Update Flutter, Android, iOS, Web, Windows, and Linux visible names**

Apply these exact changes:

```text
Homepage app bar title: OldGuida
MaterialApp title: OldGuida
Android application label: OldGuida
iOS CFBundleDisplayName: OldGuida
Web name and short_name: OldGuida
Web apple-mobile-web-app-title and HTML title: OldGuida
Web description: 意大利驾考学习工具
Windows window title, FileDescription, and ProductName: OldGuida
Linux GTK header-bar and window titles: OldGuida
README primary product name: OldGuida
```

Keep Windows `InternalName` and `OriginalFilename`, Linux `APPLICATION_ID`, HTTP user-agent strings, Dart imports, and package names unchanged.

- [ ] **Step 4: Update macOS visible product name without changing the bundle id**

Set `PRODUCT_NAME = OldGuida` in `macos/Runner/Configs/AppInfo.xcconfig`. Update only the macOS product-reference and test-host strings in `macos/Runner.xcodeproj/project.pbxproj` from `italian_driving_app.app`/`italian_driving_app` to `OldGuida.app`/`OldGuida`; leave `PRODUCT_BUNDLE_IDENTIFIER` values untouched.

- [ ] **Step 5: Run the branding verifier**

Run: `python tools\branding\verify_branding.py --root .`

Expected: PASS for every visible-name check and every preserved-identifier check.

- [ ] **Step 6: Commit display-name changes and verifier**

```powershell
git add -- lib/main.dart lib/Screen/Homepage.dart android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist macos/Runner/Configs/AppInfo.xcconfig macos/Runner.xcodeproj/project.pbxproj windows/runner/main.cpp windows/runner/Runner.rc linux/runner/my_application.cc web/manifest.json web/index.html README.md tools/branding/verify_branding.py
git commit -m "feat: rename app surfaces to OldGuida"
```

### Task 4: Verify Builds, Metadata, and Visual Output

**Files:**
- Modify only if verification finds a branding defect: files owned by Tasks 1 through 3.

**Interfaces:**
- Consumes all branding work.
- Produces build and visual evidence for supported targets available on Windows.

- [ ] **Step 1: Run generator, metadata, and Flutter checks**

```powershell
python -m unittest tools.branding.tests.test_generate_app_icons -v
python tools\branding\verify_branding.py --root .
flutter test
flutter analyze
```

Expected: every command exits 0.

- [ ] **Step 2: Build Android, Web, and Windows artifacts**

```powershell
flutter build apk --debug
flutter build web
flutter build windows
```

Expected: every build exits 0. iOS and macOS compilation cannot be performed on Windows; their asset dimensions, alpha rules, JSON manifests, plist, xcconfig, and project references are verified statically instead.

- [ ] **Step 3: Inspect packaged Android metadata**

Use the Android SDK `aapt` or `apkanalyzer` available with the Flutter toolchain:

```powershell
apkanalyzer manifest application-id build\app\outputs\flutter-apk\app-debug.apk
apkanalyzer manifest application-label build\app\outputs\flutter-apk\app-debug.apk
```

Expected: application id remains `com.example.italian_driving_app`; application label is `OldGuida`.

- [ ] **Step 4: Visually verify the running app and generated icons**

Start the Web build or local Flutter Web server, then capture desktop 1280x800 and mobile 390x844 views. Confirm the home app bar reads `OldGuida` and no title overlaps other content.

Inspect `app_icon_master.png`, Android legacy and adaptive layers, iOS 1024, Web maskable 512, macOS 16 and 1024, and Windows ICO. Check nonblank pixels, safe-area margins, opacity requirements, and small-size recognition.

- [ ] **Step 5: Confirm the final diff is scoped**

```powershell
git status --short
git diff --check HEAD~3..HEAD
git diff --name-only HEAD~3..HEAD
```

Expected: only branding source, generated icons, display metadata, tests, and README are part of the branding commits; internal ids and unrelated generated plugin files are unchanged.
