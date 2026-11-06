import hashlib, json, sys, tarfile, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KITS = ROOT / 'kits'
lock = json.loads((KITS / 'kit-lock.json').read_text())
archive = ROOT / 'build' / lock['asset']
archive.parent.mkdir(exist_ok=True)
if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != lock['sha256']:
    url = f"https://github.com/oddessentials/agent-guild-builders/releases/download/{lock['release']}/{lock['asset']}"
    urllib.request.urlretrieve(url, archive)
if hashlib.sha256(archive.read_bytes()).hexdigest() != lock['sha256']:
    sys.exit('The kit does not match kits/kit-lock.json')
with tarfile.open(archive) as tar:
    tar.extractall(KITS, filter='data')
print('Kit ready:', lock['asset'])
