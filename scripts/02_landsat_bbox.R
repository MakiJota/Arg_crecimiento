# -*- coding: utf-8 -*-
# Compuesto Landsat de un recuadro, por anio, para abrir en QGIS.
# Adaptacion a R de scripts/ag_45_landsat_fondo.py: mismas reglas de busqueda,
# enmascarado y mediana, pero guarda la REFLECTANCIA (no una imagen para la web).
#
# QUE ES. Landsat Collection 2 nivel 2 (reflectancia de superficie) de USGS,
# leido de Microsoft Planetary Computer (publico, sin cuenta):
#   1990  Landsat 5 TM        2000  Landsat 5 TM y Landsat 7 ETM+
#   2010  Landsat 5 TM        2020  Landsat 8 OLI
# (2010 sin Landsat 7: desde mayo de 2003 tiene la falla del SLC, franjas sin dato.)
# Se toman las escenas con menos de 20 % de nubes del anio calendario, primero
# Tier 1, se enmascaran nubes, sombras y relleno con QA_PIXEL y se hace la MEDIANA
# pixel a pixel. Si 1990 vuelve vacio se reintenta con 24 meses a cada lado, como
# ag_45 con 1991; las fechas reales quedan en escenas.csv.
#
# GRILLA. EPSG:4326 con el paso de GISD30 (0,00026949 grados, ~30 m), para que
# calce pixel a pixel con Rpipe/outputs/gisd30/gisd30_argentina.gpkg.
#
# SALIDA en Rpipe/outputs/landsat/<slug>/
#   landsat_<anio>.tif      6 bandas (blue green red nir swir1 swir2), reflectancia
#                           x 10000 en Int16, sin dato -32768. Para analisis.
#   landsat_<slug>.gpkg     una capa RGB por anio (landsat_<anio>), color natural con
#                           el estiramiento de ag_45, igual en todos los anios. Para ver.
#   escenas.csv             escenas usadas por anio: id, fecha, plataforma, tier, nubes.
#
# Uso: Rscript Rpipe/scripts/02_landsat_bbox.R [--slug tucuman]
#        [--bbox lat0,lon0,lat1,lon1] [--anios 1990,2000,2010,2020]
# Sin argumentos hace San Miguel de Tucuman (-27.2052,-65.8582 : -26.549,-64.7727).

# PostGIS deja PROJ_LIB y GDAL_DATA apuntando a su propia copia, vieja: con eso
# "EPSG:4326" falla. Se usan las que trae terra.
Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))

suppressPackageStartupMessages({
  library(httr2)
  library(terra)
  library(sf)
})

STAC <- "https://planetarycomputer.microsoft.com/api/stac/v1/search"
SAS <- "https://planetarycomputer.microsoft.com/api/sas/v1/token/landsat-c2-l2"
PLATAFORMAS <- list("1990" = "landsat-5", "2000" = c("landsat-5", "landsat-7"),
                    "2010" = "landsat-5", "2020" = "landsat-8")
VENTANA_RESERVA <- c("1990" = 24)  # meses a cada lado, solo si el anio vuelve vacio
RES <- 0.00026949                  # la grilla de GISD30 (~30 m)
MAX_ESCENAS <- 8
# nombre de la banda en Planetary Computer -> nombre en la salida
BANDAS <- c(blue = "blue", green = "green", red = "red",
            nir08 = "nir", swir16 = "swir1", swir22 = "swir2")

arg <- function(nombre, defecto) {
  # todo lo que sigue a `nombre` hasta el proximo --argumento, pegado con comas:
  # asi "--bbox -25.1, -65.9 , -24.5, -65.0" (con espacios, o partido en pedazos
  # por PowerShell) llega igual que "--bbox -25.1,-65.9,-24.5,-65.0"
  a <- commandArgs(trailingOnly = TRUE)
  i <- match(nombre, a)
  if (is.na(i)) return(defecto)
  fin <- which(startsWith(a, "--") & seq_along(a) > i)
  fin <- if (length(fin)) fin[1] - 1 else length(a)
  paste(a[seq_len(fin - i) + i], collapse = ",")
}
lista <- function(x) {
  x <- strsplit(x, "[,[:space:]]+")[[1]]
  x[nzchar(x)]
}
SLUG <- arg("--slug", "tucuman")
CAJA <- suppressWarnings(as.numeric(lista(arg("--bbox", "-27.2052,-65.8582,-26.549,-64.7727"))))
if (length(CAJA) != 4 || anyNA(CAJA))
  stop("--bbox tiene que ser cuatro numeros lat0,lon0,lat1,lon1 (suroeste y noreste), ",
       "por ejemplo --bbox \"-25.1367,-65.9613,-24.5644,-65.0146\"", call. = FALSE)
