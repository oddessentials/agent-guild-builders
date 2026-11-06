import sys
from pathlib import Path
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

if len(sys.argv) != 2:
    raise SystemExit('Usage: python tools/make_hero.py <agent-guild checkout>')
ROOT = Path(sys.argv[1])
CONCEPTS = ROOT / 'concept-art/professional-yard/concepts'
SKIN = ROOT / 'web/skins/professional'
OUT = Path(__file__).resolve().parent.parent / 'data/brand'
TRACED_SHOES = {
    'staff_xai': {'legs': (370, 660), 'gap': (481, 557), 'shoes': [
        [(398, 883), (430, 886), (455, 898), (477, 908), (480, 955), (440, 966), (395, 970), (345, 971), (333, 965), (333, 950), (350, 932), (372, 908)],
        [(562, 910), (595, 887), (625, 884), (645, 895), (655, 918), (672, 940), (680, 955), (678, 971), (640, 975), (600, 973), (565, 958), (558, 945)],
    ]},
    'staff_openai': {'legs': (390, 625), 'gap': (481, 549), 'shoes': [
        [(400, 899), (440, 902), (455, 912), (470, 915), (478, 925), (478, 958), (450, 968), (400, 977), (350, 977), (348, 965), (350, 950), (375, 930), (395, 908)],
        [(552, 910), (570, 905), (600, 899), (612, 905), (625, 930), (650, 950), (650, 978), (610, 980), (570, 968), (550, 955)],
    ]},
}
SCALE = 2
W, H = 1440 * SCALE, 330 * SCALE
FLOOR = 314
CAST = [('staff_google', 835, 238, FLOOR - 14), ('staff_xai', 1185, 246, FLOOR - 14), ('staff_openai', 945, 262, FLOOR - 6),
        ('staff_docker', 1300, 258, FLOOR - 6), ('staff_anthropic', 1070, 282, FLOOR), ('bot_concierge', 1385, 92, FLOOR + 6),
        ('bot_butler', 760, 112, FLOOR + 8)]


def cut(n):
    a=cv2.imread(str(CONCEPTS / (n + '.png'))); h,w=a.shape[:2]
    lab=cv2.cvtColor(cv2.medianBlur(a,9),cv2.COLOR_BGR2LAB).astype(int)
    edge=np.concatenate([lab[:20].reshape(-1,3),lab[:,:20].reshape(-1,3),lab[:,-20:].reshape(-1,3)])
    med=np.median(edge,axis=0); spread=np.percentile(np.abs(edge-med).sum(1),97)
    d=np.abs(lab-med).sum(2); near=(d<max(16,spread+5)).astype('uint8')
    _,c=cv2.connectedComponents(near); border=set(np.unique(np.concatenate([c[0],c[-1],c[:,0],c[:,-1]])))-{0}
    bg=np.isin(c,list(border)); bg=cv2.morphologyEx(bg.astype('uint8'),cv2.MORPH_OPEN,np.ones((5,5),np.uint8))>0
    fg=~bg
    m=np.where(bg,cv2.GC_PR_BGD,cv2.GC_PR_FGD).astype(np.uint8)
    m[cv2.erode(fg.astype('uint8'),np.ones((21,21),np.uint8))>0]=cv2.GC_FGD
    m[cv2.erode(bg.astype('uint8'),np.ones((15,15),np.uint8))>0]=cv2.GC_BGD
    cv2.grabCut(a,m,None,np.zeros((1,65)),np.zeros((1,65)),5,cv2.GC_INIT_WITH_MASK)
    al=np.where((m==1)|(m==3),255,0).astype('uint8')
    al=cv2.morphologyEx(al,cv2.MORPH_CLOSE,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(7,7)))
    _,c=cv2.connectedComponents(al); ct=np.bincount(c.ravel()); ct[0]=0; al=np.where(c==ct.argmax(),255,0).astype('uint8')
    if n in TRACED_SHOES:
        lum=lab[...,0]-med[0]; lo,hi=TRACED_SHOES[n]['legs']
        al[860:]=0
        al[860:,lo:hi]=np.where(lum[860:,lo:hi]<-14,255,0)
        al[900:]=0
        for shoe in TRACED_SHOES[n]['shoes']:
            cv2.fillPoly(al,[np.array(shoe,np.int32)],255)
    fl=al.copy(); ff=np.zeros((h+2,w+2),np.uint8); cv2.floodFill(fl,ff,(0,0),255); al=al|cv2.bitwise_not(fl)
    if n in TRACED_SHOES:
        lo,hi=TRACED_SHOES[n]['gap']; gap=al[640:980,lo:hi]; gap[(lab[...,0]-med[0])[640:980,lo:hi]>-14]=0; al[900:,lo:hi]=0
    al=cv2.GaussianBlur(cv2.erode(al,np.ones((3,3),np.uint8)),(3,3),0)
    im=Image.fromarray(cv2.cvtColor(a,cv2.COLOR_BGR2RGB)); im.putalpha(Image.fromarray(al)); return im.crop(im.getbbox())


