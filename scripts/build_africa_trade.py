"""Africa as a whole and product pages, from CEPII's BACI (Licence Ouverte Etalab 2.0).

    python3 scripts/build_africa_trade.py BACI_HS22_V202601.zip priv/data/africa_trade.json \
        --bec HS2022toBEC5ConversionAndCorrelationTables.xlsx \
        --bec-codes BECCodeandDescription.xlsx \
        --history BACI_HS92_V202601.zip

Writes, for the latest year of the HS 2022 archive:
- "africa": exports and imports of the 54 countries taken together (trade
  between them counted once, on each side), main products (HS 4-digit) with
  Africa's share of world exports, clients, suppliers, exporters, importers,
  stage of processing (BEC rev. 5 plus Syli Atlas's "unwrought"), and the
  series since 2000 (HS 1992 archive; before 2000 BACI reports South Africa
  with its customs union neighbours, so the African total is not comparable).
- "products": for each product of PRODUCTS (HS prefixes), Africa's exports,
  imports and world share, every African exporter and importer above one
  million dollars, the world's main exporters, the clients and suppliers,
  the steps of its processing chain (share of Africa in world exports at
  each step) and the series since 2000.

Every share is a Syli Atlas calculation from BACI values (thousands of
current dollars, converted to dollars).
"""

import argparse
import json
import re
import sys
import zipfile
from collections import defaultdict
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from build_trade import baci_files, country_codes, names, stages  # noqa: E402
from trade_labels import HS4  # noqa: E402

# id -> core HS prefixes (what "the product" is), and processing chain steps
# (each a list of prefixes), from the least to the most processed.
PRODUCTS = {
    "cocoa": (["1801"], [["1801"], ["1803"], ["1804"], ["1805"], ["1806"]]),
    "coffee": (["0901"], [["0901"], ["210111", "210112"]]),
    "tea": (["0902"], None),
    "cashew": (["08013"], None),
    "cotton": (["5201"], [["5201"], ["5205"], ["5208", "5209", "5210", "5211", "5212"], ["6109"]]),
    "rubber": (["4001"], [["4001"], ["4011"]]),
    "vanilla": (["0905"], None),
    "flowers": (["0603"], None),
    "crude-oil": (["2709"], [["2709"], ["2710"]]),
    "gas": (["2711"], None),
    "gold": (["7108"], None),
    "diamonds": (["7102"], None),
    "platinum": (["7110"], None),
    "copper": (["2603", "7402", "7403"], [["2603"], ["7402"], ["7403"], ["7408"], ["8544"]]),
    "cobalt": (["2605", "2822", "8105"], [["2605"], ["2822"], ["8105"]]),
    "iron-ore": (["2601"], None),
    "manganese": (["2602"], None),
    "phosphates": (["2510"], [["2510"], ["2809"], ["3103", "3105"]]),
    "uranium": (["2612"], None),
    "wheat": (["1001"], [["1001"], ["1101"]]),
    "rice": (["1006"], None),
    "sugar": (["1701"], None),
    "palm-oil": (["1511"], None),
    "cars": (["8703"], None),
}

MIN_ROW = 1_000_000
FIRST_YEAR = 2000


def matches(k, prefixes):
    return k.str.startswith(tuple(prefixes))


def share(part, total):
    return round(100 * part / total, 1) if total else None


def ranked(series, total, n=None, minimum=0):
    s = series[series >= minimum].sort_values(ascending=False)
    if n:
        s = s.head(n)
    return [{"code": c, "value": round(v), "share": share(v, total)} for c, v in s.items()]


def load_year(z, name, codes):
    df = pd.read_csv(
        z.open(name),
        usecols=["i", "j", "k", "v"],
        dtype={"i": "int32", "j": "int32", "k": str, "v": "float64"},
    )
    iso = {c: v[0] for c, v in codes.items()}
    df["i"] = df["i"].map(iso)
    df["j"] = df["j"].map(iso)
    df["k"] = df["k"].str.zfill(6)
    df["v"] = df["v"] * 1000
    return df


