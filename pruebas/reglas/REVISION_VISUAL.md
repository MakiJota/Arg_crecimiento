> **Note.** Independent visual review by a second Claude agent on 2026-11-15, **before** the water mask was added to `16_reglas.R` (the river and canal ribbons it describes are now masked; the irrigated-farmland errors are not). The screenshots it cites stayed on the local machine and are not in the repo. Summary and follow-up: [../CAMBIOS_2026-11-15.md](../CAMBIOS_2026-11-15.md).

# Visual review of Test 3 + fill rule (p=25, r=h60, d=200)

Reviewer: independent visual check, 2026-11-15. Viewer at http://127.0.0.1:8811/, method t3, p=25, d=200, an=1.

Screenshots were saved locally (`rev/`, not in the repo).

- **Pair images** (names without `_rd0_rd1`, `_h30_h90` or `_h30_h60`) show the imagery on the left and the opaque overlay on the right, for the same view.
- **Comparison images** (`*_rd0_rd1`, `*_h30_h90`, `*_h30_h60`) show option A on the left and option B on the right, both with the overlay.

Coordinates are approximate view centres or points read off the screenshots (about ±300 m). Esri imagery is present-day, so 1990 views can show buildings that did not exist in 1990. 

## Summary verdict

- **The approach works in compact cities surrounded by dry land or grassland.** This covers Corrientes, Tucumán, the Santa Fe city body, Salta centre, Trelew proper and the Mendoza and San Juan cores.
  - The dark-blue built-up follows the urban fabric.
  - The density cut drops large parks, fields and wetlands (red).
  - The 200 m edge ring follows the real edge.
  - In these cores roughly 70-90 % of the teal lands on built fabric: tree-covered streets, courtyards and block canopy.
- **The fill rule's main error is linear features.**
  - Rivers, canals, riparian woodland, highway medians and lake channels are narrow open strips between built pixels. A 60 m closing fills exactly that kind of gap, so they come out as teal ribbons.
  - Seen at: Río Salí (Tucumán), Río Arenales and the Tineo canal (Salta), the Limay riverbanks (Neuquén), the Chubut river (Rawson), San Juan's Circunvalación (1990), and Nordelta's lake arms and the Puerto Madero docks (Buenos Aires).
  - A water or river mask is needed. Changing the radius does not fix this.
- **The model fails in irrigated oases.**
  - **Rawson-Trelew fails as a whole.** In both 1990 and 2020 the "city" is essentially the lower Chubut irrigated valley, about 30 km of chacras between Trelew and Rawson. Fields, windbreaks, canals and greenhouses show as dark blue and teal, with red blocks scattered through them. This explains the low persons per built km².
  - **The same problem appears on a smaller scale** in Maipú and Guaymallén (Mendoza vineyards), the San Juan east belt, the Neuquén chacras and the Salta south horticultural belt.
  - GISD30 marks many cultivated or bare plots as built, and the fill then joins them up.
- **rd=1 is safer than rd=0 in the periphery, but costly in 1990.**
  - With rd=1 the teal in low-density belts turns red. That correctly removes vineyards, fields and riparian strips.
  - It also removes real low-density built tissue: Yerba Buena (Tucumán), Valle Viejo (Catamarca), the outer belts of Corrientes and San Juan, and SW Santa Fe.
  - rd=0 keeps that tissue but carries the farmland and river errors with it.
- **A 60 m gap is a reasonable middle; 90 m is too aggressive and 30 m too timid.**
  - With 90 m, Salta 1990 is almost entirely teal, including the river corridor, and all of Nordelta's channels and lots are filled.
  - With 30 m, tree-lined streets in the dense 1990 cores are left as red or violet holes.
  - 60 m is still too aggressive wherever the "built" pixels are themselves farm false positives (Maipú, Chubut valley).
  - I would keep 60 m and add exclusions (water, rivers, linear shapes, cropland) rather than change the radius.
- **Yellow (built outside the city) is mostly real, and it is not counted, so it is harmless.**
  - Real: separate towns (Lules, Paraná), barrios on the edge of Salta, rural houses along roads in the oases.
  - Runways: Tucumán, Sauce Viejo, Trelew, Salta.
  - Roads and levees.
  - Some noise on paths in parks (Parque San Martín in Mendoza, Reserva Ecológica in Buenos Aires).

