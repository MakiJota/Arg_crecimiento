# -*- coding: utf-8 -*-
# Paso 04b · Lo mismo que 04_angel_atlas.R, sin Landsat.
# 04 usa el compuesto Landsat de 02 solo como plantilla de la grilla: ninguna banda entra
# en las clases. Esa plantilla es la caja de cajas.md en grados, a la resolucion de GISD30.
# 04b recorta GISD30 directamente con la caja de cajas.md, asi que no hace falta correr 02
# (que es lo que mas tarda). El resto -clases, metricas, salidas, resumen.csv- es identico
# a 04; si cambia algo de las definiciones, cambiarlo en los dos.
#
# Clases y metricas de Angel (Atlas of Urban Expansion 2016) sobre GISD30, por ciudad.
# Script nuevo, no traduce a ninguno de scripts/. No toca la clasificacion publicada
# (scripts/angel30_clasificador.py): la reproduce al lado, como "huella del proyecto",
# para ver cuanto cambia con las definiciones del Atlas.
#
# NO HAY CODIGO OFICIAL. Angel, Parent y Civco distribuyeron sus herramientas (ULAT,
# UConn CLEAR; la del Atlas, Lincoln Institute / NYU Marron) como cajas de ArcGIS, sin
# repositorio publico. Esto se escribe desde las definiciones publicadas:
#   Angel, Blei, Parent, Lamson-Hall y Galarza (2016), Atlas of Urban Expansion, vol. 1,
#   Lincoln Institute, cap. "Areas and densities" y "Fragmentation"; y Angel, Parent,
#   Civco y Blei (2010), "The persistent decline in urban densities".
#
# DEFINICIONES (circulo de 1 km2 = radio 564,19 m alrededor de cada pixel):
#   construido urbano      fraccion construida del circulo >  0,50
#   construido suburbano   entre U_RURAL y 0,50
#   construido rural       <  U_RURAL   (Atlas: 0,25; el proyecto publica 0,10)
#   abierto de franja      pixel no construido a <= 100 m de urbano o suburbano
#   abierto capturado      manchas que no son urbano, suburbano ni franja, totalmente
#                          rodeadas por ellos (no tocan el borde del recuadro) y de
#                          menos de 200 ha. Conectividad 4 para las manchas.
#   abierto rural          el resto
#   extension urbana       urbano + suburbano + franja + capturado
# La extension se reporta de dos maneras: todo el recuadro, y LA CIUDAD: las manchas
# (componentes conexas, conectividad 8) de la extension que tocan el contorno del
# aglomerado EPH (columna contorno de Rpipe/cajas.md). Asi un aglomerado de dos ciudades
# (Ushuaia y Rio Grande, Viedma y Patagones) cuenta las dos, y un pueblo suelto de la
# caja no entra. Sin contorno (Tandil): la mancha mas grande.
# MANCHA COMPARTIDA. Si una mancha toca el perimetro de la ciudad y tambien el de otro
# aglomerado de la caja (Gran Buenos Aires y Gran La Plata desde 2010), sus pixeles se
# reparten por cercania: cada uno va al perimetro mas cercano. Las manchas que no se
# comparten no cambian.
#
# METRICAS (sobre la ciudad):
#   saturacion        construido dentro de la extension / extension
#   huella_ratio      extension / construido urbano+suburbano (Atlas: city footprint ratio)
#   apertura          promedio, sobre los pixeles construidos urbanos y suburbanos de
#                     la extension, de la fraccion NO construida de su circulo (openness)
#   proximidad        distancia media al centro de un circulo de igual area (2R/3)
#                     / distancia media de los pixeles de la extension a su centroide.
#                     1 = circulo. OJO: el Atlas mide al centro de negocios (CBD); aca
#                     al centroide, que no requiere elegir un centro a mano.
# Densidad no: necesita el censo, que no esta en Rpipe.
#
# HUELLA DEL PROYECTO (para comparar): la de angel30_clasificador.py, definicion de
# 2007, u_rural 0,10: construido con fraccion >= 0,10, mas no construido con fraccion
# > 0,50, mas no construido a <= 100 m de ese construido.
#
# EPOCAS. Lee la capa por decada del paso 01 (gisd30_decadas.vrt), no el crudo:
#   1 hasta 1990, 2 1990-2000, 3 2000-2010, 4 2010-2020, y construido hasta la
#   decada k es d >= 1 & d <= k. No hay corte anterior a 1990: el valor crudo 1 es
#   "antes de 1985" sin mas detalle.
#
# GRILLA. Se reproyecta el recorte de GISD30 a UTM (zona de la ciudad, 30 m, vecino
# mas cercano) para que el circulo y los 100 m sean metricos. El recuadro es la caja de
# la ciudad en Rpipe/cajas.md (en 04, el compuesto Landsat, que tiene esa misma caja).
#
# SALIDA en Rpipe/outputs/angel/
#   <slug>/angel_<anio>.tif   clases: 0 abierto rural, 1 urbano, 2 suburbano, 3 rural
#                             construido, 4 franja, 5 capturado; con tabla de colores
#   <slug>/huella_proyecto_<anio>.tif   1 dentro, 0 fuera
#   mapa_<slug>.png           las epocas, con el contorno EPH en negro
#   resumen.csv               km2 por clase (recuadro y ciudad) y metricas. Se agrega:
#                             correr una ciudad reemplaza solo sus filas. Exploratorio:
#                             NO es una cifra del proyecto.
#
# Uso: Rscript Rpipe/scripts/04b_angel_sin_landsat.R [--ciudades salta,tandil,tucuman]
#        [--anios 1990,2000,2010,2020] [--u-rural 0.25]
# Requiere 01_gisd30_decadas.R. No requiere 02.

Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))

