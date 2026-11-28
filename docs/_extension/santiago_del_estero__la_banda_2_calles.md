---
title: "2 · Calles"
parent: "Santiago del Estero - La Banda"
grand_parent: "Aglomerados"
nav_order: 2
---

# Santiago del Estero - La Banda · Calles


18,225 intersecciones en el cuadrado, 12,325 dentro del perimetro EPH. Perimetro EPH: 341 radios, 447,801 personas. Saltos mas grandes del tamano de la ciudad en d = 280, 130, 110 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 700 m.** A ese d, la percolacion agrega 5 radios (4,807 personas) fuera del perimetro y deja 4 radios del perimetro (5,942 personas) con menos del 50% de su area dentro.

Diagnostico: cubre el 100% a d = 1700 m (agrega 51 radios, 54,428 personas; deja 0 radios, 0 personas).

![curva]({{ '/assets/extension/santiago_del_estero__la_banda/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/santiago_del_estero__la_banda/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 7,064 | 52.4 | 209 / 262,761 | 0 / 0 | 132 / 185,040 |
| 200 | 7,818 | 66.7 | 235 / 297,860 | 0 / 0 | 106 / 149,941 |
| 500 | 13,090 | 197.5 | 336 / 440,257 | 2 / 1,737 | 5 / 7,544 |
| **700** | 13,395 | 252.9 | 337 / 441,859 | 5 / 4,807 | 4 / 5,942 |
| 800 | 13,641 | 297.3 | 337 / 441,859 | 9 / 8,446 | 4 / 5,942 |
| 1000 | 13,749 | 357.4 | 337 / 441,859 | 11 / 10,090 | 4 / 5,942 |
| 1500 | 15,613 | 929 | 339 / 444,872 | 33 / 36,601 | 2 / 2,929 |
| **1700** | 16,426 | 1249.5 | 341 / 447,801 | 51 / 54,428 | 0 / 0 |
| 2000 | 17,174 | 1679.4 | 341 / 447,801 | 65 / 66,094 | 0 / 0 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 500 m.

![radios a d = 700 m]({{ '/assets/extension/santiago_del_estero__la_banda/calles_radios_d700.webp' | relative_url }})

![radios a d = 1700 m]({{ '/assets/extension/santiago_del_estero__la_banda/calles_radios_d1700.webp' | relative_url }})







