---
title: "2 · Calles"
parent: "Comodoro Rivadavia - Rada Tilly"
grand_parent: "Aglomerados"
nav_order: 2
---

# Comodoro Rivadavia - Rada Tilly · Calles


22,407 intersecciones en el cuadrado, 11,435 dentro del perimetro EPH. Perimetro EPH: 317 radios, 210,983 personas. Saltos mas grandes del tamano de la ciudad en d = 290, 850, 900 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 430 m.** A ese d, la percolacion agrega 0 radios (0 personas) fuera del perimetro y deja 1 radios del perimetro (162 personas) con menos del 50% de su area dentro.

Diagnostico: cubre el 100% a d = 600 m (agrega 3 radios, 916 personas; deja 1 radios, 162 personas).

![curva]({{ '/assets/extension/comodoro_rivadavia__rada_tilly/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/comodoro_rivadavia__rada_tilly/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 4,171 | 23.3 | 178 / 115,063 | 0 / 0 | 139 / 95,920 |
| 200 | 5,139 | 34.6 | 192 / 123,596 | 0 / 0 | 125 / 87,387 |
| **430** | 13,576 | 183.2 | 316 / 210,821 | 0 / 0 | 1 / 162 |
| 500 | 14,152 | 227.8 | 316 / 210,821 | 2 / 622 | 1 / 162 |
| **600** | 14,230 | 255.1 | 316 / 210,821 | 3 / 916 | 1 / 162 |
| 800 | 14,926 | 340.4 | 317 / 210,983 | 4 / 1,193 | 0 / 0 |
| 1000 | 21,731 | 1104.2 | 317 / 210,983 | 7 / 2,607 | 0 / 0 |
| 1500 | 22,036 | 1477.5 | 317 / 210,983 | 8 / 3,741 | 0 / 0 |
| 2000 | 22,200 | 1808.8 | 317 / 210,983 | 10 / 3,778 | 0 / 0 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 430 m.

![radios a d = 430 m]({{ '/assets/extension/comodoro_rivadavia__rada_tilly/calles_radios_d430.webp' | relative_url }})

![radios a d = 600 m]({{ '/assets/extension/comodoro_rivadavia__rada_tilly/calles_radios_d600.webp' | relative_url }})







