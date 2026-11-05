# -*- coding: utf-8 -*-
# Paso 10 · Crosswalk de radios entre censos, y personas, hogares y viviendas de los cuatro
# censos sobre UNA grilla fija.
# Traduce a R scripts/ag_6_crosswalk.py (los pesos) y la funcion a_grilla_1991 de
# ag_12_noventa.py (como se usan), con la misma convencion de peso.
#
# POR QUE. Los radios se redibujan en cada censo (40.099 -> 46.582 -> 52.406 -> 66.502), asi
# que comparar un radio entre censos exige llevar los conteos a una misma grilla.
#
# EL PESO. Para un par de censos (viejo, nuevo), cruzando los poligonos:
#     w(i, j)       = area(viejo_i  interseccion  nuevo_j) / area(nuevo_j)
#     w_desde(i, j) = area(viejo_i  interseccion  nuevo_j) / area(viejo_i)
# w es la del proyecto: reparte cada radio NUEVO entre los viejos, y
#     valor_en_grilla_vieja[i] = sum_j w(i, j) * valor_nuevo[j]
# Cuando el radio nuevo cae entero dentro de uno viejo (subdivision), w = 1 y la cuenta es
# exacta. w_desde es la direccion inversa (reparte un radio viejo entre los nuevos) y es
# siempre una APROXIMACION areal: supone la gente pareja dentro del radio viejo. Por eso la
# grilla por defecto es la de 1991, la mas vieja: los otros tres censos llegan con w.
# Las areas se normalizan por la suma de las intersecciones, como en el original.
#
# EL UNIVERSO. Como ag_6_crosswalk.py, solo los radios que tocan los 31 aglomerados mas un
# anillo de 2 km (perimetro de raw/boundaries/aglomerados.gpkg, paso 07). Con --pais se
# hace el pais entero, que tarda bastante mas.
#
# DIFERENCIA CON LOS ARCHIVOS DE PEDRO. Los pesos de 3_datos_procesados/pesos_radios_*.csv.gz
# salen de los mismos poligonos (Source Cooperative / CEUR) y del mismo codigo COD_<anio>,
# pero con el perimetro sin simplificar (aglos_poligonos.parquet). Los de aca usan el
# perimetro simplificado de la plataforma (~200 m) con anillo de 2 km: el universo puede
# diferir en algun radio del borde. Dentro de los aglomerados el peso es el mismo.
#
# ENTRADAS  outputs/censos/radios_censos.gpkg (paso 09), raw/boundaries/aglomerados.gpkg (07)
# SALIDAS
#   outputs/censos/pesos_radios_<viejo>_<nuevo>.csv.gz   cod_desde, cod_hasta, w, w_desde,
#       desde, hasta. Codigos como texto: leerlos como texto o se pierden los ceros.
#   outputs/censos/radios_censos.gpkg, capa radios_grilla_<anio>: los radios de la grilla
#       en el universo, con slug del aglomerado (NA en el anillo), km2 y personas_<anio>,
#       hogares_<anio>, viviendas_<anio>, viv_habitadas_<anio> para los cuatro censos.
#       Los conteos interpolados tienen decimales: son repartos, no personas enteras.
#   outputs/censos/aglomerados_grilla_<anio>.csv   las mismas sumas por aglomerado
#
# Uso: Rscript Rpipe/scripts/10_crosswalk_radios.R [--grilla 1991] [--pais]
#        [--anillo 2000]

Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))
options(warn = 1)
suppressPackageStartupMessages({
  library(sf)
})

script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
RPIPE <- normalizePath(file.path(dirname(script), ".."), winslash = "/")
SAL <- file.path(RPIPE, "outputs", "censos")
GPKG <- file.path(SAL, "radios_censos.gpkg")
LIMITES <- file.path(RPIPE, "raw", "boundaries", "aglomerados.gpkg")

args <- commandArgs(trailingOnly = TRUE)
arg <- function(nombre, defecto) {
  i <- match(nombre, args)
  if (is.na(i) || i == length(args)) defecto else args[i + 1]
}
ANIOS <- c("1991", "2001", "2010", "2022")
GRILLA <- arg("--grilla", "1991")
PAIS <- "--pais" %in% args
ANILLO <- as.numeric(arg("--anillo", "2000"))   # metros
VARS <- c("personas", "hogares", "viviendas", "viv_habitadas")
CRS_METRICO <- 5347
ENTERO <- 0.995      # un radio nuevo "cae entero" en uno viejo si se lleva >= 99,5 % de el

