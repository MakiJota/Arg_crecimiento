# -*- coding: utf-8 -*-
"""Paso 20 · Huellas de edificios de Overture Maps por aglomerado.

Overture Maps Foundation, tema buildings (ODbL), que junta OpenStreetMap con las huellas
detectadas por Microsoft (Global ML Building Footprints) y Google (Open Buildings). Se leen
los GeoParquet publicos de la ultima release directamente con DuckDB, solo la caja de cada
aglomerado de cajas.md (filtro por bbox, sin bajar el mundo entero).

Es una fuente de validacion, no esta en la lista de fuentes del proyecto: sirve para decir
"hoy no hay edificio aca, asi que en 1990 tampoco habia construido", nunca lo contrario.
Ninguna cifra que salga de aca es cifra del proyecto.

Ademas de los edificios (--temas), las otras capas de Overture para las reglas:
  uso        base/land_use: parques, plazas, canchas, escuelas, cementerios, aeropuertos, areas
             protegidas, residencial, industrial... (de OpenStreetMap, clases normalizadas)
  cobertura  base/land_cover: bosque, cultivo, pastizal, arbustal, suelo desnudo, urbano; cubre
             todo el territorio (ESA WorldCover), no solo lo que alguien mapeo
  agua       base/water: rios, arroyos, canales, desagues, lagos, embalses (lineas y poligonos)
  calles     transportation/segment: calles y vias con su clase (motorway ... residential, path, rail)
  aeropuertos  base/infrastructure con subtype airport: predio, pistas, plataformas, helipuertos

SALIDAS  outputs/overture/<slug>/<tema>.gpkg (capa con el nombre del tema) y
         outputs/overture/release.txt con la release usada.

Uso: python Rpipe/scripts/20_overture_edificios.py [--ciudades salta,rosario] [--release 2026-11-18.0]
         [--temas edificios,uso,cobertura,agua,calles]
"""
import argparse
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

import duckdb

RPIPE = Path(__file__).resolve().parents[1]
SAL = RPIPE / "outputs" / "overture"
STAC = "https://stac.overturemaps.org/catalog.json"


def cajas():
    # tabla de cajas.md: slug | contorno | lat0 | lon0 | lat1 | lon1 | ...
    filas = {}
    for linea in (RPIPE / "cajas.md").read_text(encoding="utf-8").splitlines():
        c = [x.strip() for x in linea.strip().strip("|").split("|")]
        if len(c) >= 6 and re.fullmatch(r"-?\d+(\.\d+)?", c[2] or ""):
            filas[c[0]] = tuple(float(x) for x in c[2:6])
    return filas


def ultima_release():
    cat = json.load(urllib.request.urlopen(STAC, timeout=60))
    for l in cat["links"]:
        if l.get("rel") == "child" and l.get("latest"):
            return l["href"].split("/")[-2]
    raise SystemExit("no se encontro la release mas reciente en " + STAC)


TEMAS = {
    "edificios": ("buildings", "building",
                  "id, sources[1].dataset AS fuente, class AS clase, height AS altura, num_floors AS pisos"),
    "uso": ("base", "land_use", "id, subtype, class AS clase, surface, names.primary AS nombre"),
    "cobertura": ("base", "land_cover", "id, subtype"),
    "agua": ("base", "water", "id, subtype, class AS clase, is_intermittent AS intermitente, names.primary AS nombre"),
    "calles": ("transportation", "segment", "id, subtype, class AS clase, subclass, names.primary AS nombre"),
    # los aeropuertos no estan en land_use sino en infrastructure (subtype airport): predio,
    # pistas, plataformas, helipuertos
    "aeropuertos": ("base", "infrastructure", "id, subtype, class AS clase, names.primary AS nombre",
                    "subtype = 'airport'"),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ciudades", default="")
    ap.add_argument("--release", default="")
    ap.add_argument("--rehacer", action="store_true")
    ap.add_argument("--temas", default="edificios")
    a = ap.parse_args()
    C = cajas()
    ciudades = a.ciudades.split(",") if a.ciudades else sorted(C)
    rel = a.release or ultima_release()
    SAL.mkdir(parents=True, exist_ok=True)
    (SAL / "release.txt").write_text(rel + "\n", encoding="utf-8")
    con = duckdb.connect()
    for ext in ("spatial", "httpfs"):
        con.execute(f"INSTALL {ext}; LOAD {ext};")
    con.execute("SET s3_region = 'us-west-2';")
    con.execute("SET geometry_always_xy = true;")   # lon, lat (DuckDB 2.0 lo pide explicito)
    temas = a.temas.split(",")
    print(f"Overture · release {rel} · {', '.join(temas)} · {len(ciudades)} aglomerados")
    for s in ciudades:
        if s not in C:
            print("  sin caja:", s); continue
        lat0, lon0, lat1, lon1 = C[s]
        for tema in temas:
            th, ty, cols, *extra = TEMAS[tema]
            filtro = f" AND {extra[0]}" if extra else ""
            f = SAL / s / f"{tema}.gpkg"
            if f.exists() and not a.rehacer:
                print(f"  {s:22s} {tema:10s} ya estaba"); continue
            f.parent.mkdir(parents=True, exist_ok=True)
            t0 = time.time()
            tmp = f.with_suffix(".tmp.gpkg")
            if tmp.exists():
                tmp.unlink()
            fuente = f"s3://overturemaps-us-west-2/release/{rel}/theme={th}/type={ty}/*"
            con.execute(f"""
                COPY (
                  SELECT {cols}, geometry
                  FROM read_parquet('{fuente}', hive_partitioning = 1)
                  WHERE bbox.xmin <= {lon1} AND bbox.xmax >= {lon0}
                    AND bbox.ymin <= {lat1} AND bbox.ymax >= {lat0}{filtro}
                ) TO '{tmp.as_posix()}' WITH (FORMAT GDAL, DRIVER 'GPKG', LAYER_NAME '{tema}', SRS 'EPSG:4326')
            """)
            tmp.replace(f)
            g = "fuente" if tema == "edificios" else "subtype"
            rows = con.execute(f"SELECT {g}, count(*) n FROM ST_Read('{f.as_posix()}') GROUP BY 1 ORDER BY n DESC").fetchall()
            n = sum(r[1] for r in rows)
            print(f"  {s:22s} {tema:10s} {n:>9,} ({', '.join(f'{r[0]} {r[1]}' for r in rows[:6])}) · {time.time() - t0:.0f} s")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
