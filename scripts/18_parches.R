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
#           outputs/parches/<slug>/bordes2_<anio>.tif (hueco hasta 500 m; d0 ... d500 cada 50 m; INT1U)
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


# Para la pestana Reglas del visor (version 2, 2026-11-19): la franja del borde de 0 a 500 m cada
# 50, parches de hasta mas de 100 ha y huecos de hasta 500 m. Por anio, bordes2_<anio>.tif con:
#   hueco  indice (1-12) del menor radio de GAP_M cuyo cierre euclidiano (dilatar y erosionar lo
#          construido con un disco de ese radio) tapa el pixel abierto; 0 ninguno o agua
#   d0 ... d500  clase de parche con esa franja: 0 no interior, 1-9 tamano (cortes CORTES2_HA;
#          9 = mas de 100 ha), 15 agua u orilla. Con D = 0 no hay franja.
D_BORDE <- seq(0, 500, 50)
GAP_M <- c(30, 60, 90, 120, 150, 180, 210, 240, 300, 360, 420, 500)
CORTES2_HA <- c(0.5, 1, 2, 5, 10, 20, 50, 100)
huecos2 <- function(code, rr) {
  b <- code == 1 | code == 3
  d1 <- distance(ifel(b, 1, NA))                    # m al construido mas cercano
  h <- ifel(b, 0, 0)
  for (k in rev(seq_along(GAP_M))) {
    r <- GAP_M[k]
    dil <- d1 <= r
    d2 <- distance(ifel(dil, NA, 1))                # m a lo que la dilatacion no alcanza
    h <- ifel(!b & dil & d2 > r, k, h)
  }
  ifel(rr$agua == 1, 0, h)
}
clase_parches2 <- function(code, rr, D) {
  interior <- code == 2 & rr$dist > D
  abierto <- ifel(interior & rr$agua == 0, 1, NA)
  p <- patches(abierto, directions = 4)
  f <- freq(p)
  ha <- f$count * prod(res(code)) / 1e4
  cl <- findInterval(ha, CORTES2_HA, left.open = TRUE) + 1     # 1..9
  r <- classify(p, cbind(f$value, cl))
  r <- ifel(is.na(r), 0, r)
  ifel(interior & rr$agua == 1, 15, r)
}


una <- function(slug) {
  t0 <- Sys.time()
  dir <- file.path(SAL, slug); dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  for (a in ANIOS) {
    f <- file.path(dir, sprintf("parches_%d.tif", a))
    if (file.exists(f) && !("--rehacer" %in% args && !"--solo-bordes" %in% args)) next
    code <- rast(file.path(DENS, slug, sprintf("code_%d.tif", a)))
    rr <- rast(file.path(REGLAS, slug, sprintf("reglas_%d.tif", a)))
    r <- rast(lapply(D_OPC, function(D) clase_parches(code, rr, D)))
    names(r) <- paste0("d", D_OPC)
    writeRaster(r, f, overwrite = TRUE, datatype = "INT1U", gdal = "COMPRESS=DEFLATE")
  }
  for (a in ANIOS) {
    f <- file.path(dir, sprintf("bordes2_%d.tif", a))
    if (file.exists(f) && !REHACER) next
    code <- rast(file.path(DENS, slug, sprintf("code_%d.tif", a)))
    rr <- rast(file.path(REGLAS, slug, sprintf("reglas_%d.tif", a)))
    r <- rast(c(list(huecos2(code, rr)), lapply(D_BORDE, function(D) clase_parches2(code, rr, D))))
    names(r) <- c("hueco", paste0("d", D_BORDE))
    writeRaster(r, f, overwrite = TRUE, datatype = "INT1U", gdal = "COMPRESS=DEFLATE")
  }
  cat(sprintf("  %-22s (%.1f min)\n", slug, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}


cat(sprintf("Parches del interior · %d aglomerados\n", length(CIUDADES)))
for (s in CIUDADES) tryCatch(una(s), error = function(e) cat("  ERROR", s, ":", conditionMessage(e), "\n"))