## Per city

### Salta (salta)
Screenshots: `salta20_ov`, `salta20_sur`, `salta20_sur_ls`, `salta90_sur_ls`, `salta90_centro_esri`, `salta90_centro_ls`, `salta90_arenales`, `salta20_arenales`, `salta90_rd0_rd1`, `salta90_h30_h90`.

- **Centre grid:** mostly dark blue, with sparse teal speckle on courtyards and tree-lined streets. Correct.
- **Río Arenales riverbed** (about -24.807, -65.43): shown as a chain of violet (kept) and red patches. Thin teal lines run along the river and along the canal / Av. Tavella diagonal (about -24.80, -65.44). The violet riverbed and the teal banks are wrong.
- **South periphery horticultural fields** (view centre -24.865, -65.425; e.g. -24.858, -65.43):
  - Many ploughed or bare plots between barrios are dark blue, which is a GISD30 false positive.
  - Teal fills the field margins, and the large fields are red.
  - In this view about a third of the in-city land is farmland, and about half of that is drawn blue or teal.
- **rd=1 vs rd=0 in 1990** (view centre -24.80, -65.415): rd=1 turns the south belt (about -24.82, -65.41) and the centre-east (about -24.795, -65.40) red. Esri shows built fabric there today. I could not tell from the 30 m Landsat whether it was built in 1990.
- **h30 vs h90 in 1990** (-24.79, -65.41): with h30 the centre keeps red and violet clusters and a red diagonal band along the river corridor. With h90 almost everything turns teal, including that corridor.
- **Yellow:** the barrios west of the city (about -24.78, -65.46) are real settlement. The airport (SW) is outside, with yellow on its runway.
- **Edge ring:** the light-violet ring at the foot of Cerro San Bernardo (east) is sensible.

### Gran Tucumán (tucuman)
Screenshots: `tuc20_ov`, `tuc20_sali`, `tuc90_sali`, `tuc90_rd0_rd1`.

- **Overall:** good delimitation against the sugar-cane fields.
- **Parque 9 de Julio** is red (dropped), which is correct. A teal belt along its tree edge is a minor error.
- **Río Salí** (diagonal NE-SW through about -26.835, -65.18): a teal ribbon 1-2 pixels wide over several km, plus red patches to the south. This is riverbed and riparian land, so it is wrong.
- **rd=1 in 1990:** large belts turn red in Yerba Buena (W, about -26.81, -65.30) and on the east side. These look like partly built, low-density land, so rd=1 under-counts here.
- **Yellow:**
  - Lules (-26.92, -65.34) is a real separate town.
  - The vertical strip at -26.84, -65.10 is the airport runway, not settlement.
  - The northern line (about -26.70, -65.25) follows a road. I could not tell how much of it is settlement.

### Gran Catamarca (catamarca)
Screenshots: `cat20_ov`, `cat20_rio`, `cat20_valleviejo`, `cat90_rd0_rd1`.

- **Core:** fine. The hills and the bright bare land and quarries to the north stay outside, and they are not marked as built in 1990 either.
- **Río del Valle bed inside the city** (about -28.462, -65.755): the wide sandy bed between the two riverside avenues cannot be told apart in the overlay and appears dark blue. This is probably a GISD30 false positive on bright sand plus the paved banks. I could not separate the two at 30 m.
- **Valle Viejo** (about -28.445, -65.715):
  - Low-density houses under trees, with small orchards.
  - The overlay is roughly 50 % blue, 35 % teal and 15 % red; the red falls on fincas.
  - This is mostly real low-density fabric, so the teal is defensible.
- **rd=1 in 1990:** most of the eastern lobe (Valle Viejo side) turns red, which under-counts.

### Neuquén - Plottier (neuquen)
Screenshots: `neu20_ov`, `neu90_ov`, `neu20_limay`, `neu20_confl`, `neu20_costa`, `neu90_west`, `neu20_aero`.

