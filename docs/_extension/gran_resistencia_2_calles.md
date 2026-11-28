---
title: "2 · Calles"
parent: "Gran Resistencia"
grand_parent: "Aglomerados"
nav_order: 2
---

# Gran Resistencia · Calles


26,160 intersecciones en el cuadrado, 12,650 dentro del perimetro EPH. Perimetro EPH: 525 radios, 414,305 personas. Saltos mas grandes del tamano de la ciudad en d = 120, 130, 140 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 370 m.** A ese d, la percolacion agrega 1 radios (238 personas) fuera del perimetro y deja 7 radios del perimetro (4,303 personas) con menos del 50% de su area dentro.

Diagnostico: cubre el 100% a d = 1050 m (agrega 25 radios, 14,292 personas; deja 0 radios, 0 personas).

![curva]({{ '/assets/extension/gran_resistencia/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/gran_resistencia/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 10,147 | 69.6 | 447 / 349,226 | 0 / 0 | 78 / 65,079 |
| 200 | 11,507 | 87 | 479 / 376,148 | 0 / 0 | 46 / 38,157 |
| **370** | 13,091 | 144.9 | 518 / 410,002 | 1 / 238 | 7 / 4,303 |
| 500 | 13,336 | 173.2 | 522 / 411,994 | 2 / 1,306 | 3 / 2,311 |
| 800 | 13,639 | 229.5 | 524 / 413,205 | 6 / 2,691 | 1 / 1,100 |
| 1000 | 13,716 | 267.3 | 525 / 414,305 | 6 / 2,691 | 0 / 0 |
| **1050** | 14,760 | 393.4 | 525 / 414,305 | 25 / 14,292 | 0 / 0 |
| 1500 | 14,776 | 486.1 | 525 / 414,305 | 30 / 16,212 | 0 / 0 |
| 2000 | 14,816 | 601.6 | 525 / 414,305 | 31 / 16,850 | 0 / 0 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 1000 m.

![radios a d = 370 m]({{ '/assets/extension/gran_resistencia/calles_radios_d370.webp' | relative_url }})

![radios a d = 1050 m]({{ '/assets/extension/gran_resistencia/calles_radios_d1050.webp' | relative_url }})