if (!(GRILLA %in% ANIOS)) stop("--grilla tiene que ser uno de ", paste(ANIOS, collapse = ", "), call. = FALSE)
if (!file.exists(GPKG)) stop("no esta ", GPKG, ": correr antes 09_censos_radios.R", call. = FALSE)
if (!PAIS && !file.exists(LIMITES)) stop("no esta ", LIMITES, ": correr antes 07_limites_aglomerados.R", call. = FALSE)

miles <- function(x, d = 0) format(round(x, d), big.mark = ".", decimal.mark = ",", nsmall = d)


# ---- carga -------------------------------------------------------------------------

perimetros <- function() {
  p <- st_transform(st_read(LIMITES, layer = "perimetro", quiet = TRUE), CRS_METRICO)
  st_make_valid(p[, "slug"])
}


cargar <- function(y, region) {
  g <- st_read(GPKG, layer = paste0("radios_", y), quiet = TRUE)
  g <- st_transform(g[, c("cod", VARS)], CRS_METRICO)
  if (!is.null(region)) g <- g[lengths(st_intersects(g, region)) > 0, ]
  mal <- !st_is_valid(g)
  if (any(mal)) st_geometry(g)[mal] <- st_make_valid(st_geometry(g)[mal])
  g
}


# ---- pesos -------------------------------------------------------------------------

pesos <- function(viejo, nuevo, desde, hasta) {
  # tabla de pesos del par y cuantos radios nuevos caen enteros en uno viejo
  x <- suppressWarnings(st_intersection(
    st_sf(cod_desde = viejo$cod, geometry = st_geometry(viejo)),
    st_sf(cod_hasta = nuevo$cod, geometry = st_geometry(nuevo))))
  t <- data.frame(cod_desde = x$cod_desde, cod_hasta = x$cod_hasta, a = as.numeric(st_area(x)))
  t <- t[t$a > 0, ]
  t <- aggregate(a ~ cod_desde + cod_hasta, t, sum)   # una interseccion puede venir partida
  t$w <- t$a / ave(t$a, t$cod_hasta, FUN = sum)
  t$w_desde <- t$a / ave(t$a, t$cod_desde, FUN = sum)
  enteros <- sum(tapply(t$w, t$cod_hasta, max) >= ENTERO)
  t <- t[t$w >= 1e-6 | t$w_desde >= 1e-6, ]
  t$w <- round(t$w, 6)
  t$w_desde <- round(t$w_desde, 6)
  list(tabla = data.frame(t[, c("cod_desde", "cod_hasta", "w", "w_desde")], desde = desde, hasta = hasta),
       enteros = enteros)
}


a_grilla <- function(valor, cod, p, hacia_desde) {
  # lleva un conteo de un censo a la grilla del otro extremo del par.
  # hacia_desde = TRUE: valor del censo nuevo (cod_hasta) a la grilla vieja, con w (exacto
  # si hay subdivision). FALSE: del viejo (cod_desde) a la grilla nueva, con w_desde (areal).
  if (hacia_desde) {
    v <- valor[match(p$cod_hasta, cod)] * p$w
    tapply(v, p$cod_desde, sum)
  } else {
    v <- valor[match(p$cod_desde, cod)] * p$w_desde
    tapply(v, p$cod_hasta, sum)
  }
}


# ---- principal ---------------------------------------------------------------------

t0 <- Sys.time()
per <- if (PAIS) NULL else perimetros()
region <- if (PAIS) NULL else st_union(st_buffer(per, ANILLO))
cat(sprintf("Grilla %s · universo %s\n", GRILLA,
            if (PAIS) "pais entero" else sprintf("31 aglomerados + anillo de %s m", miles(ANILLO))))

censos <- lapply(setNames(ANIOS, ANIOS), function(y) {
  g <- cargar(y, region)
  cat(sprintf("  %s  %s radios en el universo\n", y, miles(nrow(g))))
  g
})

base <- censos[[GRILLA]]
out <- st_sf(cod = base$cod, geometry = st_geometry(base))
out$slug <- if (PAIS) NA_character_ else
  per$slug[vapply(st_intersects(st_point_on_surface(st_geometry(base)), per),
                  function(i) if (length(i)) i[1] else NA_integer_, 1L)]
out$km2 <- round(as.numeric(st_area(out)) / 1e6, 4)