names(CAJA) <- c("la0", "lo0", "la1", "lo1")
if (CAJA[["la0"]] >= CAJA[["la1"]] || CAJA[["lo0"]] >= CAJA[["lo1"]])
  stop("--bbox: la primera esquina tiene que ser la suroeste (lat y lon mas chicas)", call. = FALSE)
ANIOS <- lista(arg("--anios", "1990,2000,2010,2020"))

script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
RPIPE <- normalizePath(file.path(dirname(script), ".."), winslash = "/")
SAL <- file.path(RPIPE, "outputs", "landsat", SLUG)
GPKG <- file.path(SAL, sprintf("landsat_%s.gpkg", SLUG))

setGDALconfig(c("GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR", "GDAL_HTTP_MAX_RETRY=4",
                "GDAL_HTTP_RETRY_DELAY=3", "CPL_VSIL_CURL_ALLOWED_EXTENSIONS=.TIF,.tif"))


token <- function() {
  request(SAS) |> req_retry(max_tries = 4) |> req_perform() |> resp_body_json() |> _$token
}


poligono <- function(g) {
  # geometria GeoJSON de la escena (Polygon o MultiPolygon) a sfc
  anillos <- if (g$type == "Polygon") list(g$coordinates) else g$coordinates
  st_sfc(st_multipolygon(lapply(anillos, function(p)
    lapply(p, function(r) do.call(rbind, lapply(r, function(x) unlist(x)[1:2]))))), crs = 4326)
}


tier <- function(f) {
  t <- f$properties[["landsat:collection_category"]]
  if (is.null(t)) sub(".*_", "", f$id) else t
}


buscar_ventana <- function(anio, d0, d1) {
  q <- list(collections = list("landsat-c2-l2"),
            bbox = unname(CAJA[c("lo0", "la0", "lo1", "la1")]),
            datetime = sprintf("%s/%s", d0, d1), limit = 100,
            query = list("eo:cloud_cover" = list(lt = 20),
                         platform = list("in" = as.list(PLATAFORMAS[[anio]]))))
  fs <- request(STAC) |> req_body_json(q) |> req_retry(max_tries = 4) |>
    req_perform() |> resp_body_json() |> _$features
  if (!length(fs)) return(fs)
  # primero las escenas que cubren el recuadro, despues Tier 1, menos nubes y
  # mas cerca de mitad de anio (mismo orden que ag_45)
  caja <- st_as_sfc(st_bbox(c(xmin = CAJA[["lo0"]], ymin = CAJA[["la0"]],
                              xmax = CAJA[["lo1"]], ymax = CAJA[["la1"]]), crs = 4326))
  # area plana en grados, como shapely en ag_45
  cob <- suppressMessages({
    sf_use_s2(FALSE)
    on.exit(suppressMessages(sf_use_s2(TRUE)), add = TRUE)
    vapply(fs, function(f)
      as.numeric(st_area(st_intersection(poligono(f$geometry), caja)) / st_area(caja)), 0)
  })
  fs <- fs[cob >= 0.3]
  cob <- cob[cob >= 0.3]
  t1 <- vapply(fs, tier, "") == "T1"
  if (sum(t1) >= 3) { fs <- fs[t1]; cob <- cob[t1] }
  centro <- as.Date(sprintf("%s-07-01", anio))
  nubes <- vapply(fs, function(f) f$properties[["eo:cloud_cover"]], 0)
  dist <- vapply(fs, function(f) abs(as.numeric(as.Date(substr(f$properties$datetime, 1, 10)) - centro)), 0)
  orden <- order(vapply(fs, tier, "") != "T1", -round(cob, 1), nubes, dist)
  fs <- fs[orden]
  for (i in seq_along(fs)) fs[[i]]$cob <- cob[orden][i]
  head(fs, MAX_ESCENAS)
}


