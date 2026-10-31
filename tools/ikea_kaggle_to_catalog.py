"""Turn the Kaggle "IKEA Global Product Catalog" CSV into a Poltar furniture catalogue.

The dataset (kaggle.com/datasets/ranjithpanicker/ikea-global-product-catalog-and-price-2026) is a third-party
snapshot with no licence, so its output is for your own phone only. It goes in the gitignored catalog-local/
folder and must never be committed: this repository is public. Only product facts are used (name, type, size,
price, link), never IKEA's descriptions, ratings or images.

Each piece is listed once, with an offer (price and local product page) per country that sells it. A piece's kind,
size and finish come from its English listing, so pieces sold only on non-English sites are left out. Anything
missing from a size is filled with a typical value for that kind, and the piece's note says so.

    python3 tools/ikea_kaggle_to_catalog.py IKEA_product_catalog.csv catalog-local/ikea-global.json

scripts/build_ikea_catalog.sh downloads the dataset and runs this for you.
"""

from __future__ import annotations

import csv
import json
import re
import sys
from pathlib import Path

SNAPSHOT_DATE = "2026-02-27"

# (category, product types that count, words that rule a row out)
KINDS: list[tuple[str, tuple[str, ...], tuple[str, ...]]] = [
    ("bed", ("bed frame", "upholstered bed frame", "bed frame with storage", "bed frame with 2 storage boxes", "day-bed"),
     ("cover", "bunk", "loft", "children")),
    ("nightstand", ("nightstand",), ("wall-mounted",)),
    ("desk", ("desk", "desk sit/stand", "desk with storage boxes", "gaming desk"), ("and chair", "combination", "add-on", "pad")),
    ("chair", ("office chair", "office chair with armrests", "office chair with arm/headrest", "gaming chair", "swivel chair",
               "desk chair"), ("children",)),
    ("wardrobe", ("wardrobe", "wardrobe with sliding doors", "wardrobe with 2 doors", "wardrobe with 3 doors", "wardrobe combination",
                  "wardrobe with 2 doors+2 drawers"), ("corner", "reach-in", "insert", "interior", "children")),
    ("dresser", ("6-drawer dresser", "8-drawer dresser", "4-drawer dresser", "3-drawer chest", "4-drawer chest", "5-drawer chest",
                 "6-drawer chest", "2-drawer chest", "chest of drawers"), ("mini",)),
    ("bookshelf", ("bookcase", "bookcase with doors", "bookcase with glass doors", "bookcase with panel/glass doors"), ("comb",)),
    ("storage", ("shelf unit", "shelf unit with doors", "shelf unit with 4 inserts", "cabinet", "storage combination", "sideboard",
                 "cabinet with doors", "display cabinet", "glass-door cabinet"), ("outdoor", "corner", "wall", "kitchen", "bathroom")),
    ("sofa", ("sofa", "sofabed", "sleeper sofa", "loveseat", "3-seat sofa", "2-seat sofa"), ("cover", "outdoor", "modular", "chaise")),
    ("armchair", ("armchair", "low-back armchair", "armchair with cushion", "rocking chair", "easy chair"),
     ("outdoor", "cover", "footstool", "table+", "children", "frame")),
    ("coffee_table", ("coffee table", "adjustable coffee table"), ("outdoor", "set of")),
    ("tv_stand", ("tv bench", "tv bench with doors", "tv bench with drawers", "tv unit"), ("underframe",)),
    ("side_table", ("side table", "side table on casters"), ("barbecue", "sink", "outdoor", "wall-mounted")),
    ("lamp", ("floor lamp", "floor lamp with led bulb", "floor lamp, arched", "floor/reading lamp", "floor uplighter/reading lamp"),
     ("base", "spotlight")),
    ("plant", ("artificial potted plant", "artificial potted plant with pot"), ("hanging",)),
    ("dining_table", ("table", "extendable table", "drop-leaf table", "dining table", "gateleg table"), ("outdoor", "chairs", "children")),
    ("bench", ("bench", "bench with storage", "storage bench", "bench with shoe storage"), ("outdoor", "tv ")),
]

CLEARANCE = {
    "bed": {"front": 0.6, "sides": 0.5}, "nightstand": {"front": 0.3}, "desk": {"front": 0.7}, "chair": {"front": 0.3, "back": 0.3},
    "wardrobe": {"front": 0.7}, "dresser": {"front": 0.6}, "bookshelf": {"front": 0.5}, "storage": {"front": 0.5},
    "sofa": {"front": 0.5, "sides": 0.1}, "armchair": {"front": 0.4}, "coffee_table": {"front": 0.3, "sides": 0.3, "back": 0.3},
    "tv_stand": {"front": 0.9}, "side_table": {"front": 0.2}, "lamp": {}, "plant": {},
    "dining_table": {"front": 0.6, "sides": 0.6, "back": 0.6}, "bench": {"front": 0.5},
}

