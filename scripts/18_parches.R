# -*- coding: utf-8 -*-
# Paso 18 · Tamano de los parches de espacio abierto del interior de la ciudad, para las reglas
# del visor de cuatro ciudades (docs/visor/cuatro.html). Exploratorio: ningun numero es cifra
# del proyecto.
#
# La franja del borde (espacio abierto a <= D m del limite de la ciudad, medido con la distancia
# del paso 16) queda como franja. El espacio abierto MAS ALLA de D se agrupa en parches (pixeles
# abiertos que se tocan por un lado, 4 vecinos) y cada pixel recibe la clase de tamano de su
# parche. Con 8 vecinos los pixeles sueltos que se tocan en diagonal arman redes grandes y casi
# nada se rellena (Salta 1990, D 200: parches <= 2 ha, 2,7 km2 con 8 vecinos, 3,9 con 4). El visor
# rellena como construido los parches chicos de los radios densos y deja abiertos los grandes
# (plazas, parques, cauces). El agua y su orilla (mascara del paso 16) no se rellenan nunca.
#
# Por anio y por D (100, 200, 400 m), una capa con la clase del pixel abierto de la ciudad:
#   0 no es interior (franja del borde, construido o fuera de la ciudad)
#   1 parche <= 0,5 ha, 2 <= 1 ha, 3 <= 2 ha, 4 <= 5 ha, 5 <= 20 ha, 6 > 20 ha
#   7 agua u orilla en el interior
#
# ENTRADAS  outputs/densidad/<slug>/code_<anio>.tif (11), outputs/reglas/<slug>/reglas_<anio>.tif (16)
# SALIDAS   outputs/parches/<slug>/parches_<anio>.tif (capas d100, d200, d400; INT1U)
#
# Uso: Rscript Rpipe/scripts/18_parches.R [--ciudades salta,jujuy] [--rehacer]

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
REHACER <- "--rehacer" %in% args
DENS <- file.path(RPIPE, "outputs", "densidad")
REGLAS <- file.path(RPIPE, "outputs", "reglas")
SAL <- file.path(RPIPE, "outputs", "parches")
TODAS <- sort(basename(dirname(list.files(DENS, "^ciudad\\.csv$", recursive = TRUE, full.names = TRUE))))
CIUDADES <- if (is.na(match("--ciudades", args))) TODAS else strsplit(arg("--ciudades", ""), ",")[[1]]
D_OPC <- c(100, 200, 400)
CORTES_HA <- c(0.5, 1, 2, 5, 20)


clase_parches <- function(code, rr, D) {
  interior <- code == 2 & rr$dist > D
  abierto <- ifel(interior & rr$agua == 0, 1, NA)
  p <- patches(abierto, directions = 4)
  f <- freq(p)
  ha <- f$count * prod(res(code)) / 1e4
  cl <- findInterval(ha, CORTES_HA, left.open = TRUE) + 1     # 1..6
  r <- classify(p, cbind(f$value, cl))
  r <- ifel(is.na(r), 0, r)
  ifel(interior & rr$agua == 1, 7, r)
}


una <- function(slug) {
  t0 <- Sys.time()
  dir <- file.path(SAL, slug); dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  for (a in ANIOS) {
    f <- file.path(dir, sprintf("parches_%d.tif", a))
    if (file.exists(f) && !REHACER) next
    code <- rast(file.path(DENS, slug, sprintf("code_%d.tif", a)))
    rr <- rast(file.path(REGLAS, slug, sprintf("reglas_%d.tif", a)))
    r <- rast(lapply(D_OPC, function(D) clase_parches(code, rr, D)))
    names(r) <- paste0("d", D_OPC)
    writeRaster(r, f, overwrite = TRUE, datatype = "INT1U", gdal = "COMPRESS=DEFLATE")
  }
  cat(sprintf("  %-22s (%.1f min)\n", slug, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}


cat(sprintf("Parches del interior · %d aglomerados\n", length(CIUDADES)))
for (s in CIUDADES) tryCatch(una(s), error = function(e) cat("  ERROR", s, ":", conditionMessage(e), "\n"))