def africa_block(df, african, stage_of):
    ex = df[df["i"].isin(african)]
    im = df[df["j"].isin(african)]
    world_h4 = df.groupby(df["k"].str[:4])["v"].sum()
    exports, imports = ex["v"].sum(), im["v"].sum()
    intra = ex[ex["j"].isin(african)]["v"].sum()

    top_ex = ex.groupby(ex["k"].str[:4])["v"].sum().sort_values(ascending=False).head(15)
    top_im = im.groupby(im["k"].str[:4])["v"].sum().sort_values(ascending=False).head(15)

    def stage(d):
        s = d.groupby(d["k"].map(stage_of).fillna("unknown"))["v"].sum()
        t = s.sum()
        return {k: share(s.get(k, 0), t) for k in ("primary", "unwrought", "intermediate", "final")}

    outside_ex = ex[~ex["j"].isin(african)]
    outside_im = im[~im["i"].isin(african)]

    return {
        "exports": round(exports),
        "imports": round(imports),
        "intra": round(intra),
        "intra_share": share(intra, exports),
        "stages": {"exports": stage(ex), "imports": stage(im)},
        "top_exports": [
            {"code": h, "value": round(v), "share": share(v, exports), "world_share": share(v, world_h4[h])}
            for h, v in top_ex.items()
        ],
        "top_imports": [{"code": h, "value": round(v), "share": share(v, imports)} for h, v in top_im.items()],
        # Clients and suppliers outside Africa: trade between African countries
        # is shown apart (intra), so the lists do not mix both.
        "clients": ranked(outside_ex.groupby("j")["v"].sum(), exports, 10),
        "suppliers": ranked(outside_im.groupby("i")["v"].sum(), imports, 10),
        "exporters": ranked(ex.groupby("i")["v"].sum(), exports),
        "importers": ranked(im.groupby("j")["v"].sum(), imports),
    }


def product_block(df, african, core, chain):
    sub = df[matches(df["k"], core)]
    ex = sub[sub["i"].isin(african)]
    im = sub[sub["j"].isin(african)]
    world = sub["v"].sum()
    exports, imports = ex["v"].sum(), im["v"].sum()
    by_exporter = ex.groupby("i")["v"].sum()
    world_by_exporter = sub.groupby("i")["v"].sum()

    exporters = [
        dict(row, world_share=share(row["value"], world))
        for row in ranked(by_exporter, exports, minimum=MIN_ROW)
    ]

    by_importer = im.groupby("j")["v"].sum()
    from_africa = im[im["i"].isin(african)].groupby("j")["v"].sum()
    importers = [
        dict(row, from_africa=share(from_africa.get(row["code"], 0), row["value"]))
        for row in ranked(by_importer, imports, minimum=MIN_ROW)
    ]

    steps = []
    for prefixes in chain or []:
        s = df[matches(df["k"], prefixes)]
        afr = s[s["i"].isin(african)]["v"].sum()
        top = s[s["i"].isin(african)].groupby("i")["v"].sum().sort_values(ascending=False).head(3)
        steps.append(
            {
                "codes": prefixes,
                "value": round(afr),
                "world": round(s["v"].sum()),
                "world_share": share(afr, s["v"].sum()),
                "exporters": [{"code": c, "share": share(v, afr)} for c, v in top.items()],
            }
        )

    return {
        "codes": core,
        "exports": round(exports),
        "imports": round(imports),
        "world": round(world),
        "world_share": share(exports, world),
        "intra": round(ex[ex["j"].isin(african)]["v"].sum()),
        "imports_from_africa": share(im[im["i"].isin(african)]["v"].sum(), imports),
        "exporters": exporters,
        "importers": importers,
        "world_top": [
            dict(r, african=r["code"] in african) for r in ranked(world_by_exporter, world, 10)
        ],
        "clients": ranked(ex.groupby("j")["v"].sum(), exports, 8),
        "suppliers": ranked(im.groupby("i")["v"].sum(), imports, 8),
        "chain": steps,
    }


