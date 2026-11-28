---
title: "2 · Calles"
parent: "Santa Rosa - Toay"
grand_parent: "Aglomerados"
nav_order: 2
---

# Santa Rosa - Toay · Calles


6,952 intersecciones en el cuadrado, 6,013 dentro del perimetro EPH. Perimetro EPH: 220 radios, 133,002 personas. Saltos mas grandes del tamano de la ciudad en d = 120, 110, 210 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 1900 m.** A ese d, la percolacion agrega 1 radios (80 personas) fuera del perimetro y deja 2 radios del perimetro (923 personas) con menos del 50% de su area dentro.

Diagnostico: no cubre el 100% a 2000 m.

![curva]({{ '/assets/extension/santa_rosa__toay/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/santa_rosa__toay/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 4,565 | 33.4 | 181 / 109,663 | 0 / 0 | 39 / 23,339 |
| 200 | 4,923 | 41.1 | 191 / 114,485 | 0 / 0 | 29 / 18,517 |
| 500 | 6,064 | 72.4 | 216 / 131,519 | 0 / 0 | 4 / 1,483 |
| 800 | 6,110 | 92.8 | 217 / 131,649 | 0 / 0 | 3 / 1,353 |
| 1000 | 6,126 | 107.5 | 217 / 131,649 | 0 / 0 | 3 / 1,353 |
| 1500 | 6,146 | 146.6 | 217 / 131,649 | 0 / 0 | 3 / 1,353 |
| **1900** | 6,286 | 210.8 | 218 / 132,079 | 1 / 80 | 2 / 923 |
| 2000 | 6,289 | 224.5 | 218 / 132,079 | 1 / 80 | 2 / 923 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 1900 m.

![radios a d = 1900 m]({{ '/assets/extension/santa_rosa__toay/calles_radios_d1900.webp' | relative_url }})







