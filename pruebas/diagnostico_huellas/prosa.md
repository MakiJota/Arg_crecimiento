*Written by hand, without numbers: every figure it refers to is in the tables above.*

- **Footprint per dwelling is the stable quantity; GISD30 built-up per dwelling is not.** Across the 31 cities the value at
  each within-city percentile of footprint m2 per dwelling varies little (see the spread table: max / min and cv for
  *footprint m2 / dwelling*). Built-up per dwelling is close across cities at the median but fans out at p90 and explodes at
  p95, driven by a few cities (Rawson - Trelew above all, then Neuquén - Plottier and Bahía Blanca - Cerri). So a percentile
  cut on built-up per dwelling does **not** mean the same physical thing everywhere: in a city whose upper tail is farmland
  misread as built-up, its own p90 is already inflated by the error the cap is meant to remove.
- **The two ratios rank tracts similarly** (Spearman table), so footprints can serve as an independent check of where the
  excess sits, but the ranking agreement is weaker exactly in the cities with the most suspicious built-up (Salta, Río
  Cuarto, Concordia, Formosa, Santiago del Estero).
- **Near-empty tracts carry the excess.** By within-city density quartile, built-up per dwelling rises steeply from the
  densest to the emptiest quartile while footprint per dwelling rises only moderately, and the share of built pixels with
  any footprint falls. The gap between the two is the candidate for trimming.
- **Non-residential built-up is a large part of what a dwelling cap would hit.** In the p90 simulation a substantial share
  of the trimmed area lies in tracts whose built-up is mostly on mapped industrial, commercial, institutional, education,
  health, railway or airport land (Gran Buenos Aires, Gran Rosario, Gran Córdoba and Bahía Blanca - Cerri especially).
  These tracts legitimately have much built-up and few dwellings. Since land use comes from OpenStreetMap, unmapped
  industry is labelled `residential / other`, so the non-residential share is a lower bound.
- **Most of the trim could come from pixels with no footprint.** In every city the larger part of the p90 trim fits within
  the tract's built pixels that have no Overture footprint. Where the trim would have to remove footprint-confirmed
  pixels (La Plata, Buenos Aires, Córdoba, Rosario stand out) the cap is fighting real buildings: industrial and
  logistics areas, country clubs and low-density suburbs with large lots.
- **Agreement GISD30 - footprints is high for city built-up and much lower for built-up outside the city** (code 3),
  consistent with code 3 holding more non-building surfaces (farm tracks, greenhouses, bare soil). Rawson - Trelew is the
  outlier: most of its GISD30 built-up has no footprint and a large part lies on mapped farmland, the case the cap is
  designed for. Río Cuarto is the opposite outlier: a large share of footprint area falls on pixels GISD30 calls
  non-built, so GISD30 2020 seems to *miss* part of the city there (to check on the map before applying any rule).

**Implications for the dwelling cap.**

1. Express the cap in footprint terms or protect footprint-confirmed pixels: trim only built pixels **without** any
   footprint, in tracts above the city's percentile. This keeps the rule free of per-city calibration and makes it
   insensitive to the inflated upper tail of built-up per dwelling.
2. Exempt (or treat separately) tracts dominated by non-residential land use and airports, and never trim pixels on
   mapped non-residential land. Dwellings are the wrong denominator for factories, hospitals, schools, rail yards and
   airports; the census does not count them.
3. Prefer a percentile of *footprint per dwelling* (or of footprint per built m2) over a percentile of built-up per
   dwelling as the trigger: its cuts land on similar physical values in every city, so "above the city's p90" means
   roughly the same thing in Salta and in Buenos Aires.
4. Keep in mind the time mismatch: footprints are present-day, the image is 2020 and the census 2022. A footprint-based
   protection in 2020 may keep a few buildings newer than the image, which errs on the safe side; for earlier years the
   footprint can only say "no building today, so no building then", never the reverse.
5. Before adopting the rule, look at the maps of the cities where the trim is large relative to their built-up
   (Rawson - Trelew, Salta, Neuquén - Plottier, La Plata) and of Río Cuarto, where the problem runs the other way.
