# -*- coding: utf-8 -*-
# Paso 07 · Limites de los 31 aglomerados y cajas de las ciudades, en un GeoPackage.
# Script nuevo. No baja nada: junta lo que ya esta en el repo.
#
# DE DONDE SALEN LOS LIMITES. El repo no tiene shapes ni gpkg de los aglomerados: los
# originales son 3_datos_procesados/aglos_poligonos.parquet (perimetro de analisis) y
# aglos_poligonos_eph2010.parquet (EPH oficial), en el OneDrive, que arma
# scripts/ag_1_poligonos.py. Lo unico que esta en el repo es su copia para la
# plataforma: plataforma/datos/<slug>/base.js, que escribe ag_10_build.py a partir del
# "contorno" de ag_3_huella.py. Ese contorno es:
#   - el PERIMETRO DE ANALISIS (aglomerado EPH + la ciudad continua de 2022 que lo
#     desborda, decision del 2026-09-29), no el aglomerado EPH oficial;
#   - simplificado a 0,002 grados (~200 m) y con coordenadas redondeadas.
# Sirve para ver y para elegir "la ciudad" en 04; no sirve para cruzar con radios
# pixel a pixel. Para eso hacen falta los parquet del OneDrive.
#
# Salida: Rpipe/raw/boundaries/aglomerados.gpkg con dos capas:
#   perimetro  31 poligonos (slug, n_partes, km2), EPSG:4326
#   cajas      las cajas de Rpipe/cajas.md (slug, contorno, origen), EPSG:4326
#
# Uso: Rscript Rpipe/scripts/07_limites_aglomerados.R

Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))
suppressPackageStartupMessages({
  library(sf)
})

script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
SCRIPTS <- normalizePath(dirname(script), winslash = "/")
RPIPE <- dirname(SCRIPTS)
source(file.path(SCRIPTS, "lib", "cajas.R"))
DATOS <- file.path(dirname(RPIPE), "plataforma", "datos")
SAL <- file.path(RPIPE, "raw", "boundaries")
GPKG <- file.path(SAL, "aglomerados.gpkg")
dir.create(SAL, recursive = TRUE, showWarnings = FALSE)


contorno <- function(f) {
  # el JSON de BP_RECIBIR("base", slug, {...}) -> sf de una fila
  s <- paste(readLines(f, encoding = "UTF-8", warn = FALSE), collapse = "")
  j <- jsonlite::fromJSON(substr(s, regexpr("{", s, fixed = TRUE),
                                 max(gregexpr("}", s, fixed = TRUE)[[1]])),
                          simplifyVector = FALSE)
  gj <- jsonlite::toJSON(list(type = "Feature", properties = structure(list(), names = character()),
                              geometry = list(type = j$contorno$t, coordinates = j$contorno$c)),
                         auto_unbox = TRUE, digits = NA)
  g <- st_make_valid(st_read(as.character(gj), quiet = TRUE))
  st_sf(slug = basename(dirname(f)), geometry = st_geometry(g))
}


bases <- sort(list.files(DATOS, "^base\\.js$", recursive = TRUE, full.names = TRUE))
per <- do.call(rbind, lapply(bases, contorno))
st_crs(per) <- 4326
per$n_partes <- vapply(st_geometry(per), function(g) length(st_cast(st_sfc(g), "POLYGON")), 1L)
per$km2 <- round(as.numeric(st_area(per)) / 1e6, 1)
# nombre y provincia oficiales, del indice de la plataforma ({"slug":..,"nombre":..,"nomprov":..})
idx <- paste(readLines(file.path(dirname(DATOS), "index.html"), encoding = "UTF-8", warn = FALSE),
             collapse = "")
m <- regmatches(idx, gregexpr('\\{"slug":"[a-z_]+","cod":"[0-9_]+","nombre":"[^"]+","eph":"[^"]*","prov":"[^"]*","nomprov":"[^"]+"',
                              idx, perl = TRUE))[[1]]
nom <- unique(data.frame(slug = sub('.*"slug":"([^"]+)".*', "\\1", m),
                         nombre = sub('.*"nombre":"([^"]+)".*', "\\1", m),
                         provincia = sub('.*"nomprov":"([^"]+)".*', "\\1", m)))
nom <- nom[!duplicated(nom$slug), ]
per <- merge(per, nom, by = "slug", all.x = TRUE)
if (anyNA(per$nombre)) stop("sin nombre en index.html: ", paste(per$slug[is.na(per$nombre)], collapse = ", "))
per <- per[, c("slug", "nombre", "provincia", "n_partes", "km2")]

cj <- leer_cajas(RPIPE)
cajas <- st_sf(cj[, c("slug", "contorno", "origen")],
               geometry = st_sfc(lapply(seq_len(nrow(cj)), function(i)
                 st_polygon(list(rbind(c(cj$lon0[i], cj$lat0[i]), c(cj$lon1[i], cj$lat0[i]),
                                       c(cj$lon1[i], cj$lat1[i]), c(cj$lon0[i], cj$lat1[i]),
                                       c(cj$lon0[i], cj$lat0[i]))))), crs = 4326))

if (file.exists(GPKG)) unlink(GPKG)
st_write(per, GPKG, layer = "perimetro", quiet = TRUE)
st_write(cajas, GPKG, layer = "cajas", quiet = TRUE, append = TRUE)

# control: cada caja con contorno tiene que cubrir su perimetro entero
sin <- cajas[nzchar(cajas$contorno), ]
cubre <- vapply(seq_len(nrow(sin)), function(i) {
  p <- per[per$slug == sin$contorno[i], ]
  nrow(p) == 1 && isTRUE(st_covers(sin[i, ], p, sparse = FALSE)[1, 1])
}, TRUE)

cat(sprintf("Escrito %s\n  perimetro  %d aglomerados (%d de mas de una parte)\n  cajas      %d\n",
            GPKG, nrow(per), sum(per$n_partes > 1), nrow(cajas)))
if (all(cubre)) cat("  ok   cada caja cubre su perimetro entero\n") else
  cat("  AVISO  cajas que cortan su perimetro:", paste(sin$slug[!cubre], collapse = ", "), "\n")
