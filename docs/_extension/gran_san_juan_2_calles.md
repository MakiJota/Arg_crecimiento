---
title: "2 · Calles"
parent: "Gran San Juan"
grand_parent: "Aglomerados"
nav_order: 2
---

# Gran San Juan · Calles


22,676 intersecciones en el cuadrado, 16,913 dentro del perimetro EPH. Perimetro EPH: 624 radios, 601,627 personas. Saltos mas grandes del tamano de la ciudad en d = 130, 110, 1350 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 700 m.** A ese d, la percolacion agrega 12 radios (9,810 personas) fuera del perimetro y deja 10 radios del perimetro (10,577 personas) con menos del 50% de su area dentro.

Diagnostico: cubre el 100% a d = 1550 m (agrega 118 radios, 121,156 personas; deja 2 radios, 1,700 personas).

![curva]({{ '/assets/extension/gran_san_juan/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/gran_san_juan/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 11,270 | 79.8 | 460 / 424,611 | 0 / 0 | 164 / 177,016 |
| 200 | 12,621 | 105.7 | 493 / 460,799 | 0 / 0 | 131 / 140,828 |
| 500 | 16,789 | 266.2 | 581 / 557,810 | 1 / 658 | 43 / 43,817 |
| **700** | 18,170 | 405.2 | 614 / 591,050 | 12 / 9,810 | 10 / 10,577 |
| 800 | 18,799 | 490 | 615 / 592,439 | 21 / 19,098 | 9 / 9,188 |
| 1000 | 19,362 | 634.4 | 620 / 598,545 | 34 / 35,006 | 4 / 3,082 |
| 1500 | 22,004 | 1400.8 | 622 / 599,927 | 118 / 121,156 | 2 / 1,700 |
| **1550** | 22,023 | 1431 | 622 / 599,927 | 118 / 121,156 | 2 / 1,700 |
| 2000 | 22,264 | 1711.7 | 623 / 601,036 | 123 / 124,589 | 1 / 591 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 700 m.

![radios a d = 700 m]({{ '/assets/extension/gran_san_juan/calles_radios_d700.webp' | relative_url }})

![radios a d = 1550 m]({{ '/assets/extension/gran_san_juan/calles_radios_d1550.webp' | relative_url }})