- **Confluence** (about -38.95, -68.03): the riverbed and riparian land are mostly red, which is good. Errors:
  - Teal ribbons follow both banks.
  - The chacra mosaic inside the city (about -38.935, -68.045, dark green fields) is drawn dark blue plus teal.
- **Limay riverside** (-38.981, -68.078, zoom 16): teal sits on riparian woodland and vacant lots, and bare lots are dark blue. About half of the teal in this view is on non-built land.
- **Airport** (-38.95, -68.155):
  - 2020: the runway is mostly red (good).
  - 1990: the runway area lies inside the city as blue and teal.
  - The chacras west of the airport (about -38.945, -68.17) are partly dark blue, a GISD30 false positive on fields.
- **Yellow** in the Limay chacras: isolated houses and sheds. Plausible.

### Gran Santa Fe (santa_fe)
Screenshots: `sfe20_ov`, `sfe90_rd0_rd1`, `sfe20_colastine`, `sfe20_stome`.

- **City body:** well bounded by the Salado and Laguna Setúbal. The lagoon and the Paraná are excluded, and the ring follows the shore.
- **Paraná city** (large yellow patch to the SE) is correctly outside the city, as a separate agglomeration.
- **Yellow lines** along the levees, the circunvalación and RN168 are roads and embankments.
- **Colastiné / San José del Rincón** (-31.616, -60.594): weekend houses under trees, about 50/50 blue and teal. Defensible as built. The red falls on ponds and fields, which is good.
- **Santo Tomé south** (about -31.70, -60.79): a large red block on fields and sports grounds, correctly dropped. The Sauce Viejo runway is yellow.
- **rd=1 in 1990:** red is scattered over SW Santa Fe and Santo Tomé. rd=0 fills those spots teal, and they look like built fabric.

### Corrientes (corrientes)
Screenshots: `ctes20_ov`, `ctes90_rd0_rd1`, `ctes20_costa`, `ctes20_sur`.

- **Best case in the set.**
  - The historic centre is all dark blue, and teal is minimal (plazas and canopy).
  - The Paraná is excluded, and the ring follows the riverbank.
- **Interior red blobs** (about -27.525, -58.76 and -27.53, -58.775) are scrub, wetland and pasture, correctly dropped.
- **rd=1 in 1990:** much of the outer belt turns red, and part of that belt is real low-density built land.

### Rawson - Trelew (rawson): the approach fails here
Screenshots: `raw20_ov`, `raw90_ov`, `raw20_trelew`, `raw20_valle_oeste`, `raw20_valle_medio`.

- **The "city" covers the irrigated lower Chubut valley** from about -65.45 to -65.07, roughly 30 km long, in both 1990 and 2020.
  - At -43.27, -65.42 (towards Gaiman): pure chacras, with fields, greenhouses and canals. Drawn as about 50 % dark blue, 40 % teal and 10 % red.
  - At -43.285, -65.20: the meandering Chubut river is drawn in teal, and the surrounding fields are dark blue.
- **Trelew proper** (-43.25, -65.305) is correct. The airport to the north is yellow.
- **Why the density is so low:** the low persons per built km² comes from farmland in the built-up denominator, many km² of it.
- **Recommendation:** treat Rawson-Trelew as not valid until the valley is masked, with a cropland or NDVI-seasonality mask, or by restricting the city to the urban-locality polygons.

### Gran Mendoza (mendoza), esri only
Screenshots: `mza20_ov`, `mza90_ov`, `mza90_centro`, `mza20_maipu`, `mza20_maipu_z16`, `mza20_maipu_h30_h60`.

- **1990 core** (-32.89, -68.845): teal follows the tree-lined avenues and acequias. This is correct, because the canopy hides the pavement.
- **Parque San Martín** (west) is outside the city, with yellow speckle on its paths and buildings (noise).
- **Maipú / Guaymallén vineyard belt** (-32.966, -68.765; zoom 16 at -32.973, -68.752):
  - Parts of the vineyard blocks are dark blue.
  - Teal fills the strips between the vineyards and the houses.
  - The large blocks are red.
  - At zoom 16, about 40-50 % of the teal is on farmland.
