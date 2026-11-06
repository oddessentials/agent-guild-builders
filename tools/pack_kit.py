import hashlib, json, sys, tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KITS = ROOT / 'kits'
PARTS = ['meadow/models', 'meadow/textures', 'meadow/skies', 'halls']
out = Path(sys.argv[1]) if len(sys.argv) == 2 else ROOT / 'build'
out.mkdir(parents=True, exist_ok=True)
draft = out / 'kit.tar.gz'
with tarfile.open(draft, 'w:gz', compresslevel=6) as tar:
    for part in PARTS:
        for file in sorted((KITS / part).rglob('*')):
            if file.is_file():
                tar.add(file, arcname=file.relative_to(KITS).as_posix(), recursive=False)
digest = hashlib.sha256(draft.read_bytes()).hexdigest()
name = f'kit-{digest[:16]}.tar.gz'
draft.replace(out / name)
(KITS / 'kit-lock.json').write_text(json.dumps({'release': 'art', 'asset': name, 'sha256': digest}, indent=1) + '\n', newline='\n')
print(out / name)
