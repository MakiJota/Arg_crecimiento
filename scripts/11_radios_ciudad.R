# -*- coding: utf-8 -*-
# Paso 11 · Cuanta ciudad de Angel cae en cada radio censal, por aglomerado y censo.
# Script nuevo. Es la base de las pruebas 12 (densidad por radio) y 13 (franja densa).
#
# POR CIUDAD Y ANIO (GISD30 1990 con censo 1991, 2000-2001, 2010-2010, 2020-2022):
#   1. "La ciudad" de 04: manchas 8-conexas de urbano + suburbano + franja + capturado que
#      tocan el perimetro de analisis, con la regla de mancha compartida de 04 (en una mancha
#      que toca otro perimetro, los pixeles mas cerca del otro son del otro).
#   2. Codigo por pixel: 1 construido de la ciudad (urbano, suburbano), 2 abierto de la
#      ciudad (franja, capturado), 3 construido fuera de la ciudad (incluye rural construido),
#      0 resto. Recortado al MARCO: la ciudad de 2020 mas 3 km, el mismo en los cuatro anios.
#   3. Por radio que toca el marco: km2 de cada codigo dentro del radio, personas, hogares,
#      viviendas y densidades (bruta, sobre lo urbanizado, sobre lo construido).
#
# AREAS. Por defecto cada pixel de 30 m va entero al radio que contiene su centro (rapido:
# minutos por ciudad). Con --exacto se usa la fraccion exacta de pixel (terra::extract
# exact = TRUE), mucho mas lento. En Salta la diferencia se mide en el reporte de 12.
#
# ENTRADAS  outputs/angel/<slug>/angel_<anio>.tif (04 o 04b), outputs/censos/radios_censos.gpkg
#           (09), raw/boundaries/aglomerados.gpkg (07), cajas.md
# SALIDAS   outputs/densidad/<slug>/code_<anio>.tif      el codigo por pixel, en el marco
#           outputs/densidad/<slug>/radios_<anio>.gpkg    los radios del marco (con i = fila)
#           outputs/densidad/<slug>/radios_<anio>.csv     una fila por radio
#           outputs/densidad/<slug>/ciudad.csv            km2 de la ciudad entera por anio
#
# Uso: Rscript Rpipe/scripts/11_radios_ciudad.R [--ciudades salta,jujuy] [--exacto]
#        sin --ciudades: todas las de cajas.md con contorno y con salida de 04

Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))
options(warn = 1)
suppressPackageStartupMessages({
  library(terra)
  library(sf)
})
sf_use_s2(FALSE)   # los poligonos censales traen anillos que s2 rechaza; GEOS los acepta

script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
SCRIPTS <- normalizePath(dirname(script), winslash = "/")
RPIPE <- dirname(SCRIPTS)
source(file.path(SCRIPTS, "lib", "cajas.R"))

args <- commandArgs(trailingOnly = TRUE)
arg <- function(nombre, defecto) {
  i <- match(nombre, args)
  if (is.na(i) || i == length(args)) defecto else args[i + 1]
}
ANIOS <- c(1990, 2000, 2010, 2020)
CENSO <- c("1990" = "1991", "2000" = "2001", "2010" = "2010", "2020" = "2022")
GPKG <- file.path(RPIPE, "outputs", "censos", "radios_censos.gpkg")
ANGEL <- file.path(RPIPE, "outputs", "angel")
SAL <- file.path(RPIPE, "outputs", "densidad")
EXACTO <- "--exacto" %in% args
MARGEN <- 3000   # metros alrededor de la ciudad de 2020

cj_todas <- leer_cajas(RPIPE)
CIUDADES <- if (is.na(match("--ciudades", args))) {
  cj_todas$slug[nzchar(cj_todas$contorno) & file.exists(file.path(ANGEL, cj_todas$slug, "angel_2020.tif"))]
} else strsplit(arg("--ciudades", ""), ",")[[1]]
if (!file.exists(GPKG)) stop("no esta ", GPKG, ": correr antes 09_censos_radios.R", call. = FALSE)


la_ciudad <- function(m, cont, otros, ajeno) {
  # como en 04: las manchas de m que tocan el contorno; en las que tocan tambien otro
  # perimetro, se quedan solo los pixeles mas cerca del propio
  p <- patches(ifel(m, 1, NA), directions = 8)
  ids <- unique(na.omit(extract(p, cont, touches = TRUE)[, 2]))
  dentro <- ifel(is.na(p), 0, p %in% ids)
  if (!is.null(ajeno)) {
    suyos <- unique(na.omit(extract(p, otros, touches = TRUE)[, 2]))
    comun <- intersect(ids, suyos)
    if (length(comun)) dentro <- dentro & !(ifel(is.na(p), 0, p %in% comun) & ajeno)
  }
  dentro
}


areas <- function(code, v) {
  # km2 de cada codigo (0-3) dentro de cada radio: matriz radios x codigos
  if (EXACTO) {
    e <- extract(code, v, exact = TRUE)
    e <- e[!is.na(e[[2]]), ]
    km2 <- tapply(e$fraction * prod(res(code)) / 1e6,
                  list(factor(e$ID, levels = v$i), factor(e[[2]], levels = 0:3)), sum)
  } else {
    rid <- rasterize(v, code, field = "i")
    ct <- crosstab(c(rid, code), long = TRUE)
    names(ct) <- c("i", "code", "n")
    km2 <- tapply(ct$n * prod(res(code)) / 1e6,
                  list(factor(ct$i, levels = v$i), factor(ct$code, levels = 0:3)), sum)
  }
  km2[is.na(km2)] <- 0
  km2
}