- **Gap size here:** with h30 the same pixels come out red instead of teal. So it is the 60 m closing that turns these farm gaps into built land.
- **Yellow** speckle east of the city covers the vineyard belt: farm buildings, roads and dispersed houses. Not counted.

### Gran San Juan (san_juan), esri only
Screenshots: `sj20_ov`, `sj90_rd0_rd1`, `sj20_este`, `sj90_este`.

- **Core:** good.
- **1990 Circunvalación:** the ring road appears as a continuous teal ring (its median and verges), a linear-feature error.
- **East periphery** (Santa Lucía, about -31.53, -68.485): a farm mosaic inside the city. The larger fields are red, but many small fields are blue or teal.
- **Yellow:** linear along the rural roads. This is real dispersed rural housing plus road surface.
- **rd=1 in 1990:** much of the outer belt turns red, and that belt mixes vineyards with real barrios.

### Gran Buenos Aires (buenos_aires), spot checks
Screenshots: `ba20_nordelta`, `ba20_nordelta_h30_h90`, `ba20_reserva`.

- **Nordelta** (-34.405, -58.645):
  - The central lake (about -34.41, -58.645) is red, which is good.
  - The lake arms and canals between the island lots, and parts of the golf courses, are teal. That teal is on water.
  - With h90 almost everything between the barrios is teal. With h30 it is mostly red.
- **Costanera Sur:**
  - The Reserva Ecológica is correctly outside the city, with the ring along its edge.
  - The Puerto Madero docks (about -34.61, -58.363) are a mix of red and teal speckle. The teal parts are on water.

## Answers to the questions (pooled)

1. **Where the teal lands:**
   - Dense cores: about 70-90 % on built fabric.
   - Peripheral belts of the irrigated cities (Mendoza, San Juan, Neuquén, Salta south): about 40-50 % on farmland or vacant lots.
   - Rawson valley: mostly farmland and river.
   - Wherever a river, canal or highway crosses the city, there is a systematic linear error.
2. **False positives in dark blue:**
   - Ploughed or bare fields: Salta south, Neuquén chacras, Chubut valley, Maipú vineyards.
   - The sandy riverbed in Catamarca.
   - The 1990 runway area in Neuquén.
   - I did not isolate greenhouses at 30 m, although there are greenhouses inside blue areas in the Chubut valley.
3. **Violet (kept) vs red (dropped):**
   - I saw no commercial core being dropped. Cores are almost all built-up, so the density rule barely acts there.
   - The rule correctly drops parks, wetlands and large fields.
   - It keeps farmland that sits in dense-enough tracts, and it keeps part of the Arenales riverbed in Salta as violet.
4. **Edge ring:** sensible everywhere I looked. It follows riverbanks and foothills, and the fill rule correctly never fires inside it.
5. **Yellow:** mostly real (towns, rural houses, runways, roads), with some noise on park paths. Harmless.
6. **Where the approach fails:**
   - Whole city: Rawson-Trelew.
   - Partial: the Mendoza east and south belt, the San Juan east belt, and the Neuquén chacra pockets.

## Recommendations

1. **Mask water and riverbeds before the closing.** Use JRC Global Surface Water occurrence plus OSM or IGN waterway buffers. On those pixels there should be no fill, and fringe should not be kept. This fixes the Salí, Arenales, Limay, Chubut, Nordelta and Puerto Madero errors, and the violet riverbed in Salta.
2. **Do not fill elongated components.** Reject a filled connected component when it is long and thin, for example when skeleton length / area or the ratio of the minimum bounding rectangle is above a threshold. This removes river, canal and avenue ribbons and keeps courtyard-like gaps.
3. **Add a cropland check for the oasis cities** (Rawson, Mendoza, San Juan, Neuquén, Salta south). Do not fill where a growing-season NDVI series shows cropping, and ideally screen GISD30 "built" pixels the same way. Until this exists, flag Rawson-Trelew as not valid.
4. **Keep 60 m and reject 90 m.** 30 m leaves holes in the dense 1990 cores. A hybrid could work better than either rd value: rd=0 in tracts above the median density, rd=1 below it.
5. **If rd=1 becomes the default, document the 1990 under-count it causes** in Yerba Buena, Valle Viejo, the Corrientes outer belt and San Juan.
