# Arg_crecimiento · Urban growth in Argentina's agglomerations

How the 31 EPH urban agglomerations of Argentina grew between 1990 and 2020, measured with
the classes of the **Atlas of Urban Expansion** (Angel et al. 2016) on the **GISD30**
impervious-surface record (Zhang et al. 2022, Landsat, 30 m). The guiding question: how much
does it change the picture to count the *fringe open space* (the 100 m ring of unbuilt land
around urban and suburban built-up) as part of the city?

**Results site:** <https://makijota.github.io/Arg_crecimiento/>

Exploratory work done alongside the *Bolsones de pobreza* consultancy (IDB). The numbers are
not figures of that project.

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
| 05 | `scripts/05_per_muni.R` | runs 02 + 04 for a list of agglomerations |
| 06 | `scripts/06_sitio.R` | the results site in `docs/`: charts, maps and pages |
| 07 | `scripts/07_limites_aglomerados.R` | agglomerate perimeters and boxes to `raw/boundaries/aglomerados.gpkg` |

Inputs kept in the repo:

- `cajas.md`: the box of each city (perimeter + 10 km, or hand-drawn), read by 02, 04 and 05.
- `raw/boundaries/aglomerados.gpkg`: the 31 agglomerate perimeters (layer `perimetro`) and the
  boxes (layer `cajas`). The perimeter is the *Bolsones de pobreza* analysis perimeter (EPH
  agglomerate plus the continuous 2022 city), simplified to about 200 m. Step 07 rebuilds it
  and only runs inside that project's repository.

Everything under `raw/` (except the boundaries) and `outputs/` is downloaded or derived and
is not versioned.

## Running it

R 4.5 with `terra`, `sf`, `ggplot2`, `curl`, `archive`, `digest` and `jsonlite`. Then, from the folder that contains this repo:

    Rscript Arg_crecimiento/scripts/00_gisd30_descarga.R
    Rscript Arg_crecimiento/scripts/01_gisd30_decadas.R
    Rscript Arg_crecimiento/scripts/05_per_muni.R --ciudades salta,cordoba
    Rscript Arg_crecimiento/scripts/06_sitio.R

To add a city, add its row to `cajas.md` and run 05 with its slug.

## Data and licences

- GISD30: Zhang, X. et al. (2022), *Earth System Science Data* 14, 1831-1856. CC BY 4.0.
- Landsat Collection 2 (USGS), via Microsoft Planetary Computer.
- GHSL GHS-BUILT-S R2023A, European Commission JRC.
- Classes: Angel, S. et al. (2016), *Atlas of Urban Expansion, 2016 Edition*, Vol. 1.
