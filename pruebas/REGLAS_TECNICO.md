# Rules tab: technical reference

Personal working notes for the Rules tab of the single-city viewer (`docs/visor/index.html`). The plain-language version is [REGLAS.md](REGLAS.md). Exploratory: no number here is a project figure.

## 1. Pipeline and data

| Step | Output | Used for |
|---|---|---|
| 11 `11_radios_ciudad.R` | `outputs/densidad/<slug>/code_<y>.tif`: 0 rest, 1 city built-up, 2 city open (fringe or captured), 3 built outside the city. Tract tables `radios_<y>.csv`. | pixel class, tract of each pixel, persons, dwellings, km² built and open per tract, `dens_urb` |
| 16 `16_reglas.R` | `outputs/reglas/<slug>/reglas_<y>.tif`: `dist` (m to the nearest non-city pixel, city only), `share` (% of codes 1 or 3 within 150 m, circle), `hueco` (old 30/60/90 m closing, unused by the Rules tab), `agua` (JRC GSW + OSM water and shore) | distance to the edge, built-up share, water |
| 18 `18_parches.R` | `outputs/parches/<slug>/bordes2_<y>.tif`: `hueco` (gap index 0–12) and `d0`…`d500` (patch class for each ring width) | rules 1 and 2 |
| 15 `15_visor_datos.R --solo-bordes` | `docs/visor/datos/<slug>/bordes{a,b,c}_<y>.png`; `indice.json` key `bordes` | the viewer |

Also used from step 15: `clase_<y>.png` (R = code and old bits, G·256+B = tract row), `parches_<y>.png` (B = built-up share for codes 1 and 3), and `radios.json`. In `radios.json`, `viv` holds dwellings per tract; −1 means missing.

All grids are UTM 30 m in R. Step 15 projects them to the viewer's Web Mercator template with nearest neighbour.

### 1.1 Gaps (`hueco`)

Euclidean morphological closing of built-up B (codes 1 or 3) with a disc of radius r:

```
d1      = distance to nearest B pixel
dil_r   = d1 <= r
d2_r    = distance to nearest pixel outside dil_r
closed  = dil_r & d2_r > r
hueco   = smallest k with pixel ∉ B and closed at GAP_M[k]; 0 if none; 0 on water/shore
GAP_M   = 30 60 90 120 150 180 210 240 300 360 420 500  (index 1..12)
```

The radius is r, so a gap up to about 2r wide closes.

Version 1 (`bordes_<y>.tif`, square windows of k·30 m, k ≤ 8) is superseded. Square windows close slightly more than discs of the same radius. In Salta 1990 the default fill moved from 4.8 to 4.4 km² with the switch.

### 1.2 Patch classes (`d0` … `d500`)

For each ring width D in {0, 50, …, 500}:

```
interior = code == 2 & dist > D
patches  = 4-connected components of (interior & !water)
size     = n_pixels · 900 m²
class    = 1..9 by CORTES2_HA = 0.5 1 2 5 10 20 50 100 ha  (left-open; 9 = > 100 ha)
           0 = not interior (ring, or not city open land)
           15 = interior water or shore
```

4-connectivity, not 8: with 8, diagonal chains of missed pixels join into large webs and almost nothing counts as small. Salta 1990, D = 200, patches ≤ 2 ha: 2.7 km² with 8 neighbours, 3.9 with 4 (version 1 test).

D = 0 means no ring: every city open pixel is interior (`dist > 0` holds in the whole city).

### 1.3 Packing in the PNGs

| File | Content |
|---|---|
| `bordesa` | 24-bit integer R·65536 + G·256 + B; 4 bits per class, D = 0…250 (d0 in bits 0–3) |
| `bordesb` | same, D = 300…500 (20 bits) |
| `bordesc` | channel B: bits 0–3 = min(floor(dist / 50), 10) on city pixels (codes 1 or 2); bits 4–7 = gap index |

## 2. Viewer computation

### 2.1 Loading (`rdatos`)

For every pixel, the viewer keeps:
- `sh`: built-up share, codes 1 and 3;
- `dh`: distance class and gap index.

For code 2 pixels in raster order it keeps `A` and `B` (the packed classes), plus `fila`, the code-2 count at the start of each row (for random access in the popup). `nb1[r]` is the code 1 pixel count per tract.

### 2.2 Histograms (`rhist`, one pass, cached per ring width and edge discount)

Per tract r:
- `hp[r][class 0..15][gap 0..12]`: open pixels;
- `hs1[r][share 0..100]`: code 1 pixels not discounted at the edge;
- `hs3[r][share]`: code 3 pixels;
- `ne[r]`: code 1 pixels discounted at the edge.

The sliders of rules 2 and 3 only re-read these histograms. They never touch the pixels again, so they redraw fast.

### 2.3 Calibration

`f = Σ km2_construido / Σ nb1` over all tracts: km² per viewer pixel. It is one factor per city and year, so all km² in the panel are in the units of step 11. Web Mercator pixel area changes with latitude across the frame; with one factor that error is ignored.

### 2.4 Percentiles

Type 7, as R's `quantile`. The sample is the tracts with built + open land > 0 and ≥ 10 % of their area in the city (`MIN_CIUDAD`).
- Rule 2 thresholds and the rule 3 tract filter use `dens_urb`: persons per km² of built + fringe + captured land in the tract.
- The rule 3 floor uses persons ÷ km² built.

Percentile 100 is the maximum, so "from p100" selects the densest tract only.

## 3. Sliders

Hash key `rg` = `D,p2,tam,gap,p2b,tamb,modo,p3,k,S,fuera,p2t,on1,on2,on3,E,p3t`.

### Rule 1 · Edge ring (`on1`)

