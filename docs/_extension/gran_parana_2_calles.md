---
title: "2 · Calles"
parent: "Gran Paraná"
grand_parent: "Aglomerados"
nav_order: 2
---

# Gran Paraná · Calles


30,349 intersecciones en el cuadrado, 7,670 dentro del perimetro EPH. Perimetro EPH: 509 radios, 301,776 personas. Saltos mas grandes del tamano de la ciudad en d = 1100, 1350, 130 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 550 m.** A ese d, la percolacion agrega 5 radios (1,133 personas) fuera del perimetro y deja 8 radios del perimetro (1,182 personas) con menos del 50% de su area dentro.

Diagnostico: cubre el 100% a d = 1200 m (agrega 105 radios, 39,636 personas; deja 0 radios, 0 personas).

![curva]({{ '/assets/extension/gran_parana/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/gran_parana/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 5,001 | 41.5 | 373 / 234,875 | 0 / 0 | 136 / 66,901 |
| 200 | 5,627 | 56.5 | 414 / 255,613 | 0 / 0 | 95 / 46,163 |
| 500 | 7,603 | 113.8 | 487 / 293,267 | 3 / 678 | 22 / 8,509 |
| **550** | 8,080 | 131.7 | 501 / 300,594 | 5 / 1,133 | 8 / 1,182 |
| 800 | 8,178 | 163.3 | 504 / 300,946 | 6 / 1,286 | 5 / 830 |
| 1000 | 8,261 | 198.9 | 507 / 301,724 | 7 / 1,432 | 2 / 52 |
| **1200** | 11,787 | 675.7 | 509 / 301,776 | 105 / 39,636 | 0 / 0 |
| 1500 | 14,037 | 1188.6 | 509 / 301,776 | 176 / 68,528 | 0 / 0 |
| 2000 | 14,741 | 1765.9 | 509 / 301,776 | 213 / 75,921 | 0 / 0 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 1000 m.

![radios a d = 550 m]({{ '/assets/extension/gran_parana/calles_radios_d550.webp' | relative_url }})

![radios a d = 1200 m]({{ '/assets/extension/gran_parana/calles_radios_d1200.webp' | relative_url }})







