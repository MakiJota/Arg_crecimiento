# -*- coding: utf-8 -*-
# Paso 17 · MapBiomas Argentina contra la ciudad de GISD30 y las pruebas, 2020. Exploratorio:
# ningun numero es cifra del proyecto.
#
# FUENTE. MapBiomas Argentina, coleccion 2, cobertura y uso del suelo anual, 30 m (CC BY-SA 4.0).
# El bucket oficial (storage.googleapis.com/mapbiomas-public) responde 403 desde el 2026-11-02.
# Se lee de la copia de Source Cooperative (tristangruppwri/mapbiomas), que tiene 2019-2024 como
# COG en EPSG:4326 con los codigos originales sin reclasificar. Por eso solo 2020: la serie
# 1991-2010 la tiene Pedro (radios_mancha_mapbiomas, ag_24) en el OneDrive.
#
# QUE MIDE, sobre el marco de 11 (ciudad de 2020 mas 3 km) y la grilla de GISD30:
#   1. Coincidencia: urbano de MapBiomas (clase 24) contra lo construido de la ciudad de Angel,
#      contra toda la extension de Angel, contra la prueba 3 (p25) y contra construido + relleno.
#   2. Que dice MapBiomas debajo de cada parte de la ciudad: lo construido, la franja, el relleno
#      de 16. Sirve de control: cuanto de lo que GISD30 llama construido es cultivo (el regadio
#      que la revision visual encontro en Rawson, Mendoza, San Juan, Neuquen y Salta) y cuanto del
#      relleno cae sobre urbano, cultivo o agua.
#   3. Urbano de MapBiomas fuera de la ciudad de Angel.
#
# ENTRADAS  outputs/densidad/<slug>/ (11), outputs/reglas/<slug>/reglas_2020.tif (16)
# SALIDAS   outputs/mapbiomas/<slug>/mapbiomas_2020.tif (codigo de MapBiomas en la grilla de 11)
#           pruebas/mapbiomas/<slug>/REPORTE.md, tablas/; pruebas/mapbiomas/REPORTE.md (indice)
#
# Uso: Rscript Rpipe/scripts/17_mapbiomas.R [--ciudades salta,jujuy] [--rehacer]

Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"),
           GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR")
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
BASE <- file.path(RPIPE, "pruebas", "mapbiomas")
DENS <- file.path(RPIPE, "outputs", "densidad")
SAL <- file.path(RPIPE, "outputs", "mapbiomas")
REGLAS <- file.path(RPIPE, "outputs", "reglas")
CIUDADES <- if (is.na(match("--ciudades", args))) {
  sort(basename(dirname(list.files(DENS, "^ciudad\\.csv$", recursive = TRUE, full.names = TRUE))))
} else strsplit(arg("--ciudades", ""), ",")[[1]]
MB_URL <- "/vsicurl/https://data.source.coop/tristangruppwri/mapbiomas/mapbiomas-argentina/mapbiomas_argentina_%d/mapbiomas_argentina_%d.tif"
ANIO <- 2020
KM2 <- 900 / 1e6
P_C <- 25; MIN_CIUDAD <- 0.10          # prueba 3 central, como en 16

# grupos de clases de MapBiomas Argentina (leyenda de la coleccion 2)
GRUPO <- c(urbano = "24", cultivo = "9,15,19,21,36", agua = "33,34", natural = "3,4,6,11,12,63,66,73,77",
           sin_vegetacion = "25", no_observado = "27")
grupo_de <- function(v) {
  g <- rep(NA_character_, length(v))
  for (n in names(GRUPO)) g[v %in% as.integer(strsplit(GRUPO[[n]], ",")[[1]])] <- n
  g
}
GRUPOS <- names(GRUPO)
COL_G <- c(urbano = "#1f4e79", cultivo = "#c27ba0", agua = "#2532e4", natural = "#6fa65a",
           sin_vegetacion = "#db9a4f", no_observado = "#cfcdc6")


mb_de <- function(code, f) {
  # MapBiomas 2020 en la grilla de 11 (vecino mas cercano); se guarda y se reusa
  if (file.exists(f) && !REHACER) return(rast(f))
  r <- rast(sprintf(MB_URL, ANIO, ANIO))
  e <- as.vector(ext(project(as.polygons(ext(code), crs = crs(code)), "EPSG:4326")))
  r <- crop(r, ext(e[["xmin"]] - 0.01, e[["xmax"]] + 0.01, e[["ymin"]] - 0.01, e[["ymax"]] + 0.01))
  m <- project(r, code, method = "near")
  names(m) <- "mapbiomas"
  writeRaster(m, f, overwrite = TRUE, datatype = "INT1U", gdal = "COMPRESS=DEFLATE")
  rast(f)
}

