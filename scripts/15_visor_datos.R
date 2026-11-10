# -*- coding: utf-8 -*-
# Paso 15 · Datos del visor de las pruebas de densidad (docs/visor/index.html). Exploratorio:
# ningun numero es cifra del proyecto. Va solo al repo Arg_crecimiento, como el sitio (08).
#
# El visor calcula en el navegador las pruebas 1 y 2 y su comparacion para cualquier corte, a
# partir de lo que escribe 11. Por ciudad y anio, en Web Mercator (EPSG:3857) sobre la grilla
# del marco de 11 (la ciudad de 2020 mas 3 km):
#   clase_<anio>.png    R = codigo de 11 (1 construido de la ciudad, 2 franja o capturado de la
#                       ciudad, 3 construido fuera, 0 resto); G*256 + B = fila del radio (0 = ninguno)
#   landsat_<anio>.jpg  color verdadero del compuesto Landsat de 02, si existe, estirado 2-98 %
#   radios.json         por anio, una entrada por fila de radio: codigo, personas, km2 del
#                       radio, km2 construido y abierto de la ciudad en el radio, densidad sobre
#                       lo urbanizado
#   radios_<anio>.geojson  los radios como poligonos (recortados al marco, simplificados a 4 m,
#                       EPSG:4326), con el campo i que apunta a la fila de radios.json
# y datos/indice.json con nombre, limites, perimetro y que capas tiene cada ciudad.
#
# ENTRADAS  outputs/densidad/<slug>/ (11), outputs/landsat/<slug>/landsat_<anio>.tif (02)
# SALIDAS   docs/visor/datos/
#
# Uso: Rscript Rpipe/scripts/15_visor_datos.R [--ciudades salta,jujuy]

Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))
options(warn = 1)
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
SCRIPTS <- normalizePath(dirname(script), winslash = "/")
RPIPE <- dirname(SCRIPTS)
source(file.path(SCRIPTS, "lib", "cajas.R"))
source(file.path(SCRIPTS, "lib", "pruebas.R"))

args <- commandArgs(trailingOnly = TRUE)
arg <- function(nombre, defecto) {
  i <- match(nombre, args)
  if (is.na(i) || i == length(args)) defecto else args[i + 1]
}
DENS <- file.path(RPIPE, "outputs", "densidad")
LANDSAT <- file.path(RPIPE, "outputs", "landsat")
SAL <- file.path(RPIPE, "docs", "visor", "datos")
TODAS <- sort(basename(dirname(list.files(DENS, "^ciudad\\.csv$", recursive = TRUE, full.names = TRUE))))
CIUDADES <- if (is.na(match("--ciudades", args))) TODAS else strsplit(arg("--ciudades", ""), ",")[[1]]
MERC <- "EPSG:3857"


png_rgb <- function(r, archivo, tipo = "PNG", ...) {
  # escribe 3 bandas de 0-255 sin georreferencia (el visor usa los limites de indice.json)
  names(r) <- c("r", "g", "b")
  tmp <- tempfile(fileext = if (tipo == "PNG") ".png" else ".jpg")
  writeRaster(r, tmp, filetype = tipo, datatype = "INT1U", overwrite = TRUE, NAflag = NA, ...)
  file.copy(tmp, archivo, overwrite = TRUE)
  unlink(c(tmp, paste0(tmp, ".aux.xml")))
}


