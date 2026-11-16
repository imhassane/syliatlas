"""Builds priv/data/trade.json: goods trade of the 54 African countries.

Source: CEPII, BACI, Licence Ouverte Etalab 2.0. BACI reconciles what
exporters and importers declare to UN Comtrade, so countries that report
little still have figures. Values are in thousands of US dollars in the
files, in dollars here.

For each country and the latest year of the HS 2022 archive:

  * exports and imports, the five main export chapters (HS 2-digit), the
    five main clients and suppliers, the share of trade with other African
    countries, two dependence measures (share of the first chapter,
    Herfindahl index over chapters);
  * the main exported products (HS 4-digit headings) and, for each, its
    five main buyers;
  * the stage of processing of exports and imports: primary goods, gold,
    precious stones and unwrought metals (counted apart: the BEC calls them
    processed), processed intermediate goods, final goods (consumption and
    capital), from the United Nations correspondence between HS 2022 and the
    Classification by Broad Economic Categories, revision 5;
  * trade with each other African country, and the main product sold to
    the largest African partners;
  * the "African potential" (a Syli Atlas calculation, shown as such):
    HS 6-digit products the country buys outside Africa while other African
    countries already export at least as much of them to the world, grouped
    by HS 4-digit heading, with the main African exporters.

From the HS 1992 archive (optional, 1995 onwards): exports per year and the
share of the latest first chapter, for the long trend.

    python3 scripts/build_trade.py BACI_HS22_V202601.zip priv/data/trade.json \
        --bec HS2022toBEC5ConversionAndCorrelationTables.xlsx \
        --bec-codes BECCodeandDescription.xlsx \
        --history BACI_HS92_V202601.zip

The two BEC files come from https://unstats.un.org/unsd/classifications/Econ.
Partner names in French come from pycountry's ISO 3166 translations, with
the short forms below where the official name is long. Heading labels are
in scripts/trade_labels.py.
"""
import argparse, json, re, sys, zipfile, gettext
from collections import defaultdict

import pandas as pd
import pycountry

from trade_labels import HS4