jaccard <- function(a, b) { i <- sum(a & b); u <- sum(a | b); if (u > 0) i / u else NA }


una <- function(slug) {
  x <- cargar_densidad(RPIPE, slug)
  if (is.null(x)) return(NULL)
  NOMBRE <- x$nombre
  y <- x[[as.character(ANIO)]]
  dir <- file.path(BASE, slug); tab <- file.path(dir, "tablas")
  dir.create(tab, recursive = TRUE, showWarnings = FALSE)
  dsal <- file.path(SAL, slug); dir.create(dsal, recursive = TRUE, showWarnings = FALSE)
  t0 <- Sys.time()

  mb <- mb_de(y$code, file.path(dsal, sprintf("mapbiomas_%d.tif", ANIO)))
  code <- values(y$code)[, 1]; mbv <- values(mb)[, 1]
  g <- grupo_de(mbv)
  rr <- rast(file.path(REGLAS, slug, sprintf("reglas_%d.tif", ANIO)))
  relleno <- values(rr$hueco)[, 1] %in% 1:2 & values(rr$dist)[, 1] > 200 & code == 2
  # prueba 3 a p25: la franja de los radios densos
  t <- y$t; u <- t$km2_urb > 0 & !is.na(t$dens_urb) & t$km2_urb >= MIN_CIUDAD * t$km2_radio
  k <- quantile(t$dens_urb[u], P_C / 100, names = FALSE, type = 7)
  densos <- t$i_fila[t$km2_urb > 0 & !is.na(t$dens_urb) & t$dens_urb >= k]
  rid <- values(rasterize(y$v, y$code, field = "i"))[, 1]
  p3 <- code == 1 | (code == 2 & rid %in% densos)

  constr <- code == 1; angel <- code %in% 1:2; mbu <- !is.na(g) & g == "urbano"
  # que hay debajo de cada parte, en km2 por grupo de MapBiomas
  partes <- list(`built-up of the city` = constr, `fringe/captured of the city` = code == 2 & !relleno,
                 `fill (gaps of 60 m)` = relleno, `fill, dense tracts only` = relleno & rid %in% densos,
                 `built outside the city` = code == 3)
  comp <- do.call(rbind, lapply(names(partes), function(n) {
    m <- partes[[n]]
    data.frame(parte = n, grupo = GRUPOS, km2 = vapply(GRUPOS, function(gg) sum(m & !is.na(g) & g == gg) * KM2, 1),
               total_km2 = sum(m) * KM2)
  }))
  comp$pct <- 100 * comp$km2 / comp$total_km2
  write.csv(comp, file.path(tab, "composicion.csv"), row.names = FALSE)

  coin <- data.frame(
    medida = c("Built-up of the city (GISD30)", "Built-up + fill", "Test 3 at p25", "Angel extent"),
    km2 = c(sum(constr), sum(constr | relleno), sum(p3), sum(angel)) * KM2,
    mb_dentro_km2 = c(sum(constr & mbu), sum((constr | relleno) & mbu), sum(p3 & mbu), sum(angel & mbu)) * KM2,
    jaccard = c(jaccard(constr, mbu), jaccard(constr | relleno, mbu), jaccard(p3, mbu), jaccard(angel, mbu)))
  coin$pct_es_mb <- 100 * coin$mb_dentro_km2 / coin$km2
  mb_ciudad <- sum(mbu & angel) * KM2; mb_fuera <- sum(mbu & !angel) * KM2; mb_total <- sum(mbu) * KM2
  coin$pct_de_mb <- 100 * coin$mb_dentro_km2 / mb_total
  write.csv(coin, file.path(tab, "coincidencia.csv"), row.names = FALSE)

  # urbano de MapBiomas por radio, y densidad sobre ese urbano (censo 2022)
  ct <- tapply(mbu, factor(rid, levels = t$i_fila), sum)
  t$km2_mb_urbano <- ifelse(is.na(ct), 0, ct) * KM2
  t$dens_mb <- ifelse(t$km2_mb_urbano > 0, t$personas / t$km2_mb_urbano, NA)
  write.csv(t[, c("i_fila", "cod", "personas", "km2_radio", "km2_construido", "km2_abierto", "km2_mb_urbano", "dens_urb", "dens_mb")],
            file.path(tab, "radios.csv"), row.names = FALSE)

  cv <- function(n, gg) comp$pct[comp$parte == n & comp$grupo == gg]
  L <- c(sprintf("# %s · MapBiomas 2020 against the GISD30 city and the tests", NOMBRE), "",
    sprintf("Exploratory. None of these numbers are project figures (they are not in `CIFRAS_CANONICAS.json`). Generated by `Rpipe/scripts/17_mapbiomas.R`. MapBiomas Argentina collection 2, 2020, from the Source Cooperative copy (the official bucket answers 403). Run of %s. [All agglomerations](../REPORTE.md).", format(Sys.Date())), "",
    "## Agreement with MapBiomas urban areas (class 24)", "",
    sprintf("MapBiomas urban in the frame: %s km²; %s km² inside the Angel city and %s km² outside it.", f1(mb_total), f1(mb_ciudad), f1(mb_fuera)), "",
    tabla(c("GISD30 measure", "km²", "MapBiomas urban inside, km²", "% of the measure that MapBiomas calls urban", "% of MapBiomas urban it covers", "Jaccard"),
          lapply(seq_len(nrow(coin)), function(i) with(coin[i, ], c(medida, f1(km2), f1(mb_dentro_km2), f1(pct_es_mb), f1(pct_de_mb), f2(jaccard))))), "",
    sprintf("Test 3 at p%d uses the 2022 census: cut %s persons / km² urbanized.", P_C, f0(k)), "",
    "## What MapBiomas says under each part of the city", "",
    "% of the part's km² by MapBiomas group. *Crops* = temporary and perennial crops, pastures, the agriculture-pasture mosaic and forest plantations.", "",
    tabla(c("Part (GISD30, 2020)", "km²", paste0(GRUPOS, " %")),
          lapply(names(partes), function(n) c(n, f1(comp$total_km2[comp$parte == n][1]), vapply(GRUPOS, function(gg) f1(cv(n, gg)), "")))), "")
  writeLines(enc2utf8(L), file.path(dir, "REPORTE.md"), useBytes = TRUE)
  cat(sprintf("  %-22s listo (%.1f min)\n", slug, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  data.frame(slug = slug, nombre = NOMBRE, mb_total = mb_total, mb_fuera = mb_fuera,
             constr = coin$km2[1], constr_es_mb = coin$pct_es_mb[1], constr_cultivo = cv("built-up of the city", "cultivo"),
             relleno = coin$km2[2] - coin$km2[1], relleno_urbano = cv("fill (gaps of 60 m)", "urbano"),
             relleno_cultivo = cv("fill (gaps of 60 m)", "cultivo"), relleno_agua = cv("fill (gaps of 60 m)", "agua"),
             relleno_d_urbano = cv("fill, dense tracts only", "urbano"), relleno_d_cultivo = cv("fill, dense tracts only", "cultivo"),
             franja_urbano = cv("fringe/captured of the city", "urbano"),
             jac_constr = coin$jaccard[1], jac_rel = coin$jaccard[2], jac_p3 = coin$jaccard[3], jac_angel = coin$jaccard[4],
             p3 = coin$km2[3], p3_es_mb = coin$pct_es_mb[3], angel = coin$km2[4], angel_es_mb = coin$pct_es_mb[4])
}


cat(sprintf("MapBiomas %d · %d aglomerados\n", ANIO, length(CIUDADES)))
dir.create(BASE, recursive = TRUE, showWarnings = FALSE)
res <- do.call(rbind, lapply(CIUDADES, function(s) tryCatch(una(s), error = function(e) {
  cat("  ERROR", s, ":", conditionMessage(e), "\n"); NULL })))
res <- res[order(res$nombre), ]
f_res <- file.path(BASE, "resumen.csv")
if (file.exists(f_res) && !is.na(match("--ciudades", args))) {
  prev <- read.csv(f_res); res <- rbind(prev[!prev$slug %in% res$slug, names(res)], res); res <- res[order(res$nombre), ]
}
write.csv(res, f_res, row.names = FALSE)

img <- file.path(BASE, "img"); dir.create(img, showWarnings = FALSE)
lg <- rbind(data.frame(nombre = res$nombre, m = "built-up of the city", v = res$constr_es_mb),
            data.frame(nombre = res$nombre, m = "built-up + fill", v = 100 * (res$constr * res$constr_es_mb / 100 + res$relleno * res$relleno_urbano / 100) / (res$constr + res$relleno)),
            data.frame(nombre = res$nombre, m = "Angel extent", v = res$angel_es_mb))
lg$nombre <- factor(lg$nombre, levels = res$nombre[order(res$constr_es_mb)])
guardar(ggplot(lg, aes(v, nombre, colour = m)) + geom_point(size = 2.6) +
  scale_colour_manual(values = c(`built-up of the city` = "#1f4e79", `built-up + fill` = "#2a9d8f", `Angel extent` = "#8db3dd")) +
  scale_x_continuous(limits = c(0, 100)) +
  labs(x = "% that MapBiomas 2020 calls urban (class 24)", y = NULL, colour = NULL,
       title = "How much of the GISD30 city MapBiomas also calls urban, 2020",
       subtitle = "Low = GISD30 counts land that MapBiomas classifies as crops, natural cover or bare ground",
       caption = "MapBiomas Argentina collection 2 (Source Cooperative copy); GISD30 with Angel classes. Exploratory.") + tema,
  img, "coincidencia.png", w = 9, h = 8)
lc <- res; lc$nombre <- factor(lc$nombre, levels = res$nombre[order(res$constr_cultivo)])
guardar(ggplot(lc, aes(constr_cultivo, nombre)) + geom_col(fill = "#c27ba0", width = 0.65) +
  labs(x = "% of the GISD30 built-up of the city that MapBiomas 2020 classifies as crops or pasture", y = NULL,
       title = "Farmland inside what GISD30 calls built-up, 2020",
       subtitle = "The irrigated oases stand out: the visual check found the same", caption = "MapBiomas Argentina collection 2; GISD30. Exploratory.") + tema,
  img, "cultivo_en_construido.png", w = 9, h = 8)

ancla <- function(s) sprintf("[%s](%s/REPORTE.md)", res$nombre[res$slug == s], s)
L <- c("# MapBiomas 2020 against the GISD30 city and the tests, all agglomerations", "",
  sprintf("Exploratory. None of these numbers are project figures (they are not in `CIFRAS_CANONICAS.json`). Generated by `Rpipe/scripts/17_mapbiomas.R`. Run of %s. Method: [METODOS.md](../METODOS.md).", format(Sys.Date())), "",
  "**Source.** MapBiomas Argentina collection 2 (CC BY-SA 4.0), 2020, read from the Source Cooperative copy (`tristangruppwri/mapbiomas`, original class codes): the official bucket answers 403. That copy covers 2019-2024 only, so 1990-2010 wait for Pedro's tract tables (`radios_mancha_mapbiomas`).", "",
  "**Columns.** *Built % MB urban*: share of the GISD30 built-up of the city that MapBiomas calls urban. *Built % crops*: share that MapBiomas calls crops or pasture. *Fill*: the gap rule of step 16 (60 m, > 200 m from the edge, not on water) and what MapBiomas says under it, in all tracts and only in tracts above the test 3 cut (p25, census 2022). *Jaccard*: overlap / union with MapBiomas urban (1 = identical).", "",
  tabla(c("Agglomeration", "MB urban km²", "of which outside the city", "Built km²", "Built % MB urban", "Built % crops", "Fill km²", "Fill % MB urban", "Fill % crops", "Fill % water", "Fill in dense tracts: % MB urban", "% crops", "Fringe % MB urban", "Jaccard built", "Jaccard built+fill", "Jaccard test 3", "Jaccard Angel"),
        lapply(res$slug, function(s) with(res[res$slug == s, ], c(ancla(s), f1(mb_total), f1(mb_fuera), f1(constr), f1(constr_es_mb), f1(constr_cultivo),
          f1(relleno), f1(relleno_urbano), f1(relleno_cultivo), f1(relleno_agua), f1(relleno_d_urbano), f1(relleno_d_cultivo), f1(franja_urbano), f2(jac_constr), f2(jac_rel), f2(jac_p3), f2(jac_angel))))), "",
  "![Agreement](img/coincidencia.png)", "", "![Farmland in built-up](img/cultivo_en_construido.png)", "")
writeLines(enc2utf8(L), file.path(BASE, "REPORTE.md"), useBytes = TRUE)
cat("Escrito", file.path(BASE, "REPORTE.md"), "\n")
