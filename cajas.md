# Cajas de las ciudades

Recuadros para recortar Landsat y GISD30 y explorar resultados por ciudad. Los usan `02_landsat_bbox.R`, `04_angel_atlas.R` y
`05_per_muni.R`. Los scripts leen ESTA tabla: para agregar una ciudad se agrega una fila.

- **slug**: nombre de la carpeta en `outputs/<fuente>/<slug>/`.
- **contorno**: carpeta de `plataforma/datos/` con el perimetro de analisis del aglomerado
  (EPH + la ciudad continua de 2022 que lo desborda, simplificado a ~200 m; ver
  `07_limites_aglomerados.R` y `raw/boundaries/aglomerados.gpkg`). Define
  que manchas de la extension urbana son "la ciudad" (las que tocan el contorno). Vacio:
  la ciudad es la mancha mas grande.
- **caja**: `lat0,lon0,lat1,lon1`, esquina suroeste y noreste, grados WGS84.
- **origen**: las cajas propias se conservan tal cual. Las demas son el recuadro del
  perimetro mas 10 km de cada lado: mejor una caja grande que cortar la ciudad, y el
  circulo de 1 km2 de Angel necesita margen alrededor. Si el contorno tiene varias partes
  (dos ciudades, como Ushuaia y Rio Grande) la caja las cubre a todas.

Tandil no es un aglomerado EPH: no tiene contorno ni radios en el proyecto.

| slug | contorno | lat0 | lon0 | lat1 | lon1 | origen | partes |
|---|---|---|---|---|---|---|---|
| bahia_blanca | bahia_blanca__cerri | -38.9112 | -62.5414 | -38.4945 | -61.9973 | perimetro + 10 km | 2 |
| buenos_aires | gran_buenos_aires | -35.2099 | -59.3021 | -33.9121 | -57.9078 | perimetro + 10 km | 44 |
| catamarca | gran_catamarca | -28.6462 | -65.9777 | -28.1717 | -65.5800 | perimetro + 10 km | 1 |
| comodoro_rivadavia | comodoro_rivadavia__rada_tilly | -46.0351 | -67.7503 | -45.6501 | -67.2392 | perimetro + 10 km | 5 |
| concordia | concordia | -31.5436 | -58.2118 | -31.2278 | -57.8785 | perimetro + 10 km | 2 |
| cordoba | gran_cordoba | -31.6148 | -64.5521 | -30.9060 | -63.9379 | perimetro + 10 km | 7 |
| corrientes | corrientes | -27.6795 | -58.9579 | -27.3149 | -58.5620 | perimetro + 10 km | 2 |
| formosa | formosa | -26.3669 | -58.4264 | -25.8947 | -57.7511 | perimetro + 10 km | 1 |
| jujuy | jujuy__palpala | -24.3761 | -65.6728 | -23.9513 | -65.0589 | perimetro + 10 km | 1 |
| la_plata | gran_la_plata | -35.2279 | -58.2926 | -34.6903 | -57.5996 | perimetro + 10 km | 1 |
| la_rioja | la_rioja | -30.2756 | -67.0769 | -29.0091 | -66.3087 | perimetro + 10 km | 1 |
| mar_del_plata | mar_del_plata__batan | -38.2168 | -57.8503 | -37.7220 | -57.3718 | perimetro + 10 km | 5 |
| mendoza | gran_mendoza | -33.1561 | -69.1150 | -32.5664 | -68.4452 | perimetro + 10 km | 4 |
| neuquen | neuquen__plottier | -39.0933 | -68.5090 | -38.6784 | -67.7799 | perimetro + 10 km | 13 |
| parana | gran_parana | -31.9350 | -60.6831 | -31.6121 | -60.2402 | perimetro + 10 km | 3 |
| posadas | posadas | -27.7127 | -56.1522 | -27.2622 | -55.7104 | perimetro + 10 km | 2 |
| rawson | rawson__trelew | -43.4323 | -65.6404 | -43.1122 | -64.9049 | perimetro + 10 km | 3 |
| resistencia | gran_resistencia | -27.6287 | -59.2011 | -27.2754 | -58.7977 | perimetro + 10 km | 2 |
| rio_cuarto | rio_cuarto | -33.2637 | -64.5219 | -32.9111 | -64.1437 | perimetro + 10 km | 2 |
| rio_gallegos | rio_gallegos | -51.7569 | -69.4703 | -51.5107 | -69.0334 | perimetro + 10 km | 1 |
| rosario | gran_rosario | -33.2569 | -61.0940 | -32.5346 | -60.3880 | perimetro + 10 km | 12 |
| salta | salta | -25.1367 | -65.9613 | -24.5643 | -65.0146 | caja propia (Jonathan) |  |
| san_juan | gran_san_juan | -31.8155 | -68.8095 | -31.2767 | -68.2436 | perimetro + 10 km | 4 |
| san_luis | san_luis__el_chorrillo | -33.4324 | -66.5129 | -33.0571 | -66.0967 | perimetro + 10 km | 3 |
| san_nicolas | san_nicolas__villa_constitucion | -33.5333 | -60.4822 | -33.0865 | -60.0588 | perimetro + 10 km | 1 |
| santa_fe | gran_santa_fe | -31.9109 | -61.0837 | -31.3921 | -60.2007 | perimetro + 10 km | 3 |
| santa_rosa | santa_rosa__toay | -36.8053 | -64.5083 | -36.4442 | -64.0560 | perimetro + 10 km | 1 |
| santiago_del_estero | santiago_del_estero__la_banda | -28.0079 | -64.4628 | -27.5572 | -64.0800 | perimetro + 10 km | 2 |
| tandil |  | -37.4760 | -59.3611 | -37.2073 | -58.9167 | caja propia (Jonathan) |  |
| tucuman | gran_tucuman__tafi_viejo | -27.2052 | -65.8582 | -26.5490 | -64.7727 | caja propia (Jonathan) |  |
| ushuaia | ushuaia__rio_grande | -54.9409 | -68.5534 | -53.6286 | -67.4932 | perimetro + 10 km | 3 |
| viedma | viedma__carmen_de_patagones | -40.9386 | -63.1547 | -40.6795 | -62.8298 | perimetro + 10 km | 2 |
