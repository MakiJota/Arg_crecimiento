# -*- coding: utf-8 -*-
# Paso 0b · Descarga y extraccion de los tiles GISD30 que cubren Argentina.
# Traduccion a R de scripts/ag_0_gisd30.py.
#
# GISD30: superficie impermeable global a 30 m, 1985-2020 (Zhang y otros 2022,
# ESSD 14:1831-1856). Es la fuente de la huella urbana y de la tipologia de
# expansion. Licencia CC BY 4.0.
#
# COMO ESTA EMPAQUETADO. El deposito NO expone los .tif sueltos: sirve doce .rar
# agrupados por bandas de 30 grados de longitud, cada uno con todos los tiles de
# su banda. Argentina cae entera en DOS de esos doce:
#     W65_W90 ->  147,1 MB  (22 tiles)
#     W35_W60 ->   50,2 MB  ( 8 tiles)
# Total a bajar 188 MiB; los 30 tiles extraidos pesan 142 MiB.
#
# NOMBRE DE LOS TILES: GISD30_1985-2020_{E|W}<lon>{N|S}<lat>.tif, longitud primero
# y despues latitud, sin relleno de ceros (W70S50, no W070S50). El par es la
# esquina NOROESTE: el tile cubre lon [lon0, lon0+5] y lat [lat0-5, lat0]. Las
# celdas 100 % oceanicas directamente no existen en el .rar, asi que se generan
# los 40 nombres candidatos y se tolera que falten 10.
#
# VALOR DEL PIXEL: 0 = nunca impermeable; 1 = ya impermeable antes de 1985;
# 2..8 = se volvio impermeable en 1985-1990, 1990-1995, ... , 2015-2020. O sea
# que "construido hasta el ano X" es acumulativo: v>=1 y v<=ep. Al final el
# script saca un histograma de un tile para confirmarlo contra el dato real.
#
# EXTRACCION: el paquete archive (libarchive) lee RAR5. No hace falta 7-Zip.
#
# DIFERENCIAS CON EL ORIGINAL. Las rutas son locales a Rpipe y no las de rutas.py:
#     .rar   -> Rpipe/raw/gisd30/
#     tiles  -> Rpipe/outputs/gisd30/tiles/
# y se agrega una salida para QGIS, Rpipe/outputs/gisd30/gisd30_argentina.gpkg,
# con el mosaico de los 30 tiles (capa raster "gisd30", con piramides) y la
# huella de cada tile (capa vectorial "tiles").
#
# Uso: Rscript Rpipe/scripts/00_gisd30_descarga.R [--solo-verificar] [--sin-gpkg]

suppressPackageStartupMessages({
  library(curl)
  library(archive)
  library(digest)
  library(terra)
  library(sf)
})

args <- commandArgs(trailingOnly = TRUE)

# Rpipe/ a partir de la ubicacion de este script
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
RPIPE <- normalizePath(file.path(dirname(script), ".."), winslash = "/")
RAW <- file.path(RPIPE, "raw", "gisd30")
SAL <- file.path(RPIPE, "outputs", "gisd30")
TIF <- file.path(SAL, "tiles")
GPKG <- file.path(SAL, "gisd30_argentina.gpkg")

ZENODO <- "https://zenodo.org/records/5220816/files/%s?download=1"
PREFIJO <- "GISD30_1985-2020_"

# tamanio y md5 declarados por Zenodo
PAQUETES <- list(
  "GISD30_1985-2020_W35_W60.rar" = list(bytes = 50167537, md5 = "68e56fdc0e0ae1012bca91efbc556a1a"),
  "GISD30_1985-2020_W65_W90.rar" = list(bytes = 147053306, md5 = "843b8274a203a9caf2ac6051e65bacf8")
)

# Argentina continental, con margen para el buffer de 15 km del panel
BBOX <- c(oeste = -73.6, este = -53.6, sur = -55.1, norte = -21.8)
TILES_ESPERADOS <- 30


nombre_tile <- function(lon0, lat0) {
  ew <- if (lon0 < 0) sprintf("W%d", abs(lon0)) else sprintf("E%d", lon0)
  ns <- if (lat0 < 0) sprintf("S%d", abs(lat0)) else sprintf("N%d", lat0)
  paste0(PREFIJO, ew, ns, ".tif")
}


