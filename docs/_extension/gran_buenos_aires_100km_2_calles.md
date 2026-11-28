---
title: "2 · Calles"
parent: "Gran Buenos Aires (100 km)"
grand_parent: "Aglomerados"
nav_order: 2
---

# Gran Buenos Aires (100 km) · Calles


285,048 intersecciones en el cuadrado, 261,023 dentro del perimetro EPH. Perimetro EPH: 16,108 radios, 15,061,658 personas. Saltos mas grandes del tamano de la ciudad en d = 130, 140, 120 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 600 m.** A ese d, la percolacion agrega 289 radios (188,167 personas) fuera del perimetro y deja 137 radios del perimetro (50,319 personas) con menos del 50% de su area dentro.

Diagnostico: no cubre el 100% a 2000 m.

![curva]({{ '/assets/extension/gran_buenos_aires_100km/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/gran_buenos_aires_100km/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 206,942 | 1641 | 14,525 / 13,748,587 | 0 / 0 | 1,583 / 1,313,071 |
| 200 | 235,230 | 2065.8 | 15,317 / 14,509,414 | 2 / 492 | 791 / 552,244 |
| 500 | 268,314 | 3317.8 | 15,907 / 14,967,231 | 238 / 159,987 | 201 / 94,427 |
| **600** | 273,092 | 3668.4 | 15,971 / 15,011,339 | 289 / 188,167 | 137 / 50,319 |
| 800 | 275,440 | 4147.8 | 16,017 / 15,034,392 | 319 / 197,282 | 91 / 27,266 |
| 1000 | 281,995 | 4708.8 | 16,038 / 15,044,796 | 483 / 323,732 | 70 / 16,862 |
| 1500 | 284,363 | 5754.5 | 16,059 / 15,051,629 | 550 / 351,127 | 49 / 10,029 |
| 2000 | 284,711 | 6455.9 | 16,063 / 15,052,741 | 576 / 356,141 | 45 / 8,917 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 800 m.

![radios a d = 600 m]({{ '/assets/extension/gran_buenos_aires_100km/calles_radios_d600.webp' | relative_url }})







