# -*- coding: utf-8 -*-
# Paso 23 · Construido corregido: las reglas 0-3 aplicadas en secuencia sobre GISD30, cada una
# sobre la capa que deja la anterior, con la geometria recalculada en cada paso. Es la misma
# secuencia del visor de limpieza (docs/visor/limpieza.html), en la grilla UTM de 30 m original y
# con distancias y areas exactas. Exploratorio: ningun numero es cifra del proyecto; Overture no
# es fuente aprobada.
#
# Secuencia, por aglomerado y anio:
#   capa 0  GISD30 con las clases del paso 11 (1 construido de la ciudad, 2 abierto de la ciudad,
#           3 construido fuera, 0 resto)
#   regla 0 Overture (paso 21): saca lo construido sobre agua, area protegida, cultivo sin
#           edificio, sin edificio cerca o sobre una calle (estas tres solo fuera de la ciudad y en
#           radios por debajo de un percentil de densidad); suma aeropuertos enteros desde el anio
#           en que funcionan, espacios publicos y lo cubierto por edificios en radios densos
#   regla 1 franja del borde: distancia al borde y % construido en 150 m recalculados sobre la
#           capa 1; el abierto a <= D m queda como franja; descuenta construido ralo en la franja
#   regla 2 relleno: densidades, parches abiertos (4 vecinos, sin agua) y huecos (cierre con disco)
#           recalculados sobre la capa 2
#   regla 3 recorte: % construido y densidades recalculados sobre la capa 3; tope por vivienda,
#           piso de percentil o tope por huella, solo en radios por debajo de un percentil
# Un pixel cambia una sola vez: lo que una regla saca no lo rellena otra, y el recorte solo toca
# construido de GISD30 que sigue en pie.
#
# Parametros: los del visor, en el mismo formato que su enlace (rg=...), o el .json que guarda su
# boton "Download settings" (--config). Sin nada, los valores por defecto del visor. El juego usado
# queda escrito en el reporte.
#
# ENTRADAS  outputs/densidad/<slug>/ (11), outputs/etiquetas/<slug>/etiquetas.tif (21)
# SALIDAS   outputs/corregido/<slug>/clases_<anio>.tif (clase final por pixel, ver CLASES)
#           outputs/corregido/<slug>/urbanizado_<anio>.tif (1 urbanizado, 2 construido fuera de la
#           ciudad, 0 resto)
#           pruebas/corregido/resumen.csv, REPORTE.md
#
# Uso: Rscript Rpipe/scripts/23_corregido.R [--ciudades salta,jujuy] [--rg "200,25,3,2,..."]
#                                            [--config reglas.json]  (el archivo que guarda el visor)

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
terraOptions(progress = 0, memfrac = 0.6)

args <- commandArgs(trailingOnly = TRUE)
arg <- function(n, d) { i <- match(n, args); if (is.na(i) || i == length(args)) d else args[i + 1] }
DENS <- file.path(RPIPE, "outputs", "densidad")
ETQ <- file.path(RPIPE, "outputs", "etiquetas")
SAL <- file.path(RPIPE, "outputs", "corregido")
REP <- file.path(RPIPE, "pruebas", "corregido")
TODAS <- sort(list.dirs(DENS, full.names = FALSE, recursive = FALSE))
CIUDADES <- if (is.na(match("--ciudades", args))) TODAS else strsplit(arg("--ciudades", ""), ",")[[1]]
MIN_CIUDAD <- 0.10
PX_KM2 <- 0.0009

# ---------- parametros, como el enlace del visor ----------
CLAVES <- c("D", "p2", "tam", "gap", "p2b", "tamb", "modo", "p3", "k", "S", "fuera", "p2t", "on1", "on2", "on3",
            "E", "p3t", "on0", "oa", "op", "oc", "os", "oct", "oq", "ofa", "ofp", "ofe", "pf", "sx", "oab", "otc")