buscar <- function(anio) {
  fs <- buscar_ventana(anio, sprintf("%s-01-01", anio), sprintf("%s-12-31", anio))
  meses <- 6
  if (!length(fs) && anio %in% names(VENTANA_RESERVA)) {
    meses <- VENTANA_RESERVA[[anio]]
    a <- as.integer(anio)
    fs <- buscar_ventana(anio, sprintf("%d-07-01", a - meses %/% 12), sprintf("%d-06-30", a + 1 + meses %/% 12))
    if (length(fs)) cat(sprintf("    sin escenas en el anio: ventana de reserva de %d meses\n", 2 * meses))
  }
  list(fs = fs, meses = meses)
}


leer <- function(href, tk, plantilla, metodo) {
  # Banda de la escena, recortada y reproyectada a la grilla lat/lon.
  s <- rast(sprintf("/vsicurl/%s?%s", href, tk))
  NAflag(s) <- 0
  e <- project(ext(plantilla), "EPSG:4326", crs(s))
  s <- crop(s, extend(e, 60))
  project(s, plantilla, method = metodo)
}


compuesto <- function(anio, plantilla) {
  b <- buscar(anio)
  tk <- token()
  pilas <- setNames(vector("list", length(BANDAS)), BANDAS)
  usadas <- list()
  for (f in b$fs) {
    a <- f$assets
    r <- tryCatch({
      qa <- leer(a$qa_pixel$href, tk, plantilla, "near")
      # bits de QA_PIXEL: 0 relleno, 1 nube dilatada, 3 nube, 4 sombra
      ok <- app(qa, function(v) !is.na(v) & v != 0 & bitwAnd(as.integer(v), 27L) == 0L)
      frac <- global(ok, "mean", na.rm = TRUE)[[1]]
      if (frac < 0.05) {
        cat(sprintf("    sin pixeles limpios: %s\n", f$id))
        NULL
      } else {
        for (k in names(BANDAS)) {
          v <- leer(a[[k]]$href, tk, plantilla, "bilinear") * 0.0000275 - 0.2
          v <- mask(v, ok, maskvalues = 0)
          v[v <= -0.19] <- NA
          pilas[[BANDAS[[k]]]] <- c(pilas[[BANDAS[[k]]]], list(v))
        }
        data.frame(anio = anio, escena = f$id, fecha = substr(f$properties$datetime, 1, 10),
                   plataforma = f$properties$platform, tier = tier(f),
                   nubes = f$properties[["eo:cloud_cover"]], cobertura = round(f$cob, 3),
                   limpio = round(frac, 3), ventana_meses = b$meses)
      }
    }, error = function(e) {   # una escena que no se puede leer no frena el resto
      cat(sprintf("    salteada %s: %s\n", f$id, conditionMessage(e)))
      NULL
    })
    if (!is.null(r)) {
      usadas[[length(usadas) + 1]] <- r
      cat(sprintf("    %s  %s  %4.1f %% nubes  %3.0f %% limpio\n", r$fecha, r$escena, r$nubes, 100 * r$limpio))
    }
  }
  if (!length(usadas)) return(NULL)
  med <- rast(lapply(pilas, function(p) median(rast(p), na.rm = TRUE)))
  names(med) <- BANDAS
  list(med = med, escenas = do.call(rbind, usadas))
}


a_bytes <- function(med) {
  # Reflectancia a 0-255 con el mismo estiramiento para todos los anios (ag_45).
  rgb <- med[[c("red", "green", "blue")]]
  x <- round(clamp(rgb / 0.25, 0, 1)^(1 / 1.6) * 255)
  x <- ifel(is.na(x), 0, x)
  x
}


