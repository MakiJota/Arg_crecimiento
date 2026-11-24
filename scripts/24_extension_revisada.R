# -*- coding: utf-8 -*-
# Paso 24 · Perimetros revisados de los aglomerados (nuevo). Exploratorio: ningun numero es
# cifra del proyecto.
#
# Jonathan arma a mano, en QGIS, un perimetro nuevo por aglomerado: los radios censales que
# forman el aglomerado y su disolucion. Este paso los registra para que el pipeline los corra
# como una ciudad mas, con slug <slug>_rev, sin tocar el perimetro de analisis del proyecto:
#   - raw/boundaries/aglomerados_revisados.gpkg, capa perimetro (slug, nombre, provincia,
#     n_partes, km2, reemplaza, radios, censo_radios, fuente). "reemplaza" es el contorno del
#     proyecto al que sustituye: lib/cajas.R no lo cuenta como "otro aglomerado" en la caja.
#   - la fila <slug>_rev de cajas.md: caja = perimetro revisado + 10 km de cada lado (la misma
#     regla que las demas), contorno <contorno>_rev. Si la fila existe, se reescribe.
# Control: de que censo del paso 09 son los radios de la capa <slug> (codigo y personas
# iguales en todos). Los pasos siguientes cruzan los cuatro censos con el perimetro por
# geometria, no por codigo, asi que el censo de la capa no cambia nada aguas abajo.
#
# ENTRADAS  raw/adm/new_agloms.gpkg, capas <slug> (radios) y <slug>_dissolve (perimetro);
#           raw/boundaries/aglomerados.gpkg (07), outputs/censos/radios_censos.gpkg (09)
# SALIDAS   raw/boundaries/aglomerados_revisados.gpkg, la fila <slug>_rev de cajas.md
#
# Despues, la ciudad corre con los pasos de siempre nombrandola (--ciudades salta_rev); las
# corridas sin --ciudades la dejan afuera (ver revisados() en lib/cajas.R).
#
# Uso: Rscript Rpipe/scripts/24_extension_revisada.R --aglomerados salta

Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))
suppressPackageStartupMessages(library(sf))
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
SCRIPTS <- normalizePath(dirname(script), winslash = "/")
RPIPE <- dirname(SCRIPTS)
source(file.path(SCRIPTS, "lib", "cajas.R"))

args <- commandArgs(trailingOnly = TRUE)
arg <- function(nombre, defecto) {
  i <- match(nombre, args)
  if (is.na(i) || i == length(args)) defecto else args[i + 1]
}
ENTRADA <- arg("--entrada", file.path(RPIPE, "raw", "adm", "new_agloms.gpkg"))
AGLOS <- strsplit(arg("--aglomerados", "salta"), ",")[[1]]
SAL <- do.call(file.path, c(list(RPIPE), as.list(REVISADOS)))
CENSOS <- file.path(RPIPE, "outputs", "censos", "radios_censos.gpkg")
MARGEN <- 10000   # metros alrededor del perimetro, como las cajas de 07


utm <- function(lon, lat) sprintf("EPSG:%d", (if (lat < 0) 32700 else 32600) + floor((lon + 180) / 6) + 1)


caja_mas <- function(p, m) {
  # recuadro del perimetro mas m metros de cada lado, en grados (lat0, lon0, lat1, lon1)
  c <- st_coordinates(st_centroid(st_as_sfc(st_bbox(p))))
  u <- st_transform(p, utm(c[1], c[2]))
  b <- st_bbox(u); b[c("xmin", "ymin")] <- b[c("xmin", "ymin")] - m; b[c("xmax", "ymax")] <- b[c("xmax", "ymax")] + m
  g <- st_bbox(st_transform(st_as_sfc(b), 4326))
  round(c(g[["ymin"]], g[["xmin"]], g[["ymax"]], g[["xmax"]]), 4)
}


