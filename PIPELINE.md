# How the site and the report are built

Site: <https://makijota.github.io/Arg_crecimiento/>. This file, the site (`docs/`) and
`scripts/08_sitio.R` live only in the Arg_crecimiento repo.

Everything under `docs/` and `reporte/` is **generated**. Do not edit it by hand: change the
scripts or their inputs and rerun them.

## Who writes what

| Script | Writes | For |
|---|---|---|
| `scripts/06_reporte.R` | `reporte/REPORTE_angel.md` and `reporte/img/` (charts, maps, legend) | one markdown page that reads on GitHub or in VS Code |
| `scripts/08_sitio.R` | `docs/` (Jekyll pages, `_config.yml`, `docs/assets/img/`) | the GitHub Pages site |
| `scripts/lib/resultados.R` | nothing by itself | the shared part: reads the results, applies the rules, draws charts and maps, writes the text both use |

Every number and every label ("filling in", "very fast") comes from `resultados.R`, computed
from `outputs/angel/resumen.csv` with the rules declared at the top of that file. So the report
and the site always say the same thing. Only agglomerations are included: the rows of
`cajas.md` that have a `contorno` (Tandil is left out).

    Rscript scripts/06_reporte.R               # report, with maps
    Rscript scripts/08_sitio.R                 # site, with maps
    Rscript scripts/08_sitio.R --sin-mapas     # pages and charts only (fast)

## What they read, and which step makes it

| Step | Script | Produces | In git? |
|---|---|---|---|
| 00 | `scripts/00_gisd30_descarga.R` | GISD30 tiles for Argentina (`outputs/gisd30/tiles/`) | no |
| 01 | `scripts/01_gisd30_decadas.R` | the four cumulative decades (`outputs/gisd30/gisd30_decadas.vrt`) | no |
| 02 | `scripts/02_landsat_bbox.R` | the 30 m grid of each box (`outputs/landsat/<slug>/landsat_2020.tif`) | no |
| 04 | `scripts/04_angel_atlas.R` | `outputs/angel/<slug>/angel_<year>.tif` (the maps) and `outputs/angel/resumen.csv` (all the numbers) | no |
| 04b | `scripts/04b_angel_sin_landsat.R` | the same outputs as 04, without step 02 (grid cut from the box) | no |
| 05 | `scripts/05_per_muni.R` | runs 02 and 04 for a list of agglomerations | — |
| 07 | `scripts/07_limites_aglomerados.R` | `raw/boundaries/aglomerados.gpkg`: perimeters, names, provinces and boxes | yes |
| — | `scripts/lib/cajas.R`, `cajas.md` | the box and perimeter of each city | yes |

Step 03 (`scripts/03_ghsl_built_s.R`, GHSL) does not feed the site or the report.

## Rebuild from scratch

    Rscript scripts/00_gisd30_descarga.R
    Rscript scripts/01_gisd30_decadas.R
    Rscript scripts/05_per_muni.R --ciudades salta,cordoba,...   # 02 + 04 per agglomeration
    Rscript scripts/06_reporte.R
    Rscript scripts/08_sitio.R

Then commit and push: GitHub Pages rebuilds the site from `main`, folder `/docs`.

## Two repos, one folder

This folder lives inside the *Bolsones de pobreza* checkout, at `Rpipe/`, and feeds two repos:

- **Arg_crecimiento** (this one): everything, site included. Its git data is outside the
  folder, in `GitHub/Arg_crecimiento.git`; from the parent checkout use `git arg <command>`
  (a local alias: `git --git-dir=.../Arg_crecimiento.git --work-tree=.../Rpipe`).
- **pedroheppc/bolsonespobreza**: the pipeline and the report, not the site. The parent's
  `.git/info/exclude` leaves out `Rpipe/docs/`, `Rpipe/scripts/08_sitio.R` and this file.

## Dependency outside this repo

Step 07 reads the perimeters from the *Bolsones de pobreza* repository
(`plataforma/datos/<slug>/base.js` and `plataforma/index.html`), so it only runs inside that
project's checkout. Its output, `raw/boundaries/aglomerados.gpkg`, is committed here, and
everything else (04, 04b, 06, 08, through `scripts/lib/cajas.R`) reads the perimeters from
it, so this repo runs on its own.
