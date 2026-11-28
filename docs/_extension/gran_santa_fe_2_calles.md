---
title: "2 · Calles"
parent: "Gran Santa Fe"
grand_parent: "Aglomerados"
nav_order: 2
---

# Gran Santa Fe · Calles


30,279 intersecciones en el cuadrado, 14,182 dentro del perimetro EPH. Perimetro EPH: 742 radios, 536,948 personas. Saltos mas grandes del tamano de la ciudad en d = 110, 600, 1500 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 1500 m.** A ese d, la percolacion agrega 112 radios (71,481 personas) fuera del perimetro y deja 8 radios del perimetro (2,847 personas) con menos del 50% de su area dentro.

Diagnostico: no cubre el 100% a 2000 m.

![curva]({{ '/assets/extension/gran_santa_fe/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/gran_santa_fe/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 7,078 | 50.9 | 503 / 350,288 | 0 / 0 | 239 / 186,660 |
| 200 | 7,451 | 58.8 | 514 / 361,848 | 0 / 0 | 228 / 175,100 |
| 500 | 8,848 | 104.6 | 559 / 401,862 | 0 / 0 | 183 / 135,086 |
| 800 | 12,964 | 265.8 | 688 / 501,461 | 3 / 1,716 | 54 / 35,487 |
| 1000 | 13,604 | 389.8 | 690 / 503,379 | 14 / 8,573 | 52 / 33,569 |
| **1500** | 19,405 | 1281.3 | 734 / 534,101 | 112 / 71,481 | 8 / 2,847 |
| 2000 | 19,991 | 1746.6 | 736 / 535,235 | 127 / 77,701 | 6 / 1,713 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 800 m.

![radios a d = 1500 m]({{ '/assets/extension/gran_santa_fe/calles_radios_d1500.webp' | relative_url }})







