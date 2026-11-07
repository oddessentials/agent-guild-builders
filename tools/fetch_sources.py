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
        path.write_bytes(reply.read())


tree = ast.parse((ROOT / 'tools' / 'build_kit.py').read_text(encoding='utf-8'))
models = next(ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign) and n.targets[0].id == 'MODELS')
for spec in models.values():
    name = spec[0]
    if any(sorted((folder / name).rglob('*.blend')) for folder in HAVE):
        continue
    blend = json.load(fetch(f'https://api.polyhaven.com/files/{name}'))['blend']['1k']['blend']
    folder = OUT / name / '1k'
    for rel, item in blend.get('include', {}).items():
        save(item['url'], folder / rel)
    save(blend['url'], folder / f'{name}_1k.blend')
    print('fetched', name, flush=True)
print('SOURCES DONE')
