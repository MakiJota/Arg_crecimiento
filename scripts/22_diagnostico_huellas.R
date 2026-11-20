# -*- coding: utf-8 -*-
# Paso 22 · Diagnostico de huellas de edificios (Overture) contra el construido de GISD30 2020
# y el censo 2022, por radio censal, en los 31 aglomerados. Exploratorio: ningun numero es cifra
# del proyecto. Sirve para pensar el "tope por vivienda" (regla 3A): cuantos pixeles construidos
# por vivienda son plausibles en un radio casi vacio, y si los cortes por percentil de cada ciudad
# (p75, p90, p95) equivalen a valores fisicos parecidos entre ciudades.
#
# Que hace, por ciudad:
#   1. Lee code_2020.tif (30 m; 0 resto, 1 construido de la ciudad, 2 abierto de la ciudad,
#      3 construido fuera de la ciudad), los radios 2020 (censo 2022) y su tabla.
#   2. Lee las huellas de Overture (edificios.gpkg) por tramos de fid, las proyecta a UTM y:
#      - asigna cada huella al radio que contiene su centroide (busqueda en una grilla de 10 m
#        alineada a code_2020) y suma su area exacta y su cantidad por radio;
#      - la rasteriza a 10 m (presencia, centro de celda) y agrega de a 3x3: cuantas de las 9
#        celdas de 10 m de cada pixel de 30 m tienen huella (estimador del area cubierta);
#      - un pixel "tiene huella" si alguna celda de 10 m esta cubierta o si cae en el
#        centroide (las huellas chicas, < 100 m2, pueden no tocar ningun centro de celda).
#      Las huellas de mas de 1 ha se cuentan aparte (en OSM a veces una manzana entera es un
#      "edificio").
#   3. Lee el uso del suelo de Overture (uso.gpkg) y los aeropuertos (aeropuertos.gpkg),
#      rasteriza a 30 m cuatro grupos con prioridad aeropuerto > no residencial > residencial >
#      agro > verde, y mide la parte del construido de cada radio en cada grupo. Se descartan los
#      poligonos de uso de mas de 50 km2 (en Salta un "farmland" de OSM cubre todo el valle).
#   4. Escribe una fila por radio y una fila de acuerdo GISD30-huellas por ciudad.
# Despues junta las 31 ciudades: percentiles dentro de cada ciudad de pixeles construidos por
# vivienda y de m2 de huella por vivienda, simulacion del tope "recortar por encima del p90 de la
# ciudad hasta el p90" y REPORTE.md con tablas y figuras.
#
# ENTRADAS  outputs/densidad/<slug>/ (11), outputs/overture/<slug>/ (20)
# SALIDAS   pruebas/diagnostico_huellas/REPORTE.md, img/, radios.csv (una fila por radio y
#           ciudad), ciudades.csv (resumen por ciudad), acuerdo.csv, percentiles.csv, tope.csv,
#           y ciudades/<slug>_*.csv (cache por ciudad; --rehacer los recalcula)
#
# Uso: Rscript Rpipe/scripts/22_diagnostico_huellas.R [--ciudades salta,rosario] [--rehacer]
#          [--solo-reporte]

Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))
options(warn = 1)
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
SCRIPTS <- normalizePath(dirname(script), winslash = "/")
RPIPE <- dirname(SCRIPTS)
source(file.path(SCRIPTS, "lib", "cajas.R"))
source(file.path(SCRIPTS, "lib", "pruebas.R"))
suppressPackageStartupMessages(library(data.table))

args <- commandArgs(trailingOnly = TRUE)
TODAS <- sort(basename(list.dirs(file.path(RPIPE, "outputs", "densidad"), recursive = FALSE)))
i <- match("--ciudades", args)
CIUDADES <- if (is.na(i)) TODAS else strsplit(args[i + 1], ",")[[1]]
CIUDADES <- c(setdiff(CIUDADES, "buenos_aires"), intersect(CIUDADES, "buenos_aires"))  # BA al final
REHACER <- "--rehacer" %in% args
SOLO_REPORTE <- "--solo-reporte" %in% args

SAL <- file.path(RPIPE, "pruebas", "diagnostico_huellas")
IMG <- file.path(SAL, "img"); CACHE <- file.path(SAL, "ciudades")
dir.create(IMG, recursive = TRUE, showWarnings = FALSE)
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)

MIN_CIUDAD <- 0.10     # radio "de la ciudad": km2_urb >= 10 % de su area
GRANDE <- 10000        # m2: huellas de mas de 1 ha, contadas aparte
TRAMO <- 400000        # huellas por lectura
NR_DOM <- 0.25         # radio dominado por uso no residencial: >= 25 % de su construido en uso NR
PX_M2 <- 900
LU_MAX <- 50e6         # m2: poligonos de uso del suelo de mas de 50 km2 se descartan (mantos regionales de OSM)

q7 <- function(x, p) if (length(x)) as.numeric(quantile(x, p / 100, type = 7, names = FALSE)) else NA_real_
pc <- function(a, b) ifelse(b > 0, 100 * a / b, NA_real_)

# grupos de uso del suelo de Overture (subtype / clase)
NR_SUB <- c("developed", "education", "medical", "military", "religious", "cemetery", "transportation",
            "landfill", "resource_extraction", "entertainment")
AGRO_SUB <- c("agriculture", "aquaculture")
AGRO_CLASE <- c("vineyard", "orchard", "greenhouse_horticulture", "plant_nursery", "allotments")
VERDE_SUB <- c("park", "recreation", "golf", "pedestrian", "managed", "protected", "campground",
               "winter_sports", "horticulture", "construction")