# HS 2022 chapters, short labels (fr, en).
CHAPTERS = {
    "01": ("Animaux vivants", "Live animals"),
    "02": ("Viandes", "Meat"),
    "03": ("Poissons et fruits de mer", "Fish and seafood"),
    "04": ("Produits laitiers, œufs, miel", "Dairy, eggs, honey"),
    "05": ("Autres produits d'origine animale", "Other animal products"),
    "06": ("Plantes et fleurs coupées", "Plants and cut flowers"),
    "07": ("Légumes", "Vegetables"),
    "08": ("Fruits et noix (dont cajou)", "Fruit and nuts (incl. cashews)"),
    "09": ("Café, thé, épices", "Coffee, tea, spices"),
    "10": ("Céréales", "Cereals"),
    "11": ("Farines et malt", "Flour and malt"),
    "12": ("Graines oléagineuses", "Oil seeds"),
    "13": ("Gommes et résines", "Gums and resins"),
    "14": ("Matières à tresser", "Plaiting materials"),
    "15": ("Huiles et graisses (dont palme)", "Fats and oils (incl. palm)"),
    "16": ("Préparations de viande et de poisson", "Meat and fish preparations"),
    "17": ("Sucres", "Sugar"),
    "18": ("Cacao et ses préparations", "Cocoa and cocoa products"),
    "19": ("Préparations à base de céréales", "Cereal preparations"),
    "20": ("Préparations de légumes et de fruits", "Vegetable and fruit preparations"),
    "21": ("Préparations alimentaires diverses", "Other food preparations"),
    "22": ("Boissons", "Beverages"),
    "23": ("Résidus alimentaires, aliments pour animaux", "Food residues, animal feed"),
    "24": ("Tabac", "Tobacco"),
    "25": ("Sel, soufre, ciment, pierres", "Salt, sulphur, cement, stone"),
    "26": ("Minerais (fer, cuivre, cobalt, manganèse…)", "Ores (iron, copper, cobalt, manganese…)"),
    "27": ("Pétrole, gaz, charbon", "Oil, gas, coal"),
    "28": ("Produits chimiques inorganiques", "Inorganic chemicals"),
    "29": ("Produits chimiques organiques", "Organic chemicals"),
    "30": ("Produits pharmaceutiques", "Pharmaceuticals"),
    "31": ("Engrais", "Fertilisers"),
    "32": ("Teintures et peintures", "Dyes and paints"),
    "33": ("Huiles essentielles, cosmétiques", "Essential oils, cosmetics"),
    "34": ("Savons et détergents", "Soaps and detergents"),
    "35": ("Matières albuminoïdes, colles", "Albuminoids, glues"),
    "36": ("Explosifs", "Explosives"),
    "37": ("Produits photographiques", "Photographic goods"),
    "38": ("Produits chimiques divers", "Other chemicals"),
    "39": ("Plastiques", "Plastics"),
    "40": ("Caoutchouc", "Rubber"),
    "41": ("Peaux et cuirs", "Hides and skins"),
    "42": ("Articles en cuir", "Leather goods"),
    "43": ("Pelleteries", "Furskins"),
    "44": ("Bois", "Wood"),
    "45": ("Liège", "Cork"),
    "46": ("Vannerie", "Basketwork"),
    "47": ("Pâtes à papier", "Wood pulp"),
    "48": ("Papiers et cartons", "Paper and paperboard"),
    "49": ("Produits de l'édition", "Printed matter"),
    "50": ("Soie", "Silk"),
    "51": ("Laine", "Wool"),
    "52": ("Coton", "Cotton"),
    "53": ("Autres fibres végétales", "Other vegetable fibres"),
    "54": ("Filaments synthétiques", "Man-made filaments"),
    "55": ("Fibres synthétiques", "Man-made staple fibres"),
    "56": ("Ouates, ficelles, cordages", "Wadding, twine, ropes"),
    "57": ("Tapis", "Carpets"),
    "58": ("Tissus spéciaux", "Special fabrics"),
    "59": ("Tissus techniques", "Technical fabrics"),
    "60": ("Étoffes de bonneterie", "Knitted fabrics"),
    "61": ("Vêtements en maille", "Knitted clothing"),
    "62": ("Vêtements, autres qu'en maille", "Woven clothing"),
    "63": ("Autres articles textiles", "Other textile articles"),
    "64": ("Chaussures", "Footwear"),
    "65": ("Coiffures", "Headgear"),
    "66": ("Parapluies, cannes", "Umbrellas, sticks"),
    "67": ("Plumes, fleurs artificielles", "Feathers, artificial flowers"),
    "68": ("Ouvrages en pierre, ciment", "Stone and cement articles"),
    "69": ("Céramique", "Ceramics"),
    "70": ("Verre", "Glass"),
    "71": ("Or, diamants et métaux précieux", "Gold, diamonds and precious metals"),
    "72": ("Fonte, fer et acier", "Iron and steel"),
    "73": ("Ouvrages en fer ou acier", "Iron and steel articles"),
    "74": ("Cuivre", "Copper"),
    "75": ("Nickel", "Nickel"),
    "76": ("Aluminium", "Aluminium"),
    "78": ("Plomb", "Lead"),
    "79": ("Zinc", "Zinc"),
    "80": ("Étain", "Tin"),
    "81": ("Autres métaux (cobalt, titane…)", "Other base metals (cobalt, titanium…)"),
    "82": ("Outils", "Tools"),
    "83": ("Ouvrages divers en métaux", "Misc. metal articles"),
    "84": ("Machines", "Machinery"),
    "85": ("Machines et appareils électriques", "Electrical equipment"),
    "86": ("Matériel ferroviaire", "Railway equipment"),
    "87": ("Véhicules", "Vehicles"),
    "88": ("Aéronefs", "Aircraft"),
    "89": ("Navires", "Ships"),
    "90": ("Instruments d'optique et de mesure", "Optical and measuring instruments"),
    "91": ("Horlogerie", "Clocks and watches"),
    "92": ("Instruments de musique", "Musical instruments"),
    "93": ("Armes et munitions", "Arms and ammunition"),
    "94": ("Meubles", "Furniture"),
    "95": ("Jouets et articles de sport", "Toys and sports goods"),
    "96": ("Ouvrages divers", "Misc. manufactured articles"),
    "97": ("Objets d'art", "Works of art"),
    "99": ("Non classé", "Not classified"),
}

