#!/usr/bin/env python3
"""Flags of the trade partners outside Africa, from flag-icons (MIT).

    npm pack flag-icons && tar xzf flag-icons-*.tgz
    python3 scripts/build_world_flags.py package/flags/4x3

Takes every partner named in priv/data/trade.json and
priv/data/africa_trade.json (China, India, Switzerland…) and writes
priv/static/images/flags-world.svg (one <symbol> per country, ids are the
ISO 3166-1 alpha-2 codes) and priv/flags/world.json (alpha-3 -> alpha-2),
read by SyliAtlasWeb.Flags. Codes BACI gives without a country (« Other
Asia, not elsewhere specified ») get no flag.

Flags drawn with a detailed coat of arms (Mexico, Spain, Serbia…) weigh up to
180 KB each; above HEAVY bytes they are kept as a small PNG (rsvg-convert,
80×60, enough for the sizes shown) inside the symbol, so the sprite stays
light.
"""
import base64
import json
import re
import subprocess
import sys
from pathlib import Path

import pycountry



def clean(svg, prefix):
    """Same cleaning as build_flags.py: ids prefixed so flags can share a sprite."""
    svg = re.sub(r"<\?xml.*?\?>|<!--.*?-->", "", svg, flags=re.S)
    svg = re.sub(r">\s+<", "><", svg.strip())
    svg = re.sub(r'\bid="([^"]+)"', lambda m: f'id="f{prefix}-{m.group(1)}"', svg)
    svg = re.sub(r"url\(#([^)]+)\)", lambda m: f"url(#f{prefix}-{m.group(1)})", svg)
    svg = re.sub(r'(xlink:href|href)="#([^"]+)"', lambda m: f'{m.group(1)}="#f{prefix}-{m.group(2)}"', svg)
    return svg


def inner(svg):
    return re.sub(r"^<svg[^>]*>|</svg>$", "", svg)


root = Path(__file__).resolve().parent.parent
src = Path(sys.argv[1] if len(sys.argv) > 1 else "package/flags/4x3")
african = {a["code"] for a in json.load(open(root / "priv/data/areas.json"))["areas"] if a["kind"] == "country"}
codes = set()
for name in ("trade.json", "africa_trade.json"):
    codes |= set(json.load(open(root / "priv/data" / name)).get("partners", {}))

HEAVY = 6000

mapping, symbols = {}, []
for iso3 in sorted(codes - african):
    c = pycountry.countries.get(alpha_3=iso3)
    if not c or not (src / f"{c.alpha_2.lower()}.svg").exists():
        continue
    cc = c.alpha_2.lower()
    path = src / f"{cc}.svg"
    svg = clean(path.read_text(), "w" + cc)
    view = re.search(r'viewBox="([^"]+)"', svg).group(1)
    if path.stat().st_size > HEAVY:
        png = subprocess.run(
            ["rsvg-convert", "-w", "80", "-h", "60", str(path)], check=True, capture_output=True
        ).stdout
        _, _, w, h = view.split()
        body = (
            f'<image width="{w}" height="{h}" preserveAspectRatio="none" '
            f'href="data:image/png;base64,{base64.b64encode(png).decode()}"/>'
        )
    else:
        body = inner(svg)
    symbols.append(f'<symbol id="{cc}" viewBox="{view}">{body}</symbol>')
    mapping[iso3] = cc

sprite = '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">' + "".join(symbols) + "</svg>\n"
(root / "priv/static/images/flags-world.svg").write_text(sprite)
(root / "priv/flags/world.json").write_text(json.dumps(mapping, sort_keys=True, indent=0) + "\n")
print(f"{len(mapping)} flags, sprite {len(sprite)} bytes")