paquete_de <- function(lon0) {
  # A que .rar pertenece una columna de tiles.
  i <- (abs(lon0) - 5) %/% 30
  lo <- 5 + 30 * i
  hi <- 30 + 30 * i
  letra <- if (lon0 < 0) "W" else "E"
  sprintf("%s%s%d_%s%d.rar", PREFIJO, letra, lo, letra, hi)
}


tiles_de_bbox <- function(bbox) {
  # Devuelve un data.frame: tile, paquete, lon0, lat0
  lon0s <- Filter(function(x) x < bbox[["este"]] && x + 5 > bbox[["oeste"]], seq(-180, 175, 5))
  lat0s <- Filter(function(y) y - 5 < bbox[["norte"]] && y > bbox[["sur"]], seq(-55, 80, 5))
  g <- expand.grid(lon0 = lon0s, lat0 = lat0s)
  data.frame(
    tile = mapply(nombre_tile, g$lon0, g$lat0),
    paquete = vapply(g$lon0, paquete_de, ""),
    lon0 = g$lon0, lat0 = g$lat0,
    stringsAsFactors = FALSE
  )
}


bajar <- function(nombre, destino, bytes_esperados, md5_esperado) {
  if (file.exists(destino) && file.size(destino) == bytes_esperados) {
    cat(sprintf("  ya estaba: %s (%.1f MB)\n", nombre, bytes_esperados / 1e6))
  } else {
    for (intento in 1:3) {
      if (file.exists(destino) && file.size(destino) >= bytes_esperados) unlink(destino)
      # multi_download retoma con Range si el archivo quedo a medias
      r <- tryCatch(
        multi_download(sprintf(ZENODO, nombre), destino, resume = TRUE, progress = TRUE),
        error = function(e) data.frame(success = FALSE, error = conditionMessage(e))
      )
      if (isTRUE(r$success[1])) break
      cat(sprintf("    intento %d/3 fallo: %s\n", intento, substr(r$error[1], 1, 70)))
      Sys.sleep(3 * intento)
    }
    cat(sprintf("  bajado: %s (%.1f MB)\n", nombre, file.size(destino) / 1e6))
  }

  n <- file.size(destino)
  if (is.na(n) || n != bytes_esperados)
    return(list(ok = FALSE, msg = sprintf("tamanio %s, se esperaban %d", n, bytes_esperados)))
  h <- digest(destino, algo = "md5", file = TRUE)
  if (h != md5_esperado)
    return(list(ok = FALSE, msg = sprintf("md5 %s, se esperaba %s", h, md5_esperado)))
  cat(sprintf("    md5 OK (%s...)\n", substr(h, 1, 12)))
  list(ok = TRUE, msg = "ok")
}


extraer <- function(rar, quiero) {
  # Extrae del .rar solo los tiles pedidos. Devuelve los nombres que salieron.
  contenido <- archive(rar)$path
  pedidos <- contenido[basename(contenido) %in% quiero]
  if (!length(pedidos)) return(character())
  tmp <- tempfile("gisd30_", tmpdir = RAW)
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  archive_extract(rar, dir = tmp, files = pedidos)
  for (p in pedidos) file.rename(file.path(tmp, p), file.path(TIF, basename(p)))
  sort(basename(pedidos))
}


histograma <- function() {
  # Confirma la codificacion del pixel contra el dato real.
  cand <- sort(list.files(TIF, "S35\\.tif$", full.names = TRUE))
  if (!length(cand)) cand <- sort(list.files(TIF, "\\.tif$", full.names = TRUE))
  if (!length(cand)) return(invisible())
  r <- rast(cand[1])
  # submuestreo 1:8 por lado, como el out_shape del original
  a <- spatSample(r, ncell(r) / 64, method = "regular", as.raster = TRUE)
  f <- freq(a)
  etq <- c("0" = "nunca impermeable", "1" = "antes de 1985", "2" = "1985-1990",
           "3" = "1990-1995", "4" = "1995-2000", "5" = "2000-2005", "6" = "2005-2010",
           "7" = "2010-2015", "8" = "2015-2020")
  cat(sprintf("\nHistograma de %s (submuestreado 1:8)\n", basename(cand[1])))
  for (i in seq_len(nrow(f))) {
    v <- as.character(f$value[i])
    cat(sprintf("  %s  %-20s%12d\n", v, if (v %in% names(etq)) etq[[v]] else "VALOR INESPERADO",
                as.integer(f$count[i])))
  }
  fuera <- f$value[f$value > 8]
  if (length(fuera)) cat(sprintf("  AVISO  valores fuera de rango: %s\n", paste(fuera, collapse = ", ")))
  else cat("  ok     todos los valores caen en 0..8\n")
}