main <- function() {
  dir.create(SAL, recursive = TRUE, showWarnings = FALSE)
  plantilla <- rast(xmin = CAJA[["lo0"]], xmax = CAJA[["lo1"]], ymin = CAJA[["la0"]], ymax = CAJA[["la1"]],
                    resolution = RES, crs = "EPSG:4326")
  cat(sprintf("%s: %d x %d pixeles, anios %s\n", SLUG, nrow(plantilla), ncol(plantilla),
              paste(ANIOS, collapse = ", ")))
  csv <- file.path(SAL, "escenas.csv")
  todas <- if (file.exists(csv)) read.csv(csv, colClasses = "character") else NULL

  for (anio in ANIOS) {
    t0 <- Sys.time()
    cat(sprintf("\n%s\n", anio))
    r <- compuesto(anio, plantilla)
    if (is.null(r)) {
      cat("  SIN ESCENAS\n")
      next
    }
    tif <- file.path(SAL, sprintf("landsat_%s.tif", anio))
    writeRaster(round(r$med * 10000), tif, overwrite = TRUE, datatype = "INT2S", NAflag = -32768,
                gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2", "TILED=YES"))

    todas <- rbind(todas[todas$anio != anio, , drop = FALSE],
                   data.frame(lapply(r$escenas, as.character)))
    write.csv(todas, csv, row.names = FALSE)
    cat(sprintf("  %d escenas (%s a %s)  %.1f %% sin dato  %.1f min\n", nrow(r$escenas),
                min(r$escenas$fecha), max(r$escenas$fecha),
                100 * global(is.na(r$med[["red"]]), "mean")[[1]],
                as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  }
  armar_gpkg(todas)
  cat(sprintf("\nEn %s\n", SAL))
  0L
}


armar_gpkg <- function(todas) {
  # Una capa RGB por anio, a partir de todos los landsat_<anio>.tif de la carpeta.
  # GDAL no reemplaza una tabla raster suelta dentro de un gpkg: se rehace entero.
  tifs <- sort(list.files(SAL, "^landsat_\\d{4}\\.tif$", full.names = TRUE))
  if (!length(tifs)) return(invisible())
  unlink(GPKG)
  for (tif in tifs) {
    anio <- sub("landsat_(\\d{4})\\.tif", "\\1", basename(tif))
    e <- todas[todas$anio == anio, ]
    writeRaster(a_bytes(rast(tif) / 10000), GPKG, datatype = "INT1U", filetype = "GPKG",
                overwrite = !file.exists(GPKG),
                gdal = c(sprintf("RASTER_TABLE=landsat_%s", anio), "TILE_FORMAT=PNG",
                         if (file.exists(GPKG)) "APPEND_SUBDATASET=YES",
                         sprintf("RASTER_DESCRIPTION=Landsat C2 L2, mediana de %d escenas, %s a %s",
                                 nrow(e), min(e$fecha), max(e$fecha))))
  }
  cat(sprintf("\n%s: %d capas, %.1f MB\n", GPKG, length(tifs), file.size(GPKG) / 1e6))
}


quit(status = main())


# CORRIDAS. No se hace source() de este script: termina con quit() y cerraria la
# sesion de R, y los argumentos no le llegarian. Desde la consola de R se lo
# llama con system2, parado en la raiz del repositorio:
#
#   setwd("C:/Users/edgardo/Documents/GitHub/bolsonespobreza")
#
#   # San Miguel de Tucuman
#   system2("Rscript", c("Rpipe/scripts/02_landsat_bbox.R",
#                        "--slug", "tucuman",
#                        "--bbox", "-27.2052,-65.8582,-26.549,-64.7727",
#                        "--anios", "1990,2000,2010,2020"))
#
#   # Tandil
#   system2("Rscript", c("Rpipe/scripts/02_landsat_bbox.R",
#                        "--slug", "tandil",
#                        "--bbox", "-37.476,-59.3611,-37.2073,-58.9167",
#                        "--anios", "1990,2000,2010,2020"))
#


# Desde una terminal, lo mismo:
#   Rscript Rpipe/scripts/02_landsat_bbox.R --slug tucuman --bbox -27.2052,-65.8582,-26.549,-64.7727
#   Rscript Rpipe/scripts/02_landsat_bbox.R --slug tandil --bbox -37.476,-59.3611,-37.2073,-58.9167
#   Rscript Rpipe/scripts/02_landsat_bbox.R --slug salta --bbox "-25.1367,-65.9613,-24.5644,-65.0146"

# Salida en Rpipe/outputs/landsat/<slug>/: landsat_<slug>.gpkg para QGIS.
