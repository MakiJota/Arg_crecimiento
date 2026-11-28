---
title: "2 · Calles"
parent: "Salta"
grand_parent: "Aglomerados"
nav_order: 2
---

# Salta · Calles


26,304 intersecciones en el cuadrado, 19,955 dentro del perimetro EPH. Perimetro EPH: 725 radios, 705,323 personas. Saltos mas grandes del tamano de la ciudad en d = 140, 120, 650 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 800 m.** A ese d, la percolacion agrega 29 radios (22,014 personas) fuera del perimetro y deja 12 radios del perimetro (13,092 personas) con menos del 50% de su area dentro.

Diagnostico: cubre el 100% a d = 1700 m (agrega 39 radios, 28,811 personas; deja 3 radios, 1,986 personas).

![curva]({{ '/assets/extension/salta/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/salta/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 14,288 | 87 | 574 / 566,492 | 0 / 0 | 151 / 138,831 |
| 200 | 14,982 | 103 | 601 / 597,476 | 0 / 0 | 124 / 107,847 |
| 500 | 20,667 | 254.3 | 680 / 662,284 | 5 / 3,182 | 45 / 43,039 |
| **800** | 23,485 | 430.7 | 713 / 692,231 | 29 / 22,014 | 12 / 13,092 |
| 1000 | 23,755 | 516.2 | 713 / 692,231 | 31 / 23,502 | 12 / 13,092 |
| 1500 | 24,034 | 674.1 | 714 / 692,792 | 36 / 26,182 | 11 / 12,531 |
| **1700** | 24,467 | 787.2 | 722 / 703,337 | 39 / 28,811 | 3 / 1,986 |
| 2000 | 25,317 | 987.8 | 723 / 703,828 | 64 / 51,065 | 2 / 1,495 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 1700 m.

![radios a d = 800 m]({{ '/assets/extension/salta/calles_radios_d800.webp' | relative_url }})

![radios a d = 1700 m]({{ '/assets/extension/salta/calles_radios_d1700.webp' | relative_url }})







