"""Builds priv/data/africa_map.json: SVG paths of African countries.

Source: Natural Earth admin-0 countries (public domain), through the
world-atlas TopoJSON, already cut to Africa as GeoJSON (one feature per
ISO 3166-1 alpha-3 code). Equirectangular projection, simplified with
Ramer–Douglas–Peucker at 0.7 px for a 640 px wide map.

    python3 scripts/build_africa_map.py africa.geojson priv/data/africa_map.json
"""
import json, math, sys

LON0, LON1, LAT0, LAT1 = -26.0, 58.0, -35.5, 38.0
WIDTH, EPS = 640, 0.7

def rdp(pts, eps):
    if len(pts) < 3: return pts
    (x1, y1), (x2, y2) = pts[0], pts[-1]
    dx, dy = x2 - x1, y2 - y1; n = math.hypot(dx, dy) or 1e-9
    i, dmax = 0, 0
    for k in range(1, len(pts) - 1):
        d = abs(dy * pts[k][0] - dx * pts[k][1] + x2 * y1 - y2 * x1) / n
        if d > dmax: i, dmax = k, d
    if dmax > eps: return rdp(pts[:i + 1], eps)[:-1] + rdp(pts[i:], eps)
    return [pts[0], pts[-1]]

def rings(g):
    return g['coordinates'] if g['type'] == 'Polygon' else [r for p in g['coordinates'] for r in p]

def main(src, dst):
    k = WIDTH / (LON1 - LON0); height = round((LAT1 - LAT0) * k)
    xy = lambda lon, lat: ((lon - LON0) * k, (LAT1 - lat) * k)
    areas = {}
    for f in json.load(open(src))['features']:
        parts, area = [], 0
        for ring in rings(f['geometry']):
            pts = []
            for lon, lat in ring:
                p = tuple(round(v, 1) for v in xy(lon, lat))
                if not pts or p != pts[-1]: pts.append(p)
            if len(pts) > 8:
                m = len(pts) // 2  # a closed ring: simplify its halves
                pts = rdp(pts[:m + 1], EPS)[:-1] + rdp(pts[m:], EPS)
            if len(pts) < 3: continue
            area += abs(sum(pts[i][0] * pts[i - 1][1] - pts[i - 1][0] * pts[i][1] for i in range(len(pts))) / 2)
            parts.append("M" + " ".join(f"{x:g} {y:g}" for x, y in pts) + "Z")
        big = max(rings(f['geometry']), key=len)
        bx = [xy(*p)[0] for p in big]; by = [xy(*p)[1] for p in big]
        areas[f['id']] = {"d": "".join(parts), "cx": round((min(bx) + max(bx)) / 2, 1),
                          "cy": round((min(by) + max(by)) / 2, 1), "small": area < 40}
    json.dump({"width": WIDTH, "height": height, "areas": areas}, open(dst, "w"), separators=(",", ":"))

if __name__ == "__main__":
    main(*sys.argv[1:3])
