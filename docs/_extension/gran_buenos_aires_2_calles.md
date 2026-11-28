---
title: "2 · Calles"
parent: "Gran Buenos Aires"
grand_parent: "Aglomerados"
nav_order: 2
---

# Gran Buenos Aires · Calles


240,087 intersecciones en el cuadrado, 237,402 dentro del perimetro EPH. Perimetro EPH: 15,515 radios, 14,562,254 personas. Saltos mas grandes del tamano de la ciudad en d = 130, 140, 120 m.

**La ciudad cubre el 99% del aglomerado EPH a d = 430 m.** A ese d, la percolacion agrega 3 radios (805 personas) fuera del perimetro y deja 187 radios del perimetro (100,640 personas) con menos del 50% de su area dentro.

Diagnostico: no cubre el 100% a 2000 m.

![curva]({{ '/assets/extension/gran_buenos_aires/calles_curva.webp' | relative_url }})

![ciudad segun d]({{ '/assets/extension/gran_buenos_aires/calles_ciudad_d.webp' | relative_url }})

| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |
|---:|---:|---:|---:|---:|---:|
| 150 | 201,926 | 1597.5 | 14,329 / 13,536,021 | 0 / 0 | 1,186 / 1,026,233 |
| 200 | 224,156 | 1992.4 | 15,018 / 14,199,985 | 1 / 308 | 497 / 362,269 |
| **430** | 236,541 | 2572.1 | 15,328 / 14,461,614 | 3 / 805 | 187 / 100,640 |
| 500 | 237,221 | 2681.5 | 15,356 / 14,481,066 | 3 / 805 | 159 / 81,188 |
| 800 | 238,544 | 3037.8 | 15,426 / 14,522,389 | 6 / 1,777 | 89 / 39,865 |
| 1000 | 238,785 | 3204.1 | 15,438 / 14,533,322 | 8 / 1,938 | 77 / 28,932 |
| 1500 | 240,022 | 3567.9 | 15,463 / 14,547,164 | 32 / 7,389 | 52 / 15,090 |
| 2000 | 240,056 | 3766.9 | 15,468 / 14,548,989 | 41 / 7,933 | 47 / 13,265 |

En negrita, los d que cubren el 99% y el 100% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = 2000 m.

![radios a d = 430 m]({{ '/assets/extension/gran_buenos_aires/calles_radios_d430.webp' | relative_url }})