grupo_uso <- function(sub, cl) {
  g <- rep(NA_character_, length(sub))
  g[sub %in% VERDE_SUB] <- "verde"
  g[sub == "residential"] <- "res"
  g[sub %in% AGRO_SUB | cl %in% AGRO_CLASE] <- "agro"
  g[sub %in% NR_SUB | cl %in% c("stadium", "construction")] <- "nr"
  g
}


# ---------- una ciudad ----------
procesar <- function(slug) {
  t0 <- Sys.time()
  x <- cargar_densidad(RPIPE, slug)
  y <- x[["2020"]]
  code <- y$code; v <- y$v
  tb <- as.data.table(y$t)
  crsU <- crs(code)
  nc30 <- ncol(code)
  t10 <- disagg(rast(code), 3)
  nc10 <- ncol(t10)
  cv <- values(code, mat = FALSE)
  r30 <- values(rasterize(v, code, field = "i"), mat = FALSE)
  r10 <- rasterize(v, t10, field = "i")
  e4326 <- ext(project(as.polygons(ext(code), crs = crsU), "EPSG:4326"))
  # caja de cajas.md: las huellas solo existen dentro de ella
  cj <- caja_de(RPIPE, slug)
  caja <- project(vect(ext(cj$lon0, cj$lon1, cj$lat0, cj$lat1), crs = "EPSG:4326"), crsU)
  en_caja <- !is.na(values(rasterize(caja, code), mat = FALSE))

  # --- huellas ---
  f <- file.path(RPIPE, "outputs", "overture", slug, "edificios.gpkg")
  rg <- vect(f, query = "SELECT min(fid) AS a, max(fid) AS b FROM edificios", what = "attributes")
  cel_c <- integer(0); cel_g <- integer(0); cent30 <- integer(0)
  B <- list(); k <- 0L
  for (a in seq(rg$a - 1, rg$b, by = TRAMO)) {
    e <- vect(f, query = sprintf("SELECT fuente, geom FROM edificios WHERE fid > %d AND fid <= %d", a, a + TRAMO))
    if (!nrow(e)) next
    e <- project(e, crsU)
    ar <- expanse(e, transform = FALSE)
    xy <- crds(centroids(e, inside = FALSE))
    c10 <- cellFromXY(t10, xy); c30 <- cellFromXY(code, xy)
    k <- k + 1L
    B[[k]] <- data.table(fuente = e$fuente, m2 = ar, c30 = c30,
                         radio = as.integer(values(r10)[c10]))
    cent30 <- c(cent30, c30[!is.na(c30)])
    for (g in c(FALSE, TRUE)) {
      s <- e[(ar > GRANDE) == g]
      if (!nrow(s)) next
      ee <- intersect(ext(s), ext(t10))
      if (is.null(ee)) next
      tt <- crop(t10, ee, snap = "out")
      p <- rasterize(s, tt, background = NA)
      idx <- which(!is.na(values(p, mat = FALSE)))
      if (!length(idx)) next
      gl <- cellFromXY(t10, xyFromCell(tt, idx))
      if (g) cel_g <- c(cel_g, gl) else cel_c <- c(cel_c, gl)
    }
    rm(e, s, p); gc(verbose = FALSE)
  }
  B <- rbindlist(B)
  cel_c <- unique(cel_c); cel_g <- unique(setdiff(cel_g, cel_c))
  a30 <- function(cel) { r <- (cel - 1) %/% nc10; cc <- (cel - 1) %% nc10; (r %/% 3) * nc30 + cc %/% 3 + 1 }
  n10 <- tabulate(a30(c(cel_c, cel_g)), nbins = ncell(code))
  n10g <- tabulate(a30(cel_g), nbins = ncell(code))
  ncen <- tabulate(cent30, nbins = ncell(code))
  rm(r10); gc(verbose = FALSE)

  # --- uso del suelo ---
  lu <- rep(NA_character_, ncell(code)); lu_drop <- 0L; lu_drop_km2 <- 0
  u <- tryCatch(vect(file.path(RPIPE, "outputs", "overture", slug, "uso.gpkg"), extent = e4326), error = function(e) NULL)
  ap <- tryCatch(vect(file.path(RPIPE, "outputs", "overture", slug, "aeropuertos.gpkg"), extent = e4326), error = function(e) NULL)
  capas <- list()
  if (!is.null(u) && nrow(u)) {
    u <- project(u, crsU); u$g <- grupo_uso(u$subtype, u$clase)
    big <- expanse(u, transform = FALSE) > LU_MAX
    lu_drop <- sum(big); lu_drop_km2 <- sum(expanse(u[big], transform = FALSE)) / 1e6
    u <- u[!big]
    for (g in c("verde", "agro", "res", "nr")) capas[[g]] <- u[which(u$g == g)]
  }
  if (!is.null(ap) && nrow(ap)) {
    ap <- project(ap, crsU)
    capas[["aero"]] <- ap
  }
  for (g in names(capas)) {           # orden: verde < agro < res < nr < aero (lo ultimo pisa)
    if (!nrow(capas[[g]])) next
    m <- !is.na(values(rasterize(capas[[g]], code), mat = FALSE))
    lu[m] <- if (g == "aero") "nr" else g
  }
  aero <- if (!is.null(capas$aero)) !is.na(values(rasterize(capas$aero, code), mat = FALSE)) else rep(FALSE, ncell(code))

  # --- tabla por pixel y agregados por radio ---
  P <- data.table(code = cv, radio = as.integer(r30), n10 = n10, n10g = n10g, ncen = ncen, lu = lu,
                  aero = aero, caja = en_caja)
  P[, fp := n10 > 0 | ncen > 0]
  P[, built := code %in% c(1, 3)]
  R <- P[!is.na(radio), .(px1 = sum(code == 1, na.rm = TRUE), px3 = sum(code == 3, na.rm = TRUE),
                          px2 = sum(code == 2, na.rm = TRUE), px_tot = .N,
                          px_built_fp = sum(built & fp, na.rm = TRUE),
                          px1_fp = sum(code == 1 & fp, na.rm = TRUE),
                          fp10_m2 = 100 * sum(n10), fp10_m2_built = 100 * sum(n10[built %in% TRUE]),
                          fp10_m2_open = 100 * sum(n10[code %in% 2]), fp10_m2_rest = 100 * sum(n10[code %in% 0]),
                          px_nr = sum(lu %in% "nr"), px_agro = sum(lu %in% "agro"),
                          px_verde = sum(lu %in% "verde"), px_res = sum(lu %in% "res"),
                          px_aero = sum(aero), px_fuera_caja = sum(!caja),
                          built_nr = sum(built & lu %in% "nr", na.rm = TRUE),
                          built_agro = sum(built & lu %in% "agro", na.rm = TRUE),
                          built_verde = sum(built & lu %in% "verde", na.rm = TRUE),
                          built_res = sum(built & lu %in% "res", na.rm = TRUE)), by = radio]
  H <- B[!is.na(radio), .(fp_n = .N, fp_m2 = sum(m2), fp_n_big = sum(m2 > GRANDE),
                          fp_m2_big = sum(m2[m2 > GRANDE]),
                          fp_n_osm = sum(fuente == "OpenStreetMap")), by = radio]
  out <- merge(tb[, .(radio = i_fila, cod, personas, hogares, viviendas, viv_habitadas, km2_radio,
                      km2_construido, km2_otro_construido, km2_abierto, km2_urb, dens_bruta, dens_urb)],
               R, by = "radio", all.x = TRUE)
  out <- merge(out, H, by = "radio", all.x = TRUE)
  num <- setdiff(names(out), c("radio", "cod", "dens_bruta", "dens_urb"))
  for (c in num) set(out, which(is.na(out[[c]])), c, 0)   # radios sin pixel o sin huella
  out[, slug := slug]
  fwrite(out, file.path(CACHE, paste0(slug, "_radios.csv")))

  # --- acuerdo GISD30 - huellas en la ciudad y su entorno (pixeles dentro de la caja) ---
  Q <- P[caja == TRUE]
  ac <- data.table(slug = slug,
    px1 = Q[, sum(code == 1, na.rm = TRUE)], px1_fp = Q[, sum(code == 1 & fp, na.rm = TRUE)],
    px3 = Q[, sum(code == 3, na.rm = TRUE)], px3_fp = Q[, sum(code == 3 & fp, na.rm = TRUE)],
    px2 = Q[, sum(code == 2, na.rm = TRUE)], px2_fp = Q[, sum(code == 2 & fp, na.rm = TRUE)],
    px0 = Q[, sum(code == 0, na.rm = TRUE)], px0_fp = Q[, sum(code == 0 & fp, na.rm = TRUE)],
    fp10_1 = Q[, 100 * sum(n10[code %in% 1])], fp10_3 = Q[, 100 * sum(n10[code %in% 3])],
    fp10_2 = Q[, 100 * sum(n10[code %in% 2])], fp10_0 = Q[, 100 * sum(n10[code %in% 0])],
    fp10_g = Q[, 100 * sum(n10g)],
    fp_n = nrow(B), fp_m2 = sum(B$m2), fp_n_big = sum(B$m2 > GRANDE), fp_m2_big = sum(B$m2[B$m2 > GRANDE]),
    fp_n_osm = sum(B$fuente == "OpenStreetMap"), fp_n_google = sum(B$fuente == "Google Open Buildings"),
    fp_n_ms = sum(B$fuente == "Microsoft ML Buildings"),
    fp_n_big_osm = sum(B$m2 > GRANDE & B$fuente == "OpenStreetMap"),
    px_fuera_caja = sum(!P$caja), lu_drop = lu_drop, lu_drop_km2 = lu_drop_km2, nombre = x$nombre,
    seg = as.numeric(difftime(Sys.time(), t0, units = "secs")))
  fwrite(ac, file.path(CACHE, paste0(slug, "_acuerdo.csv")))
  message(sprintf("%s: %s huellas, %s radios, %.0f s", slug, f0(nrow(B)), f0(nrow(out)), ac$seg))
  invisible(NULL)
}