# Typical heights (m) when only width and depth are published.
TYPICAL_HEIGHT = {"desk": 0.75, "dining_table": 0.75, "coffee_table": 0.45, "side_table": 0.5, "bench": 0.45,
                  "nightstand": 0.6, "tv_stand": 0.5, "dresser": 0.8, "storage": 0.9, "bookshelf": 1.8, "wardrobe": 2.0}
# Typical depths (m) for upright pieces, whose two published numbers are width and height.
TYPICAL_DEPTH = {"bookshelf": 0.3, "storage": 0.4, "wardrobe": 0.6, "dresser": 0.48, "nightstand": 0.4, "tv_stand": 0.4}
# Typical whole sizes (m) when nothing is published.
TYPICAL_SIZE = {"sofa": (2.0, 0.9, 0.85), "armchair": (0.8, 0.8, 0.8), "chair": (0.65, 0.65, 1.1)}
UNMEASURED_TYPES = ("sofa", "sofabed", "armchair", "office chair", "office chair with armrests", "low-back armchair")
# Bed frames from the mattress size: a little bigger than the mattress, with a headboard about 1 m high.
BED_SIZES = [("king", (2.0, 2.1, 1.0)), ("queen", (1.62, 2.1, 1.0)), ("full", (1.45, 2.05, 1.0)), ("double", (1.45, 2.05, 1.0)),
             ("twin", (1.0, 2.05, 1.0)), ("single", (1.0, 2.05, 1.0))]
COUNTRY_NAMES = {"Czech_Republic": "Czechia", "New_Zealand": "New Zealand", "Saudi_Arabia": "Saudi Arabia",
                 "South_Korea": "South Korea", "USA": "US", "UAE": "UAE"}

# Colour and material words in a product link, and the style tags the planner matches against a theme.
STYLE_WORDS = {
    "oak": ["scandinavian", "japandi", "warm"], "birch": ["scandinavian", "japandi"], "pine": ["scandinavian", "boho"],
    "walnut": ["mid-century", "warm"], "acacia": ["warm", "boho"], "ash": ["scandinavian"], "beech": ["scandinavian"],
    "teak": ["mid-century", "warm"], "bamboo": ["japandi", "boho"], "rattan": ["japandi", "boho"],
    "white": ["scandinavian", "minimalist", "modern"], "black": ["modern", "minimalist", "dark"], "anthracite": ["modern", "dark"],
    "gray": ["minimalist", "modern"], "grey": ["minimalist", "modern"], "beige": ["minimalist", "warm"], "natural": ["japandi", "minimalist"],
    "leather": ["warm", "mid-century"], "velvet": ["warm"], "metal": ["modern"], "steel": ["modern"], "green": ["boho"],
    "brown": ["warm"],
}

NUMBER = r"(\d+(?:\.\d+)?)"


def metres(text: str) -> list[float]:
    """The metric part of a measurement: '80x28x202 cm (31 1/2x11x79 1/2 ")' gives [0.8, 0.28, 2.02]."""
    m = re.match(rf"\s*{NUMBER}(?:x{NUMBER})?(?:x{NUMBER})?\s*cm", text or "")
    return [float(v) / 100 for v in m.groups() if v] if m else []


def inches(text: str) -> list[float]:
    """An imperial-only measurement such as '31 7/8x14 5/8x79 "', in metres."""
    if not re.fullmatch(r'[\d /x.]+"', (text or "").strip()):
        return []
    out = []
    for part in text.strip().rstrip('"').split("x"):
        value = 0.0
        for token in part.split():
            num, _, den = token.partition("/")
            try:
                value += float(num) / float(den) if den else float(num)
            except (ValueError, ZeroDivisionError):
                return []  # A range such as '27 1/4/70 7/8'.
        out.append(round(value * 0.0254, 3))
    return out


def bed_size(measurements: str) -> tuple[float, float, float] | None:
    low = measurements.lower()
    size = next((s for label, s in BED_SIZES if label in low), None)
    if size is None:
        m = metres(measurements)
        if len(m) == 2 and 0.7 <= m[0] <= 2.0 and 1.85 <= m[1] <= 2.15:
            size = (round(m[0] + 0.06, 3), round(m[1] + 0.1, 3), 1.0)
    return size


def finish_words(url: str, name: str, product_type: str) -> str:
    """The colour or finish part of a product link: 'billy-bookcase-white-20522046' gives 'white'."""
    slug = url.rstrip("/").rsplit("/", 1)[-1]
    words = [w for w in slug.split("-") if not re.fullmatch(r"s?\d+", w)]
    text = (name + " " + product_type).lower()
    drop = {"with", "and", "w"}
    # Links spell the product name without its accents, in one of two ways.
    for mapping in ({"ä": "a", "ö": "o", "å": "a", "ü": "u"}, {"ä": "ae", "ö": "oe", "å": "aa", "ü": "ue"}):
        plain = "".join(mapping.get(ch, ch) for ch in text)
        drop |= set(re.sub(r"[^a-z0-9 ]", " ", plain).split())
    return " ".join(w for w in words if w not in drop)