| Slider | Key | Values | Default | Meaning |
|---|---|---|---|---|
| Ring width | `D` | 0–500 m, steps of 50 | 200 | open pixels with `dist ≤ D` have class 0 and stay fringe; picks layer `d<D>` for patch sizes |
| Built-up in the ring discounted | `E` | off, < 10 % … < 90 %, all of it | off | a code 1 pixel with distance class < D/50 and share < E is discounted (class `re`) |

- Off is the same as D = 0 with no discount.
- The discount uses 50 m classes and a strict `<`, so a pixel exactly at D is not discounted.
- Discounted pixels leave `hs1`, so rule 3's budget doesn't count them.

### Rule 2 · Fill open land inside (`on2`)

| Slider | Key | Values | Default | Meaning |
|---|---|---|---|---|
| Fill in tracts from | `p2` | p0–p95, steps of 5 | p25 | tracts with `dens_urb ≥ d2` can fill. p0 = every tract with a density |
| Patches up to | `tam` | none, 0.5, 1, 2, 5, 10, 20, 50, 100 ha | 2 ha | patch class ≤ tam fills |
| Also narrow gaps | `gap` | none, 30 … 500 m (12 steps) | 60 m | open pixel with gap index 1…gap fills, in tracts ≥ d2 |
| Bigger patches in tracts from | `p2b` | off, p30–p95 | p50 | from `dHi` the patch limit is max(tamb, tam) |
| Patches there up to | `tamb` | 0.5 ha … 100 ha, any size | 5 ha | |
| ALL open land inside, in tracts from | `p2t` | off, p30–p95, p98, p100 | p75 | from `dTot` every class 1–9 fills |

Per tract:

```
lim = dens ≥ dTot ? 9 : dens ≥ dHi ? max(tamb, tam) : dens ≥ d2 ? tam : 0
gok = dens ≥ d2 or dens ≥ dTot
fill(pixel) = 1 ≤ class ≤ 9 and (class ≤ lim or (gok and 1 ≤ gap_index ≤ gap))
```

Class 0 (ring) and class 15 (water) never fill. Tracts with no density (`dens = −1`, no city land) never fill.

### Rule 3 · Trim built-up (`on3`, `modo`)

| Slider | Key | Values | Default | Meaning |
|---|---|---|---|---|
| Only in tracts below | `p3t` | p5–p95, all tracts | p25 | rule 3 applies only where `dens_urb < d3t`, or the tract has no city land (`dens = −1`) |
| Floor (mode `piso`) | `p3` | p5–p50 | p10 | d3 = percentile of persons ÷ km² built; a tract below it keeps persons ÷ d3 km² |
| Cap per dwelling (mode `tope`) | `k` | 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4 pixels | 1 | the tract keeps at most `viv × k × 900 m²`, converted to pixels with f |
| Never trim pixels with | `S` | none, ≥ 95 … ≥ 60 % share | ≥ 80 % | protected pixels are always kept and count toward the budget |
| The cap also trims built-up outside the city | `fuera` | on/off | on | code 3 pixels join the tract's budget and can be trimmed |

**Budget (`umbralShare`):**

```
keep  = budget in pixels
H(s)  = hs1[r][s] (+ hs3[r][s] if fuera)
if Σ H ≤ keep: nothing trimmed
n = Σ_{s ≥ S} H(s)                    # protected, always kept
t = S
for s = S−1 down to 0: if n + H(s) > keep break; n += H(s); t = s
trim every pixel with share < t
```

Ties are resolved by whole share bins (1 %), not pixel by pixel. A tract can therefore keep slightly fewer pixels than its budget. Protected pixels can already exceed the budget, and are then kept anyway.

The cap uses dwellings from the census nearest the image year: 1991 for 1990, 2001, 2010, 2022 for 2020. That's all dwellings, occupied or not. Tracts with `viv = −1` are never capped.

## 4. Order of operations for a pixel

```
code 0 → nothing
code 1 → discounted at the edge (re)  if on1, dist class < D/50, share < E
       → trimmed (rx)                 if rule 3 applies to its tract and share < t[r]
       → kept (rb)
code 3 → trimmed (rx)                 if mode tope, fuera, t[r] ≥ 0, share < t[r]
       → kept (ru)
code 2 → ring (rr)                    if patch class = 0
       → filled (rf)                  if fill(pixel)
       → open kept (ro)
```

## 5. Panel figures

- **GISD30 built-up:** Σ `km2_construido` over tracts with city land.
- **Built-up with the rules:** built0 − edge + fill − trim (city only; trimming outside the city is shown apart).
- **Persons per km² built:** persons of tracts with city land ÷ built-up.
- **Growth:** (b2020 / b1990)^(1/30) − 1, for GISD30 and for the rules at the same settings.
- **Histograms:** urbanized density (moves p2); built-up per dwelling in m² (cap mode, moves k); persons per km² built (floor mode, moves p3).

## 6. Known limits

- **Thresholds are relative to each city and census,** so the share of tracts affected is constant across years. That shapes growth: compare growth across settings, not only maps.
- **Tract boundaries cut patches.** A large open patch that spans dense and sparse tracts fills only in the dense part.
- **Fill saturates at the p2 threshold.** With wide gaps and any patch size, the fill stops at all open land in tracts from p2. Salta 1990: 4.4 km² (34.8 % of interior open land) at the defaults; 5.0 km² (40.3 %) with gaps ≤ 500 m and any size from p50.
- **Viewer grid:** nearest-neighbour Web Mercator, one km² factor. Pixel counts are approximate; km² are calibrated, so totals hold.
- **Water mask** quality varies; a dry riverbed not in JRC or OSM can fill.
- **Dwelling counts** lag the image in 2020: the 2022 census is two years after the 2020 image.
