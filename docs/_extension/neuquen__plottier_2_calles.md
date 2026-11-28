---
title: "2 · Calles"
parent: "Neuquén - Plottier"
grand_parent: "Aglomerados"
nav_order: 2
---

# Neuquén - Plottier · Calles


32,519 intersecciones en el cuadrado, 21,248 dentro del perimetro EPH. Perimetro EPH: 677 radios, 500,612 personas. Saltos mas grandes del tamano de la ciudad en d = 460, 120, 420 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 500 m.** A ese d, la percolacion agrega 16 radios (8,297 personas) fuera del perimetro y deja 6 radios del perimetro (5,210 personas) con menos del 50% de su area dentro.

Diagnostico: cubre el 100% a d = 900 m (agrega 100 radios, 68,937 personas; deja 0 radios, 0 personas).

![curva]({{ '/assets/extension/neuquen__plottier/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/neuquen__plottier/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 8,887 | 48.1 | 344 / 254,981 | 0 / 0 | 333 / 245,631 |
| 200 | 10,176 | 61.6 | 363 / 269,638 | 0 / 0 | 314 / 230,974 |
| **500** | 25,067 | 333.2 | 671 / 495,402 | 16 / 8,297 | 6 / 5,210 |
| 800 | 28,758 | 576.9 | 677 / 500,612 | 96 / 66,670 | 0 / 0 |
| **900** | 28,927 | 641.1 | 677 / 500,612 | 100 / 68,937 | 0 / 0 |
| 1000 | 28,967 | 682.1 | 677 / 500,612 | 101 / 69,300 | 0 / 0 |
| 1500 | 31,939 | 1227.6 | 677 / 500,612 | 148 / 99,972 | 0 / 0 |
| 2000 | 31,960 | 1406.5 | 677 / 500,612 | 149 / 100,833 | 0 / 0 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 500 m.

![radios a d = 500 m]({{ '/assets/extension/neuquen__plottier/calles_radios_d500.webp' | relative_url }})

![radios a d = 900 m]({{ '/assets/extension/neuquen__plottier/calles_radios_d900.webp' | relative_url }})







