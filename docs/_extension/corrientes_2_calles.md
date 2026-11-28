---
title: "2 · Calles"
parent: "Corrientes"
grand_parent: "Aglomerados"
nav_order: 2
---

# Corrientes · Calles


27,476 intersecciones en el cuadrado, 8,970 dentro del perimetro EPH. Perimetro EPH: 448 radios, 428,925 personas. Saltos mas grandes del tamano de la ciudad en d = 100, 110, 130 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 1300 m.** A ese d, la percolacion agrega 15 radios (10,872 personas) fuera del perimetro y deja 1 radios del perimetro (966 personas) con menos del 50% de su area dentro.

Diagnostico: no cubre el 100% a 2000 m.

![curva]({{ '/assets/extension/corrientes/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/corrientes/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 7,643 | 49.4 | 401 / 379,159 | 1 / 681 | 47 / 49,766 |
| 200 | 8,028 | 56.1 | 411 / 388,410 | 1 / 681 | 37 / 40,515 |
| 500 | 8,396 | 81.1 | 435 / 417,656 | 1 / 681 | 13 / 11,269 |
| 800 | 9,348 | 145.8 | 444 / 424,701 | 6 / 3,806 | 4 / 4,224 |
| 1000 | 9,434 | 174.1 | 444 / 424,701 | 7 / 4,309 | 4 / 4,224 |
| **1300** | 10,060 | 289.4 | 447 / 427,959 | 15 / 10,872 | 1 / 966 |
| 1500 | 10,072 | 327.9 | 447 / 427,959 | 17 / 11,193 | 1 / 966 |
| 2000 | 10,288 | 513 | 448 / 428,925 | 25 / 13,713 | 0 / 0 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 800 m.

![radios a d = 1300 m]({{ '/assets/extension/corrientes/calles_radios_d1300.webp' | relative_url }})