suppressPackageStartupMessages(library(terra))

script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
source(file.path(dirname(script), "lib", "cajas.R"))

args <- commandArgs(trailingOnly = TRUE)
arg <- function(nombre, defecto) {
  i <- match(nombre, args)
  if (is.na(i) || i == length(args)) defecto else args[i + 1]
}
CIUDADES <- strsplit(arg("--ciudades", "salta,tandil,tucuman"), ",")[[1]]
ANIOS <- as.integer(strsplit(arg("--anios", "1990,2000,2010,2020"), ",")[[1]])
U_RURAL <- as.numeric(arg("--u-rural", "0.25"))

U_URBANO <- 0.50
U_PROYECTO <- 0.10
R_CIRC <- sqrt(1e6 / pi)   # 564,19 m
FRANJA <- 100
CAPT_HA <- 200
RES <- 30
# anio -> ultima decada (capa del paso 01) que cuenta como construido
DECADA <- c("1990" = 1, "2000" = 2, "2010" = 3, "2020" = 4)

script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
RPIPE <- normalizePath(file.path(dirname(script), ".."), winslash = "/")
GISD <- file.path(RPIPE, "outputs", "gisd30", "gisd30_decadas.vrt")
LANDSAT <- file.path(RPIPE, "outputs", "landsat")
SAL <- file.path(RPIPE, "outputs", "angel")

CLASES <- c("abierto rural", "urbano", "suburbano", "rural construido", "franja",
            "capturado")
COLORES <- c("#f2efe6", "#b2182b", "#ef8a62", "#7f7f7f", "#fddbc7", "#67a9cf")


circulo <- function(radio_m) {
  # matriz de pesos 0/1 del circulo, en pixeles de RES metros
  r <- floor(radio_m / RES)
  d <- outer(-r:r, -r:r, function(i, j) sqrt(i^2 + j^2) * RES)
  (d <= radio_m) * 1
}
W_CIRC <- circulo(R_CIRC)
W_FRANJA <- circulo(FRANJA)


fraccion <- function(m) {
  # fraccion de la vecindad de 1 km2 que es 1; lo de afuera del recuadro cuenta 0
  focal(m, W_CIRC, fun = "sum", na.rm = TRUE, fillvalue = 0) / sum(W_CIRC)
}


cerca <- function(m) {
  # 1 si hay algun pixel de m a <= 100 m
  focal(m, W_FRANJA, fun = "max", na.rm = TRUE, fillvalue = 0)
}


utm <- function(lon, lat) {
  sprintf("EPSG:%d", (if (lat < 0) 32700 else 32600) + floor((lon + 180) / 6) + 1)
}