control <- list()
cat(sprintf("\n%-11s%10s%10s%12s%16s%14s%8s\n", "par", "viejos", "nuevos", "pesos", "nuevos enteros", "personas", "seg"))
for (y in ANIOS) {
  g <- censos[[y]]
  if (y == GRILLA) {
    for (v in VARS) out[[paste0(v, "_", y)]] <- g[[v]]
    next
  }
  t1 <- Sys.time()
  desde <- min(y, GRILLA); hasta <- max(y, GRILLA)
  pr <- pesos(censos[[desde]], censos[[hasta]], desde, hasta)
  f <- file.path(SAL, sprintf("pesos_radios_%s_%s.csv.gz", desde, hasta))
  con <- gzfile(f, "w"); write.csv(pr$tabla, con, row.names = FALSE); close(con)
  hacia_desde <- GRILLA == desde
  for (v in VARS) {
    s <- a_grilla(g[[v]], g$cod, pr$tabla, hacia_desde)
    out[[paste0(v, "_", y)]] <- round(unname(s[out$cod]), 2)
    if (!all(is.na(g[[v]]))) out[[paste0(v, "_", y)]][is.na(s[out$cod])] <- 0   # sin interseccion
  }
  # control de conservacion: lo que el censo y tiene en los radios que tocan la grilla
  # tiene que llegar entero (con w); con w_desde se pierde lo que cae fuera del universo
  cods <- if (hacia_desde) unique(pr$tabla$cod_hasta) else unique(pr$tabla$cod_desde)
  origen <- sum(g$personas[g$cod %in% cods])
  llega <- sum(out[[paste0("personas_", y)]])
  nuevos <- nrow(censos[[hasta]])
  control[[y]] <- data.frame(censo = y, grilla = GRILLA, desde = desde, hasta = hasta,
                             pesos = nrow(pr$tabla), radios_nuevos = nuevos,
                             nuevos_enteros_pct = round(100 * pr$enteros / nuevos, 1),
                             personas_origen = origen, personas_en_grilla = round(llega),
                             dif_pct = round(100 * (llega / origen - 1), 3))
  cat(sprintf("%-11s%10s%10s%12s%14.1f %%%13.3f %%%8.0f\n", paste0(desde, "-", hasta),
              miles(nrow(censos[[desde]])), miles(nuevos), miles(nrow(pr$tabla)),
              100 * pr$enteros / nuevos, 100 * (llega / origen - 1),
              as.numeric(difftime(Sys.time(), t1, units = "secs"))))
  cat(sprintf("           escrito %s\n", basename(f)))
}

capa <- paste0("radios_grilla_", GRILLA)
st_write(st_transform(out, 4326), GPKG, layer = capa, quiet = TRUE, delete_layer = TRUE)

cols <- grep(paste0("^(", paste(VARS, collapse = "|"), ")_"), names(out), value = TRUE)
tab <- st_drop_geometry(out)
tab$slug[is.na(tab$slug)] <- "(anillo)"
agl <- aggregate(tab[, c("km2", cols)], list(slug = tab$slug), function(x) round(sum(x), 1))
agl <- cbind(agl[, "slug", drop = FALSE], radios = as.vector(table(tab$slug)[agl$slug]), agl[, -1])
csv <- file.path(SAL, sprintf("aglomerados_grilla_%s.csv", GRILLA))
write.csv(agl, csv, row.names = FALSE)
write.csv(do.call(rbind, control), file.path(SAL, sprintf("control_grilla_%s.csv", GRILLA)), row.names = FALSE)

cat(sprintf("\nUniverso sobre la grilla %s (%s radios):\n", GRILLA, miles(nrow(out))))
for (y in ANIOS) {
  s <- function(v) { x <- sum(out[[paste0(v, "_", y)]]); if (is.na(x)) "NA" else miles(x) }
  cat(sprintf("  %s  personas %s  hogares %s  viviendas %s  habitadas %s\n", y,
              s("personas"), s("hogares"), s("viviendas"), s("viv_habitadas")))
}
cat("\n  'nuevos enteros' es el porcentaje de radios del censo nuevo que caen enteros dentro")
cat("\n  de uno solo del viejo: ahi la grilla fija es una agregacion exacta, no un reparto.\n")
cat(sprintf("\nEscrito %s, capa %s\nEscrito %s\nEscrito %s\n(%.1f min)\n", GPKG, capa, csv,
            file.path(SAL, sprintf("control_grilla_%s.csv", GRILLA)),
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))
