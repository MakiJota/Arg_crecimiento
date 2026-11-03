# -*- coding: utf-8 -*-
# Paso 01 · GISD30 por decada: de las 8 epocas quinquenales a 4 decadas.
# Script nuevo. Los pasos siguientes leen ESTA capa, no los tiles crudos.
#
# POR QUE. GISD30 trae la epoca de primera deteccion en saltos de 5 anios:
#   0 nunca impermeable     1 antes de 1985     2 1985-1990
#   3 1990-1995   4 1995-2000   5 2000-2005   6 2005-2010   7 2010-2015   8 2015-2020
# Los censos son 1991, 2001, 2010 y 2022, y el proyecto los compara con GISD30
# 1990, 2000, 2010 y 2020 (scripts/rutas.py, EP_PIXEL). Entonces la epoca util es la
# decada, y "construido hasta el anio X" es ACUMULADO:
#   hasta 1990  valores 1-2
#   hasta 2000  valores 1-4
#   hasta 2010  valores 1-6
#   hasta 2020  valores 1-8
# El valor 1 no se puede partir: es "antes de 1985" sin mas detalle, y no hay nada
# anterior en esta fuente. Por eso no hay corte de 1985.
#
# CODIFICACION DE LA SALIDA: decada de primera deteccion.
#   0 nunca     1 hasta 1990 (1-2)     2 1990-2000 (3-4)
#   3 2000-2010 (5-6)                  4 2010-2020 (7-8)
# Construido hasta la decada k es d >= 1 & d <= k. Sin dato: 255, igual que el crudo.
#
# SALIDA en Rpipe/outputs/gisd30/
#   decadas/<tile>_decadas.tif   uno por tile, misma grilla que el crudo
#   gisd30_decadas.vrt           mosaico virtual de los 30, el que leen los pasos 03 y 04
#
# CONTROL. Para cada tile se cuenta, sobre una muestra regular 1:8 por lado, que los
# pixeles de cada decada sean exactamente la suma de sus dos epocas. Si no cierra, se
# corta.
#
# Uso: Rscript Rpipe/scripts/01_gisd30_decadas.R [--rehacer]
# Requiere 00_gisd30_descarga.R.

Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))

suppressPackageStartupMessages(library(terra))

REHACER <- "--rehacer" %in% commandArgs(trailingOnly = TRUE)

script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
RPIPE <- normalizePath(file.path(dirname(script), ".."), winslash = "/")
TIF <- file.path(RPIPE, "outputs", "gisd30", "tiles")
DEC <- file.path(RPIPE, "outputs", "gisd30", "decadas")
VRT <- file.path(RPIPE, "outputs", "gisd30", "gisd30_decadas.vrt")

# epoca cruda -> decada
TABLA <- cbind(de = 0:8, a = c(0, 1, 1, 2, 2, 3, 3, 4, 4))


control <- function(crudo, dec) {
  # misma muestra regular en los dos: la decada k tiene que ser la suma de sus epocas
  a <- freq(spatSample(crudo, ncell(crudo) / 64, method = "regular", as.raster = TRUE))
  b <- freq(spatSample(dec, ncell(dec) / 64, method = "regular", as.raster = TRUE))
  n <- function(f, v) sum(f$count[f$value %in% v])
  esperado <- sapply(0:4, function(k) n(a, TABLA[TABLA[, "a"] == k, "de"]))
  obtenido <- sapply(0:4, function(k) n(b, k))
  if (any(esperado != obtenido))
    stop("no cierra el control: esperado ", paste(esperado, collapse = "/"),
         " obtenido ", paste(obtenido, collapse = "/"), call. = FALSE)
  obtenido
}


main <- function() {
  tifs <- sort(list.files(TIF, "\\.tif$", full.names = TRUE))
  if (!length(tifs)) stop("no hay tiles en ", TIF, ": correr antes 00_gisd30_descarga.R",
                          call. = FALSE)
  dir.create(DEC, recursive = TRUE, showWarnings = FALSE)
  salidas <- character()
  tot <- numeric(5)
  for (f in tifs) {
    s <- file.path(DEC, sub("\\.tif$", "_decadas.tif", basename(f)))
    crudo <- rast(f)
    if (REHACER || !file.exists(s)) {
      # lo que no esta en la tabla (255, sin dato) queda como esta
      classify(crudo, TABLA, others = NA, filename = s, overwrite = TRUE,
               datatype = "INT1U", NAflag = 255, gdal = "COMPRESS=DEFLATE")
    }
    n <- control(crudo, rast(s))
    tot <- tot + n
    cat(sprintf("  %-32s ok   muestra 0/1/2/3/4: %s\n", basename(s),
                paste(n, collapse = " / ")))
    salidas <- c(salidas, s)
  }
  vrt(salidas, VRT, overwrite = TRUE)
  cat(sprintf("\n%d tiles. Escrito %s\n", length(salidas), VRT))
  cat(sprintf("Muestra total: nunca %.0f | hasta 1990 %.0f | 1990-2000 %.0f | 2000-2010 %.0f | 2010-2020 %.0f\n",
              tot[1], tot[2], tot[3], tot[4], tot[5]))
}

main()
