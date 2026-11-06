"""Writes data/agx_mhc.lut: the Yard plates' colour transform as a 3D table, so the
app gives the official look without Blender.

Linear Rec.709 -> AgX "Medium High Contrast" -> sRGB, from Blender's own OpenColorIO
config (OCIO is BSD-3-Clause; see the config's ocio-license.txt). The table is indexed
by log2 of the linear value, because scene light spans many stops.

  python tools/make_agx_lut.py [path to Blender's config.ocio]
"""
import struct, sys
import numpy as np
import PyOpenColorIO as O

if len(sys.argv) != 2:
    raise SystemExit("Usage: python tools/make_agx_lut.py <Blender config.ocio>")
CONFIG = sys.argv[1]
SIZE, LO, HI = 65, -12.5, 12.5


def processor():
    cfg = O.Config.CreateFromFile(CONFIG)
    g = O.GroupTransform()
    g.appendTransform(O.LookTransform(src='Linear Rec.709', dst='Linear Rec.709', looks='AgX - Medium High Contrast'))
    g.appendTransform(O.DisplayViewTransform(src='Linear Rec.709', display='sRGB', view='AgX'))
    return cfg.getProcessor(g).getDefaultCPUProcessor()


def to_linear(t):
    return np.where(t <= 0, 0.0, 2.0 ** (t * (HI - LO) + LO))


def sample(lut, x):
    """Trilinear lookup, as the bake shader does it."""
    t = np.clip((np.log2(np.maximum(x, 2.0 ** LO)) - LO) / (HI - LO), 0, 1) * (SIZE - 1)
    i = np.minimum(t.astype(int), SIZE - 2)
    f = t - i
    out = 0
    for dz in (0, 1):
        for dy in (0, 1):
            for dx in (0, 1):
                w = (f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1]) * (f[..., 2] if dz else 1 - f[..., 2])
                out = out + w[..., None] * lut[i[..., 2] + dz, i[..., 1] + dy, i[..., 0] + dx]
    return out


def main():
    cpu = processor()
    axis = to_linear(np.linspace(0, 1, SIZE))
    b, g, r = np.meshgrid(axis, axis, axis, indexing='ij')
    grid = np.stack([r, g, b], -1).astype(np.float32).reshape(-1, 1, 3)
    cpu.applyRGB(grid)
    lut = np.clip(grid.reshape(SIZE, SIZE, SIZE, 3), 0, 1)

    rng = np.random.default_rng(1)
    test = (2.0 ** rng.uniform(-10, 6, (200000, 3))).astype(np.float32).reshape(-1, 1, 3)
    true = test.copy()
    cpu.applyRGB(true)
    got = sample(lut, test[:, 0, :])
    err = np.abs(got - np.clip(true[:, 0, :], 0, 1))
    print('8-bit error against OpenColorIO: mean %.2f, p99 %.2f, max %.2f levels' % (err.mean() * 255, np.percentile(err, 99) * 255, err.max() * 255))

    rgba = np.concatenate([lut, np.ones((*lut.shape[:3], 1))], -1).astype(np.float16)
    with open('data/agx_mhc.lut', 'wb') as f:
        f.write(struct.pack('<Iff', SIZE, LO, HI))
        f.write(rgba.tobytes())
    print('wrote data/agx_mhc.lut', rgba.nbytes)


main()
