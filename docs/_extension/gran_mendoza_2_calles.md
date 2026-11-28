---
title: "2 · Calles"
parent: "Gran Mendoza"
grand_parent: "Aglomerados"
nav_order: 2
---

# Gran Mendoza · Calles


41,984 intersecciones en el cuadrado, 31,408 dentro del perimetro EPH. Perimetro EPH: 1,338 radios, 1,115,703 personas. Saltos mas grandes del tamano de la ciudad en d = 120, 110, 170 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 410 m.** A ese d, la percolacion agrega 85 radios (84,018 personas) fuera del perimetro y deja 23 radios del perimetro (22,946 personas) con menos del 50% de su area dentro.

Diagnostico: no cubre el 100% a 2000 m.

![curva]({{ '/assets/extension/gran_mendoza/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/gran_mendoza/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 20,370 | 131.2 | 998 / 802,414 | 0 / 0 | 340 / 313,289 |
| 200 | 26,432 | 200.9 | 1,169 / 949,160 | 0 / 0 | 169 / 166,543 |
| **410** | 35,479 | 462.5 | 1,315 / 1,092,757 | 85 / 84,018 | 23 / 22,946 |
| 500 | 37,038 | 580.9 | 1,325 / 1,106,365 | 120 / 126,252 | 13 / 9,338 |
| 800 | 38,799 | 890.9 | 1,331 / 1,111,932 | 150 / 164,172 | 7 / 3,771 |
| 1000 | 39,827 | 1093.5 | 1,332 / 1,112,038 | 175 / 195,806 | 6 / 3,665 |
| 1500 | 41,105 | 1615 | 1,333 / 1,112,885 | 208 / 231,262 | 5 / 2,818 |
| 2000 | 41,306 | 1992.3 | 1,333 / 1,112,885 | 223 / 248,597 | 5 / 2,818 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 410 m.

![radios a d = 410 m]({{ '/assets/extension/gran_mendoza/calles_radios_d410.webp' | relative_url }})