R <- list(D = 200, p2 = 25, tam = 3, gap = 2, p2b = 50, tamb = 4, modo = "tope", p3 = 10, k = 1, S = 80, fuera = TRUE,
          p2t = 75, on1 = TRUE, on2 = TRUE, on3 = TRUE, E = 0, p3t = 25, on0 = TRUE, oa = 50, op = TRUE, oc = 1,
          os = 60, oct = 30, oq = 50, ofa = TRUE, ofp = TRUE, ofe = 30, pf = 90, sx = 10, oab = 2, otc = TRUE)
rg <- arg("--rg", "")
cfg <- arg("--config", "")
if (nzchar(cfg)) {
  # archivo que guarda el visor de limpieza ("Download settings"): toma su campo rg
  if (!file.exists(cfg)) cfg <- file.path(RPIPE, "pruebas", "corregido", cfg)
  rg <- jsonlite::read_json(cfg)$rg
  cat("Parametros de", cfg, "
")
}
if (nzchar(rg)) {
  v <- strsplit(URLdecode(rg), ",")[[1]]
  for (j in seq_along(CLAVES)) if (j <= length(v)) {
    k <- CLAVES[j]
    R[[k]] <- if (k == "modo") v[j] else if (is.logical(R[[k]])) v[j] == "1" else as.numeric(v[j])
  }
}
if (!R$on3 || R$modo == "no") R$modo <- "no"
TAM_LIM <- c(0, 0.5, 1, 2, 5, 10, 20, 50, 100, Inf)          # ha por clase de tamano (visor TAM_T)
GAP_M <- c(0, 30, 60, 90, 120, 150, 180, 210, 240, 300, 360, 420, 500)
CLASES <- c(rb = 1, ru = 2, oo = 3, rr = 4, ro = 5, rf = 6, of = 7, ow = 8, oc = 9, on = 10, od = 11, re = 12, rx = 13)
ETQ_CLASE <- c(rb = "built-up kept", ru = "built outside the city, kept", rr = "fringe (edge ring)", ro = "captured open space",
               rf = "filled (rule 2)", of = "filled (rule 0, Overture)", ow = "removed: water or protected",
               oc = "removed: farmland", on = "removed: no building nearby", od = "road", re = "discounted at the edge (rule 1)",
               rx = "trimmed (rule 3)")

pct <- function(x, p) if (length(x)) as.numeric(quantile(x, p / 100, type = 7, names = FALSE)) else 0
umbral <- function(h, keep, S) {
  # % construido minimo que se conserva (h: conteos por % 0-100); -1 si no hace falta recortar
  if (sum(h) <= keep) return(-1)
  S <- min(S, 101); n <- if (S <= 100) sum(h[(S:100) + 1]) else 0; tr <- S
  if (S > 0) for (s in (S - 1):0) { m <- h[s + 1]; if (n + m > keep) break; n <- n + m; tr <- s }
  tr
}
compartido <- function(b, plantilla) {
  # % de pixeles construidos en un circulo de 150 m (como el paso 16)
  r <- rast(plantilla); values(r) <- b
  w <- focalMat(r, 150, "circle"); w[w > 0] <- 1
  round(100 * values(focal(r, w, fun = "sum", na.rm = TRUE), mat = FALSE) / sum(w))
}
distancia_a <- function(objeto, plantilla) {
  # m de cada pixel al pixel con objeto TRUE mas cercano
  r <- rast(plantilla); values(r) <- ifelse(objeto, 1, NA)
  values(distance(r), mat = FALSE)
}

anio_ciudad <- function(slug, a, y, et) {
  code <- y$code; n <- ncell(code)
  c0 <- values(code, mat = FALSE); c0[is.na(c0)] <- 0
  rid <- values(rasterize(y$v, code, field = "i"), mat = FALSE); rid[is.na(rid)] <- 0
  t <- y$t[order(y$t$i_fila), ]; nr <- max(t$i_fila)
  pers <- numeric(nr); area <- numeric(nr); viv <- rep(NA_real_, nr)
  pers[t$i_fila] <- t$personas; area[t$i_fila] <- t$km2_radio; viv[t$i_fila] <- t$viviendas
  E <- lapply(names(et), function(k) values(et[[k]], mat = FALSE)); names(E) <- names(et)
  for (k in names(E)) E[[k]][is.na(E[[k]])] <- 0
  cls <- integer(n); cls[c0 == 1] <- CLASES[["rb"]]; cls[c0 == 3] <- CLASES[["ru"]]; cls[c0 == 2] <- CLASES[["oo"]]
  porRadio <- function(sel) tabulate(rid[sel & rid > 0], nbins = nr)
  densidad <- function(ciudad) {
    km <- porRadio(ciudad) * PX_KM2
    d <- ifelse(km > 0, pers / km, -1)
    list(dens = d, univ = d[km > 0 & km >= MIN_CIUDAD * area], km = km)
  }
  dT <- function(D) { d <- rep(-1, n); d[rid > 0] <- D$dens[rid[rid > 0]]; d }

  # ---- regla 0 ----
  D0 <- densidad(c0 == 1 | c0 == 2)
  dq <- if (R$oq >= 100) Inf else pct(D0$univ, R$oq)
  d2o <- if (R$p2 == 0) 0 else pct(D0$univ, R$p2)
  dp <- dT(D0)
  if (R$on0) {
    construido <- c0 == 1 | c0 == 3
    elig <- c0 == 3 | dp < 0 | dp < dq
    flag <- function(k) E[[k]] == 1
    quita <- rep(NA_character_, n)
    sel <- construido & is.na(quita) & R$oa > 0 & E$agua >= R$oa; quita[sel] <- "ow"
    sel <- construido & is.na(quita) & R$op & flag("protegida"); quita[sel] <- "ow"
    cultivo <- flag("cultivo") | (R$oc == 2 & E$cobertura == 2)
    sel <- construido & is.na(quita) & elig & R$oc > 0 & E$edif == 0 & E$dedif >= 30 & cultivo; quita[sel] <- "oc"
    sel <- construido & is.na(quita) & elig & R$oct > 0 & E$calle >= R$oct & E$edif == 0; quita[sel] <- "od"
    sel <- construido & is.na(quita) & elig & R$os > 0 & E$dedif > R$os; quita[sel] <- "on"
    cls[!is.na(quita)] <- CLASES[quita[!is.na(quita)]]
    # aeropuertos: areas conexas (8 vecinos), activas si tocan la ciudad o GISD30 ve construido >= oab %
    activo <- rep(FALSE, n)
    if (R$ofa && any(E$aeropuerto == 1)) {
      r <- rast(code); values(r) <- ifelse(E$aeropuerto == 1, 1, NA)
      comp <- values(patches(r, directions = 8), mat = FALSE)
      ok <- !is.na(comp)
      A <- data.table(k = comp[ok], c = c0[ok])[, .(n = .N, b = sum(c %in% c(1, 3)), ci = sum(c %in% c(1, 2))), by = k]
      A[, act := (R$otc & ci > 0) | (R$oab > 0 & 100 * b / n >= R$oab)]
      activo[ok] <- comp[ok] %in% A$k[A$act]
    }
    llena <- (c0 == 2 & (activo | (R$ofp & flag("publico")) | (R$ofe > 0 & dp >= 0 & dp >= d2o & E$edif >= R$ofe))) |
             (c0 == 0 & activo)
    cls[llena] <- CLASES[["of"]]
  }
  esCiudad <- c0 == 1 | c0 == 2 | cls == CLASES[["of"]]
  esConstruido <- function() cls %in% CLASES[c("rb", "ru", "of", "rf")]

  # ---- regla 1 ----
  dist <- distancia_a(!esCiudad, code)
  share <- compartido(as.integer(esConstruido()), code)
  D <- if (R$on1) R$D else 0
  Ee <- if (R$on1 && D > 0) R$E else 0
  if (D > 0) {
    cls[esCiudad & cls == CLASES[["oo"]] & dist <= D] <- CLASES[["rr"]]
    if (Ee > 0) cls[esCiudad & cls == CLASES[["rb"]] & dist <= D & share < Ee] <- CLASES[["re"]]
  }

  # ---- regla 2 ----
  D2 <- densidad(esCiudad)
  d2 <- if (R$p2 == 0) 0 else pct(D2$univ, R$p2)
  dHi <- if (R$p2b > 100) Inf else pct(D2$univ, R$p2b)
  dTot <- if (R$p2t > 100) Inf else pct(D2$univ, R$p2t)
  dd <- D2$dens
  lim <- ifelse(!R$on2 | dd < 0, 0, ifelse(dd >= dTot, 9, ifelse(dd >= dHi, max(R$tamb, R$tam), ifelse(dd >= d2, R$tam, 0))))
  gok <- R$on2 & dd >= 0 & (dd >= d2 | dd >= dTot)
  agua <- E$agua >= 50
  int <- cls == CLASES[["oo"]] & !agua
  r <- rast(code); values(r) <- ifelse(int, 1, NA)
  lab <- values(patches(r, directions = 4), mat = FALSE)
  tamHa <- rep(NA_real_, n)
  if (any(!is.na(lab))) { ft <- tabulate(lab[!is.na(lab)]); tamHa[!is.na(lab)] <- ft[lab[!is.na(lab)]] * PX_KM2 * 100 }
  cubre <- rep(FALSE, n)
  if (R$on2 && R$gap > 0) {
    rg_ <- GAP_M[R$gap + 1]; b <- esConstruido()
    d1 <- distancia_a(b, code)
    dil <- d1 <= rg_
    d2x <- distancia_a(!dil, code)
    cubre <- !b & dil & d2x > rg_
  }
  li <- rep(0, n); go <- rep(FALSE, n); li[rid > 0] <- lim[rid[rid > 0]]; go[rid > 0] <- gok[rid[rid > 0]]
  candidato <- cls == CLASES[["oo"]]
  rell <- candidato & int & ((tamHa <= TAM_LIM[li + 1]) | (go & cubre))
  rell[is.na(rell)] <- FALSE
  cls[rell] <- CLASES[["rf"]]
  cls[candidato & !rell] <- CLASES[["ro"]]

  # ---- regla 3 ----
  share <- compartido(as.integer(esConstruido()), code)
  D3 <- densidad(esCiudad)
  d3t <- if (R$p3t >= 100) Inf else pct(D3$univ, R$p3t)
  bC <- porRadio(cls %in% CLASES[c("rb", "of", "rf")])
  okr <- bC > 0 & D3$km >= MIN_CIUDAD * area
  db <- pers[okr] / (bC[okr] * PX_KM2)
  d3 <- pct(db, R$p3)
  fuera <- R$fuera && R$modo != "piso"
  cand <- cls == CLASES[["rb"]] | (fuera & cls == CLASES[["ru"]])
  T <- data.table(r = rid[cand & rid > 0], s = share[cand & rid > 0], sinEd = E$edif[cand & rid > 0] == 0)
  nb <- tabulate(T$r, nbins = nr)
  fpx <- as.numeric(tapply(E$edif[rid > 0] / 100, factor(rid[rid > 0], levels = seq_len(nr)), sum)); fpx[is.na(fpx)] <- 0
  svc <- tabulate(rid[rid > 0 & (E$servicio == 1 | E$aeropuerto == 1)], nbins = nr)
  tot <- tabulate(rid[rid > 0], nbins = nr)
  rz <- if (R$modo == "huella") { ok <- nb > 0 & fpx > 0 & D3$km >= MIN_CIUDAD * area; nb[ok] / fpx[ok] } else numeric(0)
  rf_ <- if (length(rz)) pct(rz, R$pf) else Inf
  tr <- rep(-1, nr); soloSinEd <- rep(FALSE, nr)
  if (R$modo != "no") {
    H <- T[, .(h = list(tabulate(s + 1, nbins = 101)), hn = list(tabulate(s[sinEd] + 1, nbins = 101))), by = r]
    for (q in seq_len(nrow(H))) {
      r_ <- H$r[q]; d_ <- D3$dens[r_]
      if (!(d_ < 0 || d_ < d3t)) next
      if (R$modo == "huella") {
        razon <- if (fpx[r_] > 0) nb[r_] / fpx[r_] else Inf
        if (razon <= rf_) next
        if (R$sx > 0 && tot[r_] > 0 && 100 * svc[r_] / tot[r_] >= R$sx) next
        sobra <- nb[r_] - fpx[r_] * rf_; hn <- H$hn[[q]]; m <- 0; k <- 0
        while (k <= 100 && m < sobra) { m <- m + hn[k + 1]; k <- k + 1 }
        if (k > 0) { tr[r_] <- k; soloSinEd[r_] <- TRUE }
        next
      }
      keep <- -1
      if (R$modo == "piso" && bC[r_] > 0 && pers[r_] / (bC[r_] * PX_KM2) < d3) keep <- pers[r_] / d3 / PX_KM2
      if (R$modo == "tope" && !is.na(viv[r_])) keep <- viv[r_] * R$k
      if (keep >= 0) tr[r_] <- umbral(H$h[[q]], keep, R$S)
    }
  }
  ti <- rep(-1, n); ti[rid > 0] <- tr[rid[rid > 0]]
  se <- rep(FALSE, n); se[rid > 0] <- soloSinEd[rid[rid > 0]]
  cls[cand & ti >= 0 & share < ti & (!se | E$edif == 0)] <- CLASES[["rx"]]

  # ---- salidas y cifras ----
  k <- tabulate(cls, nbins = length(CLASES)) * PX_KM2; names(k) <- names(CLASES)
  kc <- tabulate(cls[c0 == 1 | c0 == 2], nbins = length(CLASES)) * PX_KM2; names(kc) <- names(CLASES)
  urb <- integer(n); urb[(cls == CLASES[["rb"]] & c0 == 1) | cls %in% CLASES[c("rf", "of")]] <- 1L; urb[cls == CLASES[["ru"]]] <- 2L
  rc <- rast(code); values(rc) <- cls
  ru <- rast(code); values(ru) <- urb
  list(clases = rc, urbanizado = ru,
       fila = data.table(anio = a, gisd30 = sum(c0 == 1) * PX_KM2, urbanizado = sum(urb == 1) * PX_KM2,
                         quitado_r0 = sum(kc[c("ow", "oc", "on", "od")]), lleno_r0 = k[["of"]], franja = k[["rr"]],
                         descontado_r1 = k[["re"]], lleno_r2 = k[["rf"]], abierto_capturado = k[["ro"]],
                         recortado_r3 = kc[["rx"]], fuera_quitado = sum(k[c("ow", "oc", "on", "od", "rx")]) - sum(kc[c("ow", "oc", "on", "od", "rx")]),
                         personas = sum(pers[D0$km > 0])))
}

una <- function(slug) {
  t0 <- Sys.time()
  x <- cargar_densidad(RPIPE, slug)
  fe <- file.path(ETQ, slug, "etiquetas.tif")
  if (is.null(x) || !file.exists(fe)) { cat("  ", slug, ": faltan datos\n"); return(NULL) }
  et <- rast(fe)
  dir <- file.path(SAL, slug); dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  filas <- lapply(ANIOS, function(a) {
    o <- anio_ciudad(slug, a, x[[as.character(a)]], et)
    writeRaster(o$clases, file.path(dir, sprintf("clases_%d.tif", a)), overwrite = TRUE, datatype = "INT1U", gdal = "COMPRESS=DEFLATE")
    writeRaster(o$urbanizado, file.path(dir, sprintf("urbanizado_%d.tif", a)), overwrite = TRUE, datatype = "INT1U", gdal = "COMPRESS=DEFLATE")
    o$fila
  })
  res <- rbindlist(filas); res[, `:=`(slug = slug, nombre = x$nombre)]
  cat(sprintf("  %-22s 1990 %6.1f -> %6.1f km2 · 2020 %6.1f -> %6.1f km2 (%.1f min)\n", slug,
              res$gisd30[1], res$urbanizado[1], res$gisd30[4], res$urbanizado[4], as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  res
}

cat(sprintf("Construido corregido · %d aglomerados\n", length(CIUDADES)))
RES <- rbindlist(lapply(CIUDADES, function(s) tryCatch(una(s), error = function(e) { cat("  ERROR", s, ":", conditionMessage(e), "\n"); NULL })))
dir.create(file.path(REP, "img"), recursive = TRUE, showWarnings = FALSE)
f_res <- file.path(REP, "resumen.csv")
if (file.exists(f_res) && length(CIUDADES) < length(TODAS)) {
  prev <- fread(f_res); RES <- rbind(prev[!slug %in% RES$slug], RES, fill = TRUE)
}
setorder(RES, nombre, anio)
fwrite(RES, f_res)

# ---------- reporte ----------
crec <- RES[, .(g90 = gisd30[anio == 1990], g20 = gisd30[anio == 2020], u90 = urbanizado[anio == 1990], u20 = urbanizado[anio == 2020]), by = .(slug, nombre)]
crec[, `:=`(tg = tasa(g90, g20, 30), tu = tasa(u90, u20, 30))]
g <- ggplot(melt(crec, id.vars = c("slug", "nombre"), measure.vars = c("tg", "tu")),
            aes(value, reorder(nombre, value), colour = variable)) + geom_point(size = 2.4) +
  scale_colour_manual(values = c(tg = "#8a8985", tu = "#1f4e79"), labels = c("GISD30 as is", "corrected"), name = NULL) +
  labs(x = "annual growth of built-up / urbanized land 1990-2020 (%)", y = NULL, title = "Growth before and after the correction", caption = PIE) + tema
guardar(g, file.path(REP, "img"), "crecimiento.png", w = 9, h = 8)
L <- c("# Corrected built-up: rules 0-3 in sequence", "",
       "Exploratory. No number here is a project figure; Overture Maps is a validation layer, not an approved project source. Generated by `scripts/23_corregido.R`; do not edit by hand.", "",
       "Each rule works on the layer the previous one left, with the geometry recomputed in between (edge distance, % built-up within 150 m, open patches, gaps, tract densities). **Urbanized** = GISD30 built-up kept + filled by rule 0 + filled by rule 2. Rasters per city and year in `outputs/corregido/<slug>/` (`clases_<year>.tif`, `urbanizado_<year>.tif`).", "",
       "## Settings", "", paste0("`rg=", paste(vapply(CLAVES, function(k) { v <- R[[k]]; if (is.logical(v)) as.character(as.integer(v)) else as.character(v) }, ""), collapse = ","), "`"), "",
       "Same order as the cleaning viewer's link, so the run can be reproduced there.", "",
       "## Growth 1990-2020", "", "![growth](img/crecimiento.png)", "",
       tabla(c("Agglomeration", "GISD30 1990 km2", "Urbanized 1990 km2", "GISD30 2020 km2", "Urbanized 2020 km2", "Growth GISD30 %/yr", "Growth corrected %/yr"),
             lapply(seq_len(nrow(crec)), function(j) with(crec[j], c(nombre, f1(g90), f1(u90), f1(g20), f1(u20), f2(tg), f2(tu))))), "",
       "## What each rule did, by year", "",
       tabla(c("Agglomeration", "Year", "GISD30", "− rule 0", "+ rule 0", "− rule 1", "+ rule 2", "− rule 3", "= urbanized", "fringe", "captured open", "removed outside the city"),
             lapply(seq_len(nrow(RES)), function(j) with(RES[j], c(nombre, anio, f1(gisd30), f1(quitado_r0), f1(lleno_r0), f1(descontado_r1),
                                                                     f1(lleno_r2), f1(recortado_r3), f1(urbanizado), f1(franja), f1(abierto_capturado), f1(fuera_quitado))))),
       "", "All values in km². “− rule 0” counts city built-up removed; “+ rule 0” includes airport land outside the city.")
writeLines(L, file.path(REP, "REPORTE.md"), useBytes = TRUE)
cat("Listo:", file.path(REP, "REPORTE.md"), "\n")