def make(name, source, bg, shadow, light, floor_fade=False):
    hall = Image.open(SKIN / source).convert('RGB')
    hall = hall.resize((W, int(hall.height * W / hall.width)), Image.LANCZOS)
    top = int(hall.height * .34)
    page = hall.crop((0, top, W, top + H))
    x = np.arange(W) / SCALE
    fade = np.clip(1 - np.maximum(0, x - 470) / 330, 0, 1) * 245 + np.clip(1 - x / 240, 0, 1) * 10
    page.paste(Image.new('RGB', (W, H), bg), (0, 0), Image.fromarray(np.tile(fade.astype('uint8'), (H, 1))))
    if floor_fade:
        ramp = (np.clip((np.arange(H) / H - .66) / .24, 0, 1) * 240).astype('uint8')
        page.paste(Image.new('RGB', (W, H), bg), (0, 0), Image.fromarray(np.tile(ramp[:, None], (1, W))))
    for kind, cx, height, floor in CAST:
        person = crew[kind]
        tall = height * SCALE
        person = person.resize((int(person.width * tall / person.height), tall), Image.LANCZOS)
        if light != 1:
            person = Image.merge('RGBA', (*ImageEnhance.Brightness(person.convert('RGB')).enhance(light).split(), person.getchannel('A')))
        cx, floor = cx * SCALE, floor * SCALE
        pool = Image.new('L', (W, H), 0)
        ImageDraw.Draw(pool).ellipse((cx - person.width * .42, floor - 18, cx + person.width * .42, floor + 14), fill=95)
        page.paste(Image.new('RGB', (W, H), shadow), (0, 0), pool.filter(ImageFilter.GaussianBlur(14)))
        page.paste(person, (cx - person.width // 2, floor - tall), person)
    page.save(OUT / name, quality=88, method=6)


def robot(kind, tall):
    bot = cut(kind)
    bot = bot.resize((int(bot.width * tall / bot.height), tall), Image.LANCZOS)
    pad = tall // 8
    canvas = Image.new('RGBA', (bot.width + pad * 2, tall + pad * 2), (0, 0, 0, 0))
    pool = Image.new('L', canvas.size, 0)
    ImageDraw.Draw(pool).ellipse((pad, tall + pad - tall // 14, pad + bot.width, tall + pad + tall // 14), fill=90)
    canvas.putalpha(pool.filter(ImageFilter.GaussianBlur(tall // 28)))
    canvas.alpha_composite(bot, (pad, pad))
    canvas.save(OUT / f"{kind.replace('_', '-')}.webp", quality=90, method=6)


crew = {kind: cut(kind) for kind, *_ in CAST}
OUT.mkdir(exist_ok=True)
make('hero-light.webp', 'page-light.webp', '#f5f6f8', '#2a2f38', 1.0)
make('hero-dark.webp', 'page.webp', '#0d1015', '#000000', .84, True)
for kind in ('bot_concierge', 'bot_courier', 'bot_butler'):
    robot(kind, 400)
