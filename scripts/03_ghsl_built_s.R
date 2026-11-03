# -*- coding: utf-8 -*-
# GHS-BUILT-S (JRC, GHSL R2023A) recortado a una ciudad y puesto sobre la grilla de
# GISD30, para comparar las dos capas en QGIS. Script nuevo, no traduce a ninguno de
# scripts/.
#
# QUE ES. Superficie construida por celda, en m2 (no un si/no):
#   10 m   epoca 2018      Sentinel-2 + Landsat, cuadros de 10 m  (0..100 m2)
#   100 m  1990 2000 2010 2020   serie multitemporal, Landsat     (0..10000 m2)
# Pesaresi y Politis (2023), GHS-BUILT-S R2023A, JRC, doi:10.2905/9F06F36F-4B11-47EC-ABB0-4F8B7B1D72EA.
# Licencia CC BY 4.0. Es JRC, o sea una fuente admitida por la regla de precision.
# OJO: GHSL mide CONSTRUIDO (techos), no impermeable; las calles quedan afuera.
# GISD30 mide impermeable (techos + pavimento). No miden lo mismo.
#
# DESCARGA. jeodpp.jrc.ec.europa.eu, cuadros de 1000 x 1000 km en Mollweide
# (ESRI:54009), R<fila>_C<columna>, origen en x = -18041000, y = 9000000. Se lee el .tif
# directo del .zip (/vsizip/), sin extraer. Salta y Tandil caen en un cuadro, Tucuman
# en dos (R13_C12 y R13_C13). El de 10 m pesa 40-155 MB por cuadro.
#
# GRILLA. La del compuesto Landsat de la ciudad (Rpipe/outputs/landsat/<slug>/
# landsat_2020.tif), que es la de GISD30: EPSG:4326, 0,00026949 grados. El de 10 m se
# lleva a 30 m PROMEDIANDO la fraccion (method = "average"); el de 100 m, por vecino
# mas cercano, porque es mas grueso que la grilla de destino.
#
# SALIDA en Rpipe/outputs/ghsl/<slug>/
#   ghsl10_2018_nativo.tif      recorte en Mollweide a 10 m, m2 por celda, sin tocar
#   comparacion_<slug>.tif      grilla GISD30, una banda por capa:
#       gisd30_<anio>           1 si impermeable hasta ese anio (acumulado 1..ep), 0 si no
#       ghsl100_<anio>          fraccion construida 0..1, serie de 100 m
#       ghsl10_2018             fraccion construida 0..1, 10 m promediado a 30 m
#       cruce_2020              1 ambas, 2 solo GISD30 2020, 3 solo GHSL 10 m 2018 (>= umbral)
#   resumen.csv                 km2 por capa y por anio, y el cruce. Exploratorio: NO es
#                               una cifra del proyecto, no sale de CIFRAS_CANONICAS.json.
#
# El umbral para pasar la fraccion a si/no es 0,20 por defecto, el mismo que usa la
# version GHSL de la herramienta (LEEME_ghsl_tipologia.txt). Se cambia con --umbral.
# El cruce compara GISD30 2020 con GHSL 2018: dos anios de diferencia, a favor de GISD30.
#
# Uso: Rscript Rpipe/scripts/03_ghsl_built_s.R [--ciudades salta,tandil,tucuman]
#        [--umbral 0.2] [--sin-10m]
# Requiere 01_gisd30_decadas.R y 02_landsat_bbox.R para cada ciudad.

# PostGIS deja PROJ_LIB y GDAL_DATA apuntando a su propia copia, vieja: con eso
# "EPSG:4326" falla. Se usan las que trae terra.
Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))

suppressPackageStartupMessages({
  library(curl)
  library(terra)
})

args <- commandArgs(trailingOnly = TRUE)
arg <- function(nombre, defecto) {
  i <- match(nombre, args)
  if (is.na(i) || i == length(args)) defecto else args[i + 1]
}
CIUDADES <- strsplit(arg("--ciudades", "salta,tandil,tucuman"), ",")[[1]]
UMBRAL <- as.numeric(arg("--umbral", "0.2"))
CON_10M <- !("--sin-10m" %in% args)

script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
RPIPE <- normalizePath(file.path(dirname(script), ".."), winslash = "/")
RAW <- file.path(RPIPE, "raw", "ghsl")
SAL <- file.path(RPIPE, "outputs", "ghsl")
GISD <- file.path(RPIPE, "outputs", "gisd30", "gisd30_decadas.vrt")
LANDSAT <- file.path(RPIPE, "outputs", "landsat")

BASE <- "https://jeodpp.jrc.ec.europa.eu/ftp/jrc-opendata/GHSL/GHS_BUILT_S_GLOBE_R2023A"
ANIOS <- c(1990, 2000, 2010, 2020)
# anio -> ultima decada (capa del paso 01) que cuenta como construido
DECADA <- c("1990" = 1, "2000" = 2, "2010" = 3, "2020" = 4)
MOLL <- "ESRI:54009"


producto <- function(anio, res) sprintf("GHS_BUILT_S_E%d_GLOBE_R2023A_54009_%d", anio, res)


cuadros <- function(caja_moll) {
  e <- as.vector(ext(caja_moll))
  filas <- unique(floor((9e6 - e[c("ymax", "ymin")]) / 1e6) + 1)
  cols <- unique(floor((e[c("xmin", "xmax")] + 18041000) / 1e6) + 1)
  as.vector(outer(filas, cols, function(f, c) sprintf("R%d_C%d", f, c)))
}


