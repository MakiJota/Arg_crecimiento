# -*- coding: utf-8 -*-
# Paso 21 · Etiquetas por pixel desde las capas vectoriales de Overture Maps (paso 20), sobre la
# grilla de GISD30 de cada aglomerado (UTM 30 m, la de code_<anio>.tif del paso 11). Exploratorio:
# Overture no es fuente del proyecto; sirve para validar y limpiar el ruido de GISD30.
#
# Overture describe el presente (2022-2025). Sirve en un solo sentido hacia atras: lo que hoy es
# agua, area protegida o cultivo, o no tiene edificios ni calles cerca, no estaba construido en
# 1990; lo que hoy esta construido no dice nada de 1990. Las etiquetas no dependen del anio.
#
# Capas de outputs/etiquetas/<slug>/etiquetas.tif (INT1U salvo dedif):
#   edif      % del pixel cubierto por huellas de edificios (0-100), rasterizado a 10 m y agregado
#   dedif     m al pixel de 10 m con edificio mas cercano, tope 1000 (INT2U)
#   calle     % del pixel cubierto por calles y vias: cada linea con un ancho tipico por clase
#             (ANCHO_CALLE; peatonales, senderos y escaleras no cuentan)
#   agua      % del pixel cubierto por agua: poligonos (sin piletas) y cursos con ancho por clase
#   protegida 1 area protegida (land_use subtype protected)
#   aeropuerto 1 aeropuerto (infrastructure subtype airport: predio, pistas, plataformas)
#   publico   1 espacio abierto publico: parque, plaza, cancha, estadio, cementerio, golf...
#   servicio  1 escuela, universidad, hospital, institucional, militar
#   cultivo   1 uso agricola u horticola (farmland, meadow, orchard, vineyard...; no farmyard)
#             Los poligonos de uso de mas de 50 km2 se descartan (salvo areas protegidas): OSM tiene
#             "mantas" que cubren valles enteros con la ciudad adentro
#   cobertura clase de ESA WorldCover en Overture: 1 urbano, 2 cultivo, 3 pastizal, 4 arbustal,
#             5 bosque, 6 suelo desnudo, 7 humedal, 8 otro; 0 sin dato
#
# ENTRADAS  outputs/densidad/<slug>/code_2020.tif (11), outputs/overture/<slug>/*.gpkg (20)
# SALIDAS   outputs/etiquetas/<slug>/etiquetas.tif
#
# Uso: Rscript Rpipe/scripts/21_etiquetas.R [--ciudades salta,jujuy] [--rehacer]

Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))
options(warn = 1)
suppressPackageStartupMessages(library(terra))
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
RPIPE <- dirname(normalizePath(dirname(script), winslash = "/"))
args <- commandArgs(trailingOnly = TRUE)
i <- match("--ciudades", args)
DENS <- file.path(RPIPE, "outputs", "densidad")
OVT <- file.path(RPIPE, "outputs", "overture")
SAL <- file.path(RPIPE, "outputs", "etiquetas")
source(file.path(RPIPE, "scripts", "lib", "cajas.R"))   # revisados(): perimetros del paso 24
CIUDADES <- if (is.na(i)) setdiff(sort(list.dirs(DENS, full.names = FALSE, recursive = FALSE)), revisados(RPIPE)) else strsplit(args[i + 1], ",")[[1]]
REHACER <- "--rehacer" %in% args
terraOptions(progress = 0, memfrac = 0.6)

# ancho total (m) de cada clase de calle o via; lo que no esta no cuenta
ANCHO_CALLE <- c(motorway = 30, trunk = 25, primary = 20, secondary = 16, tertiary = 14,
                 residential = 12, living_street = 10, unclassified = 10, unknown = 10, service = 8,
                 track = 6, standard_gauge = 10, narrow_gauge = 8, broad_gauge = 10, rail = 10)
# ancho total (m) de los cursos de agua dibujados como linea
ANCHO_AGUA <- c(river = 40, canal = 15, stream = 6, drain = 5, ditch = 3)
PUBLICO <- c("park", "village_green", "plaza", "pedestrian", "pitch", "playground", "recreation_ground",
             "track", "stadium", "garden", "cemetery", "golf_course", "rough", "fairway", "green", "tee", "bunker")
SERVICIO <- c("school", "education", "university", "college", "kindergarten", "hospital", "clinic", "doctors",
              "institutional", "military", "prison")
CULTIVO <- c("farmland", "meadow", "orchard", "vineyard", "plant_nursery", "greenhouse_horticulture", "allotments", "aquaculture")
COBERTURA <- c(urban = 1, crop = 2, grass = 3, shrub = 4, forest = 5, barren = 6, wetland = 7)

leer <- function(slug, tema, crs_, tipo = "polygons") {
  # una capa de Overture con un solo tipo de geometria (los gpkg mezclan lineas y poligonos y
  # vect() se queda solo con una clase)
  f <- file.path(OVT, slug, paste0(tema, ".gpkg"))
  if (!file.exists(f)) return(NULL)
  g <- if (tipo == "lines") "('LINESTRING', 'MULTILINESTRING')" else "('POLYGON', 'MULTIPOLYGON')"
  v <- tryCatch(vect(f, query = sprintf("SELECT * FROM %s WHERE ST_GeometryType(geom) IN %s", tema, g)),
                error = function(e) NULL)
  if (is.null(v) || !nrow(v)) return(NULL)
  project(v, crs_)
}

compartir <- function(v, plantilla) {
  # % de cada pixel de 30 m cubierto por los poligonos v: presencia a 10 m, agregada por 3
  if (is.null(v) || !nrow(v)) return(plantilla * 0)
  r10 <- disagg(rast(plantilla), 3)
  p <- rasterize(v, r10, field = 1, background = 0)
  round(100 * aggregate(p, 3, "mean"))
}

