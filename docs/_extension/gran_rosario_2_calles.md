---
title: "2 · Calles"
parent: "Gran Rosario"
grand_parent: "Aglomerados"
nav_order: 2
---

# Gran Rosario · Calles


46,499 intersecciones en el cuadrado, 32,845 dentro del perimetro EPH. Perimetro EPH: 2,070 radios, 1,447,588 personas. Saltos mas grandes del tamano de la ciudad en d = 160, 130, 120 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 550 m.** A ese d, la percolacion agrega 32 radios (12,677 personas) fuera del perimetro y deja 9 radios del perimetro (3,328 personas) con menos del 50% de su area dentro.

Diagnostico: cubre el 100% a d = 1300 m (agrega 119 radios, 63,157 personas; deja 1 radios, 34 personas).

![curva]({{ '/assets/extension/gran_rosario/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/gran_rosario/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 18,099 | 129 | 1,579 / 1,075,511 | 0 / 0 | 491 / 372,077 |
| 200 | 30,797 | 265.2 | 1,908 / 1,332,549 | 1 / 431 | 162 / 115,039 |
| 500 | 39,260 | 533.4 | 2,059 / 1,442,817 | 30 / 11,930 | 11 / 4,771 |
| **550** | 39,503 | 568.2 | 2,061 / 1,444,260 | 32 / 12,677 | 9 / 3,328 |
| 800 | 40,661 | 742.7 | 2,066 / 1,446,568 | 42 / 18,195 | 4 / 1,020 |
| 1000 | 41,788 | 932.8 | 2,067 / 1,447,331 | 62 / 29,476 | 3 / 257 |
| **1300** | 44,929 | 1585.7 | 2,069 / 1,447,554 | 119 / 63,157 | 1 / 34 |
| 1500 | 45,194 | 1924.4 | 2,069 / 1,447,554 | 127 / 64,304 | 1 / 34 |
| 2000 | 46,400 | 2921.1 | 2,070 / 1,447,588 | 163 / 77,449 | 0 / 0 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 550 m.

![radios a d = 550 m]({{ '/assets/extension/gran_rosario/calles_radios_d550.webp' | relative_url }})

![radios a d = 1300 m]({{ '/assets/extension/gran_rosario/calles_radios_d1300.webp' | relative_url }})