fila_cajas <- function(slug, contorno, caja, partes) {
  # escribe (o reescribe) la fila del slug en cajas.md
  f <- file.path(RPIPE, "cajas.md")
  l <- readLines(f, encoding = "UTF-8")
  nueva <- sprintf("| %s | %s | %.4f | %.4f | %.4f | %.4f | perimetro revisado + 10 km | %d |",
                   slug, contorno, caja[1], caja[2], caja[3], caja[4], partes)
  i <- which(startsWith(l, paste0("| ", slug, " |")))
  if (length(i)) l[i] <- nueva else {
    j <- max(which(startsWith(l, "| ")))
    l <- append(l, nueva, after = j)
  }
  con <- file(f, "w", encoding = "UTF-8"); writeLines(l, con); close(con)
}


per_proy <- st_read(file.path(RPIPE, "raw", "boundaries", "aglomerados.gpkg"), "perimetro", quiet = TRUE)
CENSOS_09 <- c("1991", "2001", "2010", "2022")
RAD09 <- if (file.exists(CENSOS)) setNames(lapply(CENSOS_09, function(y)
  st_drop_geometry(st_read(CENSOS, paste0("radios_", y), quiet = TRUE))[, c("cod", "personas")]), CENSOS_09) else list()
if (!length(RAD09)) CENSOS_09 <- character(0)
capas <- st_layers(ENTRADA)$name
prev <- if (file.exists(SAL)) st_read(SAL, "perimetro", quiet = TRUE) else NULL

for (s in AGLOS) {
  cj <- caja_de(RPIPE, s)
  if (!nzchar(cj$contorno)) stop(s, " no tiene contorno en cajas.md", call. = FALSE)
  for (k in c(s, paste0(s, "_dissolve")))
    if (!k %in% capas) stop("falta la capa ", k, " en ", ENTRADA, call. = FALSE)
  d <- st_make_valid(st_transform(st_read(ENTRADA, paste0(s, "_dissolve"), quiet = TRUE), 4326))
  rad <- st_read(ENTRADA, s, quiet = TRUE)
  g <- st_union(st_geometry(d))
  partes <- length(st_cast(g, "POLYGON"))
  base <- per_proy[per_proy$slug == cj$contorno, ]
  slug_c <- paste0(cj$contorno, "_rev")
  p <- st_sf(slug = slug_c, nombre = paste(base$nombre, "(revised extent)"), provincia = base$provincia,
             n_partes = partes, km2 = round(as.numeric(st_area(g)) / 1e6, 1), reemplaza = cj$contorno,
             radios = nrow(rad), censo_radios = NA_character_, fuente = paste0(basename(ENTRADA), ":", s, "_dissolve"), geometry = g)

  # control: de que censo del paso 09 son los radios de la capa (codigo y personas iguales)
  cod <- gsub(" ", "0", sprintf("%09s", as.character(rad$cod)))
  censo <- NA_character_
  for (y in CENSOS_09) {
    z <- RAD09[[y]]; m <- match(cod, z$cod)
    iguales <- sum(!is.na(m) & z$personas[m] == rad$personas, na.rm = TRUE)
    cat(sprintf("%s: radios de %s · %d de %d codigos coinciden, %d con las mismas personas\n",
                s, y, sum(!is.na(m)), nrow(rad), iguales))
    if (iguales == nrow(rad)) censo <- y
  }
  cat(sprintf("  la capa %s son los radios del censo %s\n", s, if (is.na(censo)) "? (ninguno coincide entero)" else censo))
  p$censo_radios <- censo
  ov <- as.numeric(st_area(st_intersection(g, st_make_valid(st_geometry(base))))) / 1e6
  cat(sprintf("  perimetro revisado %s km2 en %d partes; el del proyecto %s km2, %s km2 de el dentro del nuevo\n",
              p$km2, partes, base$km2, round(ov, 1)))

  caja <- caja_mas(p, MARGEN)
  fila_cajas(paste0(s, "_rev"), slug_c, caja, partes)
  cat(sprintf("  cajas.md: %s_rev  %s\n", s, paste(caja, collapse = ",")))
  if (!is.null(prev)) {
    prev <- prev[prev$slug != slug_c, ]
    for (k in setdiff(names(p), names(prev))) prev[[k]] <- rep(NA, nrow(prev))   # filas de una version anterior
  }
  prev <- if (is.null(prev) || !nrow(prev)) p else rbind(prev[, names(p)], p)
}

if (file.exists(SAL)) unlink(SAL)
st_write(prev, SAL, layer = "perimetro", quiet = TRUE)
cat("Escrito", SAL, "\n")