una <- function(slug) {
  t0 <- Sys.time()
  x <- cargar_densidad(RPIPE, slug)
  dir <- file.path(SAL, slug); dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  plantilla <- project(x[["2020"]]$code, MERC, method = "near")
  radios <- list(); landsat <- integer(0)
  for (a in ANIOS) {
    y <- x[[as.character(a)]]
    code <- project(y$code, plantilla, method = "near")
    rid <- project(rasterize(y$v, y$code, field = "i"), plantilla, method = "near")
    code <- ifel(is.na(code), 0, code); rid <- ifel(is.na(rid), 0, rid)
    if (global(rid, "max")[[1]] > 65535) stop("mas de 65535 radios en el marco")
    png_rgb(c(code, rid %/% 256, rid %% 256), file.path(dir, sprintf("clase_%d.png", a)), "PNG", gdal = "ZLEVEL=9")

    t <- y$t[order(y$t$i_fila), ]
    radios[[as.character(a)]] <- list(censo = CENSO[[as.character(a)]], ciudad_km2 = round(y$ciudad_km2, 3),
      cod = I(t$cod), personas = I(t$personas), construido = I(round(t$km2_construido, 4)), abierto = I(round(t$km2_abierto, 4)),
      area = I(round(t$km2_radio, 4)), dens = I(ifelse(is.na(t$dens_urb), -1, round(t$dens_urb, 1))))

    # los radios como poligonos: recortados al marco, simplificados a 4 m, en grados con 5
    # decimales (~1 m); solo el campo i, que apunta a la fila de radios.json
    v <- simplifyGeom(crop(y$v[, "i"], ext(y$code)), tolerance = 4, preserveTopology = TRUE)
    v <- project(v[!is.empty(v), ], "EPSG:4326")
    tmp <- tempfile(fileext = ".geojson")
    writeVector(v, tmp, filetype = "GeoJSON", options = c("COORDINATE_PRECISION=5", "RFC7946=YES"))
    file.copy(tmp, file.path(dir, sprintf("radios_%d.geojson", a)), overwrite = TRUE); unlink(tmp)

    f <- file.path(LANDSAT, slug, sprintf("landsat_%d.tif", a))
    if (file.exists(f)) {
      l <- project(rast(f)[[c("red", "green", "blue")]], plantilla, method = "bilinear")
      q <- global(l, quantile, probs = c(0.02, 0.98), na.rm = TRUE)
      l <- rast(lapply(1:3, function(b) {
        v <- (l[[b]] - q[b, 1]) / (q[b, 2] - q[b, 1])
        round(255 * clamp(v, 0, 1)^0.85)
      }))
      l <- ifel(is.na(l), 250, l)
      png_rgb(l, file.path(dir, sprintf("landsat_%d.jpg", a)), "JPEG", gdal = "QUALITY=82")
      landsat <- c(landsat, a)
    }
  }
  jsonlite::write_json(radios, file.path(dir, "radios.json"), auto_unbox = TRUE, digits = NA)

  e <- as.vector(ext(plantilla))
  esq <- project(vect(rbind(c(e[["xmin"]], e[["ymin"]]), c(e[["xmax"]], e[["ymax"]])), crs = MERC), "EPSG:4326")
  esq <- crds(esq)
  cont <- simplifyGeom(contorno_de(RPIPE, slug), tolerance = 0.0005)
  tmp <- tempfile(fileext = ".geojson"); writeVector(cont[, 0], tmp, filetype = "GeoJSON")
  cat(sprintf("  %-22s %s x %s px, landsat %s (%.1f min)\n", slug, ncol(plantilla), nrow(plantilla),
              if (length(landsat)) paste(landsat, collapse = ",") else "no",
              as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  list(slug = slug, nombre = x$nombre, ancho = ncol(plantilla), alto = nrow(plantilla),
       limites = list(c(esq[1, 2], esq[1, 1]), c(esq[2, 2], esq[2, 1])), landsat = I(landsat),
       perimetro = jsonlite::fromJSON(tmp, simplifyVector = FALSE))
}


cat(sprintf("Datos del visor · %d aglomerados\n", length(CIUDADES)))
dir.create(SAL, recursive = TRUE, showWarnings = FALSE)
nuevas <- lapply(CIUDADES, function(s) tryCatch(una(s), error = function(e) {
  cat("  ERROR", s, ":", conditionMessage(e), "\n"); NULL }))
names(nuevas) <- CIUDADES
f_ind <- file.path(SAL, "indice.json")
ind <- if (file.exists(f_ind)) jsonlite::read_json(f_ind) else list(ciudades = list())
previas <- setNames(ind$ciudades, vapply(ind$ciudades, `[[`, "", "slug"))
for (s in names(nuevas)) if (!is.null(nuevas[[s]])) previas[[s]] <- nuevas[[s]]
previas <- previas[order(vapply(previas, `[[`, "", "nombre"))]
jsonlite::write_json(list(generado = format(Sys.Date()), anios = ANIOS, censos = unname(CENSO),
                          ciudades = unname(previas)), f_ind, auto_unbox = TRUE, digits = NA)
cat("Escrito", f_ind, "\n")