angel <- function(v, ep) {
  B <- v >= 1 & v <= ep
  f <- fraccion(B)
  urb <- B & f > U_URBANO
  sub <- B & f >= U_RURAL & f <= U_URBANO
  rur <- B & f < U_RURAL
  us <- urb | sub
  fra <- !B & cerca(us)
  # capturado: manchas de lo que no es urbano, suburbano ni franja
  resto <- ifel(!(us | fra), 1, NA)
  p <- patches(resto, directions = 4)
  ha <- freq(p)
  ha$ha <- ha$count * RES^2 / 1e4
  borde <- unique(c(p[1, ], p[nrow(p), ], p[, 1], p[, ncol(p)]))
  borde <- unique(unlist(borde))
  ok <- ha$value[ha$ha < CAPT_HA & !(ha$value %in% borde)]
  cap <- ifel(is.na(p), 0, p %in% ok)
  cls <- ifel(urb, 1, ifel(sub, 2, ifel(cap, 5, ifel(rur, 3, ifel(fra, 4, 0)))))
  # huella del proyecto, definicion 2007 (angel30_clasificador.py, u_rural 0,10)
  us10 <- B & f >= U_PROYECTO
  huella_p <- us10 | (!B & f > U_URBANO) | (!B & cerca(us10))
  list(cls = cls, f = f, B = B, huella_p = huella_p)
}


# AJENO: los pixeles mas cerca del perimetro de otro aglomerado de la caja que del
# propio (lo arma ciudad(); NULL si no hay otro). Solo se usa en manchas compartidas.
AJENO <- NULL
OTROS <- NULL

la_ciudad <- function(m, cont) {
  # las componentes conexas (8) de m que tocan el contorno; sin contorno, la mas grande
  p <- patches(ifel(m, 1, NA), directions = 8)
  if (is.null(cont)) {
    fr <- freq(p)
    ids <- fr$value[which.max(fr$count)]
  } else {
    ids <- unique(na.omit(extract(p, cont, touches = TRUE)[, 2]))
  }
  dentro <- ifel(is.na(p), 0, p %in% ids)
  if (!is.null(AJENO)) {
    # manchas que tocan tambien otro perimetro: se queda solo lo mas cercano al propio
    suyos <- unique(na.omit(extract(p, OTROS, touches = TRUE)[, 2]))
    comun <- intersect(ids, suyos)
    if (length(comun)) dentro <- dentro & !(ifel(is.na(p), 0, p %in% comun) & AJENO)
  }
  dentro
}


metricas <- function(slug, anio, a, cont) {
  km2 <- function(x) global(x, "sum", na.rm = TRUE)[[1]] * RES^2 / 1e6
  cls <- a$cls
  ext_todo <- cls %in% c(1, 2, 4, 5)
  pr <- la_ciudad(ext_todo, cont)
  us <- cls %in% c(1, 2)
  ext_km2 <- km2(pr)
  us_km2 <- km2(us & pr)
  b_km2 <- km2(a$B & pr)
  # apertura: fraccion abierta del circulo, promediada sobre urbano+suburbano de la mancha
  ap <- global(ifel(us & pr, 1 - a$f, NA), "mean", na.rm = TRUE)[[1]]
  # proximidad al centroide
  xy <- xyFromCell(pr, cells(ifel(pr, 1, NA)))
  d <- sqrt((xy[, 1] - mean(xy[, 1]))^2 + (xy[, 2] - mean(xy[, 2]))^2)
  r_eq <- sqrt(ext_km2 * 1e6 / pi)
  hp <- a$huella_p
  data.frame(
    ciudad = slug, anio = anio, u_rural = U_RURAL,
    urbano_km2 = km2(cls == 1), suburbano_km2 = km2(cls == 2),
    rural_construido_km2 = km2(cls == 3), franja_km2 = km2(cls == 4),
    capturado_km2 = km2(cls == 5),
    extension_recuadro_km2 = km2(ext_todo),
    urbano_ciudad_km2 = km2(cls == 1 & pr), suburbano_ciudad_km2 = km2(cls == 2 & pr),
    capturado_ciudad_km2 = km2(cls == 5 & pr), franja_ciudad_km2 = km2(cls == 4 & pr),
    extension_ciudad_km2 = ext_km2,
    construido_ciudad_km2 = b_km2,
    saturacion = b_km2 / ext_km2,
    huella_ratio = ext_km2 / us_km2,
    apertura = ap,
    proximidad = (2 * r_eq / 3) / mean(d),
    huella_proyecto_recuadro_km2 = km2(hp),
    huella_proyecto_ciudad_km2 = km2(la_ciudad(hp, cont)))
}