bajar <- function(anio, res, cuadro) {
  p <- producto(anio, res)
  zip <- sprintf("%s_V1_0_%s.zip", p, cuadro)
  destino <- file.path(RAW, zip)
  url <- sprintf("%s/%s/V1-0/tiles/%s", BASE, p, zip)
  # el tamanio esperado sale del encabezado: un .zip cortado no se reutiliza
  h <- curl_fetch_memory(url, handle = new_handle(nobody = TRUE))
  esperado <- as.numeric(parse_headers_list(h$headers)[["content-length"]])
  if (!file.exists(destino) || file.size(destino) != esperado) {
    cat(sprintf("  bajando %s (%.1f MB)\n", zip, esperado / 2^20))
    # el servidor de JRC corta conexiones a mitad de descarga: hasta 5 intentos
    for (intento in 1:5) {
      ok <- tryCatch({ curl_download(url, destino, quiet = TRUE); TRUE },
                     error = function(e) { cat("    reintento:", conditionMessage(e), "\n"); FALSE })
      if (ok && file.size(destino) == esperado) break
      Sys.sleep(5 * intento)
    }
    if (file.size(destino) != esperado) stop("descarga incompleta: ", zip, call. = FALSE)
  }
  sprintf("/vsizip/%s/%s_V1_0_%s.tif", destino, p, cuadro)
}


ghsl_recorte <- function(anio, res, caja_moll) {
  tifs <- vapply(cuadros(caja_moll), function(q) bajar(anio, res, q), "")
  # mosaico virtual: los cuadros no se solapan y merge() reescribe todo el cuadro entero
  r <- if (length(tifs) == 1) rast(tifs) else vrt(tifs)
  r <- crop(r, caja_moll, snap = "out")
  # m2 por celda; lo que pase del maximo posible es sin dato
  maximo <- res^2
  classify(r, cbind(maximo, Inf, NA), right = FALSE)
}


ciudad <- function(slug) {
  plantilla <- file.path(LANDSAT, slug, "landsat_2020.tif")
  if (!file.exists(plantilla))
    stop("falta ", plantilla, ": correr antes 02_landsat_bbox.R --slug ", slug, call. = FALSE)
  g <- rast(plantilla)[[1]]
  dir.create(file.path(SAL, slug), recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("\n%s\n", slug))
  # 2 km de margen en Mollweide para que la reproyeccion no deje bordes vacios
  caja <- buffer(project(as.polygons(ext(g), crs = crs(g)), MOLL), 2000)

  # GISD30 en la misma grilla
  if (!file.exists(GISD)) stop("falta ", GISD, ": correr antes 01_gisd30_decadas.R", call. = FALSE)
  gisd <- crop(rast(GISD), g, snap = "near")
  if (!compareGeom(gisd, g, stopOnError = FALSE)) gisd <- resample(gisd, g, method = "near")
  capas <- list()
  for (a in ANIOS) capas[[sprintf("gisd30_%d", a)]] <- gisd >= 1 & gisd <= DECADA[[as.character(a)]]

  for (a in ANIOS) {
    r <- ghsl_recorte(a, 100, caja) / 100^2
    capas[[sprintf("ghsl100_%d", a)]] <- project(r, g, method = "near")
  }
  if (CON_10M) {
    r <- ghsl_recorte(2018, 10, caja)
    writeRaster(r, file.path(SAL, slug, "ghsl10_2018_nativo.tif"), overwrite = TRUE,
                datatype = "INT1U", gdal = "COMPRESS=DEFLATE")
    capas[["ghsl10_2018"]] <- project(r / 100, g, method = "average")
    ambas <- capas$gisd30_2020 & capas$ghsl10_2018 >= UMBRAL
    capas[["cruce_2020"]] <- ifel(ambas, 1, ifel(capas$gisd30_2020, 2,
                                  ifel(capas$ghsl10_2018 >= UMBRAL, 3, 0)))
  }
  s <- rast(capas)
  names(s) <- names(capas)
  writeRaster(s, file.path(SAL, slug, sprintf("comparacion_%s.tif", slug)), overwrite = TRUE,
              datatype = "FLT4S", gdal = "COMPRESS=DEFLATE")

  # km2: area real de cada pixel (la grilla es en grados)
  km2 <- cellSize(g, unit = "km")
  suma <- function(x) global(x * km2, "sum", na.rm = TRUE)[[1]]
  filas <- list()
  for (a in ANIOS) {
    f <- capas[[sprintf("ghsl100_%d", a)]]
    filas[[length(filas) + 1]] <- data.frame(
      ciudad = slug, anio = a,
      gisd30_impermeable_km2 = suma(capas[[sprintf("gisd30_%d", a)]]),
      ghsl100_construido_km2 = suma(f),
      ghsl100_pixeles_umbral_km2 = suma(f >= UMBRAL))
  }
  res <- do.call(rbind, filas)
  if (CON_10M) {
    res$ghsl10_2018_construido_km2 <- NA
    res$ghsl10_2018_pixeles_umbral_km2 <- NA
    i <- res$anio == 2020
    res$ghsl10_2018_construido_km2[i] <- suma(capas$ghsl10_2018)
    res$ghsl10_2018_pixeles_umbral_km2[i] <- suma(capas$ghsl10_2018 >= UMBRAL)
    for (k in 1:3) {
      col <- c("cruce_ambas_km2", "cruce_solo_gisd30_km2", "cruce_solo_ghsl_km2")[k]
      res[[col]] <- NA
      res[[col]][i] <- suma(capas$cruce_2020 == k)
    }
  }
  res$umbral <- UMBRAL
  print(res, row.names = FALSE, digits = 4)
  res
}


main <- function() {
  dir.create(RAW, recursive = TRUE, showWarnings = FALSE)
  todo <- do.call(rbind, lapply(CIUDADES, ciudad))
  write.csv(todo, file.path(SAL, "resumen.csv"), row.names = FALSE)
  cat(sprintf("\nEscrito %s\n", file.path(SAL, "resumen.csv")))
}

main()
