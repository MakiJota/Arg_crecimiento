# -*- coding: utf-8 -*-
# Paso 05 · Una ciudad de punta a punta: Landsat de su caja y metricas de Angel.
# Script nuevo. No calcula nada propio: lee la caja de Rpipe/cajas.md y corre, para
# cada ciudad pedida, los pasos que ya existen:
#   02_landsat_bbox.R  --slug <slug> --bbox <caja>    -> outputs/landsat/<slug>/
#   04_angel_atlas.R   --ciudades <slug>              -> outputs/angel/<slug>/
# Las carpetas son las de siempre, una por ciudad dentro de cada fuente. Para traer
# una ciudad nueva: agregar su fila en cajas.md y correr este paso con su slug.
#
# Si el Landsat de la ciudad ya esta (landsat_2020.tif), no se vuelve a bajar salvo
# con --rehacer-landsat. Una ciudad que falla no corta a las demas: al final se
# lista que salio y que no.
#
# Uso: Rscript Rpipe/scripts/05_per_muni.R --ciudades viedma,ushuaia
#        [--anios 1990,2000,2010,2020] [--rehacer-landsat] [--solo-angel]
# Requiere 01_gisd30_decadas.R.

script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
SCRIPTS <- normalizePath(dirname(script), winslash = "/")
RPIPE <- dirname(SCRIPTS)
source(file.path(SCRIPTS, "lib", "cajas.R"))

args <- commandArgs(trailingOnly = TRUE)
arg <- function(nombre, defecto) {
  i <- match(nombre, args)
  if (is.na(i) || i == length(args)) defecto else args[i + 1]
}
CIUDADES <- strsplit(arg("--ciudades", ""), ",")[[1]]
ANIOS <- arg("--anios", "1990,2000,2010,2020")
REHACER <- "--rehacer-landsat" %in% args
SOLO_ANGEL <- "--solo-angel" %in% args
RSCRIPT <- file.path(R.home("bin"), "Rscript")

if (!length(CIUDADES) || !all(nzchar(CIUDADES)))
  stop("falta --ciudades. Las de Rpipe/cajas.md: ",
       paste(leer_cajas(RPIPE)$slug, collapse = ", "), call. = FALSE)


paso <- function(nombre, ...) {
  # corre un paso numerado en un proceso aparte; devuelve TRUE si termino bien
  st <- system2(RSCRIPT, c(file.path(SCRIPTS, nombre), ...))
  identical(as.integer(st), 0L)
}


una <- function(slug) {
  c <- caja_de(RPIPE, slug)
  caja <- sprintf("%.4f,%.4f,%.4f,%.4f", c$lat0, c$lon0, c$lat1, c$lon1)
  cat(sprintf("\n==== %s  caja %s  (%s)\n", slug, caja, c$origen))
  t0 <- Sys.time()
  hay <- file.exists(file.path(RPIPE, "outputs", "landsat", slug, "landsat_2020.tif"))
  if (!SOLO_ANGEL && (REHACER || !hay)) {
    if (!paso("02_landsat_bbox.R", "--slug", slug, "--bbox", caja, "--anios", ANIOS))
      return("fallo Landsat")
  } else cat("  Landsat ya esta, no se baja\n")
  if (!paso("04_angel_atlas.R", "--ciudades", slug, "--anios", ANIOS)) return("fallo Angel")
  sprintf("ok (%.0f min)", as.numeric(difftime(Sys.time(), t0, units = "mins")))
}


res <- vapply(CIUDADES, una, "")
cat("\n==== resultado\n")
for (s in names(res)) cat(sprintf("  %-22s %s\n", s, res[[s]]))
quit(status = if (all(startsWith(res, "ok"))) 0L else 1L)