ciudad <- function(slug) {
  t0 <- Sys.time()
  cj <- caja_de(RPIPE, slug)
  dir <- file.path(SAL, slug)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  r0 <- rast(file.path(ANGEL, slug, "angel_2020.tif"))
  cont <- project(contorno_de(RPIPE, slug), crs(r0))
  otros <- otros_de(RPIPE, slug)
  ajeno <- NULL
  if (!is.null(otros) && nrow(otros)) {
    otros <- project(otros, crs(r0))
    ajeno <- distance(rasterize(otros, r0, touches = TRUE)) < distance(rasterize(cont, r0, touches = TRUE))
  } else otros <- NULL
  ciu <- function(cls) la_ciudad(cls %in% c(1, 2, 4, 5), cont, otros, ajeno)

  marco <- intersect(ext(trim(ifel(ciu(r0) == 1, 1, NA))) + MARGEN, ext(r0))
  m <- as.vector(marco)
  marco_sf <- st_as_sfc(st_bbox(c(xmin = m[["xmin"]], ymin = m[["ymin"]], xmax = m[["xmax"]], ymax = m[["ymax"]]),
                                crs = st_crs(crs(r0))))
  cat(sprintf("\n%s  (marco %s x %s km%s)\n", slug, round((m[["xmax"]] - m[["xmin"]]) / 1000),
              round((m[["ymax"]] - m[["ymin"]]) / 1000),
              if (is.null(otros)) "" else paste0("; mancha compartida con ", paste(otros$slug, collapse = ", "))))

  tot <- list()
  for (a in ANIOS) {
    cls <- rast(file.path(ANGEL, slug, sprintf("angel_%d.tif", a)))
    dentro <- ciu(cls)
    code <- ifel(dentro == 1, ifel(cls %in% c(1, 2), 1, 2), ifel(cls %in% c(1, 2, 3), 3, 0))
    code <- crop(code, marco)
    names(code) <- "code"

    g <- st_read(GPKG, layer = paste0("radios_", CENSO[[as.character(a)]]), quiet = TRUE,
                 wkt_filter = st_as_text(st_transform(marco_sf, 4326)))
    g <- st_make_valid(st_transform(g[, c("cod", "personas", "hogares", "viviendas", "viv_habitadas")], crs(r0)))
    g <- g[lengths(st_intersects(g, marco_sf)) > 0, ]
    v <- vect(g)
    v$i <- seq_len(nrow(v))
    km2 <- areas(code, v)
    t <- data.frame(i_fila = v$i, anio = a, censo = CENSO[[as.character(a)]], cod = g$cod,
                    personas = g$personas, hogares = g$hogares, viviendas = g$viviendas,
                    viv_habitadas = g$viv_habitadas, km2_radio = as.numeric(st_area(g)) / 1e6,
                    km2_construido = km2[, "1"], km2_abierto = km2[, "2"], km2_otro_construido = km2[, "3"])
    t$km2_urb <- t$km2_construido + t$km2_abierto
    t$dens_bruta <- t$personas / t$km2_radio
    t$dens_urb <- ifelse(t$km2_urb > 0, t$personas / t$km2_urb, NA)
    t$dens_construido <- ifelse(t$km2_construido > 0, t$personas / t$km2_construido, NA)

    writeRaster(code, file.path(dir, sprintf("code_%d.tif", a)), overwrite = TRUE, datatype = "INT1U",
                gdal = "COMPRESS=DEFLATE")
    writeVector(v[, c("i", "cod")], file.path(dir, sprintf("radios_%d.gpkg", a)), overwrite = TRUE)
    write.csv(t, file.path(dir, sprintf("radios_%d.csv", a)), row.names = FALSE)
    ciudad_km2 <- global(dentro, "sum", na.rm = TRUE)[[1]] * prod(res(cls)) / 1e6
    tot[[as.character(a)]] <- data.frame(slug = slug, anio = a, ciudad_km2 = ciudad_km2,
                                         en_radios_km2 = sum(t$km2_urb), radios = nrow(t),
                                         radios_ciudad = sum(t$km2_urb > 0), areas = if (EXACTO) "exacta" else "pixel")
    cat(sprintf("  %d  %s radios, %s tocan la ciudad; ciudad %.1f km2, en radios %.1f km2\n", a,
                nrow(t), sum(t$km2_urb > 0), ciudad_km2, sum(t$km2_urb)))
  }
  write.csv(do.call(rbind, tot), file.path(dir, "ciudad.csv"), row.names = FALSE)
  cat(sprintf("  (%.1f min)\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}

cat(sprintf("Radios y ciudad · %d aglomerados · areas %s\n", length(CIUDADES),
            if (EXACTO) "exactas" else "por pixel entero"))
for (s in CIUDADES) tryCatch(ciudad(s), error = function(e) cat("  ERROR", s, ":", conditionMessage(e), "\n"))