if (!SOLO_REPORTE) for (s in CIUDADES) {
  if (!REHACER && file.exists(file.path(CACHE, paste0(s, "_acuerdo.csv")))) { message(s, ": en cache"); next }
  procesar(s)
}


# ======================= analisis y reporte (todas las ciudades en cache) =======================
fs <- list.files(CACHE, "_radios\\.csv$", full.names = TRUE)
D <- rbindlist(lapply(fs, fread, colClasses = c(cod = "character")))
AC <- rbindlist(lapply(list.files(CACHE, "_acuerdo\\.csv$", full.names = TRUE), fread))
NOM <- setNames(AC$nombre, AC$slug)
D[, nombre := NOM[slug]]

D[, `:=`(px_built = px1 + px3, en_ciudad = km2_urb > 0 & km2_urb >= MIN_CIUDAD * km2_radio)]
D[, `:=`(m2_built = px_built * PX_M2,
         bpd = ifelse(viviendas > 0, px_built / viviendas, NA_real_),
         fpd = ifelse(viviendas > 0, fp_m2 / viviendas, NA_real_),
         pers_km2_built = ifelse(px_built > 0, personas / (px_built * PX_M2 / 1e6), NA_real_),
         pers_km2_fp = ifelse(fp_m2 > 0, personas / (fp_m2 / 1e6), NA_real_),
         viv_km2 = viviendas / km2_radio,
         cov_px = ifelse(px_built > 0, px_built_fp / px_built, NA_real_),
         fp_sobre_built = ifelse(fp10_m2 > 0, fp10_m2_built / fp10_m2, NA_real_),
         fp_por_px = ifelse(px_built > 0, fp_m2 / (px_built * PX_M2), NA_real_),
         nr_built = ifelse(px_built > 0, built_nr / px_built, NA_real_),
         agro_built = ifelse(px_built > 0, built_agro / px_built, NA_real_),
         nr_area = ifelse(px_tot > 0, px_nr / px_tot, NA_real_),
         big_share = ifelse(fp_m2 > 0, fp_m2_big / fp_m2, NA_real_))]