mapa <- function(slug, capas, cont) {
  # zoom a la ciudad del ultimo anio, con 3 km de margen
  ult <- capas[[length(capas)]]
  pr <- la_ciudad(ult %in% c(1, 2, 4, 5), cont)
  zoom <- ext(trim(ifel(pr == 1, 1, NA))) + 3000
  capas <- lapply(capas, crop, zoom)
  # hasta dos epocas en una fila; mas, en dos filas
  filas <- if (length(capas) <= 2) 1 else 2
  cols <- ceiling(length(capas) / filas)
  png(file.path(SAL, sprintf("mapa_%s.png", slug)), width = 900 * cols,
      height = 900 * filas, res = 110)
  par(mfrow = c(filas, cols), mar = c(1, 1, 3, 1))
  for (n in names(capas)) {
    plot(capas[[n]], col = COLORES, type = "classes", levels = CLASES,
         breaks = 0:6 - 0.5, legend = n == names(capas)[1],
         plg = list(x = "bottomleft", cex = 0.8, bg = "white"), axes = FALSE,
         main = sprintf("%s %s  (rural < %.2f)", slug, n, U_RURAL), mar = c(1, 1, 3, 1))
    if (!is.null(cont)) lines(cont, col = "black", lwd = 1)
  }
  dev.off()
}


ciudad <- function(slug) {
  # la caja de cajas.md, en grados (la misma que tiene el compuesto Landsat de 02)
  cj <- caja_de(RPIPE, slug)
  g <- ext(cj$lon0, cj$lon1, cj$lat0, cj$lat1)
  dir.create(file.path(SAL, slug), recursive = TRUE, showWarnings = FALSE)
  # una corrida anterior con otros anios dejaria capas viejas al lado de las nuevas
  unlink(list.files(file.path(SAL, slug), "^(angel|huella_proyecto)_\\d{4}\\.tif$",
                    full.names = TRUE))
  cat(sprintf("\n%s\n", slug))
  e <- as.vector(g)
  crs_utm <- utm(mean(e[1:2]), mean(e[3:4]))
  if (!file.exists(GISD)) stop("falta ", GISD, ": correr antes 01_gisd30_decadas.R", call. = FALSE)
  v <- crop(rast(GISD), g, snap = "out")
  v <- project(v, crs_utm, res = RES, method = "near")
  cont <- contorno_de(RPIPE, slug)
  if (!is.null(cont)) cont <- project(cont, crs_utm)
  # perimetros de otros aglomerados en la caja: distancia a cada uno, una vez por ciudad
  otros <- otros_de(RPIPE, slug)
  AJENO <<- OTROS <<- NULL
  if (!is.null(otros) && nrow(otros)) {
    OTROS <<- project(otros, crs_utm)
    d_mio <- distance(rasterize(cont, v[[1]], touches = TRUE))
    d_otro <- distance(rasterize(OTROS, v[[1]], touches = TRUE))
    AJENO <<- d_otro < d_mio
    cat("  otros aglomerados en la caja:", paste(otros$slug, collapse = ", "), "
")
  }
  capas <- list()
  filas <- list()
  for (anio in ANIOS) {
    a <- angel(v, DECADA[[as.character(anio)]])
    cls <- a$cls
    coltab(cls) <- data.frame(value = 0:5, col = COLORES)
    writeRaster(cls, file.path(SAL, slug, sprintf("angel_%d.tif", anio)), overwrite = TRUE,
                datatype = "INT1U", gdal = "COMPRESS=DEFLATE")
    writeRaster(a$huella_p, file.path(SAL, slug, sprintf("huella_proyecto_%d.tif", anio)),
                overwrite = TRUE, datatype = "INT1U", gdal = "COMPRESS=DEFLATE")
    capas[[as.character(anio)]] <- a$cls
    filas[[length(filas) + 1]] <- metricas(slug, anio, a, cont)
    cat(sprintf("  %d listo\n", anio))
  }
  mapa(slug, capas, cont)
  do.call(rbind, filas)
}


main <- function() {
  dir.create(SAL, recursive = TRUE, showWarnings = FALSE)
  todo <- do.call(rbind, lapply(CIUDADES, ciudad))
  # correr una sola ciudad no borra las otras del resumen
  csv <- file.path(SAL, "resumen.csv")
  if (file.exists(csv)) {
    viejo <- read.csv(csv)
    viejo <- viejo[!(viejo$ciudad %in% CIUDADES) & viejo$u_rural == U_RURAL, ]
    # filas de una version anterior con otras columnas se descartan: hay que recorrerlas
    if (identical(names(viejo), names(todo))) todo <- rbind(viejo, todo)
    else cat("  resumen.csv tenia otras columnas: quedan solo las ciudades de esta corrida\n")
  }
  todo <- todo[order(todo$ciudad, todo$anio), ]
  write.csv(todo, csv, row.names = FALSE)
  print(todo, row.names = FALSE, digits = 3)
  cat(sprintf("\nEscrito %s\n", file.path(SAL, "resumen.csv")))
}

main()
