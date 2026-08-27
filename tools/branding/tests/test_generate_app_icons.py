import tempfile
import unittest
from pathlib import Path

from PIL import Image

from tools.branding.generate_app_icons import draw_composite, draw_foreground, generate


class AppIconGeneratorTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)

    def tearDown(self):
        self.temporary_directory.cleanup()

    def test_foreground_is_transparent_and_composite_is_opaque(self):
        foreground = draw_foreground(1024)
        composite = draw_composite(1024)

        self.assertEqual(foreground.mode, "RGBA")
        self.assertEqual(foreground.getpixel((0, 0))[3], 0)
        self.assertEqual(composite.mode, "RGB")

    def test_generate_writes_all_platform_exports_at_expected_dimensions(self):
        paths = generate(self.root)

        expected = {
            "assets/branding/app_icon_master.png": (2048, 2048),
            "assets/branding/app_icon_foreground.png": (2048, 2048),
            "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": (48, 48),
            "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": (72, 72),
            "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": (96, 96),
            "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": (144, 144),
            "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": (192, 192),
            "android/app/src/main/res/mipmap-mdpi/ic_launcher_foreground.png": (108, 108),
            "android/app/src/main/res/mipmap-hdpi/ic_launcher_foreground.png": (162, 162),
            "android/app/src/main/res/mipmap-xhdpi/ic_launcher_foreground.png": (216, 216),
            "android/app/src/main/res/mipmap-xxhdpi/ic_launcher_foreground.png": (324, 324),
            "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png": (432, 432),
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png": (20, 20),
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png": (40, 40),
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png": (60, 60),
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png": (29, 29),
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png": (58, 58),
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png": (87, 87),
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png": (40, 40),
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png": (80, 80),
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png": (120, 120),
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png": (120, 120),
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png": (180, 180),
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png": (76, 76),
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png": (152, 152),
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png": (167, 167),
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png": (1024, 1024),
            "web/icons/Icon-192.png": (192, 192),
            "web/icons/Icon-512.png": (512, 512),
            "web/icons/Icon-maskable-192.png": (192, 192),
            "web/icons/Icon-maskable-512.png": (512, 512),
            "web/favicon.png": (32, 32),
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png": (16, 16),
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png": (32, 32),
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png": (64, 64),
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png": (128, 128),
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png": (256, 256),
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png": (512, 512),
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png": (1024, 1024),
            "windows/runner/resources/app_icon.ico": (256, 256),
        }

        self.assertEqual({self.root / path for path in expected}, set(paths))
        for relative_path, size in expected.items():
            with Image.open(self.root / relative_path) as image:
                self.assertEqual(image.size, size)

    def test_maskable_icons_keep_the_foreground_inside_the_central_safe_zone(self):
        generate(self.root)
        with Image.open(self.root / "web/icons/Icon-maskable-512.png") as image:
            pixels = image.convert("RGB")
            teal = (19, 138, 131)
            occupied = [
                (x, y)
                for y in range(image.height)
                for x in range(image.width)
                if pixels.getpixel((x, y)) != teal
            ]

        self.assertTrue(occupied)
        self.assertGreaterEqual(min(x for x, _ in occupied), 102)
        self.assertLessEqual(max(x for x, _ in occupied), 409)
        self.assertGreaterEqual(min(y for _, y in occupied), 102)
        self.assertLessEqual(max(y for _, y in occupied), 409)

    def test_windows_ico_contains_all_required_resolutions(self):
        generate(self.root)
        ico_path = self.root / "windows/runner/resources/app_icon.ico"
        with Image.open(ico_path) as icon:
            sizes = set(icon.ico.sizes())

        self.assertEqual(
            sizes,
            {(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)},
        )


if __name__ == "__main__":
    unittest.main()