SHORT_FR = {
    "USA": "États-Unis", "GBR": "Royaume-Uni", "KOR": "Corée du Sud", "PRK": "Corée du Nord",
    "RUS": "Russie", "IRN": "Iran", "VNM": "Viêt Nam", "TZA": "Tanzanie", "COD": "RD Congo",
    "BOL": "Bolivie", "VEN": "Venezuela", "SYR": "Syrie", "TWN": "Taïwan", "MDA": "Moldavie",
    "LAO": "Laos", "CZE": "Tchéquie", "TUR": "Turquie", "ARE": "Émirats arabes unis",
    "NLD": "Pays-Bas", "CIV": "Côte d'Ivoire", "CPV": "Cabo Verde", "SWZ": "Eswatini",
}
SHORT_EN = {
    "USA": "United States", "GBR": "United Kingdom", "KOR": "South Korea", "RUS": "Russia",
    "IRN": "Iran", "VNM": "Vietnam", "TZA": "Tanzania", "COD": "DR Congo", "TWN": "Taiwan",
    "TUR": "Türkiye", "ARE": "United Arab Emirates", "BOL": "Bolivia", "VEN": "Venezuela",
    "SYR": "Syria", "LAO": "Laos", "MDA": "Moldova", "CZE": "Czechia", "CIV": "Côte d'Ivoire",
}


def names(iso3, fallback):
    fr = gettext.translation("iso3166-1", pycountry.LOCALES_DIR, languages=["fr"])
    c = pycountry.countries.get(alpha_3=iso3)
    en = SHORT_EN.get(iso3) or (c and getattr(c, "common_name", None) or (c and c.name)) or fallback
    fr_name = SHORT_FR.get(iso3) or (c and fr.gettext(getattr(c, "common_name", None) or c.name)) or fallback
    return {"fr": fr_name, "en": en}


def top(d, total, n=5):
    rows = sorted(d.items(), key=lambda kv: -kv[1])[:n]
    return [(k, v, round(100 * v / total, 1) if total else None) for k, v in rows]


def pct(part, total):
    return round(100 * part / total, 1) if total else None


def baci_files(z):
    files = sorted(n for n in z.namelist() if re.match(r"BACI_HS\d+_Y\d{4}_V\d+\.csv", n))
    return files


def country_codes(z):
    name = next(n for n in z.namelist() if n.startswith("country_codes"))
    df = pd.read_csv(z.open(name), dtype=str)
    return {int(r.country_code): (r.country_iso3, r.country_name) for r in df.itertuples()}


def read_year(z, name, codes, african):
    """Flows of one year touching Africa: i, j as ISO3, k as HS6 string, v in dollars."""
    df = pd.read_csv(
        z.open(name), usecols=["i", "j", "k", "v"],
        dtype={"i": "int32", "j": "int32", "k": str, "v": "float64"},
    )
    iso = {c: v[0] for c, v in codes.items()}
    df["i"] = df["i"].map(iso)
    df["j"] = df["j"].map(iso)
    df["k"] = df["k"].str.zfill(6)
    df["v"] = df["v"] * 1000
    return df


# Headings the BEC counts as processed goods although they leave the country as
# barely processed raw materials: gold, silver, platinum, diamonds and precious
# stones, unwrought or as waste, and unwrought base metals (copper cathodes,
# nickel, aluminium, zinc, tin, cobalt…). Syli Atlas puts them in a category of
# their own ("unwrought"), shown as such, so that a gold or copper exporter is
# not presented as a seller of processed goods.
UNWROUGHT = {
    "7102", "7103", "7106", "7108", "7110", "7112",
    "7401", "7402", "7403", "7404", "7405",
    "7501", "7502", "7503", "7601", "7602", "7801", "7802",
    "7901", "7902", "8001", "8002",
    "8101", "8102", "8103", "8104", "8105", "8106", "8108", "8109", "8110", "8111", "8112",
}


def stages(bec_path, bec_codes_path):
    """HS 2022 six-digit code -> primary / unwrought / intermediate / final (BEC rev. 5)."""
    desc = pd.read_excel(bec_codes_path, sheet_name="BEC5", dtype=str)
    desc = dict(zip(desc["Code"], desc["Description"]))
    conv = pd.read_excel(bec_path, sheet_name=0, dtype=str)
    out = {}
    for hs, bec in zip(conv.iloc[:, 0], conv.iloc[:, 1]):
        parts = [p.strip() for p in str(desc.get(bec, "")).split("|")]
        if hs.zfill(6)[:4] in UNWROUGHT and "Primary" not in parts:
            out[hs.zfill(6)] = "unwrought"
        elif "Primary" in parts:
            out[hs.zfill(6)] = "primary"
        elif "Intermediate Consumption" in parts:
            out[hs.zfill(6)] = "intermediate"
        elif "Final Consumption" in parts or "Gross Fixed Capital Formation" in parts:
            out[hs.zfill(6)] = "final"
    return out


def stage_shares(df, stage_of):
    s = df.groupby(df["k"].map(stage_of).fillna("unknown"))["v"].sum()
    total = s.sum()
    return {k: pct(s.get(k, 0), total) for k in ("primary", "unwrought", "intermediate", "final")}


