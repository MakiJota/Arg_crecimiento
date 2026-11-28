# Percolación de calles: qué radios forman el aglomerado

Guía para usar `Rpipe/scripts/30_percolacion_calles.R`. Es exploratorio: nada de lo que sale de acá
es cifra del proyecto mientras no pase por `CIFRAS_CANONICAS.json` con su consulta.

**Los resultados de los 31 aglomerados ya están corridos**: [`pruebas/percolacion/HALLAZGOS.md`](pruebas/percolacion/HALLAZGOS.md),
con los mapas, la tabla por aglomerado y, en cada carpeta, la lista de radios (`radios.csv`). No hace
falta correr nada para leerlos.

## Para qué sirve

Para discutir con un criterio reproducible hasta dónde llega cada aglomerado y qué radios censales
2022 le corresponden, y compararlo con el perímetro de análisis (EPH) que usamos hoy. La salida
concreta es una lista de radios: los que coinciden con el perímetro EPH, los que la red de calles
agrega y los que el perímetro tiene pero la red no une al núcleo.

## La técnica

Arcaute, E., Molinero, C., Hatna, E., Murcio, R., Vargas-Ruiz, C., Masucci, A. P. y Batty, M. (2015).
*Constructing cities, deconstructing scaling laws*. Journal of the Royal Society Interface 12: 20140745.

1. **Intersecciones.** Los nodos de la red de calles de Overture Maps (OpenStreetMap más otras
   fuentes) donde se juntan tres o más tramos. Se usan las calles manejables: sin sendas, veredas,
   escaleras ni ciclovías. Las líneas se cortan en cada cruce, así que un puente cuenta como
   intersección.
2. **Percolación.** Dos intersecciones se unen si están a menos de *d* metros; cada grupo conectado
   es una "ciudad". El script barre *d* de 20 a 2000 m (cada 10 m hasta 500, cada 50 m después). En
   la práctica es un enlace simple sobre la distancia euclídea, calculado con el árbol de expansión
   mínima.
3. **La ciudad a cada d.** De todos los grupos, el que tiene más intersecciones dentro del perímetro
   EPH. Su área son las celdas de 20 m que están a menos de *d*/2 de alguna de sus intersecciones.
4. **Radios 2022.** Un radio es de la ciudad si al menos el 50 % de su área cae dentro (`--parte`).
   Con la misma regla se arma el conjunto de radios del perímetro EPH, y a cada *d* se cuentan radios
   y personas en tres clases: en los dos, solo percolación, solo EPH.

El tamaño de la ciudad no crece parejo con *d*: crece a saltos. Cada salto es un *d* donde cambia lo
que se está llamando ciudad (se suma un barrio, una localidad vecina). Las mesetas entre saltos son
los valores defendibles, y ese es el argumento del paper para justificar el *d* elegido.

## El criterio para elegir d

Criterio propuesto: **el menor d al que la ciudad cubre el 99 % del aglomerado EPH**, medido en las
intersecciones del perímetro. Se calcula sobre el barrido completo. A ese *d*, los radios "solo
percolación" son lo que la red de calles agrega al aglomerado oficial (los candidatos a discutir) y los
"solo EPH" lo que el perímetro tiene y la red no une al núcleo.

Como diagnóstico, **el menor d que cubre el 100 %**. Es frágil: si el perímetro tiene un fragmento
lejano o mucho campo vacío (La Rioja: 3.325 km²), solo se alcanza a un *d* muy alto, y para llegar la
percolación encadena localidades vecinas (Córdoba a 1.800 m suma 606 radios). En los 31 aglomerados el
99 % se alcanza en todos menos Formosa, casi siempre entre 400 y 800 m; el 100 % no se alcanza a 2.000 m
en 10 de las 32 ventanas. Cuando el 100 % queda muy por encima del 99 %, el perímetro EPH tiene partes
que conviene revisar a mano.

El script también informa el *d* que mejor reproduce el perímetro (el que deja menos personas en radios
que difieren), como referencia.

### Ejemplo: Salta

Salido de `outputs/percolacion/salta/radios_por_d.csv` y `curva.csv`:

- Transición principal entre 120 y 140 m: se arma el núcleo compacto. Meseta entre 150 y 220 m.
- Segundo salto cerca de 650 m: se suman Cerrillos y Rosario de Lerma.
- La ciudad cubre el 99 % de las intersecciones EPH a 800 m y el 100 % a 1700 m. El último 1 % es un
  fragmento del perímetro que queda lejos y recién se une a 1600-1700 m.

| d | en los dos | solo percolación | solo EPH |
|---:|---|---|---|
| 200 m | 601 radios · 597.476 personas | 0 | 124 radios · 107.847 personas |
| 800 m (cubre 99 %) | 713 · 692.231 | 29 · 22.014 | 12 · 13.092 |
| 1700 m (cubre 100 %) | 722 · 703.337 | 39 · 28.811 | 3 · 1.986 |
| 2000 m | 723 · 703.828 | 64 · 51.065 | 2 · 1.495 |

El perímetro EPH tiene 725 radios y 705.323 personas (radios con al menos el 50 % de su área dentro).

## Cómo correrlo

Hace falta R 4.5 con `sf`, `terra`, `igraph` y `ggplot2`, y Python con `duckdb` para bajar las
calles. Los pasos corren desde la raíz del repo.