armar_gpkg <- function(quiero) {
  # Mosaico de los tiles en un GeoPackage para QGIS, mas la huella de cada tile.
  tifs <- sort(list.files(TIF, paste0("^", PREFIJO, ".*\\.tif$"), full.names = TRUE))
  if (!length(tifs)) return(invisible())
  if (file.exists(GPKG)) unlink(GPKG)
  vrt <- file.path(SAL, "gisd30_argentina.vrt")
  cfg <- c(GDAL_CACHEMAX = "2048", GDAL_NUM_THREADS = "ALL_CPUS")

  cat("\nArmando el mosaico ...\n")
  # -vrtnodata 255: lo que no cubre ningun tile (oceano) queda sin dato y no se
  # escribe en el GeoPackage; el 0 sigue siendo "nunca impermeable"
  gdal_utils("buildvrt", tifs, vrt, options = c("-vrtnodata", "255"))
  t0 <- Sys.time()
  gdal_utils("translate", vrt, GPKG, config_options = cfg, options = c(
    "-of", "GPKG", "-co", "RASTER_TABLE=gisd30", "-co", "TILE_FORMAT=PNG",
    "-co", "RASTER_IDENTIFIER=GISD30 1985-2020, Argentina",
    "-co", "RASTER_DESCRIPTION=0 nunca impermeable; 1 antes de 1985; 2..8 = 1985-90 ... 2015-20"
  ))
  cat(sprintf("  mosaico escrito en %.1f min\n", difftime(Sys.time(), t0, units = "mins")))

  cat("  piramides para QGIS ...\n")
  gdal_addo(GPKG, overviews = 2^(1:9), method = "nearest", config_options = cfg)

  # huella de cada tile segun su georreferencia real, no la del nombre
  huellas <- do.call(rbind, lapply(tifs, function(f) {
    e <- as.vector(ext(rast(f)))
    st_sf(tile = basename(f),
          paquete = quiero$paquete[match(basename(f), quiero$tile)],
          geometry = st_as_sfc(st_bbox(c(xmin = e[["xmin"]], ymin = e[["ymin"]],
                                         xmax = e[["xmax"]], ymax = e[["ymax"]]),
                                       crs = st_crs(crs(rast(f))))))
  }))
  st_write(huellas, GPKG, layer = "tiles", quiet = TRUE)
  unlink(vrt)
  cat(sprintf("  %s: %.1f MB (capas gisd30 y tiles)\n", GPKG, file.size(GPKG) / 1e6))
}


main <- function() {
  for (d in c(RAW, SAL, TIF)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  quiero <- tiles_de_bbox(BBOX)
  cat(sprintf("Argentina (%s): %d celdas candidatas, %d con tierra esperados\n\n",
              paste(BBOX, collapse = ", "), nrow(quiero), TILES_ESPERADOS))

  if (!"--solo-verificar" %in% args) {
    for (nombre in names(PAQUETES)) {
      p <- PAQUETES[[nombre]]
      r <- bajar(nombre, file.path(RAW, nombre), p$bytes, p$md5)
      if (!r$ok) {
        cat(sprintf("  FALLA %s: %s\n", nombre, r$msg))
        return(1L)
      }
    }

    for (nombre in names(PAQUETES)) {
      pedidos <- quiero$tile[quiero$paquete == nombre]
      cat(sprintf("\nExtrayendo de %s (%d tiles pedidos) ...\n", nombre, length(pedidos)))
      salieron <- extraer(file.path(RAW, nombre), pedidos)
      cat(sprintf("  salieron %d; faltaron %d (celdas oceanicas, es esperable)\n",
                  length(salieron), length(pedidos) - length(salieron)))
    }
  }

  hay <- sort(list.files(TIF, paste0("^", PREFIJO, ".*\\.tif$")))
  peso <- sum(file.size(file.path(TIF, hay)))
  cat(sprintf("\nEn %s: %d tiles, %.1f MB\n", TIF, length(hay), peso / 1e6))
  if (length(hay) != TILES_ESPERADOS) {
    cat(sprintf("  AVISO  se esperaban %d tiles\n", TILES_ESPERADOS))
  } else {
    cat(sprintf("  ok     %d tiles, como declara el relevamiento\n", TILES_ESPERADOS))
  }
  histograma()
  if (!"--sin-gpkg" %in% args) armar_gpkg(quiero)
  0L
}


quit(status = main())