def shape(kind: str, ptype: str, measurements: str) -> tuple[tuple[float, float, float], list[str]] | None:
    """A piece's [width, depth, height] in metres and notes on anything estimated, or None to skip it."""
    measured = metres(measurements) or inches(measurements)
    notes = []
    if kind == "bed":
        size = bed_size(measurements)
        if size is None:
            return None
        notes.append(f"Frame size estimated from the bed size ({measurements}).")
        w, d, h = size
    elif kind == "lamp":
        h = measured[0] if len(measured) == 1 else 1.5
        w = d = 0.3
        notes.append("Base size estimated." if measured else "Size estimated.")
    elif kind == "plant":
        if len(measured) != 1 or measured[0] < 0.17:
            return None  # Small table-top plants.
        w = d = round(measured[0] + 0.05, 2)
        h = round(measured[0] * 4.5, 2)
        notes.append(f"Pot {round(measured[0] * 100)} cm across; plant height estimated.")
    elif len(measured) == 3:
        w, d, h = measured
    elif len(measured) == 2 and kind in TYPICAL_DEPTH and measured[1] > TYPICAL_HEIGHT[kind] * 0.6:
        w, h = measured
        d = TYPICAL_DEPTH[kind]
        notes.append("Depth estimated.")
    elif len(measured) == 2 and kind in TYPICAL_HEIGHT:
        w, d = measured
        h = TYPICAL_HEIGHT[kind]
        notes.append("Height estimated.")
    elif not measured and kind in TYPICAL_SIZE and ptype in UNMEASURED_TYPES:
        w, d, h = TYPICAL_SIZE[kind]
        notes.append("Size not published here; a typical size is assumed. Check the store page.")
    else:
        return None
    if not (0.1 <= w <= 3.0 and 0.1 <= d <= 3.0 and 0.05 <= h <= 2.6):
        return None
    return (round(w, 3), round(d, 3), round(h, 3)), notes


def convert(csv_path: Path) -> tuple[dict, list[dict]]:
    """The regions (code to name, currency and store) and the pieces, each with its offers by region."""
    regions: dict[str, dict] = {}
    described: dict[str, dict] = {}  # Product id to the English row that describes it, metric preferred.
    offers: dict[str, dict[str, list]] = {}
    with open(csv_path, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            url = row["url"].strip()
            m = re.match(r"https://www\.ikea\.com/([a-z]{2})/([a-z]{2})/p/", url)
            if not m or row.get("online_sellable") == "False":
                continue
            code, lang = m.group(1).upper(), m.group(2)
            if code not in regions:
                country = row["country"]
                name = COUNTRY_NAMES.get(country, country.replace("_", " "))
                regions[code] = {"name": name, "currency": row["currency"], "store": f"IKEA {name}"}
            pid = row["product_id"]
            if lang == "en":
                best = described.get(pid)
                if best is None or ("cm" in row["product_measurements"] and "cm" not in best["product_measurements"]):
                    described[pid] = row
            try:
                price = round(float(row["price"]), 2)
            except ValueError:
                continue
            if price > 0:
                offers.setdefault(pid, {}).setdefault(code, [price, url])

    items = []
    for pid, row in described.items():
        if pid not in offers:
            continue
        ptype = row["product_type"].strip().lower()
        kind = next((k for k, types, bad in KINDS if ptype in types and not any(b in ptype for b in bad)), None)
        if kind is None:
            continue
        shaped = shape(kind, ptype, row["product_measurements"])
        if shaped is None:
            continue
        size, notes = shaped
        finish = finish_words(row["url"], row["product_name"], ptype)
        notes.append("From a public catalogue snapshot; the price may have changed.")
        items.append({
            "catalog_id": f"ikea_{pid}",
            "name": f"{row['product_name'].strip()} {ptype}" + (f", {finish}" if finish else ""),
            "category": kind, "size": list(size),
            "styles": sorted({s for word in finish.split() for s in STYLE_WORDS.get(word, [])}),
            "clearance": CLEARANCE[kind], "note": " ".join(notes), "offers": dict(sorted(offers[pid].items())),
        })
    return dict(sorted(regions.items())), items


def main() -> None:
    source, target = Path(sys.argv[1]).expanduser(), Path(sys.argv[2]).expanduser()
    regions, items = convert(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({
        "catalog_version": 3, "updated": SNAPSHOT_DATE,
        "note": "From a third-party public snapshot on Kaggle; for personal use only.",
        "regions": regions, "items": items,
    }, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    kinds: dict[str, int] = {}
    for item in items:
        kinds[item["category"]] = kinds.get(item["category"], 0) + 1
    print(f"{len(items)} pieces in {len(regions)} regions -> {target}")
    print(", ".join(f"{k} {v}" for k, v in sorted(kinds.items())))


if __name__ == "__main__":
    main()
