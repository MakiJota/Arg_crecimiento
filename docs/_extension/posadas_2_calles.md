---
title: "2 · Calles"
parent: "Posadas"
grand_parent: "Aglomerados"
nav_order: 2
---

# Posadas · Calles


25,899 intersecciones en el cuadrado, 12,295 dentro del perimetro EPH. Perimetro EPH: 510 radios, 385,202 personas. Saltos mas grandes del tamano de la ciudad en d = 1100, 110, 100 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 650 m.** A ese d, la percolacion agrega 7 radios (3,907 personas) fuera del perimetro y deja 2 radios del perimetro (235 personas) con menos del 50% de su area dentro.

Diagnostico: cubre el 100% a d = 1750 m (agrega 87 radios, 44,355 personas; deja 0 radios, 0 personas).

![curva]({{ '/assets/extension/posadas/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/posadas/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 7,601 | 50.7 | 366 / 268,043 | 0 / 0 | 144 / 117,159 |
| 200 | 7,774 | 56 | 370 / 270,771 | 0 / 0 | 140 / 114,431 |
| 500 | 12,845 | 180.5 | 507 / 384,170 | 6 / 3,215 | 3 / 1,032 |
| **650** | 13,105 | 233.7 | 508 / 384,967 | 7 / 3,907 | 2 / 235 |
| 800 | 13,277 | 285.6 | 509 / 385,127 | 11 / 4,228 | 1 / 75 |
| 1000 | 14,691 | 396.1 | 509 / 385,127 | 39 / 22,816 | 1 / 75 |
| 1500 | 23,378 | 1514.4 | 510 / 385,202 | 66 / 33,942 | 0 / 0 |
| **1750** | 24,870 | 2138.7 | 510 / 385,202 | 87 / 44,355 | 0 / 0 |
| 2000 | 25,175 | 2496.9 | 510 / 385,202 | 98 / 47,144 | 0 / 0 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 650 m.

![radios a d = 650 m]({{ '/assets/extension/posadas/calles_radios_d650.webp' | relative_url }})

![radios a d = 1750 m]({{ '/assets/extension/posadas/calles_radios_d1750.webp' | relative_url }})







