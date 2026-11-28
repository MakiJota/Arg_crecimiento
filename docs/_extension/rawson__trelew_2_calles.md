---
title: "2 · Calles"
parent: "Rawson - Trelew"
grand_parent: "Aglomerados"
nav_order: 2
---

# Rawson - Trelew · Calles


11,515 intersecciones en el cuadrado, 7,278 dentro del perimetro EPH. Perimetro EPH: 227 radios, 147,163 personas. Saltos mas grandes del tamano de la ciudad en d = 650, 100, 600 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 950 m.** A ese d, la percolacion agrega 19 radios (8,886 personas) fuera del perimetro y deja 0 radios del perimetro (0 personas) con menos del 50% de su area dentro.

Diagnostico: cubre el 100% a d = 1200 m (agrega 19 radios, 8,886 personas; deja 0 radios, 0 personas).

![curva]({{ '/assets/extension/rawson__trelew/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/rawson__trelew/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 4,056 | 24 | 146 / 97,304 | 0 / 0 | 81 / 49,859 |
| 200 | 4,227 | 28.3 | 150 / 100,417 | 0 / 0 | 77 / 46,746 |
| 500 | 5,483 | 92.3 | 155 / 104,547 | 1 / 378 | 72 / 42,616 |
| 800 | 9,876 | 346.5 | 226 / 147,144 | 11 / 4,077 | 1 / 19 |
| **950** | 10,575 | 458.6 | 227 / 147,163 | 19 / 8,886 | 0 / 0 |
| 1000 | 10,613 | 485.2 | 227 / 147,163 | 19 / 8,886 | 0 / 0 |
| **1200** | 10,692 | 552.5 | 227 / 147,163 | 19 / 8,886 | 0 / 0 |
| 1500 | 10,963 | 669.9 | 227 / 147,163 | 19 / 8,886 | 0 / 0 |
| 2000 | 11,050 | 847.2 | 227 / 147,163 | 19 / 8,886 | 0 / 0 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 800 m.

![radios a d = 950 m]({{ '/assets/extension/rawson__trelew/calles_radios_d950.webp' | relative_url }})

![radios a d = 1200 m]({{ '/assets/extension/rawson__trelew/calles_radios_d1200.webp' | relative_url }})