ensanchar <- function(lin, pol, anchos, campo = "clase") {
  # lineas a poligonos con medio ancho por clase, mas los poligonos como estan
  out <- list()
  if (!is.null(lin)) {
    lin <- lin[lin[[campo, drop = TRUE]] %in% names(anchos)]
    if (nrow(lin)) out[[1]] <- buffer(lin, width = unname(anchos[lin[[campo, drop = TRUE]]]) / 2, capstyle = "flat")[, 0]
  }
  if (!is.null(pol) && nrow(pol)) out[[length(out) + 1]] <- pol[, 0]
  if (!length(out)) return(NULL)
  do.call(rbind, out)
}

edificios <- function(slug, plantilla) {
  # por bloques, para no cargar millones de poligonos juntos (Gran Buenos Aires: 5,7 millones)
  f <- file.path(OVT, slug, "edificios.gpkg")
  r10 <- disagg(rast(plantilla), 3)
  nb <- max(1, ceiling(ncell(plantilla) / 1.5e6))
  filas <- unique(round(seq(0, nrow(r10), length.out = nb + 1)))
  partes <- list()
  for (k in seq_len(length(filas) - 1)) {
    h <- yres(r10) / 2
    e <- ext(xmin(r10), xmax(r10), yFromRow(r10, filas[k + 1]) - h, yFromRow(r10, filas[k] + 1) + h)
    trozo <- crop(r10, e)
    ell <- project(e, crs(plantilla), "EPSG:4326")
    v <- vect(f, extent = ell)
    partes[[k]] <- if (nrow(v)) rasterize(project(v, crs(plantilla)), trozo, field = 1, background = 0) else trozo * 0 + 0
  }
  p10 <- if (length(partes) == 1) partes[[1]] else do.call(merge, partes)
  list(edif = round(100 * aggregate(p10, 3, "mean")),
       dedif = clamp(round(distance(ifel(p10 == 1, 1, NA))), 0, 1000))
}

una <- function(slug) {
  t0 <- Sys.time()
  f <- file.path(SAL, slug, "etiquetas.tif")
  if (file.exists(f) && !REHACER) { cat(sprintf("  %-22s ya estaba\n", slug)); return(invisible()) }
  dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
  plantilla <- rast(file.path(DENS, slug, "code_2020.tif"))
  cr <- crs(plantilla)
  ed <- edificios(slug, plantilla)
  ed$dedif <- resample(aggregate(ed$dedif, 3, "min"), plantilla, method = "near")

  calles <- leer(slug, "calles", cr, "lines")
  agua_l <- leer(slug, "agua", cr, "lines")
  agua_p <- leer(slug, "agua", cr)
  if (!is.null(agua_p)) agua_p <- agua_p[!agua_p$clase %in% c("swimming_pool", "hot_spring")]
  uso <- leer(slug, "uso", cr)
  # OSM tiene poligonos "manta" enormes (en Salta un cultivo cubre todo el valle, ciudad incluida):
  # fuera los de mas de 50 km2, salvo las areas protegidas, que pueden ser asi de grandes
  if (!is.null(uso)) uso <- uso[uso$subtype == "protected" | expanse(uso, unit = "km") <= 50]
  aer_pol <- leer(slug, "aeropuertos", cr)
  aer_lin <- leer(slug, "aeropuertos", cr, "lines")
  cob <- leer(slug, "cobertura", cr)

  binario <- function(v) if (is.null(v) || !nrow(v)) plantilla * 0 else rasterize(v, plantilla, field = 1, background = 0)
  sel <- function(v, cond) if (is.null(v)) NULL else v[cond(v)]
  # pistas y calles de rodaje dibujadas como linea: 45 m de ancho
  if (!is.null(aer_lin)) aer_pol <- if (is.null(aer_pol)) buffer(aer_lin, 22.5)[, 0] else rbind(aer_pol[, 0], buffer(aer_lin, 22.5)[, 0])

  r <- c(ed$edif, ed$dedif,
         compartir(ensanchar(calles, NULL, ANCHO_CALLE), plantilla),
         compartir(ensanchar(agua_l, agua_p, ANCHO_AGUA), plantilla),
         binario(sel(uso, function(v) v$subtype == "protected")),
         binario(aer_pol),
         binario(sel(uso, function(v) v$clase %in% PUBLICO)),
         binario(sel(uso, function(v) v$clase %in% SERVICIO)),
         binario(sel(uso, function(v) v$clase %in% CULTIVO)),
         if (is.null(cob)) plantilla * 0 else {
           cob$k <- unname(COBERTURA[cob$subtype]); cob$k[is.na(cob$k)] <- 8
           rasterize(cob, plantilla, field = "k", background = 0)
         })
  names(r) <- c("edif", "dedif", "calle", "agua", "protegida", "aeropuerto", "publico", "servicio", "cultivo", "cobertura")
  r <- ifel(is.na(r), 0, r)
  tmp <- sub("\\.tif$", ".tmp.tif", f)
  writeRaster(r, tmp, overwrite = TRUE, datatype = "INT2U", gdal = "COMPRESS=DEFLATE")
  file.rename(tmp, f)
  cat(sprintf("  %-22s (%.1f min)\n", slug, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}

cat(sprintf("Etiquetas de Overture por pixel · %d aglomerados\n", length(CIUDADES)))
for (s in CIUDADES) tryCatch(una(s), error = function(e) cat("  ERROR", s, ":", conditionMessage(e), "\n"))
