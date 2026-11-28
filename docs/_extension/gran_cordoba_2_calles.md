---
title: "2 · Calles"
parent: "Gran Córdoba"
grand_parent: "Aglomerados"
nav_order: 2
---

# Gran Córdoba · Calles


78,247 intersecciones en el cuadrado, 48,228 dentro del perimetro EPH. Perimetro EPH: 2,330 radios, 1,709,852 personas. Saltos mas grandes del tamano de la ciudad en d = 700, 110, 120 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 700 m.** A ese d, la percolacion agrega 425 radios (216,870 personas) fuera del perimetro y deja 9 radios del perimetro (6,167 personas) con menos del 50% de su area dentro.

Diagnostico: cubre el 100% a d = 1800 m (agrega 606 radios, 331,592 personas; deja 0 radios, 0 personas).

![curva]({{ '/assets/extension/gran_cordoba/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/gran_cordoba/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 36,081 | 228.3 | 1,957 / 1,422,505 | 0 / 0 | 373 / 287,347 |
| 200 | 41,551 | 295.1 | 2,094 / 1,526,389 | 5 / 3,002 | 236 / 183,463 |
| 500 | 49,418 | 572.6 | 2,278 / 1,661,045 | 11 / 7,362 | 52 / 48,807 |
| **700** | 68,862 | 1117.2 | 2,321 / 1,703,685 | 425 / 216,870 | 9 / 6,167 |
| 800 | 69,328 | 1222.9 | 2,324 / 1,706,338 | 432 / 220,048 | 6 / 3,514 |
| 1000 | 69,814 | 1424.7 | 2,325 / 1,707,056 | 442 / 221,667 | 5 / 2,796 |
| 1500 | 76,208 | 2551.4 | 2,328 / 1,708,705 | 540 / 293,425 | 2 / 1,147 |
| **1800** | 78,081 | 3332.4 | 2,330 / 1,709,852 | 606 / 331,592 | 0 / 0 |
| 2000 | 78,113 | 3574.2 | 2,330 / 1,709,852 | 610 / 331,879 | 0 / 0 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 500 m.

![radios a d = 700 m]({{ '/assets/extension/gran_cordoba/calles_radios_d700.webp' | relative_url }})

![radios a d = 1800 m]({{ '/assets/extension/gran_cordoba/calles_radios_d1800.webp' | relative_url }})