D[, uso := fifelse(px_aero > 0 & px_aero >= 0.10 * px_tot, "airport",
           fifelse(nr_built %in% NA, "no built-up",
           fifelse(nr_built >= NR_DOM, "non-residential",
           fifelse(agro_built >= NR_DOM, "farmland (Overture)", "residential / other"))))]
setcolorder(D, c("slug", "nombre", "radio", "cod", "en_ciudad", "uso"))
fwrite(D, file.path(SAL, "radios.csv"))

C <- D[en_ciudad == TRUE]            # radios de la ciudad
CP <- C[viviendas > 0 & px_built > 0]  # para cocientes por vivienda (log)
ord <- C[, .(v = median(bpd[viviendas > 0 & px_built > 0])), by = nombre][order(v), nombre]
C[, nombre := factor(nombre, ord)]; CP[, nombre := factor(nombre, ord)]

# ---------- percentiles dentro de cada ciudad ----------
PCT <- c(50, 75, 90, 95)
PE <- CP[, c(.(n = .N),
             setNames(lapply(PCT, function(p) q7(bpd * PX_M2, p)), paste0("b", PCT)),
             setNames(lapply(PCT, function(p) q7(fpd[fp_m2 > 0], p)), paste0("f", PCT)),
             setNames(lapply(PCT, function(p) q7(fp_por_px, p)), paste0("c", PCT))), by = .(slug, nombre)]
PE[, nombre := as.character(nombre)]; setorder(PE, nombre)
fwrite(PE, file.path(SAL, "percentiles.csv"))
cv_ <- function(x) sd(x) / mean(x)
DISP <- rbindlist(lapply(c("b", "f"), function(m) rbindlist(lapply(PCT, function(p) {
  z <- PE[[paste0(m, p)]]
  data.table(medida = m, p = p, min = min(z), med = median(z), max = max(z), ratio = max(z) / min(z), cv = cv_(z))
}))))

# percentil de cada radio dentro de su ciudad
CP[, `:=`(pr_b = frank(bpd, ties.method = "average") / .N, pr_f = frank(fpd, ties.method = "average") / .N), by = slug]

# ---------- radios casi vacios: cuartiles de viviendas por km2 dentro de cada ciudad ----------
CP[, cuartil := cut(frank(viv_km2, ties.method = "average") / .N, c(0, .25, .5, .75, 1),
                    labels = c("Q1 (emptiest)", "Q2", "Q3", "Q4 (densest)"), include.lowest = TRUE), by = slug]
QC <- CP[, .(n = .N, b = median(bpd) * PX_M2, f = median(fpd), cov = sum(px_built_fp) / sum(px_built),
             c = median(fp_por_px), nr = sum(uso %in% c("non-residential", "airport"))), by = .(slug, cuartil)]
QP <- CP[, .(n = .N, viv = sum(viviendas), b = median(bpd) * PX_M2, f = median(fpd), cov = sum(px_built_fp) / sum(px_built),
             c = median(fp_por_px), nr = sum(uso %in% c("non-residential", "airport")),
             agro = sum(uso == "farmland (Overture)")), by = cuartil]
QS <- QC[, .(b_min = min(b), b_max = max(b), f_min = min(f), f_max = max(f), cov_min = min(cov), cov_max = max(cov)), by = cuartil]
QP <- merge(QP, QS, by = "cuartil"); setorder(QP, cuartil)
fwrite(QC, file.path(SAL, "cuartiles_densidad.csv"))

# ---------- tope: recortar por encima del pXX de la ciudad hasta el pXX ----------
tope <- function(p) {
  lim <- CP[, .(lim = q7(bpd, p)), by = slug]
  Z <- merge(C, lim, by = "slug")
  Z[, sobra := fifelse(viviendas > 0, pmax(0, px_built - lim * viviendas), as.numeric(px_built))]
  Z[, sin_fp := px_built - px_built_fp]
  Z[, `:=`(sobra_sin_fp = pmin(sobra, sin_fp), sobra_con_fp = pmax(0, sobra - sin_fp))]
  Z[, nr := uso %in% c("non-residential", "airport")]
  Z[, p := p]
  Z
}
TP <- rbindlist(lapply(c(75, 90, 95), tope))
TS <- TP[, .(radios = .N, built_km2 = sum(px_built) * PX_M2 / 1e6,
             af = sum(sobra > 0 & viviendas > 0), af0 = sum(sobra > 0 & viviendas == 0),
             rec_km2 = sum(sobra) * PX_M2 / 1e6,
             rec0_km2 = sum(sobra[viviendas == 0]) * PX_M2 / 1e6,
             rec_nr_km2 = sum(sobra[nr]) * PX_M2 / 1e6, af_nr = sum(sobra > 0 & nr),
             rec_agro_km2 = sum(sobra[uso == "farmland (Overture)"]) * PX_M2 / 1e6,
             rec_sinfp_km2 = sum(sobra_sin_fp) * PX_M2 / 1e6,
             rec_confp_km2 = sum(sobra_con_fp) * PX_M2 / 1e6), by = .(p, slug, nombre)]
