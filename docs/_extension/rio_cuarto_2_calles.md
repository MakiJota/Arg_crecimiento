---
title: "2 · Calles"
parent: "Río Cuarto"
grand_parent: "Aglomerados"
nav_order: 2
---

# Río Cuarto · Calles


9,174 intersecciones en el cuadrado, 6,032 dentro del perimetro EPH. Perimetro EPH: 350 radios, 187,790 personas. Saltos mas grandes del tamano de la ciudad en d = 160, 150, 120 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 550 m.** A ese d, la percolacion agrega 1 radios (920 personas) fuera del perimetro y deja 2 radios del perimetro (1,586 personas) con menos del 50% de su area dentro.

Diagnostico: cubre el 100% a d = 1700 m (agrega 14 radios, 7,564 personas; deja 0 radios, 0 personas).

![curva]({{ '/assets/extension/rio_cuarto/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/rio_cuarto/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 3,730 | 30.6 | 255 / 130,108 | 0 / 0 | 95 / 57,682 |
| 200 | 5,720 | 53.8 | 340 / 181,421 | 0 / 0 | 10 / 6,369 |
| 500 | 6,379 | 86.5 | 348 / 186,204 | 1 / 920 | 2 / 1,586 |
| **550** | 6,413 | 91.6 | 348 / 186,204 | 1 / 920 | 2 / 1,586 |
| 800 | 6,474 | 113.5 | 349 / 186,722 | 1 / 920 | 1 / 1,068 |
| 1000 | 6,556 | 150.4 | 349 / 186,722 | 3 / 1,843 | 1 / 1,068 |
| 1500 | 7,139 | 335 | 350 / 187,790 | 13 / 7,306 | 0 / 0 |
| **1700** | 7,202 | 428.4 | 350 / 187,790 | 14 / 7,564 | 0 / 0 |
| 2000 | 7,254 | 572.4 | 350 / 187,790 | 15 / 7,924 | 0 / 0 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 800 m.

![radios a d = 550 m]({{ '/assets/extension/rio_cuarto/calles_radios_d550.webp' | relative_url }})

![radios a d = 1700 m]({{ '/assets/extension/rio_cuarto/calles_radios_d1700.webp' | relative_url }})







