---
title: "2 · Calles"
parent: "Gran Catamarca"
grand_parent: "Aglomerados"
nav_order: 2
---

# Gran Catamarca · Calles


10,991 intersecciones en el cuadrado, 8,442 dentro del perimetro EPH. Perimetro EPH: 246 radios, 229,102 personas. Saltos mas grandes del tamano de la ciudad en d = 120, 140, 190 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 650 m.** A ese d, la percolacion agrega 1 radios (671 personas) fuera del perimetro y deja 2 radios del perimetro (367 personas) con menos del 50% de su area dentro.

Diagnostico: cubre el 100% a d = 1350 m (agrega 9 radios, 6,157 personas; deja 1 radios, 163 personas).

![curva]({{ '/assets/extension/gran_catamarca/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/gran_catamarca/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 6,331 | 42.4 | 190 / 174,276 | 0 / 0 | 56 / 54,826 |
| 200 | 7,506 | 58.3 | 214 / 199,984 | 0 / 0 | 32 / 29,118 |
| 500 | 8,449 | 99.4 | 234 / 219,967 | 1 / 671 | 12 / 9,135 |
| **650** | 8,802 | 124.6 | 244 / 228,735 | 1 / 671 | 2 / 367 |
| 800 | 8,821 | 136.9 | 244 / 228,735 | 1 / 671 | 2 / 367 |
| 1000 | 9,179 | 192.4 | 245 / 228,939 | 5 / 4,647 | 1 / 163 |
| **1350** | 9,358 | 310.5 | 245 / 228,939 | 9 / 6,157 | 1 / 163 |
| 1500 | 9,480 | 348.5 | 245 / 228,939 | 14 / 8,783 | 1 / 163 |
| 2000 | 9,494 | 431.7 | 245 / 228,939 | 18 / 10,030 | 1 / 163 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 650 m.

![radios a d = 650 m]({{ '/assets/extension/gran_catamarca/calles_radios_d650.webp' | relative_url }})

![radios a d = 1350 m]({{ '/assets/extension/gran_catamarca/calles_radios_d1350.webp' | relative_url }})