TS[, nombre := as.character(nombre)]; setorder(TS, p, nombre)
fwrite(TS, file.path(SAL, "tope.csv"))
TT <- TS[, lapply(.SD, sum), by = p, .SDcols = setdiff(names(TS), c("p", "slug", "nombre"))]

# ---------- acuerdo por ciudad ----------
AC[, `:=`(fp10_tot = fp10_1 + fp10_3 + fp10_2 + fp10_0)]
setorder(AC, nombre)
fwrite(AC, file.path(SAL, "acuerdo.csv"))

# ---------- resumen por ciudad ----------
RS <- C[, .(radios = .N, radios_viv0 = sum(viviendas == 0), personas = sum(personas), viviendas = sum(viviendas),
            built_km2 = sum(px_built) * PX_M2 / 1e6, px3_km2 = sum(px3) * PX_M2 / 1e6,
            fp_km2 = sum(fp_m2) / 1e6, fp_n = sum(fp_n),
            m2b_viv = sum(px_built) * PX_M2 / sum(viviendas), m2f_viv = sum(fp_m2) / sum(viviendas),
            cov = sum(px_built_fp) / sum(px_built), fp_on_b = sum(fp10_m2_built) / sum(fp10_m2),
            nr_built_km2 = sum(built_nr) * PX_M2 / 1e6, agro_built_km2 = sum(built_agro) * PX_M2 / 1e6,
            radios_nr = sum(uso %in% c("non-residential", "airport")),
            built_nr_radios_km2 = sum(px_built[uso %in% c("non-residential", "airport")]) * PX_M2 / 1e6,
            big_km2 = sum(fp_m2_big) / 1e6, big_n = sum(fp_n_big)), by = .(slug, nombre)]
RS[, nombre := as.character(nombre)]; setorder(RS, nombre)
fwrite(RS, file.path(SAL, "ciudades.csv"))


# ---------- figuras ----------
COLU <- c("residential / other" = "#1f4e79", "non-residential" = "#d1495b", "airport" = "#7b2d8e",
          "farmland (Overture)" = "#e9a23b", "no built-up" = "#9a9a9a")
g <- ggplot(CP, aes(bpd * PX_M2, nombre)) +
  geom_boxplot(outlier.size = 0.3, outlier.alpha = 0.3, fill = "#9ecae1", colour = "#1f4e79", linewidth = 0.3) +
  scale_x_log10(labels = scales::label_comma()) +
  labs(x = "GISD30 built-up m2 per dwelling (codes 1 + 3; log scale)", y = NULL,
       title = "Built-up per dwelling, tracts in the city", caption = PIE) + tema
guardar(g, IMG, "built_por_vivienda.png", 9, 9)

g <- ggplot(CP[fp_m2 > 0], aes(fpd, nombre)) +
  geom_boxplot(outlier.size = 0.3, outlier.alpha = 0.3, fill = "#f6c89f", colour = "#a04e0b", linewidth = 0.3) +
  scale_x_log10(labels = scales::label_comma()) +
  labs(x = "Overture footprint m2 per dwelling (log scale)", y = NULL,
       title = "Footprint per dwelling, tracts in the city", caption = PIE) + tema
guardar(g, IMG, "huella_por_vivienda.png", 9, 9)

PL <- melt(PE, id.vars = c("slug", "nombre", "n"), measure.vars = c(paste0("b", PCT[-1]), paste0("f", PCT[-1])))
PL[, medida := ifelse(substr(variable, 1, 1) == "b", "GISD30 built-up m2 per dwelling", "footprint m2 per dwelling")]
PL[, pct := paste0("p", substring(variable, 2))]
PL[, nombre := factor(nombre, ord)]
g <- ggplot(PL, aes(value, nombre, colour = pct)) + geom_point(size = 1.8) +
  facet_wrap(~medida, scales = "free_x") + scale_x_log10(labels = scales::label_comma()) +
  scale_colour_manual(values = c(p75 = "#9ecae1", p90 = "#1f4e79", p95 = "#d1495b"), name = NULL) +
  labs(x = "value at the city's percentile (log scale)", y = NULL,
       title = "Within-city percentile cuts in physical units", caption = PIE) + tema
guardar(g, IMG, "cortes_percentil.png", 11, 9)

g <- ggplot(C[px_built > 0 & fp_m2 > 0], aes(m2_built, fp_m2, colour = uso)) +
  geom_abline(slope = 1, intercept = 0, colour = TINTA2, linewidth = 0.3) +
  geom_abline(slope = 1, intercept = -1, colour = TINTA2, linewidth = 0.3, linetype = 2) +
  geom_point(size = 0.25, alpha = 0.4) + facet_wrap(~nombre, ncol = 6) +
  scale_x_log10(labels = scales::label_comma()) + scale_y_log10(labels = scales::label_comma()) +
  scale_colour_manual(values = COLU, name = NULL) +
  guides(colour = guide_legend(override.aes = list(size = 2, alpha = 1))) +
  labs(x = "GISD30 built-up m2 in the tract (log)", y = "Overture footprint m2 in the tract (log)",
       title = "Footprint vs GISD30 built-up per tract", subtitle = "solid line 1:1; dashed line footprint = 10 % of built-up",
       caption = PIE) + tema + theme(strip.text = element_text(size = 7), axis.text = element_text(size = 6))
guardar(g, IMG, "huella_vs_built.png", 13, 13)

