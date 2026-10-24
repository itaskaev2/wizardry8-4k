"""Build the before/after images in docs/ from screenshots taken while making the mod (wizardry8-hdui/shots).
Usage: python tools/make_compare.py <shots dir>"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

SHOTS = sys.argv[1]
DOCS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs")
FONT = ImageFont.truetype(os.path.join(os.path.dirname(DOCS), "payload", "wiz8hd_fonts", "Jost-500-Medium.ttf"), 30)
BAR = 52


def shot(name):
    return Image.open(os.path.join(SHOTS, name)).convert("RGB")


def labelled(img, text, size):
    img = img.resize(size, Image.LANCZOS)
    out = Image.new("RGB", (size[0], size[1] + BAR), (24, 24, 24))
    out.paste(img, (0, BAR))
    ImageDraw.Draw(out).text((16, 8), text, font=FONT, fill=(235, 225, 200))
    return out


def pair(before, after, name, size, vertical=False):
    a, b = labelled(before[0], before[1], size), labelled(after[0], after[1], size)
    gap = 8
    if vertical:
        out = Image.new("RGB", (a.width, a.height * 2 + gap), (0, 0, 0))
        out.paste(a, (0, 0)); out.paste(b, (0, a.height + gap))
    else:
        out = Image.new("RGB", (a.width * 2 + gap, a.height), (0, 0, 0))
        out.paste(a, (0, 0)); out.paste(b, (a.width + gap, 0))
    os.makedirs(DOCS, exist_ok=True)
    out.save(os.path.join(DOCS, name), quality=88)
    print(name, out.size)


LABELS = {
    "": ("До: меню 640x480, растянуто на 16:9", "После: широкий HD-фон 3840x2160",
         "До: интерфейс 640x480 4:3, пиксельный шрифт", "После: интерфейс по краям, HD-шрифт",
         "До: шрифт игры 640x480, увеличенный до 4K", "После: TrueType-шрифт Jost в родном 4K"),
    "_en": ("Before: 640x480 menu stretched to 16:9", "After: wide HD background, 3840x2160",
            "Before: 640x480 4:3 interface, pixel font", "After: interface at the edges, HD font",
            "Before: the game's 640x480 font scaled to 4K", "After: Jost TrueType font at native 4K"),
}
box = (1300, 1560, 2600, 2160)
for sfx, t in LABELS.items():
    # menu: without the mod the game's own 640x480 frame is stretched over the 16:9 screen
    pair((shot("menu2d_2d.png"), t[0]), (shot("fin_menu.jpg"), t[1]), f"compare_menu{sfx}.jpg", (1280, 720))
    # world: same place, same party
    pair((shot("hud.png"), t[2]), (shot("fin_after.jpg"), t[3]), f"compare_game{sfx}.jpg", (1280, 720))
    # text close-up at native 4K pixels
    pair((shot("hud.png").crop(box), t[4]), (shot("fin_after.jpg").crop(box), t[5]), f"compare_text{sfx}.jpg",
         (1300, 600), vertical=True)
