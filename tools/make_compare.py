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
    font, pt = FONT, 30
    while pt > 16 and font.getlength(text) > size[0] - 32:     # a narrow close-up: a smaller label
        pt -= 2
        font = ImageFont.truetype(FONT.path, pt)
    ImageDraw.Draw(out).text((16, 8 + (30 - pt) // 2), text, font=font, fill=(235, 225, 200))
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


def ui_box(mode, x0, y0, x1, y1):
    """A rectangle of the 640x480 interface on a 3840x2160 shot: 'stretch' = the game without the mod (the
    interface stretched over 16:9), 'center' = a full-screen 4:3 screen with the mod, 'left' = the HUD's left
    column with the mod (moved to the screen edge)."""
    k = 4.5
    if mode == "stretch":
        return (round(x0 * 6), round(y0 * k), round(x1 * 6), round(y1 * k))
    dx = 480 if mode == "center" else 0
    return (round(dx + x0 * k), round(y0 * k), round(dx + x1 * k), round(y1 * k))


def crop_pair(before, after, rect, before_mode, after_mode, name, labels, height):
    """The same interface rectangle without and with the mod, side by side at the same height (4K pixels for
    the mod's side, the stretched picture squeezed back to 4:3 for the other)."""
    b = shot(before).crop(ui_box(before_mode, *rect))
    a = shot(after).crop(ui_box(after_mode, *rect))
    w = round(a.width * height / a.height)
    pair((b, labels[0]), (a, labels[1]), name, (w, height))


LABELS = {
    "": ("До: меню 640x480, растянуто на 16:9", "После: широкий HD-фон 3840x2160",
         "До: интерфейс 640x480 растянут на 16:9", "После: интерфейс по краям, HD-шрифт, HD-портреты и картинки",
         "До: шрифт игры 640x480, увеличенный до 4K", "После: TrueType-шрифт Jost в родном 4K"),
    "_en": ("Before: 640x480 menu stretched to 16:9", "After: wide HD background, 3840x2160",
            "Before: 640x480 interface stretched to 16:9", "After: HUD at the edges, HD font, portraits, pictures",
            "Before: the game's 640x480 font scaled to 4K", "After: Jost TrueType font at native 4K"),
}
# more screens: ex_off_* = the game without the mod, ex_on_* = with it (wizardry8-hdui tools/shoot_examples.sh)
SCREENS = {
    "": {
        "inventory": ("До: инвентарь растянут на 16:9", "После: 4:3 по центру, камень по бокам, всё в HD"),
        "skills": ("До: лист персонажа, пиксельный шрифт", "После: навыки, HD-шрифт и HD-рамки"),
        "spells": ("До: панель заклинаний", "После: панель заклинаний в HD, камень по бокам"),
        "map": ("До: карта растянута", "После: карта 4:3, HD-кнопки"),
        "rest": ("До: привал", "После: HD-фон привала, спящие HD-портреты"),
        "battle": ("До: бой с крабами", "После: тот же бой"),
        "items": ("До: предметы 640x480, увеличены до 4K", "После: предметы в HD (xBR), пиксели 4K 1:1"),
        "portraits": ("До: колонка портретов", "После: HD-портреты, рамки и полоски"),
    },
    "_en": {
        "inventory": ("Before: inventory stretched to 16:9", "After: 4:3 in the middle, stone beside, all HD"),
        "skills": ("Before: character sheet, pixel font", "After: skills with HD font and frames"),
        "spells": ("Before: spell panel", "After: HD spell panel, stone beside it"),
        "map": ("Before: automap stretched", "After: 4:3 automap, HD buttons"),
        "rest": ("Before: camp", "After: HD camp picture, sleeping HD portraits"),
        "battle": ("Before: a fight with crabs", "After: the same fight"),
        "items": ("Before: items, 640x480 scaled to 4K", "After: HD items (xBR), 4K pixels 1:1"),
        "portraits": ("Before: the portrait column", "After: HD portraits, frames and bars"),
    },
}
SHOT = {"inventory": "inv", "skills": "skills", "spells": "spells", "map": "map", "rest": "rest", "battle": "battle"}
box = (1300, 1560, 2600, 2160)
for sfx, t in LABELS.items():
    # menu: without the mod the game's own 640x480 frame is stretched over the 16:9 screen
    pair((shot("menu2d_2d.png"), t[0]), (shot("fin_menu.jpg"), t[1]), f"compare_menu{sfx}.jpg", (1280, 720))
    # world: same place, same party
    pair((shot("ex_off_hud.jpg"), t[2]), (shot("ex_on_hud.jpg"), t[3]), f"compare_game{sfx}.jpg", (1280, 720))
    # text close-up at native 4K pixels
    pair((shot("hud.png").crop(box), t[4]), (shot("fin_after.jpg").crop(box), t[5]), f"compare_text{sfx}.jpg",
         (1300, 600), vertical=True)
    s = SCREENS[sfx]
    for key, name in SHOT.items():
        pair((shot(f"ex_off_{name}.jpg"), s[key][0]), (shot(f"ex_on_{name}.jpg"), s[key][1]),
             f"compare_{key}{sfx}.jpg", (960, 540))
    # close-ups: the party's items in the inventory, the left portrait column in the HUD
    crop_pair("ex_off_inv.jpg", "ex_on_inv.jpg", (478, 168, 614, 320), "stretch", "center", f"compare_items{sfx}.jpg",
              s["items"], 640)
    crop_pair("ex_off_hud.jpg", "ex_on_hud.jpg", (0, 100, 128, 358), "stretch", "left", f"compare_portraits{sfx}.jpg",
              s["portraits"], 900)