Todo sale de archivos que ya están en el repo (los `base.js` de la plataforma) y de descargas
públicas. En R: `install.packages(c("sf", "terra", "igraph", "ggplot2", "magick"))`.

```bash
# 0. Los perímetros EPH en GeoPackage (de plataforma/datos/*/base.js; segundos)
Rscript Rpipe/scripts/07_limites_aglomerados.R

# 0b. Radios censales 1991-2022 con personas (descarga pública de Source Cooperative; unos minutos)
Rscript Rpipe/scripts/09_censos_radios.R

# 1. Las cajas: un cuadrado de 70 x 70 km centrado en cada aglomerado, más 10 km de margen.
#    Gran Buenos Aires tiene además una ventana de 100 km (--extra).
Rscript Rpipe/scripts/29_od_aglomerados.R --solo-cajas

# 2. Las calles de Overture para esas cajas (unos 10 s por aglomerado).
python Rpipe/scripts/20_overture_edificios.py \
  --cajas-csv Rpipe/outputs/od_aglomerados/cajas.csv \
  --salida Rpipe/outputs/overture_od --temas calles

# 3. La percolación. Sin --aglomerados corre los 31 y la ventana de 100 km de Buenos Aires.
Rscript Rpipe/scripts/30_percolacion_calles.R --aglomerados salta
```

Tarda alrededor de 2 minutos por aglomerado; Gran Buenos Aires y Córdoba tardan más.

Después, opcional:

```bash
# 4. Mapas finales: la ciudad a d cubre 99 % con las comunidades de localidades del paso 29 (Leiden
#    tau 15 y 30) y con el urbano de MapBiomas 2022. Necesita el paso 29 corrido completo.
Rscript Rpipe/scripts/31_mapa_final.R
Rscript Rpipe/scripts/30_percolacion_calles.R --solo-texto   # rehace HALLAZGOS.md con esos mapas

# 5. Publicar: copia HALLAZGOS.md, sus imágenes (en WebP) y los CSV a pruebas/percolacion/
Rscript Rpipe/scripts/32_publicar_hallazgos.R
```

Opciones de `30_percolacion_calles.R`:

| Opción | Por defecto | Qué hace |
|---|---|---|
| `--aglomerados` | todos | slugs del perímetro, separados por coma (`salta,gran_cordoba`) |
| `--d-mapa` | `150,200,500,800,1000,1500,2000` | los *d* con mapa y tabla de radios; los *d* de cobertura se agregan solos |
| `--d` | `200` | el *d* de la ciudad compacta, con su mapa de radios |
| `--parte` | `0.5` | qué parte del área de un radio tiene que caer dentro para contarlo |

## Qué sale

En `Rpipe/outputs/percolacion/<aglomerado>/`:

| Archivo | Contenido |
|---|---|
| `curva.csv`, `curva.png` | por *d*: intersecciones de la ciudad, componentes, cobertura del EPH; los saltos y los *d* de cobertura marcados |
| `ciudad_d.png` | la ciudad a cada *d* mapeado sobre el perímetro EPH |
| `radios_por_d.csv` | a cada *d*: radios y personas en los dos, solo percolación y solo EPH |
| `radios_d<d>.png` | mapa de radios por clase a los *d* de cobertura y a `--d` |
| `radios.csv` | cada radio: código, personas, área, share dentro del EPH y de la ciudad a cada *d* |
| `percolacion.gpkg` | para QGIS: capas `ciudad_<d>` (polígono) y `radios` (con `share_d<d>` y `clase_d<d>`) |

Y en `Rpipe/outputs/percolacion/`: `resumen.csv` (una fila por aglomerado, con `d_cubre99`,
`d_cubre100` y los radios que difieren a ese *d*), `mapbiomas_resumen.csv` (urbano de MapBiomas dentro
del perímetro y de la ciudad) y `HALLAZGOS.md` (método, tablas y una sección por aglomerado con sus
mapas). Se generan de los CSV; no hay números escritos a mano. La versión publicada, sin GeoPackages,
está en `Rpipe/pruebas/percolacion/`.

### Cómo sacar la lista de radios

En QGIS, capa `radios` de `percolacion.gpkg`, filtrar por la clase al *d* elegido. Por ejemplo, para
Salta a d cubre 99 % (800 m):

```
"clase_d800" IN ('en los dos', 'solo percolacion')
```

O desde R o Python con `radios.csv` (también en `pruebas/percolacion/<aglomerado>/`):
`share_d800 >= 0.5`. El código de radio está en `cod`. El *d* de cada aglomerado está en la columna
`d_cubre99` de `resumen.csv`.

## Limitaciones

- Donde el mapeo de calles de OpenStreetMap es pobre, la percolación subestima la ciudad.
- Los cruces a distinto nivel (puentes, autopistas) cuentan como intersecciones.
- El área de la ciudad es un buffer de *d*/2: a *d* grande los bordes se redondean y un radio rural
  grande puede pasar el corte del 50 % solo por el buffer.
- La regla del área penaliza los radios grandes del borde, que pueden tener un barrio en una esquina.
  Una alternativa más fiel al método es contar la parte de las intersecciones del radio que cae en la
  ciudad; no está implementada.
- El cuadrado de 70 km puede dejar afuera partes lejanas de aglomerados de varias partes (Ushuaia -
  Río Grande).
- Personas: censo 2022 por radio, del paso 09 (copia CEUR-CONICET de los datos del INDEC).
