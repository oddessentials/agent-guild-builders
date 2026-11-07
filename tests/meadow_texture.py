import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import build_kit


class MeadowTextureTests(unittest.TestCase):
    def setUp(self):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        (ROOT / '.cache').mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=ROOT / '.cache')
        self.folder = Path(self.temporary.name)
        self.source = self.folder / 'meadow.jpg'
        pixels = np.ones((48, 64, 4), dtype=np.float32)
        pixels[:, :, 0] = np.linspace(.05, .65, 64)[None, :]
        pixels[:, :, 1] = np.linspace(.1, .6, 48)[:, None]
        pixels[:, :, 2] = .2
        image = bpy.data.images.new('source', 64, 48)
        image.pixels[:] = pixels.ravel()
        image.filepath_raw, image.file_format = str(self.source), 'JPEG'
        image.save()
        bpy.data.images.remove(image)

    def tearDown(self):
        self.temporary.cleanup()

    def pixels(self, path):
        image = bpy.data.images.load(str(path))
        w, h = image.size
        result = np.array(image.pixels[:]).reshape(h, w, 4)[:, :, :3]
        bpy.data.images.remove(image)
        return result

    def test_build_wraps_both_axes_without_changing_source(self):
        original = self.source.read_bytes()
        raw = self.pixels(self.source)
        grounds = self.folder / 'leafy_grass'
        grounds.mkdir()
        for suffix in ('diff', 'nor_gl', 'rough'):
            (grounds / f'leafy_grass_{suffix}_2k.jpg').write_bytes(original)
        kit = self.folder / 'kit'
        with patch.multiple(build_kit, SOURCE=self.folder, MEADOW=self.source, KIT=kit,
                            MODELS={}, MADE_HERE={}, MORE_SOURCES=[], SKIES={}, GROUNDS={'grass': ('leafy_grass', 'Meadow grass')}, create=True):
            build_kit.main()
            output = kit / 'textures/grass_diff.jpg'
            first = output.read_bytes()
            tile = self.pixels(output)
            self.assertEqual(tile.shape, raw.shape)
            for axis in (0, 1):
                raw_edge = np.abs(np.take(raw, 0, axis) - np.take(raw, -1, axis)).mean()
                self.assertGreater(raw_edge, np.abs(np.diff(raw, axis=axis)).mean() * 10)
                tile_edge = np.abs(np.take(tile, 0, axis) - np.take(tile, -1, axis)).mean()
                self.assertLess(tile_edge, raw_edge / 4)
            build_kit.main()
            self.assertEqual(output.read_bytes(), first)
        self.assertEqual(self.source.read_bytes(), original)

    def test_prepared_png_is_refused(self):
        prepared = self.folder / 'meadow.png'
        prepared.write_bytes(b'prepared tile')
        with self.assertRaisesRegex(SystemExit, 'original Meadow source JPG'):
            build_kit.inputs([str(self.folder), str(prepared)])
        self.assertEqual(build_kit.inputs([str(self.folder), str(self.source)]), (self.folder, self.source, []))
        self.assertEqual(build_kit.inputs([str(self.folder), str(self.source), str(self.folder)]), (self.folder, self.source, [self.folder]))
        with self.assertRaisesRegex(SystemExit, 'does not exist'):
            build_kit.inputs([str(self.folder), str(self.source), str(self.folder / 'missing')])

    def test_unreadable_source_fails_before_creating_kit(self):
        self.source.write_bytes(b'not an image')
        kit = self.folder / 'kit'
        with patch.multiple(build_kit, SOURCE=self.folder, MEADOW=self.source, KIT=kit, create=True):
            with self.assertRaises(RuntimeError):
                build_kit.main()
        self.assertFalse(kit.exists())


if __name__ == '__main__':
    result = unittest.main(argv=[__file__], exit=False).result
    if not result.wasSuccessful():
        raise RuntimeError('Meadow texture checks failed')