def history(path, african):
    z = zipfile.ZipFile(path)
    codes = country_codes(z)
    out = {"africa": {}, "products": defaultdict(dict)}
    version = None
    for name in baci_files(z):
        year = int(re.search(r"_Y(\d{4})_", name).group(1))
        if year < FIRST_YEAR:
            continue
        version = re.search(r"_V(\d+)\.csv", name).group(1)
        df = load_year(z, name, codes)
        ex = df[df["i"].isin(african)]
        im = df[df["j"].isin(african)]
        out["africa"][str(year)] = {
            "exports": round(ex["v"].sum()),
            "imports": round(im["v"].sum()),
            "intra": round(ex[ex["j"].isin(african)]["v"].sum()),
        }
        for pid, (core, _chain) in PRODUCTS.items():
            out["products"][pid][str(year)] = {
                "exports": round(ex[matches(ex["k"], core)]["v"].sum()),
                "imports": round(im[matches(im["k"], core)]["v"].sum()),
            }
        print(year, file=sys.stderr, flush=True)
    return out, version


def main():
    p = argparse.ArgumentParser()
    p.add_argument("archive")
    p.add_argument("output")
    p.add_argument("--bec", required=True)
    p.add_argument("--bec-codes", required=True)
    p.add_argument("--history", required=True)
    p.add_argument("--areas", default="priv/data/areas.json")
    args = p.parse_args()

    areas = json.load(open(args.areas))["areas"]
    african = {a["code"] for a in areas if a["kind"] == "country"}

    z = zipfile.ZipFile(args.archive)
    codes = country_codes(z)
    latest = baci_files(z)[-1]
    year = int(re.search(r"_Y(\d{4})_", latest).group(1))
    version = re.search(r"_V(\d+)\.csv", latest).group(1)
    df = load_year(z, latest, codes)
    stage_of = stages(args.bec, args.bec_codes)

    africa = africa_block(df, african, stage_of)
    products = {pid: product_block(df, african, core, chain) for pid, (core, chain) in PRODUCTS.items()}

    hist, hist_version = history(args.history, african)
    africa["history"] = hist["africa"]
    for pid in products:
        products[pid]["history"] = hist["products"][pid]

    # Names of every partner used, for countries outside Africa.
    used = set()
    for key in ("clients", "suppliers", "exporters", "importers"):
        used |= {r["code"] for r in africa[key]}
    for prod in products.values():
        for key in ("exporters", "importers", "world_top", "clients", "suppliers"):
            used |= {r["code"] for r in prod[key]}
        for step in prod["chain"]:
            used |= {r["code"] for r in step["exporters"]}
    by_iso = {v[0]: v[1] for v in codes.values()}
    partners = {c: names(c, by_iso.get(c, c)) for c in sorted(used - african)}

    needed = {r["code"] for r in africa["top_exports"] + africa["top_imports"]}
    missing = sorted(h for h in needed if h not in HS4)
    if missing:
        sys.exit("HS4 labels missing in trade_labels.py: " + ", ".join(missing))

    doc = {
        "source": {
            "name": "CEPII, BACI",
            "url": "https://www.cepii.fr/CEPII/en/bdd_modele/bdd_modele_item.asp?id=37",
            "license": "Licence Ouverte Etalab 2.0",
            "version": version,
            "nomenclature": "HS 2022",
        },
        "history_source": {"nomenclature": "HS 1992", "version": hist_version, "first_year": FIRST_YEAR},
        "year": year,
        "headings": {h: {"fr": HS4[h][0], "en": HS4[h][1]} for h in sorted(needed)},
        "partners": partners,
        "africa": africa,
        "products": products,
    }
    with open(args.output, "w") as f:
        json.dump(doc, f, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    print(f"{args.output}: {len(products)} products, year {year}", file=sys.stderr)


if __name__ == "__main__":
    main()