g <- ggplot(CP, aes(viv_km2, bpd * PX_M2, colour = uso)) +
  geom_point(size = 0.25, alpha = 0.4) + facet_wrap(~nombre, ncol = 6) +
  scale_x_log10(labels = scales::label_comma()) + scale_y_log10(labels = scales::label_comma()) +
  scale_colour_manual(values = COLU, name = NULL) +
  guides(colour = guide_legend(override.aes = list(size = 2, alpha = 1))) +
  labs(x = "dwellings per km2 of tract (log)", y = "GISD30 built-up m2 per dwelling (log)",
       title = "Built-up per dwelling against tract dwelling density", caption = PIE) +
  tema + theme(strip.text = element_text(size = 7), axis.text = element_text(size = 6))
guardar(g, IMG, "built_por_vivienda_vs_densidad.png", 13, 13)

AL <- melt(AC[, .(nombre, `code 1 · city built-up` = pc(px1_fp, px1), `code 3 · built outside city` = pc(px3_fp, px3),
                  `code 2 · city open land` = pc(px2_fp, px2), `code 0 · rest` = pc(px0_fp, px0))], id.vars = "nombre")
AL[, nombre := factor(nombre, rev(sort(unique(nombre))))]
g <- ggplot(AL, aes(value, nombre, colour = variable)) + geom_point(size = 2) +
  scale_colour_manual(values = c("#1f4e79", "#f2c500", "#2a9d8f", "#9a9a9a"), name = NULL) +
  labs(x = "% of 30 m pixels with at least one Overture footprint", y = NULL,
       title = "Agreement between GISD30 2020 and Overture footprints", caption = PIE) + tema +
  guides(colour = guide_legend(nrow = 2))
guardar(g, IMG, "acuerdo.png", 9, 9)

TB <- TP[p == 90 & sobra > 0, .(km2 = sum(sobra) * PX_M2 / 1e6),
         by = .(nombre, clase = fifelse(viviendas == 0, "tracts with 0 dwellings",
                                fifelse(nr, "non-residential / airport", fifelse(uso == "farmland (Overture)",
                                        "farmland (Overture)", "residential / other"))))]
TB[, nombre := factor(nombre, ord)]
g <- ggplot(TB, aes(km2, nombre, fill = clase)) + geom_col(width = 0.7) +
  scale_fill_manual(values = c("residential / other" = "#1f4e79", "non-residential / airport" = "#d1495b",
                               "farmland (Overture)" = "#e9a23b", "tracts with 0 dwellings" = "#9a9a9a"), name = NULL) +
  labs(x = "built-up km2 the cap would trim", y = NULL,
       title = "Cap at the city's p90 of built-up per dwelling: what it trims", caption = PIE) + tema +
  guides(fill = guide_legend(nrow = 2))
guardar(g, IMG, "tope_p90.png", 9, 9)

g <- ggplot(CP, aes(pr_b, pr_f)) + geom_bin2d(bins = 40) +
  scale_fill_gradient(low = "#e6eef7", high = "#0b2642", trans = "log10", name = "tracts") +
  labs(x = "within-city percentile of GISD30 built-up per dwelling",
       y = "within-city percentile of footprint per dwelling",
       title = "Do the two ratios rank tracts the same way?", caption = PIE) + tema
guardar(g, IMG, "percentiles_bpd_fpd.png", 7, 6.5)


# ---------- REPORTE.md ----------
sp <- function(x, m = "s") suppressWarnings(cor(x, m, method = "spearman", use = "complete.obs"))
RHO <- CP[fp_m2 > 0, .(rho_bf = sp(bpd, fpd), rho_bm = sp(m2_built, fp_m2), n = .N), by = nombre]
RHO[, nombre := as.character(nombre)]; setorder(RHO, nombre)

L <- c("# Overture footprints vs GISD30 2020 built-up and the 2022 census, by tract",
  "",
  "Exploratory. No number here is a project figure. Generated by `scripts/22_diagnostico_huellas.R`; numbers in tables are",
  "written by the script. Purpose: inform the dwelling cap (rule 3A): how much built-up per dwelling is plausible, and",
  "whether a within-city percentile cut means similar physical values in every city.",
  "",
  "## Method",
  "",
  "**Data.**",
  "- GISD30 2020 pixel classes from step 11 (`outputs/densidad/<slug>/code_2020.tif`, UTM, 30 m = 900 m2): 1 city built-up,",
  "  2 city open land, 3 built-up outside the city, 0 rest.",
  "- 2022 census tracts and their table (`radios_2020.*`): persons, households, dwellings.",
  "- Overture Maps buildings (step 20; OpenStreetMap + Google Open Buildings + Microsoft ML footprints), land use and airports.",
  "  These are present-day (2022-2025 imagery and edits), the image is 2020 and the census 2022: a footprint without",
  "  built-up can be new construction, and built-up without footprint can be demolished, missed by the detectors, or",
  "  not a building at all (pavement, bare soil, farmland misread as built).",
  "",
  "**Definitions.**",
  sprintf("- *Tract in the city*: km2_urb (built + open city land) >= %d %% of the tract area. City statistics use only these; `radios.csv` keeps every tract with the flag `en_ciudad`.", round(100 * MIN_CIUDAD)),
  "- *Built pixels* = code 1 + code 3 pixels whose centre falls in the tract. *Built m2 per dwelling* = built pixels x 900 / dwellings.",
  "- *Footprint area / count of a tract*: exact planar area (UTM) of the footprints whose centroid falls in the tract",
  "  (looked up on a 10 m grid aligned to the GISD30 pixels, so a centroid within ~5 m of a boundary may go to the neighbour).",
  "- *Footprint coverage of a pixel*: the footprints are rasterized at 10 m (cell centre inside the polygon) and counted per",
  "  30 m pixel (0-9 cells, 100 m2 each). This is an unbiased but noisy estimate of covered area; footprints under 100 m2 can",
  "  miss every cell centre, so a pixel *has a footprint* if any 10 m cell is covered **or** a footprint centroid falls in it.",
  "- *Share of footprint area on built pixels*: covered 10 m cells on code 1 or 3 pixels / all covered cells.",
  sprintf("- *Large footprints*: polygons over %s m2 (1 ha). In OpenStreetMap a whole block is sometimes drawn as one building; they are kept in the totals and reported apart.", f0(GRANDE)),
  "- *Land use* (Overture, mostly from OpenStreetMap, so mapping completeness varies by city): rasterized at 30 m into",
  "  four groups, later ones overriding earlier ones: green/recreation < farmland < residential < non-residential",
  "  (developed: industrial, commercial, retail, works, brownfield, institutional; education; medical; military; religious;",
  "  cemetery; railway; landfill; quarries; entertainment; stadiums; construction sites) < airport (all airport polygons).",
  sprintf("  Land-use polygons over %s km2 are dropped: they are regional blankets, not parcels (in Salta one OSM `farmland` polygon covers the whole valley). Dropped per city: column `lu_drop` of `acuerdo.csv`.", f0(LU_MAX / 1e6)),
  sprintf("- *Tract use label*: `airport` if airport land covers >= 10 %% of the tract; `non-residential` if >= %d %% of its built pixels lie on non-residential land use; `farmland (Overture)` if >= %d %% lie on mapped farmland; `no built-up` if it has no built pixel; otherwise `residential / other`.", round(100 * NR_DOM), round(100 * NR_DOM)),
  "- Percentiles are type 7, within each city, over tracts in the city with dwellings > 0 and built pixels > 0 (footprint",
  "  percentiles also need footprint area > 0).",
  "",
  "**Limitations.** Land use is only as good as the OSM mapping: an unmapped factory counts as `residential / other`.",
  "Footprint completeness varies by source and city (see the source columns). The tract lookup of centroids and the",
  "10 m sampling are approximations described above. The census counts dwellings, not lots: second homes, empty",
  "dwellings and non-residential units are part of the denominator as the census reports them.",
  "")

