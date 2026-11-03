---
title: "Method"
nav_order: 2
---

# Method

1. TOC
{:toc}

## Data

- **GISD30** (Zhang et al. 2022, *Earth System Science Data* 14:1831-1856, CC BY 4.0): global impervious surface at 30 m from Landsat. Each pixel stores the period of its first detection: 0 never, 1 before 1985, 2-8 five-year periods 1985-2020. The record is cumulative: a pixel never stops being built.
- **Decades** (`01_gisd30_decadas.R`): built-up by 1990 = values 1-2, by 2000 = 1-4, by 2010 = 1-6, by 2020 = 1-8.
- **Agglomerate perimeters** (`07_limites_aglomerados.R`): the analysis perimeter of the *Bolsones de pobreza* project, i.e. the EPH agglomerate plus the continuous 2022 city that spills over it, simplified to about 200 m.
- **Boxes** (`cajas.md`): the perimeter's bounding box plus 10 km on every side, so the 1 km² neighbourhood never runs out of data at the edge of the city. Salta and Gran Tucumán use hand-drawn boxes that also cover the whole perimeter.
- Each box is reprojected to its UTM zone at 30 m (nearest neighbour) so that distances are metric.
- **Grid**: 17 agglomerations were cut on the grid of their Landsat composite (`04_angel_atlas.R`) and 14 directly with their box (`04b_angel_sin_landsat.R`). Landsat is only a grid template, never an input to the classes, and the composite has the same box, so the two grids differ by a fraction of a pixel at the edge. On the box grid: Gran Buenos Aires, Gran Mendoza, Gran Paraná, Gran Resistencia, Gran San Juan, La Rioja, Posadas, Rawson - Trelew, Río Cuarto, Río Gallegos, San Luis - El Chorrillo, San Nicolás - Villa Constitución, Santa Rosa - Toay, Santiago del Estero - La Banda.

## Classes

Each 30 m pixel looks at the circle of 1 km² around it (radius 564 m) and the share of that circle that is built-up. Rural cut used here: **0.25** (Atlas 2016 edition).

| Value | Class | Rule | In the urban extent? |
|---|---|---|---|
| 0 | rural open space | not built-up, none of the below | no |
| 1 | urban built-up | built-up, circle > 50 % built | yes |
| 2 | suburban built-up | built-up, circle 25-50 % built | yes |
| 3 | rural built-up | built-up, circle < 25 % built | no |
| 4 | fringe open space | not built-up, within 100 m of urban or suburban built-up | yes |
| 5 | captured open space | open patch (4-connected) under 200 ha, fully enclosed, not touching the box edge | yes |

**Urban extent** = urban + suburban + fringe + captured.

### How the fringe is drawn

A 100 m circle on the 30 m grid is centred on every urban and suburban pixel; every pixel that is not built-up and falls inside one of those circles is fringe. On the grid the circle reaches 3 pixels straight out (90 m) and 85-95 m on the diagonals. Rural built-up pixels do not make fringe. Captured open space is assigned after the fringe, so the two never overlap.

Because each built edge brings its own ring, the fringe grows with the *length of the city's edge*, not with its area: fragmented cities carry the most fringe, and a city that builds on its old fringe loses fringe as it grows.

## "The city"

Inside each box, the city is the set of urban-extent patches (8-connected) that touch the agglomerate perimeter. A town inside the box that never touches the perimeter is left out; the two cities of a two-city agglomerate (Ushuaia and Río Grande, Viedma and Carmen de Patagones) count together.

When one patch touches the perimeters of two agglomerates, each of its pixels goes to the nearer perimeter. Without that rule the patch would count twice. Of the 31 agglomerates, it applies only to Gran Buenos Aires and Gran La Plata, whose built-up areas join (checked on the 2020 extent); patches that are not shared are not affected.

## Metrics

| Metric | Definition |
|---|---|
| built-up | built-up pixels inside the city's urban extent |
| saturation | built-up / urban extent |
| openness | average unbuilt share of the 1 km² circle around the city's urban and suburban pixels |
| fringe share | fringe open space / urban extent |
| growth | annual compound rate, (x1 / x0)^(1 / years) - 1 |
| project footprint | the *Bolsones de pobreza* definition (Angel, Parent & Civco 2007; rural cut 0.10): built-up with ≥ 10 % of its circle built, plus unbuilt pixels with > 50 % built around them or within 100 m of that built-up; patches touching the perimeter |

## Rules used to describe the cities

- **Pace** (built-up growth 1990-2020 per year): very fast ≥ 4 %, fast ≥ 2.5 %, moderate ≥ 1.5 %, slow < 1.5 %.
- **Shape** (saturation change 1990-2020): filling in ≥ +0.03, spreading out ≤ -0.03, stable in between.
- **Check**: built-up growth ≥ 4 % a year is flagged for review against GHSL or imagery.

## Caveats

- **GISD30 is the only input.** Its 1985-2000 detection is the weakest of the series (few Landsat 5 scenes), so part of the post-2000 acceleration may come from the data. In arid cities bare soil is read as impervious surface; very fast growth in the arid west and northwest should be checked against GHSL or imagery before being used.
- **Water counts as open space.** GISD30 has no water mask, so riverbanks and coasts next to the city become fringe or captured open space. The Atlas removes water from open space; this pipeline does not yet.
- **The perimeter is simplified** to about 200 m. It decides which patches are "the city"; it is not used to cut pixels.
- **Proximity is not reported**: measured to the centroid it is meaningless for multi-part agglomerates.
- **Rural cut**: the Atlas 2016 edition puts suburban at 25-50 %; the *Bolsones de pobreza* project uses the 2007-2010 definition (rural below 10 %), so its footprint is larger than the extent measured here.
- **No density yet**: it needs census population per tract.

## Pipeline

| Step | Script | What it does |
|---|---|---|
| 00 | `00_gisd30_descarga.R` | GISD30 tiles for Argentina (Zenodo, md5 checked) |
| 01 | `01_gisd30_decadas.R` | eight five-year epochs to four cumulative decades |
| 02 | `02_landsat_bbox.R` | Landsat composite of each box (grid template for 04) |
| 03 | `03_ghsl_built_s.R` | GHSL built-up surface, to compare with GISD30 |
| 04 | `04_angel_atlas.R` | Angel classes and metrics per decade |
| 04b | `04b_angel_sin_landsat.R` | the same as 04, cutting GISD30 with the box instead of the Landsat grid (no step 02 needed) |
| 05 | `05_per_muni.R` | runs 02 + 04 for a list of agglomerations from `cajas.md` |
| 06 | `06_reporte.R` | the same results as one markdown report |
| 07 | `07_limites_aglomerados.R` | agglomerate perimeters and boxes to a GeoPackage |
| 08 | `08_sitio.R` | this site |

## References

- Angel, S. et al. (2016). *Atlas of Urban Expansion, 2016 Edition. Volume 1: Areas and Densities.* NYU, UN-Habitat, Lincoln Institute of Land Policy.
- Angel, S., Parent, J. & Civco, D. (2007). Urban sprawl metrics: an analysis of global urban expansion using GIS. ASPRS Annual Conference.
- Zhang, X. et al. (2022). GISD30: global 30 m impervious-surface dynamic dataset from 1985 to 2020 using time-series Landsat imagery on the Google Earth Engine platform. *Earth System Science Data* 14, 1831-1856.
