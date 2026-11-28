---
title: "2 · Calles"
parent: "Ushuaia - Río Grande"
grand_parent: "Aglomerados"
nav_order: 2
---

# Ushuaia - Río Grande · Calles


2,796 intersecciones en el cuadrado, 2,373 dentro del perimetro EPH. Perimetro EPH: 99 radios, 78,490 personas. Saltos mas grandes del tamano de la ciudad en d = 200, 110, 140 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 700 m.** A ese d, la percolacion agrega 1 radios (919 personas) fuera del perimetro y deja 3 radios del perimetro (2,046 personas) con menos del 50% de su area dentro.

Diagnostico: cubre el 100% a d = 1000 m (agrega 1 radios, 919 personas; deja 0 radios, 0 personas).

![curva]({{ '/assets/extension/ushuaia__rio_grande/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/ushuaia__rio_grande/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 1,579 | 10 | 66 / 51,596 | 1 / 919 | 33 / 26,894 |
| 200 | 2,224 | 16.8 | 86 / 68,239 | 1 / 919 | 13 / 10,251 |
| 500 | 2,476 | 33.6 | 95 / 76,243 | 1 / 919 | 4 / 2,247 |
| **700** | 2,580 | 49.7 | 96 / 76,444 | 1 / 919 | 3 / 2,046 |
| 800 | 2,582 | 54.2 | 98 / 77,893 | 1 / 919 | 1 / 597 |
| **1000** | 2,584 | 63.7 | 99 / 78,490 | 1 / 919 | 0 / 0 |
| 1500 | 2,597 | 94.4 | 99 / 78,490 | 1 / 919 | 0 / 0 |
| 2000 | 2,643 | 140.7 | 99 / 78,490 | 1 / 919 | 0 / 0 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 1000 m.

![radios a d = 700 m]({{ '/assets/extension/ushuaia__rio_grande/calles_radios_d700.webp' | relative_url }})

![radios a d = 1000 m]({{ '/assets/extension/ushuaia__rio_grande/calles_radios_d1000.webp' | relative_url }})