L <- c(L, "## Agreement between GISD30 2020 and the footprints, per city", "",
  "Pixels inside the city's box (where footprints exist). *% with footprint* = pixels with at least one footprint / pixels of that code.",
  "*Footprint on* = share of the sampled footprint area (10 m cells) falling on each code.", "",
  "![agreement](img/acuerdo.png)", "",
  tabla(c("City", "code 1 px", "% code 1 with fp", "code 3 px", "% code 3 with fp", "% code 2 with fp", "% code 0 with fp",
          "fp area km2 (10 m)", "fp on 1+3 %", "fp on 2 %", "fp on 0 %"),
        lapply(seq_len(nrow(AC)), function(i) with(AC[i], c(nombre, f0(px1), f1(pc(px1_fp, px1)), f0(px3), f1(pc(px3_fp, px3)),
          f1(pc(px2_fp, px2)), f1(pc(px0_fp, px0)), f1(fp10_tot / 1e6), f1(pc(fp10_1 + fp10_3, fp10_tot)),
          f1(pc(fp10_2, fp10_tot)), f1(pc(fp10_0, fp10_tot)))))),
  "", sprintf("Pixels (any code) of tracts in the city that fall outside the footprint box, where there are no footprint data: %s (all cities).",
        f0(C[, sum(px_fuera_caja)])),
  "", sprintf("All cities: %s of %s code 1 pixels have a footprint (%s %%); %s of %s code 3 pixels (%s %%).",
        f0(sum(AC$px1_fp)), f0(sum(AC$px1)), f1(pc(sum(AC$px1_fp), sum(AC$px1))),
        f0(sum(AC$px3_fp)), f0(sum(AC$px3)), f1(pc(sum(AC$px3_fp), sum(AC$px3)))),
  "", "Footprint sources and large polygons (all footprints read, whole box):", "",
  tabla(c("City", "footprints", "OSM", "Google", "Microsoft", "> 1 ha", "> 1 ha from OSM", "km2 in > 1 ha", "% of footprint km2"),
        lapply(seq_len(nrow(AC)), function(i) with(AC[i], c(nombre, f0(fp_n), f0(fp_n_osm), f0(fp_n_google), f0(fp_n_ms),
          f0(fp_n_big), f0(fp_n_big_osm), f2(fp_m2_big / 1e6), f1(pc(fp_m2_big, fp_m2)))))),
  "")

L <- c(L, "## Per-city summary (tracts in the city)", "",
  tabla(c("City", "tracts", "tracts 0 dw.", "dwellings", "built km2", "footprint km2", "built m2 / dw.", "footprint m2 / dw.",
          "% built px with fp", "% fp on built", "built km2 on NR land", "built km2 on farmland", "NR/airport tracts", "their built km2"),
        lapply(seq_len(nrow(RS)), function(i) with(RS[i], c(nombre, f0(radios), f0(radios_viv0), f0(viviendas), f1(built_km2),
          f1(fp_km2), f0(m2b_viv), f0(m2f_viv), f1(100 * cov), f1(100 * fp_on_b), f1(nr_built_km2), f1(agro_built_km2),
          f0(radios_nr), f1(built_nr_radios_km2))))),
  "")

L <- c(L, "## Distributions per city", "",
  "![built per dwelling](img/built_por_vivienda.png)", "", "![footprint per dwelling](img/huella_por_vivienda.png)", "",
  "![built per dwelling vs density](img/built_por_vivienda_vs_densidad.png)", "",
  "![footprint vs built](img/huella_vs_built.png)", "",
  "Spearman rank correlation per city between tracts' footprint m2 and built m2, and between footprint per dwelling and built per dwelling:", "",
  tabla(c("City", "tracts", "rho (footprint m2, built m2)", "rho (fp / dw., built / dw.)"),
        lapply(seq_len(nrow(RHO)), function(i) with(RHO[i], c(as.character(nombre), f0(n), f2(rho_bm), f2(rho_bf))))),
  "", "![percentile vs percentile](img/percentiles_bpd_fpd.png)", "")

