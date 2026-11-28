---
title: "2 · Calles"
parent: "Bahía Blanca - Cerri"
grand_parent: "Aglomerados"
nav_order: 2
---

# Bahía Blanca - Cerri · Calles


14,932 intersecciones en el cuadrado, 11,195 dentro del perimetro EPH. Perimetro EPH: 473 radios, 331,231 personas. Saltos mas grandes del tamano de la ciudad en d = 140, 1400, 130 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 1550 m.** A ese d, la percolacion agrega 89 radios (64,220 personas) fuera del perimetro y deja 1 radios del perimetro (47 personas) con menos del 50% de su area dentro.

Diagnostico: no cubre el 100% a 2000 m.

![curva]({{ '/assets/extension/bahia_blanca__cerri/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/bahia_blanca__cerri/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 8,212 | 72.4 | 408 / 289,851 | 0 / 0 | 65 / 41,380 |
| 200 | 8,436 | 83.3 | 412 / 292,179 | 0 / 0 | 61 / 39,052 |
| 500 | 11,318 | 169.6 | 456 / 320,734 | 0 / 0 | 17 / 10,497 |
| 800 | 11,449 | 205.3 | 461 / 323,387 | 0 / 0 | 12 / 7,844 |
| 1000 | 11,533 | 227.5 | 461 / 323,387 | 1 / 619 | 12 / 7,844 |
| 1500 | 13,648 | 424.2 | 462 / 323,480 | 89 / 64,220 | 11 / 7,751 |
| **1550** | 14,007 | 465.8 | 472 / 331,184 | 89 / 64,220 | 1 / 47 |
| 2000 | 14,097 | 631.9 | 472 / 331,184 | 89 / 64,220 | 1 / 47 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 800 m.

![radios a d = 1550 m]({{ '/assets/extension/bahia_blanca__cerri/calles_radios_d1550.webp' | relative_url }})







