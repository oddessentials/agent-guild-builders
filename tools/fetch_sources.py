import ast, json, sys, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if len(sys.argv) < 2:
    raise SystemExit('Usage: python tools/fetch_sources.py <download folder> [folders that may already hold sources]')
OUT = Path(sys.argv[1])
HAVE = [OUT, *map(Path, sys.argv[2:])]
HEADERS = {'User-Agent': 'agent-guild-builders-kit'}


def fetch(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=120)


def save(url, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with fetch(url) as reply:
        data = reply.read()
    path.with_name(path.name + '.part').write_bytes(data)
    path.with_name(path.name + '.part').replace(path)


def have(rel):
    return any((folder / rel).is_file() for folder in HAVE)


tree = ast.parse((ROOT / 'tools' / 'build_kit.py').read_text(encoding='utf-8'))
specs = {n.targets[0].id: ast.literal_eval(n.value) for n in tree.body
         if isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name) and n.targets[0].id in ('MODELS', 'GROUNDS', 'SKIES')}
for spec in specs['MODELS'].values():
    name = spec[0].partition(':')[0]
    if any(sorted((folder / name).rglob('*.blend')) for folder in HAVE):
        continue
    blend = json.load(fetch(f'https://api.polyhaven.com/files/{name}'))['blend']['1k']['blend']
    folder = OUT / name / '1k'
    for rel, item in blend.get('include', {}).items():
        save(item['url'], folder / rel)
    save(blend['url'], folder / f'{name}_1k.blend')
    print('fetched', name, flush=True)
made = ast.parse((ROOT / 'tools' / 'make_sources.py').read_text(encoding='utf-8'))
graded = next(ast.literal_eval(n.value) for n in made.body if isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name) and n.targets[0].id == 'GRADED')
for name in [spec[0] for spec in specs['GROUNDS'].values()] + [spec[0] for spec in graded.values()]:
    if name.startswith('made_'):
        continue
    maps = {'diff': 'Diffuse', 'nor_gl': 'nor_gl', 'rough': 'Rough'}
    if all(have(f'{name}/{name}_{m}_2k.jpg') for m in maps):
        continue
    files = json.load(fetch(f'https://api.polyhaven.com/files/{name}'))
    for m, key in maps.items():
        save(files[key]['2k']['jpg']['url'], OUT / name / f'{name}_{m}_2k.jpg')
    print('fetched', name, flush=True)
for spec in specs['SKIES'].values():
    name = spec[0]
    if name.startswith('made_') or '/' in name or have(f'{name}/{name}_1k.hdr'):
        continue
    save(json.load(fetch(f'https://api.polyhaven.com/files/{name}'))['hdri']['1k']['hdr']['url'], OUT / name / f'{name}_1k.hdr')
    print('fetched', name, flush=True)
print('SOURCES DONE')