def history(path, codes_hint, african, first_chapters):
    """Exports per year and share of the latest first chapter, HS 1992 archive."""
    z = zipfile.ZipFile(path)
    codes = country_codes(z)
    by_year = defaultdict(dict)
    chapter_share = defaultdict(dict)
    version = None
    for name in baci_files(z):
        y = re.search(r"_Y(\d{4})_", name).group(1)
        version = re.search(r"_V(\d+)\.csv", name).group(1)
        df = read_year(z, name, codes, african)
        df = df[df["i"].isin(african)]
        totals = df.groupby("i")["v"].sum()
        ch = df.groupby([df["i"], df["k"].str[:2]])["v"].sum()
        for c, total in totals.items():
            by_year[c][y] = round(total)
            first = first_chapters.get(c)
            if first:
                chapter_share[c][y] = pct(ch.get((c, first), 0), total)
        print(name, "read", file=sys.stderr)
    return by_year, chapter_share, version


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("zip_path")
    ap.add_argument("out_path")
    ap.add_argument("--bec")
    ap.add_argument("--bec-codes")
    ap.add_argument("--history")
    args = ap.parse_args()

    areas = json.load(open("priv/data/areas.json"))["areas"]
    african = {a["code"] for a in areas if a["kind"] == "country"}

    z = zipfile.ZipFile(args.zip_path)
    files = baci_files(z)
    version = re.search(r"_V(\d+)\.csv", files[0]).group(1)
    nomenclature = re.match(r"BACI_(HS\d+)_", files[0]).group(1)
    codes = country_codes(z)
    name_of = {iso: n for iso, n in codes.values()}
    latest = files[-1]
    year = int(re.search(r"_Y(\d{4})_", latest).group(1))

    exports_by_year = defaultdict(dict)
    for name in files[:-1]:
        df = read_year(z, name, codes, african)
        y = re.search(r"_Y(\d{4})_", name).group(1)
        for c, v in df[df["i"].isin(african)].groupby("i")["v"].sum().items():
            exports_by_year[c][y] = round(v)
        print(name, "read", file=sys.stderr)

    df = read_year(z, latest, codes, african)
    print(latest, "read", file=sys.stderr)
    df["h4"] = df["k"].str[:4]
    df["ch"] = df["k"].str[:2]
    exp = df[df["i"].isin(african)]
    imp = df[df["j"].isin(african)]
    for c, v in exp.groupby("i")["v"].sum().items():
        exports_by_year[c][str(year)] = round(v)

    stage_of = stages(args.bec, args.bec_codes) if args.bec else {}

    # African supply of each HS6 line: what each African country sells to the world.
    afr_supply = exp.groupby(["k", "i"])["v"].sum()
    afr_supply_total = exp.groupby("k")["v"].sum()

    partner_names = {}
    countries = {}
    used_h4 = set()

    def remember(p):
        if p and isinstance(p, str) and p not in partner_names:
            partner_names[p] = names(p, name_of.get(p, p))

    for c in sorted(african):
        e = exp[exp["i"] == c]
        m = imp[imp["j"] == c]
        total = e["v"].sum()
        if not total:
            continue
        imp_total = m["v"].sum()
        chapters = e.groupby("ch")["v"].sum().to_dict()
        shares = [v / total for v in chapters.values()]
        tops = top(chapters, total)
        clients = top(e.groupby("j")["v"].sum().to_dict(), total)
        suppliers = top(m.groupby("i")["v"].sum().to_dict(), imp_total)
        for p, _, _ in clients + suppliers:
            remember(p)

        # Main products (HS4) and their buyers.
        products = []
        for h4, v, s in top(e.groupby("h4")["v"].sum().to_dict(), total, 6):
            buyers = top(e[e["h4"] == h4].groupby("j")["v"].sum().to_dict(), v)
            for p, _, _ in buyers:
                remember(p)
            used_h4.add(h4)
            products.append({
                "code": h4, "value": round(v), "share": s,
                "clients": [{"code": p, "share": bs} for p, _, bs in buyers],
            })
        by_h6 = e.groupby("k")["v"].sum()

        # Trade with each African partner.
        e_afr = e[e["j"].isin(african)].groupby("j")["v"].sum()
        m_afr = m[m["i"].isin(african)].groupby("i")["v"].sum()
        africa = {}
        for p in sorted(set(e_afr.index) | set(m_afr.index)):
            if p == c:
                continue
            africa[p] = [round(e_afr.get(p, 0)), round(m_afr.get(p, 0))]
        africa_top = []
        for p, (ev, iv) in sorted(africa.items(), key=lambda kv: -(kv[1][0] + kv[1][1]))[:5]:
            remember(p)
            sold = e[e["j"] == p].groupby("h4")["v"].sum()
            h4 = sold.idxmax() if len(sold) else None
            if h4:
                used_h4.add(h4)
            africa_top.append({"code": p, "exports": ev, "imports": iv, "product": h4})

        # African potential: HS6 bought outside Africa that other African countries export.
        outside = m[~m["i"].isin(african)]
        out_h6 = outside.groupby("k")["v"].sum()
        lines = []
        for k, v in out_h6.items():
            if v < 1e6:
                continue
            others = afr_supply_total.get(k, 0) - afr_supply.get((k, c), 0)
            if others >= max(5e6, v):
                lines.append(k)
        potential = []
        if lines:
            sel = outside[outside["k"].isin(lines)]
            per_h4 = sel.groupby("h4")["v"].sum().sort_values(ascending=False)
            for h4, v in per_h4.head(5).items():
                ks = [k for k in lines if k[:4] == h4]
                supplier = sel[sel["h4"] == h4].groupby("i")["v"].sum().idxmax()
                sup = afr_supply[afr_supply.index.get_level_values(0).isin(ks)]
                sup = sup.groupby(level=1).sum().drop(c, errors="ignore").sort_values(ascending=False)
                exporters = [p for p in sup.index[:3]]
                for p in exporters + [supplier]:
                    remember(p)
                used_h4.add(h4)
                potential.append({
                    "code": h4, "value": round(v), "supplier": supplier,
                    "exporters": exporters,
                })

        entry = {
            "exports_usd": round(total),
            "imports_usd": round(imp_total),
            "exports_by_year": exports_by_year[c],
            "top_exports": [{"chapter": k, "value": round(v), "share": s} for k, v, s in tops],
            "top_clients": [{"code": k, "value": round(v), "share": s} for k, v, s in clients],
            "top_suppliers": [{"code": k, "value": round(v), "share": s} for k, v, s in suppliers],
            "africa_share_exports": pct(e_afr.sum(), total),
            "africa_share_imports": pct(m_afr.sum(), imp_total),
            "first_chapter_share": tops[0][2] if tops else None,
            "top5_share": round(sum(s for _, _, s in tops), 1),
            "hhi": round(sum(s * s for s in shares), 3),
            "top_products": products,
            "products_exported": int((by_h6 > 0).sum()),
            "products_over_1m": int((by_h6 >= 1e6).sum()),
            "africa_partners": africa_top,
            "africa_trade": africa,
            "potential": potential,
        }
        if stage_of:
            entry["stages"] = {"exports": stage_shares(e, stage_of), "imports": stage_shares(m, stage_of)}
        countries[c] = entry

    hist_version = None
    if args.history:
        first = {c: v["top_exports"][0]["chapter"] for c, v in countries.items() if v["top_exports"]}
        by_year, chapter_share, hist_version = history(args.history, codes, african, first)
        for c, v in countries.items():
            v["history"] = {"exports": by_year.get(c, {}), "first_chapter_share": chapter_share.get(c, {})}

    missing = sorted(h for h in used_h4 if h not in HS4)
    if missing:
        sys.exit("labels missing in scripts/trade_labels.py: " + " ".join(missing))

    out = {
        "source": {
            "name": "CEPII, BACI",
            "url": "https://www.cepii.fr/CEPII/en/bdd_modele/bdd_modele_item.asp?id=37",
            "license": "Licence Ouverte Etalab 2.0",
            "version": version,
            "nomenclature": nomenclature,
        },
        "year": year,
        "chapters": {k: {"fr": fr, "en": en} for k, (fr, en) in CHAPTERS.items()},
        "headings": {h: {"fr": HS4[h][0], "en": HS4[h][1]} for h in sorted(used_h4)},
        "partners": partner_names,
        "countries": countries,
    }
    if args.bec:
        out["stages_source"] = {
            "name": "United Nations Statistics Division, HS 2022 to BEC Rev. 5 conversion table",
            "url": "https://unstats.un.org/unsd/classifications/Econ",
        }
    if hist_version:
        out["history_source"] = {"nomenclature": "HS92", "version": hist_version}
    json.dump(out, open(args.out_path, "w"), ensure_ascii=False, indent=1)
    print(f"{args.out_path}: {len(countries)} countries, {year}", file=sys.stderr)


if __name__ == "__main__":
    main()
