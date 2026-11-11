#!/usr/bin/env python3
"""Builds the flags of the 54 African countries from flag-icons (MIT).

    npm pack flag-icons && tar xzf flag-icons-*.tgz
    python3 scripts/build_flags.py package/flags/4x3

Writes priv/flags/<iso2>.svg (one per country, inlined in a country page by
SyliAtlasWeb.Flags) and priv/static/images/flags.svg (one <symbol> per
country, for pages that show many flags). Ids inside each flag get a prefix
so that several flags can share a page or a sprite.
"""
import re
import sys
from pathlib import Path

CODES = (
    "dz ao bj bw bf bi cv cm cf td km cg cd ci dj eg gq er sz et ga gm gh gn gw ke ls lr ly mg "
    "mw ml mr mu ma mz na ne ng rw st sn sc sl so za ss sd tz tg tn ug zm zw"
).split()

root = Path(__file__).resolve().parent.parent
src = Path(sys.argv[1] if len(sys.argv) > 1 else "package/flags/4x3")
out = root / "priv" / "flags"
out.mkdir(parents=True, exist_ok=True)


def clean(svg, cc):
    svg = re.sub(r"<\?xml.*?\?>|<!--.*?-->", "", svg, flags=re.S)
    svg = re.sub(r">\s+<", "><", svg.strip())
    svg = re.sub(r'\bid="([^"]+)"', lambda m: f'id="f{cc}-{m.group(1)}"', svg)
    svg = re.sub(r"url\(#([^)]+)\)", lambda m: f"url(#f{cc}-{m.group(1)})", svg)
    svg = re.sub(r'(xlink:href|href)="#([^"]+)"', lambda m: f'{m.group(1)}="#f{cc}-{m.group(2)}"', svg)
    return svg


def inner(svg):
    return re.sub(r"^<svg[^>]*>|</svg>$", "", svg)


symbols = []
for cc in CODES:
    svg = clean((src / f"{cc}.svg").read_text(), cc)
    view = re.search(r'viewBox="([^"]+)"', svg).group(1)
    body = inner(svg)
    (out / f"{cc}.svg").write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}">{body}</svg>\n')
    symbols.append(f'<symbol id="{cc}" viewBox="{view}">{body}</symbol>')

sprite = '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">' + "".join(symbols) + "</svg>\n"
(root / "priv" / "static" / "images" / "flags.svg").write_text(sprite)
print(f"{len(CODES)} flags, sprite {len(sprite)} bytes")