L <- c(L, "## Near-empty tracts: by within-city quartile of dwelling density", "",
  "Tracts in the city with dwellings > 0 and built-up > 0, split into quartiles of dwellings per km2 of tract *within each city*.",
  "Pooled medians over all cities, and the range of the per-city medians (min-max over the 31 cities). *cov* = built pixels",
  "with a footprint / built pixels; *c* = footprint m2 per built m2 (median).", "",
  tabla(c("quartile", "tracts", "dwellings", "built m2 / dw. (median)", "city range", "footprint m2 / dw. (median)", "city range",
          "cov %", "city range", "c (median)", "NR / airport tracts", "farmland tracts"),
        lapply(seq_len(nrow(QP)), function(i) with(QP[i], c(as.character(cuartil), f0(n), f0(viv), f0(b), paste(f0(b_min), "-", f0(b_max)),
          f0(f), paste(f0(f_min), "-", f0(f_max)), f1(100 * cov), paste(f1(100 * cov_min), "-", f1(100 * cov_max)), f2(c),
          f0(nr), f0(agro))))),
  "", "Per city and quartile: `cuartiles_densidad.csv`.", "")

L <- c(L, "## Do percentile cuts mean the same physical value in every city?", "",
  "Value at each within-city percentile. *b* = GISD30 built-up m2 per dwelling; *f* = footprint m2 per dwelling;",
  "*c* = footprint m2 per built m2 of the tract.", "",
  "![cuts](img/cortes_percentil.png)", "",
  tabla(c("City", "tracts", "b p50", "b p75", "b p90", "b p95", "f p50", "f p75", "f p90", "f p95", "c p50", "c p90"),
        lapply(seq_len(nrow(PE)), function(i) with(PE[i], c(nombre, f0(n), f0(b50), f0(b75), f0(b90), f0(b95),
          f0(f50), f0(f75), f0(f90), f0(f95), f2(c50), f2(c90))))),
  "", "Spread across the 31 cities of the value at each percentile (cv = sd / mean):", "",
  tabla(c("measure", "percentile", "min", "median", "max", "max / min", "cv"),
        lapply(seq_len(nrow(DISP)), function(i) with(DISP[i], c(ifelse(medida == "b", "built m2 / dwelling", "footprint m2 / dwelling"),
          paste0("p", p), f0(min), f0(med), f0(max), f1(ratio), f2(cv))))),
  "")

L <- c(L, "## What a cap at the city's percentile would trim", "",
  "Rule simulated: in each tract in the city, built pixels above *dwellings x the city's pXX of built pixels per dwelling* are",
  "trimmed (tracts with 0 dwellings would lose all their built-up: shown apart). *Without footprint* = the part of the trim",
  "that could come from built pixels with no footprint (min of trim and the tract's built pixels without footprint); *with",
  "footprint* = the rest, which would necessarily remove pixels where a building exists today.", "",
  "![cap p90](img/tope_p90.png)", "", "All 31 cities:", "",
  tabla(c("cut", "tracts", "built km2", "tracts trimmed (dw. > 0)", "tracts with 0 dw. and built-up", "km2 trimmed",
          "of which in 0-dw. tracts", "in NR / airport tracts", "in farmland tracts", "without footprint", "with footprint"),
        lapply(seq_len(nrow(TT)), function(i) with(TT[i], c(paste0("p", p), f0(radios), f1(built_km2), f0(af), f0(af0),
          sprintf("%s (%s %%)", f1(rec_km2), f1(pc(rec_km2, built_km2))), f1(rec0_km2), f1(rec_nr_km2), f1(rec_agro_km2),
          f1(rec_sinfp_km2), f1(rec_confp_km2))))),
  "", "Per city, cut at p90:", "",
  tabla(c("City", "tracts", "built km2", "trimmed tracts (dw. > 0)", "0-dw. tracts", "km2 trimmed", "% of built",
          "in 0-dw. tracts", "in NR / airport", "in farmland", "without fp", "with fp"),
        lapply(which(TS$p == 90), function(i) with(TS[i], c(nombre, f0(radios), f1(built_km2), f0(af), f0(af0), f1(rec_km2),
          f1(pc(rec_km2, built_km2)), f1(rec0_km2), f1(rec_nr_km2), f1(rec_agro_km2), f1(rec_sinfp_km2), f1(rec_confp_km2))))),
  "")

L <- c(L, "## Implications for the dwelling cap", "", "<!-- PROSA -->", "",
  "## Files", "",
  "- `radios.csv`: one row per tract and city (all tracts, flag `en_ciudad`), with every measure above.",
  "- `ciudades.csv`, `acuerdo.csv`, `percentiles.csv`, `tope.csv`, `cuartiles_densidad.csv`: the tables of this report.",
  "- `ciudades/`: per-city cache written by the script (`--rehacer` recomputes).", "")

# la prosa a mano (sin numeros) vive en prosa.md y se inserta si existe
fp <- file.path(SAL, "prosa.md")
if (file.exists(fp)) L <- sub("<!-- PROSA -->", paste(readLines(fp, encoding = "UTF-8"), collapse = "\n"), L, fixed = TRUE)
writeLines(L, file.path(SAL, "REPORTE.md"), useBytes = TRUE)
message("reporte: ", file.path(SAL, "REPORTE.md"))
