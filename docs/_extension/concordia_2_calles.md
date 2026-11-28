---
title: "2 · Calles"
parent: "Concordia"
grand_parent: "Aglomerados"
nav_order: 2
---

# Concordia · Calles


11,842 intersecciones en el cuadrado, 4,829 dentro del perimetro EPH. Perimetro EPH: 215 radios, 174,660 personas. Saltos mas grandes del tamano de la ciudad en d = 600, 100, 110 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 1250 m.** A ese d, la percolacion agrega 21 radios (12,188 personas) fuera del perimetro y deja 0 radios del perimetro (0 personas) con menos del 50% de su area dentro.

Diagnostico: cubre el 100% a d = 1250 m (agrega 21 radios, 12,188 personas; deja 0 radios, 0 personas).

![curva]({{ '/assets/extension/concordia/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/concordia/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 4,093 | 28.2 | 184 / 151,399 | 0 / 0 | 31 / 23,261 |
| 200 | 4,269 | 32.2 | 190 / 156,529 | 0 / 0 | 25 / 18,131 |
| 500 | 4,781 | 55.8 | 198 / 162,578 | 1 / 9 | 17 / 12,082 |
| 800 | 7,747 | 154.8 | 202 / 165,635 | 2 / 638 | 13 / 9,025 |
| 1000 | 8,324 | 270.8 | 203 / 166,151 | 6 / 2,254 | 12 / 8,509 |
| **1250** | 9,690 | 532.3 | 215 / 174,660 | 21 / 12,188 | 0 / 0 |
| 1500 | 10,442 | 814.3 | 215 / 174,660 | 34 / 16,487 | 0 / 0 |
| 2000 | 10,568 | 1135.7 | 215 / 174,660 | 37 / 17,090 | 0 / 0 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 800 m.

![radios a d = 1250 m]({{ '/assets/extension/concordia/calles_radios_d1250.webp' | relative_url }})







