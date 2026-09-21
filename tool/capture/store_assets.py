"""Turns the store renders into files Google Play accepts.

    flutter test --update-goldens tool/capture/store_test.dart
    python tool/capture/store_assets.py

Play wants the icon as a 512 x 512 32-bit PNG, and the feature graphic and
screenshots as 24-bit PNGs with no alpha channel. Screenshots may be at most
twice as long as they are wide. Needs Pillow.
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, 'out', 'store')
TARGET = os.path.join(HERE, '..', '..', 'docs', 'store-assets')
INK = (14, 14, 12)


def flatten(image):
    base = Image.new('RGB', image.size, INK)
    base.paste(image, mask=image.getchannel('A') if image.mode == 'RGBA' else None)
    return base


def main():
    names = sorted(n for n in os.listdir(SOURCE) if n.endswith('.png'))
    if not names:
        raise SystemExit('No renders found. Run the store capture test first.')
    for name in names:
        image = Image.open(os.path.join(SOURCE, name)).convert('RGBA')
        width, height = image.size
        if name.startswith('phone-'):
            assert max(width, height) <= 2 * min(width, height), f'{name}: longer than 2:1'
            assert 320 <= min(width, height) and max(width, height) <= 3840, f'{name}: size out of range'
        out = image if name == 'high-res-icon.png' else flatten(image)
        out.save(os.path.join(TARGET, name), optimize=True)
        print(f'{name:28} {width} x {height}  {out.mode}')


if __name__ == '__main__':
    main()
