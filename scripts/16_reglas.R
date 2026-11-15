# -*- coding: utf-8 -*-
# Paso 16 · Reglas: prueba 3 (corte relativo por aglomerado) y relleno del centro. 1990-2020.
# Exploratorio: ningun numero es cifra del proyecto.
#
# DOS PROBLEMAS DE LA FRANJA DE ANGEL, dos reglas:
#
# 1. PRUEBA 3, corte relativo. Las pruebas 1 y 2 usan cortes absolutos (personas/km2) iguales
#    para todos los aglomerados, pero la distribucion de la densidad de los radios cambia
#    mucho entre ciudades y entre censos. Aca el corte es un percentil de la propia ciudad:
#        ciudad(p) = construido + franja y capturado de los radios con dens_urb >= P_p
#        P_p = percentil p de dens_urb de los radios de esa ciudad y ese censo
#    Universo del percentil: radios con al menos 10 % de su superficie en la ciudad (un radio
#    con una astilla de ciudad tiene una densidad urbanizada inflada). La regla de la franja
#    se aplica a todos los radios, como en 13: lo construido nunca sale.
#
# 2. RELLENO DEL CENTRO. En centros viejos (Salta, Tucuman, Catamarca) GISD30 deja pixeles
#    sin detectar en medio de manzanas construidas: Angel los llama franja o capturado, pero
#    son construido mal leido. Se separan del anillo de franja del borde con tres medidas por
#    pixel abierto de la ciudad:
#      dist   distancia (m) al suelo mas cercano fuera de la ciudad: el anillo del borde esta
#             cerca, el centro lejos
#      hueco  el menor cierre morfologico (dilatar y erosionar lo construido con una ventana
#             cuadrada de 30, 60 o 90 m de radio) que tapa el pixel: un hueco angosto entre
#             construido (calle arbolada, patio, techo mal leido) se tapa con 30-60 m; una
#             plaza o un parque, no
#      share  parte de los pixeles en 150 m a la redonda que son construidos (GISD30, dentro o
#             fuera de la ciudad)
#    Regla de relleno: un pixel abierto con dist > D que tapa el cierre de radio r (regla de
#    hueco) o con share >= S (regla de share) pasa a construido. Central: hueco de 60 m y
#    D = 200 m. La de share (80 %, la idea inicial) casi no rellena: en el centro de Salta 1990
#    GISD30 ve construido alrededor de la mitad de los pixeles, asi que los huecos tienen 30-60 %
#    de construido en 150 m, no 80 %. Sensibilidad: r = 30/60/90 m, S = 60/70/80/90 %,
#    D = 100/200/400 m; con la condicion de radio denso (dens_urb >= 500) o sin ella. Dentro de
#    la ciudad de Angel el relleno no cambia la extension: cambia que parte es construido. En las
#    pruebas 1 a 3 si cambia la extension cuando el relleno no exige radio denso.
#    MASCARA DE AGUA (2026-11-15, tras la revision visual): rios, canales y brazos de lagunas son
#    huecos angostos entre construido y el cierre los rellenaba como cintas. No se rellenan nunca:
#    el agua de JRC Global Surface Water (ocurrencia >= 25 %) con 60 m de orilla, y los rios (90 m
#    a cada lado), canales (30 m) y espejos de agua de OpenStreetMap, que si ven los rios angostos
#    o secos casi todo el anio (Sali, Arenales). No cubre el regadio que GISD30 marca como
#    construido (valle inferior del Chubut, Maipu, Santa Lucia): eso sigue abierto.
#
# ENTRADAS  outputs/densidad/<slug>/ (paso 11); JRC Global Surface Water v1.4, ocurrencia,
#           leida por ventana de storage.googleapis.com/global-surface-water
#           raw/osm/argentina-latest.osm.pbf (Geofabrik): rios, canales y agua -> outputs/osm/agua_osm.gpkg
# SALIDAS   outputs/reglas/<slug>/reglas_<anio>.tif   dist (m), share (%), hueco (0-3) y agua por pixel; lo lee 15
#           outputs/reglas/<slug>/agua.tif
#           pruebas/reglas/<slug>/REPORTE.md, img/, tablas/
#           pruebas/reglas/REPORTE.md   indice y comparacion entre aglomerados
#
# Uso: Rscript Rpipe/scripts/16_reglas.R [--ciudades salta,jujuy] [--sin-mapas] [--rehacer]
#        --rehacer recalcula los rasters de dist y share aunque existan

Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))
options(warn = 1)
Sys.setenv(GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR")
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
SIN_MAPAS <- "--sin-mapas" %in% args
REHACER <- "--rehacer" %in% args
BASE <- file.path(RPIPE, "pruebas", "reglas")
DENS <- file.path(RPIPE, "outputs", "densidad")
SAL <- file.path(RPIPE, "outputs", "reglas")
CIUDADES <- if (is.na(match("--ciudades", args))) {
  sort(basename(dirname(list.files(DENS, "^ciudad\\.csv$", recursive = TRUE, full.names = TRUE))))
} else strsplit(arg("--ciudades", ""), ",")[[1]]

PCTS <- c(10, 20, 25, 30, 40, 50, 60, 70, 75, 80, 90)
P_C <- 25                          # percentil central de los resumenes
MIN_CIUDAD <- 0.10                 # universo del percentil: >= 10 % del radio en la ciudad
RADIO_SHARE <- 150                 # m, vecindario del share
D_OPC <- c(100, 200, 400); S_OPC <- c(60, 70, 80, 90); H_OPC <- c(30, 60, 90)
D_C <- 200; H_C <- 60; T_C <- 500  # regla central de relleno: hueco de 60 m a mas de 200 m del borde
REGLAS <- rbind(expand.grid(tipo = "hueco", valor = H_OPC, D = D_OPC, stringsAsFactors = FALSE),
                expand.grid(tipo = "share", valor = S_OPC, D = D_OPC, stringsAsFactors = FALSE))
REGLAS$id <- sprintf("%s%d_D%d", REGLAS$tipo, REGLAS$valor, REGLAS$D)
CENTRAL <- sprintf("hueco%d_D%d", H_C, D_C)
DCLASE <- c(0, 100, 200, 400)      # dclase k = cuantos de estos umbrales supera dist (0-3)
KM2 <- 900 / 1e6                   # un pixel de 30 m


# ---- rasters por pixel ------------------------------------------------------------------

VIAS <- file.path(RPIPE, "outputs", "osm", "agua_osm.gpkg")
vias_agua <- function() {
  # una vez: rios, canales y agua de OpenStreetMap (extracto de Geofabrik de la Argentina,
  # raw/osm/argentina-latest.osm.pbf) a outputs/osm/agua_osm.gpkg
  if (file.exists(VIAS)) return(invisible())
  pbf <- file.path(RPIPE, "raw", "osm", "argentina-latest.osm.pbf")
  if (!file.exists(pbf)) stop("falta ", pbf, " (https://download.geofabrik.de/south-america/argentina-latest.osm.pbf)")
  dir.create(dirname(VIAS), recursive = TRUE, showWarnings = FALSE)
  cat("  cursos de agua de OSM (una vez, unos minutos)\n")
  l <- vect(pbf, layer = "lines", query = "SELECT osm_id, waterway FROM lines WHERE waterway IN ('river', 'canal')")
  writeVector(l, VIAS, layer = "lineas", overwrite = TRUE)
  p <- vect(pbf, layer = "multipolygons", query = "SELECT osm_id, natural FROM multipolygons WHERE natural = 'water'")
  writeVector(p, VIAS, layer = "poligonos", insert = TRUE)
}


agua_de <- function(code, f) {
  # mascara de agua: JRC Global Surface Water 1984-2021 (Pekel y otros 2016, v1.4), ocurrencia
  # >= 25 % (rios, lagunas, canales, tambien los de agua estacional), mas 60 m alrededor para las
  # orillas. Se lee por ventana desde el bucket publico; el marco es el mismo los cuatro anios.
  if (file.exists(f) && !REHACER) return(rast(f))
  e <- as.vector(ext(project(as.polygons(ext(code), crs = crs(code)), "EPSG:4326")))
  lon <- seq(floor(e[["xmin"]] / 10) * 10, floor(e[["xmax"]] / 10) * 10, by = 10)
  lat <- seq(ceiling(e[["ymin"]] / 10) * 10, ceiling(e[["ymax"]] / 10) * 10, by = 10)
  trozos <- list()
  for (x in lon) for (y in lat) {
    nom <- sprintf("occurrence_%d%s_%d%s", abs(x), if (x < 0) "W" else "E", abs(y), if (y <= 0) "S" else "N")
    r <- rast(sprintf("/vsicurl/https://storage.googleapis.com/global-surface-water/downloads2021/occurrence/%sv1_4_2021.tif", nom))
    trozos[[nom]] <- crop(r, ext(e[["xmin"]] - 0.01, e[["xmax"]] + 0.01, e[["ymin"]] - 0.01, e[["ymax"]] + 0.01))
  }
  occ <- if (length(trozos) == 1) trozos[[1]] else do.call(merge, unname(trozos))
  occ <- project(occ, code, method = "max")
  a <- ifel(!is.na(occ) & occ >= 25 & occ <= 100, 1, 0)
  a <- focal(a, matrix(1, 5, 5), "max", na.rm = TRUE)          # 60 m de orilla
  # GSW no ve los rios angostos o secos la mayor parte del anio (Sali, Arenales): se suman los
  # cursos de OpenStreetMap. Rio: 90 m a cada lado (el cauce de los rios de montania es ancho);
  # canal: 30 m; agua como poligono: tal cual
  vias_agua()
  ee <- ext(e[["xmin"]], e[["xmax"]], e[["ymin"]], e[["ymax"]])
  l <- vect(VIAS, layer = "lineas", extent = ee)
  if (nrow(l)) {
    l <- project(l, crs(code))
    for (t in c("river", "canal")) {
      lt <- l[l$waterway == t, ]
      if (nrow(lt)) a <- ifel(rasterize(buffer(lt, if (t == "river") 90 else 30), code, touches = TRUE, background = 0) == 1, 1, a)
    }
  }
  p <- vect(VIAS, layer = "poligonos", extent = ee)
  if (nrow(p)) a <- ifel(rasterize(project(p, crs(code)), code, touches = TRUE, background = 0) == 1, 1, a)
  writeRaster(a, f, overwrite = TRUE, datatype = "INT1U", gdal = "COMPRESS=DEFLATE")
  rast(f)
}


reglas_raster <- function(code, f, agua) {
  # dist: m al pixel mas cercano fuera de la ciudad (solo en la ciudad); share: % construido
  # en 150 m (todo pixel); hueco: menor k (1-3, k*30 m) cuyo cierre tapa el pixel, 0 ninguno;
  # agua: 1 si es agua u orilla (JRC GSW). En el agua y su orilla ni el hueco ni el share
  # rellenan: se guardan en 0. Se guarda y se reusa.
  if (file.exists(f) && !REHACER && nlyr(rast(f)) == 4) return(rast(f))
  fuera <- ifel(code == 1 | code == 2, NA, 1)
  d <- distance(fuera)
  d <- ifel(code == 1 | code == 2, d, 0)
  w <- focalMat(code, RADIO_SHARE, "circle"); w[w > 0] <- 1
  b <- ifel(code == 1 | code == 3, 1, 0)
  share <- focal(b, w, fun = "sum", na.rm = TRUE) / sum(w)
  hueco <- b * 0
  for (k in 3:1) {
    m <- matrix(1, 2 * k + 1, 2 * k + 1)
    cierre <- focal(focal(b, m, "max", na.rm = TRUE), m, "min", na.rm = TRUE)
    hueco <- ifel(b == 0 & cierre == 1, k, hueco)
  }
  r <- c(clamp(round(d), 0, 65535), ifel(agua == 1, 0, round(100 * share)), ifel(agua == 1, 0, hueco), agua)
  names(r) <- c("dist", "share", "hueco", "agua")
  writeRaster(r, f, overwrite = TRUE, datatype = "INT2U", gdal = "COMPRESS=DEFLATE")
  rast(f)
}


abierto_por_radio <- function(code, rr, rid) {
  # pixeles abiertos de la ciudad por radio, clase de distancia, hueco y share en decimos
  dcl <- (rr$dist > 100) + (rr$dist > 200) + (rr$dist > 400)
  sdec <- min(rr$share %/% 10, 10)
  k <- ifel(code == 2, dcl * 44 + rr$hueco * 11 + sdec, NA)
  ct <- crosstab(c(ifel(is.na(rid), 0, rid), k), long = TRUE, useNA = FALSE)
  names(ct) <- c("i", "k", "n")
  data.frame(i = ct$i, dclase = ct$k %/% 44, hueco = (ct$k %% 44) %/% 11, sdec = ct$k %% 11, n = ct$n)
}


rellena <- function(ab, id) {
  r <- REGLAS[REGLAS$id == id, ]
  ab$dclase >= match(r$D, DCLASE) - 1 &
    (if (r$tipo == "hueco") ab$hueco >= 1 & ab$hueco <= r$valor / 30 else ab$sdec >= r$valor / 10)
}
km2_relleno <- function(ab, id, ids = NULL) {
  m <- rellena(ab, id)
  if (!is.null(ids)) m <- m & ab$i %in% ids
  sum(ab$n[m]) * KM2
}
por_radio_relleno <- function(ab, id, n_filas) {
  m <- rellena(ab, id)
  v <- tapply(ab$n[m] * KM2, factor(ab$i[m], levels = seq_len(n_filas)), sum)
  ifelse(is.na(v), 0, v)
}


cortes_pct <- function(t) {
  u <- t$km2_urb > 0 & !is.na(t$dens_urb) & t$km2_urb >= MIN_CIUDAD * t$km2_radio
  setNames(quantile(t$dens_urb[u], PCTS / 100, names = FALSE, type = 7), PCTS)
}


# ---- una ciudad --------------------------------------------------------------------------

una <- function(slug) {
  x <- cargar_densidad(RPIPE, slug)
  if (is.null(x)) { cat("  sin salida de 11:", slug, "\n"); return(NULL) }
  NOMBRE <- x$nombre
  dir <- file.path(BASE, slug); img <- file.path(dir, "img"); tab <- file.path(dir, "tablas")
  dir.create(img, recursive = TRUE, showWarnings = FALSE); dir.create(tab, showWarnings = FALSE)
  dsal <- file.path(SAL, slug); dir.create(dsal, recursive = TRUE, showWarnings = FALSE)
  t0 <- Sys.time()

  agua <- agua_de(x[["2020"]]$code, file.path(dsal, "agua.tif"))
  datos <- lapply(setNames(ANIOS, ANIOS), function(a) {
    y <- x[[as.character(a)]]
    rr <- reglas_raster(y$code, file.path(dsal, sprintf("reglas_%d.tif", a)), agua)
    rid <- rasterize(y$v, y$code, field = "i")
    list(rr = rr, rid = rid, ab = abierto_por_radio(y$code, rr, rid))
  })

  # ---- prueba 3: percentiles propios
  p3 <- do.call(rbind, lapply(ANIOS, function(a) {
    t <- x[[as.character(a)]]$t; en <- t$km2_urb > 0
    cp <- cortes_pct(t)
    do.call(rbind, lapply(c(0, PCTS, Inf), function(p) {
      k <- if (p == 0) 0 else if (is.infinite(p)) Inf else cp[[as.character(p)]]
      entra <- en & !is.na(t$dens_urb) & t$dens_urb >= k
      data.frame(anio = a, pct = p, corte = k, construido_km2 = sum(t$km2_construido[en]),
                 franja_total_km2 = sum(t$km2_abierto[en]), franja_entra_km2 = sum(t$km2_abierto[entra]),
                 radios_universo = sum(en & !is.na(t$dens_urb) & t$km2_urb >= MIN_CIUDAD * t$km2_radio),
                 radios_franja = sum(entra & t$km2_abierto > 0), personas = sum(t$personas[en]))
    }))
  }))
  p3$ciudad_km2 <- p3$construido_km2 + p3$franja_entra_km2
  p3$pct_franja_entra <- 100 * p3$franja_entra_km2 / p3$franja_total_km2
  write.csv(p3, file.path(tab, "prueba3.csv"), row.names = FALSE)
  g3 <- function(a, p, col) p3[[col]][p3$anio == a & p3$pct == p]

  # ---- relleno: cada regla (hueco y share, por distancia al borde), con y sin radio denso
  rel <- do.call(rbind, lapply(ANIOS, function(a) {
    t <- x[[as.character(a)]]$t; ab <- datos[[as.character(a)]]$ab; en <- t$km2_urb > 0
    densos <- t$i_fila[en & !is.na(t$dens_urb) & t$dens_urb >= T_C]
    do.call(rbind, lapply(seq_len(nrow(REGLAS)), function(j) {
      r <- REGLAS[j, ]
      data.frame(anio = a, regla = r$id, tipo = r$tipo, valor = r$valor, D = r$D, abierto_km2 = sum(ab$n) * KM2,
                 abierto_interior_km2 = sum(ab$n[ab$dclase >= match(r$D, DCLASE) - 1]) * KM2,
                 relleno_km2 = km2_relleno(ab, r$id), relleno_denso_km2 = km2_relleno(ab, r$id, densos),
                 construido_km2 = sum(t$km2_construido[en]), personas = sum(t$personas[en]))
    }))
  }))
  rel$construido_rel_km2 <- rel$construido_km2 + rel$relleno_denso_km2
  rel$pct_abierto_relleno <- 100 * rel$relleno_km2 / rel$abierto_km2
  rel$pct_interior_relleno <- 100 * rel$relleno_km2 / rel$abierto_interior_km2
  write.csv(rel, file.path(tab, "relleno.csv"), row.names = FALSE)
  gr <- function(a, col, id = CENTRAL) rel[[col]][rel$anio == a & rel$regla == id]

  # premisa con y sin relleno: personas por km2 construido de la ciudad
  prem <- do.call(rbind, lapply(ANIOS, function(a) {
    t <- x[[as.character(a)]]$t
    data.frame(anio = a, personas = sum(t$personas[t$km2_urb > 0]),
               construido_km2 = gr(a, "construido_km2"), construido_rel_km2 = gr(a, "construido_rel_km2"))
  }))
  prem$dens <- prem$personas / prem$construido_km2; prem$dens_rel <- prem$personas / prem$construido_rel_km2
  write.csv(prem, file.path(tab, "premisa.csv"), row.names = FALSE)

  # prueba 3 + relleno sin condicion de densidad (la extension que mas cambia)
  comb <- do.call(rbind, lapply(ANIOS, function(a) {
    t <- x[[as.character(a)]]$t; en <- t$km2_urb > 0
    r <- por_radio_relleno(datos[[as.character(a)]]$ab, CENTRAL, nrow(t))[t$i_fila]
    k <- cortes_pct(t)[[as.character(P_C)]]
    entra <- en & !is.na(t$dens_urb) & t$dens_urb >= k
    data.frame(anio = a, prueba3_km2 = sum(t$km2_construido[en]) + sum(t$km2_abierto[entra]),
               prueba3_relleno_km2 = sum(t$km2_construido[en]) + sum(t$km2_abierto[entra]) + sum(r[en & !entra]),
               angel_km2 = sum(t$km2_urb[en]))
  }))
  write.csv(comb, file.path(tab, "prueba3_relleno.csv"), row.names = FALSE)

  # ---- distribucion de la densidad de los radios (para el grafico y el visor)
  dist_d <- do.call(rbind, lapply(ANIOS, function(a) {
    t <- x[[as.character(a)]]$t
    u <- t$km2_urb > 0 & !is.na(t$dens_urb) & t$km2_urb >= MIN_CIUDAD * t$km2_radio & t$dens_urb > 0
    data.frame(anio = factor(a), dens = t$dens_urb[u])
  }))
  cps <- do.call(rbind, lapply(ANIOS, function(a)
    data.frame(anio = factor(a), p = c(10, P_C, 50, 75, 90),
               v = cortes_pct(x[[as.character(a)]]$t)[as.character(c(10, P_C, 50, 75, 90))])))

  # ---- graficos
  guardar(ggplot(dist_d, aes(dens)) +
    geom_histogram(aes(fill = anio), bins = 40, colour = FONDO, linewidth = 0.2) +
    geom_vline(data = cps, aes(xintercept = v), colour = TINTA2, linetype = "22", linewidth = 0.4) +
    geom_text(data = cps, aes(x = v, y = Inf, label = paste0("p", p)), vjust = 1.4, hjust = -0.1, size = 3, colour = TINTA2) +
    facet_wrap(~anio, ncol = 1, labeller = labeller(anio = function(a) sprintf("%s (census %s)", a, CENSO[a]))) +
    scale_x_log10(labels = f0, breaks = c(10, 100, 300, 1000, 3000, 10000, 30000)) +
    scale_fill_manual(values = COL_ANIO, guide = "none") +
    labs(x = "Tract density on urbanized land (persons / km², log scale)", y = "tracts",
         title = sprintf("%s · density of the census tracts, by census", NOMBRE),
         subtitle = sprintf("Tracts with at least %d %% of their area in the city. Dashed: the city's own percentiles", round(100 * MIN_CIUDAD)),
         caption = PIE) + tema, img, "distribucion.png", w = 9, h = 8)
  r3 <- p3[is.finite(p3$pct), ]
  guardar(ggplot(r3, aes(pct, ciudad_km2, colour = factor(anio))) + geom_line(linewidth = 0.9) + geom_point(size = 2.2) +
    geom_hline(data = p3[is.infinite(p3$pct), ], aes(yintercept = ciudad_km2, colour = factor(anio)), linetype = "22", linewidth = 0.4) +
    scale_colour_manual(values = COL_ANIO) + scale_x_continuous(breaks = c(0, PCTS), labels = c("none", PCTS)) +
    scale_y_continuous(limits = c(0, NA), labels = f0) +
    labs(x = "Fringe dropped in tracts below this percentile of the city's own density", y = "km²", colour = NULL,
         title = sprintf("%s · test 3, city size by percentile", NOMBRE),
         subtitle = "Built-up always counts. Dashed: built-up only", caption = PIE) + tema, img, "prueba3_por_percentil.png")
  cc <- p3[p3$pct %in% c(10, 25, 50, 75, 90), ]
  guardar(ggplot(cc, aes(anio, corte, colour = factor(pct))) + geom_line(linewidth = 0.9) + geom_point(size = 2.2) +
    scale_colour_manual(values = colorRampPalette(c("#a9c6e6", "#0b2642"))(5)) +
    scale_x_continuous(breaks = ANIOS) + scale_y_continuous(labels = f0, limits = c(0, NA)) +
    labs(x = NULL, y = "persons / km² urbanized", colour = "percentile",
         title = sprintf("%s · what each percentile means in persons per km²", NOMBRE),
         subtitle = "The same percentile is a different absolute cut in each census", caption = PIE) + tema,
    img, "percentiles_absolutos.png", w = 8, h = 4.8)
  rs <- rel
  rs$D <- factor(paste0("> ", rs$D, " m from the edge"), levels = paste0("> ", D_OPC, " m from the edge"))
  rs$regla_txt <- factor(ifelse(rs$tipo == "hueco", paste0("gap ", rs$valor, " m"), paste0("share ", rs$valor, " %")),
                         levels = c(paste0("gap ", H_OPC, " m"), paste0("share ", rev(S_OPC), " %")))
  guardar(ggplot(rs, aes(anio, relleno_km2, colour = regla_txt)) + geom_line(linewidth = 0.8) + geom_point(size = 1.8) +
    facet_wrap(~D) + scale_colour_manual(values = c("#0b2642", "#1f4e79", "#8db3dd", "#f2c500", "#e09f3e", "#c4622d", "#7a3b1d")) +
    scale_x_continuous(breaks = ANIOS) + scale_y_continuous(limits = c(0, NA), labels = f1) +
    labs(x = NULL, y = "km² of open city land filled", colour = "rule",
         title = sprintf("%s · how much open land each fill rule turns into built-up", NOMBRE),
         subtitle = "Gap: closed by dilating and eroding the built-up by r. Share: at least S % built within 150 m", caption = PIE) +
    tema + theme(legend.position = "right"), img, "relleno_sensibilidad.png", w = 10, h = 4.8)

  # ---- mapas
  if (!SIN_MAPAS) {
    # anillo y centro: construido, abierto del borde, abierto interior, relleno, construido fuera
    pal_a <- c("#fcfcfb", "#1f4e79", "#efb48f", "#8e44ad", "#2a9d8f", "#cfcdc6")
    capas <- rast(lapply(ANIOS, function(a) {
      y <- x[[as.character(a)]]; rr <- datos[[as.character(a)]]$rr
      int <- rr$dist > D_C; rl <- int & rr$hueco >= 1 & rr$hueco <= H_C / 30
      ifel(y$code == 1, 1, ifel(y$code == 2, ifel(rl, 4, ifel(int, 3, 2)), ifel(y$code == 3, 5, 0)))
    }))
    tit <- vapply(ANIOS, function(a) sprintf("%d · fill %s km² (%s%% of open land)", a, f1(gr(a, "relleno_km2")),
                                             f0(gr(a, "pct_abierto_relleno"))), "")
    mapa_paneles(file.path(img, "anillo_centro.png"), capas, pal_a, tit,
                 sprintf("%s · open land of the city: edge ring vs interior, and the fill rule (gaps up to %d m, > %d m from the edge)", NOMBRE, H_C, D_C),
                 c("built-up", sprintf("open, edge ring (<= %d m)", D_C), "open, interior", "open, interior, filled", "built outside the city"),
                 x$cont)
    pal_3 <- c("#fcfcfb", "#1f4e79", "#8e44ad", "#d7263d", "#cfcdc6")
    capas <- rast(lapply(ANIOS, function(a) {
      y <- x[[as.character(a)]]; rid <- datos[[as.character(a)]]$rid
      ok <- marcar(rid, radios_con(y$t, cortes_pct(y$t)[[as.character(P_C)]]))
      ifel(y$code == 1, 1, ifel(y$code == 2, ifel(ok, 2, 3), ifel(y$code == 3, 4, 0)))
    }))
    tit <- vapply(ANIOS, function(a) sprintf("%d · p%d = %s p/km² · %s km²", a, P_C, f0(g3(a, P_C, "corte")), f1(g3(a, P_C, "ciudad_km2"))), "")
    mapa_paneles(file.path(img, "prueba3.png"), capas, pal_3, tit,
                 sprintf("%s · test 3: fringe only in tracts above the city's own %dth percentile", NOMBRE, P_C),
                 c("built-up (always city)", "fringe/captured, added", "fringe/captured, left out", "built outside the city"), x$cont)
  }

  # ---- reporte
  L <- c(sprintf("# %s · relative cut (test 3) and the fill rule, 1990-2020", NOMBRE), "",
    sprintf("Exploratory. None of these numbers are project figures (they are not in `CIFRAS_CANONICAS.json`). Generated by `Rpipe/scripts/16_reglas.R` from step 11. Run of %s. [All agglomerations](../REPORTE.md) · [methods](../../METODOS.md).", format(Sys.Date())), "",
    "## The density of the tracts", "",
    sprintf("Tracts with at least %d %% of their area in the city, and the city's own percentiles of their density on urbanized land.", round(100 * MIN_CIUDAD)), "",
    tabla(c("Year", "Tracts", paste0("p", c(10, 25, 50, 75, 90))),
          lapply(ANIOS, function(a) c(sprintf("%d (census %s)", a, CENSO[[as.character(a)]]), f0(g3(a, 0, "radios_universo")),
                                       f0(cortes_pct(x[[as.character(a)]]$t)[as.character(c(10, 25, 50, 75, 90))])))), "",
    "![Density distribution](img/distribucion.png)", "", "![Percentiles in persons per km²](img/percentiles_absolutos.png)", "",
    "## Test 3 · fringe only above the city's own percentile", "",
    "Built-up land is always city. Fringe and captured land join only in tracts at or above percentile p of the city's own tract densities, that census.", "",
    tabla(c("Percentile", paste0(ANIOS, " cut p/km²"), paste0(ANIOS, " km²"), "1990-2020 %/yr"),
          lapply(c(0, PCTS, Inf), function(p) {
            v <- vapply(ANIOS, function(a) g3(a, p, "ciudad_km2"), 1)
            k <- vapply(ANIOS, function(a) g3(a, p, "corte"), 1)
            c(if (p == 0) "none (Angel)" else if (is.infinite(p)) "built only" else paste0("p", p),
              if (p == 0) rep("0", 4) else if (is.infinite(p)) rep("—", 4) else f0(k), f1(v), f2(tasa(v[1], v[4], 30)))
          })), "",
    "![Test 3 by percentile](img/prueba3_por_percentil.png)", "",
    "## Fill rule · open land in the centre that is probably built", "",
    sprintf("An open pixel of the city (fringe or captured) farther than D from any land outside the city becomes built-up if it is a narrow gap in the built-up: closing the built-up (dilate, then erode) with a square of radius r covers it. Central rule: r = %d m, D = %d m; *dense* = tract at or above %s p/km². The alternative share rule fills a pixel with at least S of the pixels within %d m built.", H_C, D_C, f0(T_C), RADIO_SHARE), "",
    tabla(c("Year", "Open city land km²", sprintf("Interior (> %d m) km²", D_C), "Filled km²", "Filled in dense tracts km²", "Built-up km²", "Built-up + fill km²", "Persons / km² built", "With fill"),
          lapply(ANIOS, function(a) c(sprintf("%d (census %s)", a, CENSO[[as.character(a)]]), f1(gr(a, "abierto_km2")), f1(gr(a, "abierto_interior_km2")),
            f1(gr(a, "relleno_km2")), f1(gr(a, "relleno_denso_km2")), f1(gr(a, "construido_km2")), f1(gr(a, "construido_rel_km2")),
            f0(prem$dens[prem$anio == a]), f0(prem$dens_rel[prem$anio == a])))), "",
    "![Fill sensitivity](img/relleno_sensibilidad.png)", "",
    "**Sensitivity: km² filled by each rule** (in brackets, % of the interior open land):", "",
    tabla(c("Year", "Farther than", paste0("gap ", H_OPC, " m"), paste0("share ", S_OPC, " %")),
          unlist(lapply(ANIOS, function(a) lapply(D_OPC, function(D)
            c(a, paste(D, "m"), vapply(c(paste0("hueco", H_OPC, "_D", D), paste0("share", S_OPC, "_D", D)), function(id)
              sprintf("%s (%s)", f1(gr(a, "relleno_km2", id)), f0(gr(a, "pct_interior_relleno", id))), "")))), recursive = FALSE)), "",
    sprintf("**Test 3 at p%d plus the central fill, without asking for a dense tract** (the fill keeps interior gaps of sparse tracts that test 3 drops):", P_C), "",
    tabla(c("Year", "Angel km²", sprintf("Test 3 p%d km²", P_C), "Test 3 + fill km²"),
          lapply(seq_len(nrow(comb)), function(i) with(comb[i, ], c(anio, f1(angel_km2), f1(prueba3_km2), f1(prueba3_relleno_km2))))), "")
  if (file.exists(file.path(img, "anillo_centro.png")))
    L <- c(L, "## Maps", "", "### Edge ring, interior and fill", "", "![Edge ring and interior](img/anillo_centro.png)", "",
           sprintf("### Test 3 at p%d", P_C), "", "![Test 3](img/prueba3.png)", "")
  writeLines(enc2utf8(L), file.path(dir, "REPORTE.md"), useBytes = TRUE)
  cat(sprintf("  %-22s listo (%.1f min)\n", slug, as.numeric(difftime(Sys.time(), t0, units = "mins"))))

  data.frame(slug = slug, nombre = NOMBRE,
             p25_1990 = g3(1990, P_C, "corte"), p25_2020 = g3(2020, P_C, "corte"),
             angel_1990 = g3(1990, 0, "ciudad_km2"), angel_2020 = g3(2020, 0, "ciudad_km2"),
             p3_1990 = g3(1990, P_C, "ciudad_km2"), p3_2020 = g3(2020, P_C, "ciudad_km2"),
             abierto_1990 = gr(1990, "abierto_km2"), abierto_2020 = gr(2020, "abierto_km2"),
             relleno_1990 = gr(1990, "relleno_km2"), relleno_2020 = gr(2020, "relleno_km2"),
             constr_1990 = gr(1990, "construido_km2"), constr_2020 = gr(2020, "construido_km2"),
             constr_rel_1990 = gr(1990, "construido_rel_km2"), constr_rel_2020 = gr(2020, "construido_rel_km2"),
             dens_1990 = prem$dens[1], dens_rel_1990 = prem$dens_rel[1], dens_2020 = prem$dens[4], dens_rel_2020 = prem$dens_rel[4])
}


# ---- todas e indice ----------------------------------------------------------------------

cat(sprintf("Reglas · prueba 3 y relleno · %d aglomerados\n", length(CIUDADES)))
dir.create(BASE, recursive = TRUE, showWarnings = FALSE)
res <- do.call(rbind, lapply(CIUDADES, function(s) tryCatch(una(s), error = function(e) {
  cat("  ERROR", s, ":", conditionMessage(e), "\n"); NULL })))
res <- res[order(res$nombre), ]
f_res <- file.path(BASE, "resumen.csv")
if (file.exists(f_res) && !is.na(match("--ciudades", args))) {   # una corrida parcial no pisa las demas
  prev <- read.csv(f_res); res <- rbind(prev[!prev$slug %in% res$slug, names(res)], res); res <- res[order(res$nombre), ]
}
write.csv(res, f_res, row.names = FALSE)

img <- file.path(BASE, "img"); dir.create(img, showWarnings = FALSE)
lg <- rbind(data.frame(nombre = res$nombre, anio = "1990", v = res$p25_1990),
            data.frame(nombre = res$nombre, anio = "2020", v = res$p25_2020))
lg$nombre <- factor(lg$nombre, levels = res$nombre[order(res$p25_2020)])
guardar(ggplot(lg, aes(v, nombre, colour = anio)) + geom_point(size = 2.6) +
  scale_colour_manual(values = COL_ANIO[c("1990", "2020")]) + scale_x_continuous(labels = f0) +
  labs(x = sprintf("percentile %d of tract density, persons / km² urbanized", P_C), y = NULL, colour = NULL,
       title = sprintf("The %dth percentile is a different cut in every city", P_C),
       subtitle = "Why a single absolute cut treats cities unevenly", caption = PIE) + tema, img, "p25_por_ciudad.png", w = 9, h = 8)
lr <- rbind(data.frame(nombre = res$nombre, anio = "1990", v = 100 * res$relleno_1990 / res$abierto_1990),
            data.frame(nombre = res$nombre, anio = "2020", v = 100 * res$relleno_2020 / res$abierto_2020))
lr$nombre <- factor(lr$nombre, levels = res$nombre[order(res$relleno_1990 / res$abierto_1990)])
guardar(ggplot(lr, aes(v, nombre, colour = anio)) + geom_point(size = 2.6) +
  scale_colour_manual(values = COL_ANIO[c("1990", "2020")]) + scale_x_continuous(limits = c(0, NA)) +
  labs(x = "% of the city's open land (fringe + captured) the fill rule turns into built-up", y = NULL, colour = NULL,
       title = sprintf("Fill rule (gaps up to %d m, > %d m from the edge), 1990 and 2020", H_C, D_C),
       subtitle = "High in 1990 and lower later = centres the older imagery under-detects", caption = PIE) + tema,
  img, "relleno_por_ciudad.png", w = 9, h = 8)

ancla <- function(s) sprintf("[%s](%s/REPORTE.md)", res$nombre[res$slug == s], s)
L <- c("# Rules · relative cut (test 3) and fill of the centre, all agglomerations", "",
  sprintf("Exploratory. None of these numbers are project figures (they are not in `CIFRAS_CANONICAS.json`). Generated by `Rpipe/scripts/16_reglas.R` from step 11. Run of %s. Method: [METODOS.md](../METODOS.md).", format(Sys.Date())), "",
  "## Method", "",
  sprintf("- **Test 3.** Built-up always counts; fringe and captured land only in tracts at or above percentile p of the city's own tract densities that census (p = %s). Percentiles over tracts with at least %d %% of their area in the city.", paste(PCTS, collapse = ", "), round(100 * MIN_CIUDAD)),
  sprintf("- **Edge ring vs interior.** Each open pixel of the city gets its distance to the nearest land outside the city. Within %d m it is the edge ring; beyond, interior.", D_C),
  sprintf("- **Fill rule.** An interior open pixel that closing the built-up with radius %d m covers (a narrow gap between built pixels) becomes built-up. With a dense tract (>= %s p/km²) as an extra condition, or without it. Sensitivity: gap %s m, distance %s m, and the share rule (%s %% built within %d m).", H_C, f0(T_C), paste(H_OPC, collapse = "/"), paste(D_OPC, collapse = "/"), paste(S_OPC, collapse = "/"), RADIO_SHARE),
  "- **What the fill changes.** Inside the Angel city it moves land from open to built: the Angel extent is the same, built-up and persons per km² built change. Without the dense-tract condition it also keeps, in tests 1-3, interior land of sparse tracts.", "",
  sprintf("## All agglomerations · test 3 at p%d and the fill", P_C), "",
  tabla(c("Agglomeration", "p25 1990 p/km²", "p25 2020 p/km²", "Angel 2020 km²", "Test 3 2020 km²", "Growth Angel %/yr", "Growth test 3 %/yr",
          "Fill 1990 km² (% open)", "Fill 2020 km² (% open)", "Built 1990 km²", "+ fill (dense)", "Persons/km² built 1990", "with fill"),
        lapply(res$slug, function(s) with(res[res$slug == s, ], c(ancla(s), f0(p25_1990), f0(p25_2020), f1(angel_2020), f1(p3_2020),
          f2(tasa(angel_1990, angel_2020, 30)), f2(tasa(p3_1990, p3_2020, 30)),
          sprintf("%s (%s)", f1(relleno_1990), f0(100 * relleno_1990 / abierto_1990)), sprintf("%s (%s)", f1(relleno_2020), f0(100 * relleno_2020 / abierto_2020)),
          f1(constr_1990), f1(constr_rel_1990), f0(dens_1990), f0(dens_rel_1990))))), "",
  "![p25 by city](img/p25_por_ciudad.png)", "", "![Fill by city](img/relleno_por_ciudad.png)", "",
  suppressWarnings(indice_mapas(BASE, res, c(`ring and fill` = "anillo_centro.png", `test 3` = "prueba3.png", density = "distribucion.png"),
               cols = "all", cab = "Maps (four years each)")))
writeLines(enc2utf8(L), file.path(BASE, "REPORTE.md"), useBytes = TRUE)
cat("Escrito", file.path(BASE, "REPORTE.md"), "\n")
