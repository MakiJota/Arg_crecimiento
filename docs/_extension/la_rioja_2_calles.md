---
title: "2 · Calles"
parent: "La Rioja"
grand_parent: "Aglomerados"
nav_order: 2
---

# La Rioja · Calles


9,370 intersecciones en el cuadrado, 8,773 dentro del perimetro EPH. Perimetro EPH: 258 radios, 209,485 personas. Saltos mas grandes del tamano de la ciudad en d = 130, 100, 120 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 1700 m.** A ese d, la percolacion agrega 0 radios (0 personas) fuera del perimetro y deja 2 radios del perimetro (1,643 personas) con menos del 50% de su area dentro.

Diagnostico: no cubre el 100% a 2000 m.

![curva]({{ '/assets/extension/la_rioja/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/la_rioja/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 7,167 | 51.1 | 227 / 182,370 | 0 / 0 | 31 / 27,115 |
| 200 | 8,244 | 71.9 | 244 / 197,876 | 0 / 0 | 14 / 11,609 |
| 500 | 8,819 | 113.2 | 255 / 207,484 | 0 / 0 | 3 / 2,001 |
| 800 | 8,915 | 141.2 | 255 / 207,484 | 0 / 0 | 3 / 2,001 |
| 1000 | 8,973 | 163.8 | 255 / 207,484 | 0 / 0 | 3 / 2,001 |
| 1500 | 8,995 | 209.3 | 255 / 207,484 | 0 / 0 | 3 / 2,001 |
| **1700** | 9,052 | 243.2 | 256 / 207,842 | 0 / 0 | 2 / 1,643 |
| 2000 | 9,270 | 306.5 | 256 / 207,842 | 5 / 2,925 | 2 / 1,643 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 1700 m.

![radios a d = 1700 m]({{ '/assets/extension/la_rioja/calles_radios_d1700.webp' | relative_url }})







