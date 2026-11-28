---
title: "2 · Calles"
parent: "Río Gallegos"
grand_parent: "Aglomerados"
nav_order: 2
---

# Río Gallegos · Calles


7,598 intersecciones en el cuadrado, 4,659 dentro del perimetro EPH. Perimetro EPH: 150 radios, 113,121 personas. Saltos mas grandes del tamano de la ciudad en d = 170, 100, 130 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 250 m.** A ese d, la percolacion agrega 11 radios (1,203 personas) fuera del perimetro y deja 2 radios del perimetro (967 personas) con menos del 50% de su area dentro.

Diagnostico: cubre el 100% a d = 390 m (agrega 13 radios, 1,446 personas; deja 1 radios, 129 personas).

![curva]({{ '/assets/extension/rio_gallegos/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/rio_gallegos/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 3,583 | 21.6 | 117 / 97,871 | 0 / 0 | 33 / 15,250 |
| 200 | 5,391 | 39.5 | 143 / 108,670 | 3 / 389 | 7 / 4,451 |
| **250** | 6,208 | 57.4 | 148 / 112,154 | 11 / 1,203 | 2 / 967 |
| **390** | 6,366 | 74.3 | 149 / 112,992 | 13 / 1,446 | 1 / 129 |
| 500 | 6,369 | 81.7 | 149 / 112,992 | 13 / 1,446 | 1 / 129 |
| 800 | 6,414 | 102.8 | 150 / 113,121 | 13 / 1,446 | 0 / 0 |
| 1000 | 6,575 | 130.2 | 150 / 113,121 | 13 / 1,446 | 0 / 0 |
| 1500 | 6,722 | 204.2 | 150 / 113,121 | 13 / 1,446 | 0 / 0 |
| 2000 | 6,776 | 282.5 | 150 / 113,121 | 13 / 1,446 | 0 / 0 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 800 m.

![radios a d = 250 m]({{ '/assets/extension/rio_gallegos/calles_radios_d250.webp' | relative_url }})

![radios a d = 390 m]({{ '/assets/extension/rio_gallegos/calles_radios_d390.webp' | relative_url }})







