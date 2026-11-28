---
title: "2 · Calles"
parent: "Gran La Plata"
grand_parent: "Aglomerados"
nav_order: 2
---

# Gran La Plata · Calles


66,942 intersecciones en el cuadrado, 24,708 dentro del perimetro EPH. Perimetro EPH: 1,225 radios, 916,202 personas. Saltos mas grandes del tamano de la ciudad en d = 490, 140, 210 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 1000 m.** A ese d, la percolacion agrega 2,237 radios (2,273,821 personas) fuera del perimetro y deja 17 radios del perimetro (7,325 personas) con menos del 50% de su area dentro.

Diagnostico: no cubre el 100% a 2000 m.

![curva]({{ '/assets/extension/gran_la_plata/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/gran_la_plata/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 14,540 | 135.5 | 910 / 678,460 | 0 / 0 | 315 / 237,742 |
| 200 | 15,589 | 164.9 | 939 / 702,232 | 0 / 0 | 286 / 213,970 |
| 500 | 61,238 | 881.6 | 1,188 / 897,612 | 2,186 / 2,233,875 | 37 / 18,590 |
| 800 | 61,752 | 1092.5 | 1,203 / 906,715 | 2,219 / 2,264,966 | 22 / 9,487 |
| **1000** | 63,098 | 1276.4 | 1,208 / 908,877 | 2,237 / 2,273,821 | 17 / 7,325 |
| 1500 | 65,970 | 1850.4 | 1,215 / 911,142 | 2,326 / 2,324,003 | 10 / 5,060 |
| 2000 | 66,822 | 2605.1 | 1,218 / 912,039 | 2,345 / 2,329,252 | 7 / 4,163 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 200 m.

![radios a d = 1000 m]({{ '/assets/extension/gran_la_plata/calles_radios_d1000.webp' | relative_url }})







