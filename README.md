# Rpipe · Urban growth in Argentina's agglomerations (R)

How the 31 EPH urban agglomerations of Argentina grew between 1990 and 2020, measured with
the classes of the **Atlas of Urban Expansion** (Angel et al. 2016) on the **GISD30**
impervious-surface record (Zhang et al. 2022, Landsat, 30 m). The guiding question: how much
does it change the picture to count the *fringe open space* (the 100 m ring of unbuilt land
around urban and suburban built-up) as part of the city?

**Report:** [`reporte/REPORTE_angel.md`](reporte/REPORTE_angel.md), with its charts and maps
in `reporte/img/`.

Exploratory work done alongside the *Bolsones de pobreza* consultancy (IDB). The numbers are
not figures of that project and are not in `CIFRAS_CANONICAS.json`. Author: Jonathan.

## Pipeline

R scripts, numbered in run order. Paths are relative to this folder, resolved from each
script's own location.

| Step | Script | What it does |
|---|---|---|
| 00 | `scripts/00_gisd30_descarga.R` | GISD30 tiles for Argentina from Zenodo (md5 checked) |
| 01 | `scripts/01_gisd30_decadas.R` | eight five-year epochs to four cumulative decades (1990, 2000, 2010, 2020) |
| 02 | `scripts/02_landsat_bbox.R` | Landsat composite of a box, Planetary Computer STAC (grid template for 04) |
| 03 | `scripts/03_ghsl_built_s.R` | GHSL built-up surface (JRC), to compare with GISD30 |
| 04 | `scripts/04_angel_atlas.R` | Angel / Atlas classes and metrics per decade |
| 04b | `scripts/04b_angel_sin_landsat.R` | the same as 04 without Landsat: cuts GISD30 with the box of `cajas.md` (no step 02 needed) |
| 05 | `scripts/05_per_muni.R` | runs 02 + 04 for a list of agglomerations |
| 06 | `scripts/06_reporte.R` | the report in `reporte/`, generated entirely from 04's results |
| 07 | `scripts/07_limites_aglomerados.R` | agglomerate perimeters and boxes to `raw/boundaries/aglomerados.gpkg` |
| 09 | `scripts/09_censos_radios.R` | census tracts 1991, 2001, 2010, 2022 with persons, households and dwellings: one GeoPackage layer per census (`outputs/censos/radios_censos.gpkg`) |
| 10 | `scripts/10_crosswalk_radios.R` | tract crosswalk between censuses (port of the project's `ag_6_crosswalk.py`) and persons, households and dwellings of the four censuses on one fixed grid (1991 by default): layer `radios_grilla_1991` in the same GeoPackage, plus totals per agglomeration |

`scripts/lib/`: `cajas.R` (boxes and perimeters) and `resultados.R` (the numbers, rules,
charts, maps and text of the report).

Inputs:

- `cajas.md`: boxes to cut Landsat and GISD30 and explore results per city (perimeter +
  10 km, or hand-drawn). Read by 02, 04 and 05.
- `raw/boundaries/aglomerados.gpkg`: the 31 agglomerate perimeters (layer `perimetro`) and the
  boxes (layer `cajas`). The perimeter is the *Bolsones de pobreza* analysis perimeter (EPH
  agglomerate plus the continuous 2022 city), simplified to about 200 m. Step 07 rebuilds it
  from the project's `plataforma/`.

Everything under `raw/` and `outputs/` is downloaded or derived and is not versioned.

## Running it

R 4.5 with `terra`, `sf`, `ggplot2`, `curl`, `archive`, `digest` and `jsonlite`. From the
folder that contains `Rpipe/`:

    Rscript Rpipe/scripts/00_gisd30_descarga.R
    Rscript Rpipe/scripts/01_gisd30_decadas.R
    Rscript Rpipe/scripts/07_limites_aglomerados.R
    Rscript Rpipe/scripts/05_per_muni.R --ciudades salta,cordoba
    Rscript Rpipe/scripts/06_reporte.R

To add a city, add its row to `cajas.md` and run 05 with its slug.

## Data and licences

- GISD30: Zhang, X. et al. (2022), *Earth System Science Data* 14, 1831-1856. CC BY 4.0.
- Landsat Collection 2 (USGS), via Microsoft Planetary Computer.
- GHSL GHS-BUILT-S R2023A, European Commission JRC.
- Classes: Angel, S. et al. (2016), *Atlas of Urban Expansion, 2016 Edition*, Vol. 1.
