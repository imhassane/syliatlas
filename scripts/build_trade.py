"""Builds priv/data/trade.json: goods trade of the 54 African countries.

Source: CEPII, BACI (HS 2022 nomenclature), Licence Ouverte Etalab 2.0.
BACI reconciles what exporters and importers declare to UN Comtrade, so
countries that report little still have figures. Values are in thousands of
US dollars in the files, in dollars here.

For each country and the latest year: exports and imports, the five main
export chapters (HS 2-digit, labels below), the five main clients and
suppliers, the share of trade with other African countries, and two
dependence measures computed by Syli Atlas (share of the first chapter,
Herfindahl index over chapters). Exports of the earlier years of the file
give the trend.

    python3 scripts/build_trade.py BACI_HS22_V202601.zip priv/data/trade.json

Partner names in French come from pycountry's ISO 3166 translations, with
the short forms below where the official name is long.
"""
import csv, io, json, sys, zipfile, re, gettext
from collections import defaultdict

import pycountry

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


def main(zip_path, out_path):
    areas = json.load(open("priv/data/areas.json"))["areas"]
    african = {a["code"] for a in areas if a["kind"] == "country"}

    z = zipfile.ZipFile(zip_path)
    files = sorted(n for n in z.namelist() if re.match(r"BACI_HS\d+_Y\d{4}_V\d+\.csv", n))
    version = re.search(r"_V(\d+)\.csv", files[0]).group(1)
    nomenclature = re.match(r"BACI_(HS\d+)_", files[0]).group(1)
    codes = {}
    with z.open(next(n for n in z.namelist() if n.startswith("country_codes"))) as f:
        for r in csv.DictReader(io.TextIOWrapper(f, "utf-8")):
            codes[r["country_code"]] = (r["country_iso3"], r["country_name"])

    exports_by_year = defaultdict(dict)
    latest = files[-1]
    year = int(re.search(r"_Y(\d{4})_", latest).group(1))

    exp_total = defaultdict(float); imp_total = defaultdict(float)
    exp_chapter = defaultdict(lambda: defaultdict(float))
    exp_partner = defaultdict(lambda: defaultdict(float))
    imp_partner = defaultdict(lambda: defaultdict(float))
    exp_africa = defaultdict(float); imp_africa = defaultdict(float)

    for name in files:
        y = int(re.search(r"_Y(\d{4})_", name).group(1))
        totals = defaultdict(float)
        with z.open(name) as f:
            for r in csv.DictReader(io.TextIOWrapper(f, "utf-8")):
                i = codes.get(r["i"], (None,))[0]
                j = codes.get(r["j"], (None,))[0]
                if i not in african and j not in african:
                    continue
                v = float(r["v"]) * 1000
                if i in african:
                    totals[i] += v
                if y != year:
                    continue
                if i in african:
                    exp_total[i] += v
                    exp_chapter[i][r["k"][:2]] += v
                    exp_partner[i][j] += v
                    if j in african:
                        exp_africa[i] += v
                if j in african:
                    imp_total[j] += v
                    imp_partner[j][i] += v
                    if i in african:
                        imp_africa[j] += v
        for c, v in totals.items():
            exports_by_year[c][str(y)] = round(v)
        print(name, "read", file=sys.stderr)

    partner_names = {}
    countries = {}
    for c in sorted(african):
        total = exp_total.get(c, 0)
        if not total:
            continue
        chapters = exp_chapter[c]
        shares = [v / total for v in chapters.values()]
        tops = top(chapters, total)
        clients = top(exp_partner[c], total)
        suppliers = top(imp_partner[c], imp_total.get(c, 0))
        for p, _, _ in clients + suppliers:
            if p and p not in partner_names:
                partner_names[p] = names(p, next((n for iso, n in codes.values() if iso == p), p))
        countries[c] = {
            "exports_usd": round(total),
            "imports_usd": round(imp_total.get(c, 0)),
            "exports_by_year": exports_by_year[c],
            "top_exports": [{"chapter": k, "value": round(v), "share": s} for k, v, s in tops],
            "top_clients": [{"code": k, "value": round(v), "share": s} for k, v, s in clients],
            "top_suppliers": [{"code": k, "value": round(v), "share": s} for k, v, s in suppliers],
            "africa_share_exports": round(100 * exp_africa[c] / total, 1),
            "africa_share_imports": round(100 * imp_africa[c] / imp_total[c], 1) if imp_total.get(c) else None,
            "first_chapter_share": tops[0][2] if tops else None,
            "top5_share": round(sum(s for _, _, s in tops), 1),
            "hhi": round(sum(s * s for s in shares), 3),
        }

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
        "partners": partner_names,
        "countries": countries,
    }
    json.dump(out, open(out_path, "w"), ensure_ascii=False, indent=1)
    print(f"{out_path}: {len(countries)} countries, {year}", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
