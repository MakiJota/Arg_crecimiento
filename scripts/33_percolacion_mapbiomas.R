# -*- coding: utf-8 -*-
# Paso 33 · Percolacion sobre lo construido de MapBiomas: que radios forman el aglomerado (nuevo).
# Exploratorio: ningun numero es cifra del proyecto.
#
# METODO: City Clustering Algorithm (Rozenfeld et al. 2008, PNAS 105: 18702; Rozenfeld, Rybski,
# Gabaix y Makse 2011, American Economic Review 101: 2205), la misma percolacion del paso 30 pero
# sobre celdas construidas en lugar de intersecciones de calles.
#
#   1. Construido: urbano de MapBiomas Argentina (coleccion 2, clase 24, 30 m) del ANIO, recortado al
#      cuadrado del paso 29 (lo guarda el 29 en od_aglomerados/<slug>/mapbiomas_urbano_<anio>_<lado>km.tif).
#   2. Percolacion: dos celdas urbanas estan en la misma ciudad si hay una cadena de celdas urbanas a
#      menos de d entre si. En raster: la distancia de cada celda a la urbana mas cercana se calcula una
#      vez; a cada d, las celdas a menos de d/2 forman manchas 8-conexas. Se barre d de 30 a 2000 m.
#   3. La ciudad a cada d: la mancha con mas urbano dentro del perimetro de analisis (EPH, paso 07).
#   4. Dos objetivos para elegir d, siempre con el 99% (y el 100% como diagnostico):
#      a. EPH: el menor d al que la ciudad contiene el 99% del urbano dentro del perimetro EPH.
#      b. Calles: el menor d al que la ciudad contiene el 95% del urbano dentro de la ciudad por
#         percolacion de calles del paso 30 (a su d cubre 99%). Pregunta: cuanto hay que dilatar lo
#         construido para reproducir lo que la red de calles ya une. 95% y no 99%: la red une caserios
#         a lo largo de las rutas que el construido no une ni a 2000 m (Salta llega a 98,3%).
#   5. Radios 2022: un radio es de la ciudad si al menos PARTE de sus celdas urbanas estan en ella (los
#      radios sin urbano no entran). Se comparan con los radios con al menos PARTE de su area en el
#      perimetro EPH, y (objetivo b) con los radios de la ciudad de calles del paso 30 (su radios.csv).
#
# ENTRADAS  outputs/od_aglomerados/<slug>/mapbiomas_urbano_<anio>_<lado>km.tif y resumen.csv (29),
#           outputs/od_aglomerados/cajas.csv (29), raw/boundaries/aglomerados.gpkg (07),
#           outputs/censos/radios_censos.gpkg capa radios_2022 (09),
#           outputs/percolacion/resumen.csv y <slug>/percolacion.gpkg (30, para comparar; opcional)
# SALIDAS   outputs/percolacion_mb/<slug>/ curva.csv, curva.png, ciudad_d.png, radios.csv,
#           radios_por_d.csv, comparacion.png (contra EPH), comparacion_calles.png (contra la ciudad de
#           calles); outputs/percolacion_mb/resumen.csv y HALLAZGOS.md
#
# --solo-texto rehace HALLAZGOS.md de los CSV, sin recalcular.
#
# Uso: Rscript Rpipe/scripts/33_percolacion_mapbiomas.R [--aglomerados salta] [--anio 2022] [--parte 0.5]

Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))
suppressPackageStartupMessages({ library(sf); library(ggplot2) })
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
SCRIPTS <- normalizePath(dirname(script), winslash = "/")
RPIPE <- dirname(SCRIPTS)
source(file.path(SCRIPTS, "lib", "od.R"))   # utm

args <- commandArgs(trailingOnly = TRUE)
arg <- function(nombre, defecto) {
  i <- match(nombre, args)
  if (is.na(i) || i == length(args)) defecto else args[i + 1]
}
ANIO <- as.integer(arg("--anio", "2022"))
PARTE <- as.numeric(arg("--parte", "0.5"))
SOLO_TEXTO <- "--solo-texto" %in% args
D_SERIE <- c(seq(30, 300, 30), seq(400, 1000, 100), seq(1200, 2000, 200))
D_MAPA <- c(60, 150, 300, 600, 1000, 2000)
OD <- file.path(RPIPE, "outputs", "od_aglomerados")
PERC <- file.path(RPIPE, "outputs", "percolacion")
SAL <- file.path(RPIPE, "outputs", "percolacion_mb")
PERIM <- file.path(RPIPE, "raw", "boundaries", "aglomerados.gpkg")
RADIOS <- file.path(RPIPE, "outputs", "censos", "radios_censos.gpkg")

ag <- st_read(PERIM, "perimetro", quiet = TRUE)
cajas <- read.csv(file.path(OD, "cajas.csv"))
res_od <- read.csv(file.path(OD, "resumen.csv"), check.names = FALSE, encoding = "UTF-8")
res_perc <- if (file.exists(file.path(PERC, "resumen.csv"))) read.csv(file.path(PERC, "resumen.csv")) else NULL
base_de <- function(s) sub("_[0-9.]+km$", "", s)
AGLOS <- strsplit(arg("--aglomerados", paste(res_od$slug, collapse = ",")), ",")[[1]]
dir.create(SAL, showWarnings = FALSE, recursive = TRUE)
fmt <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)


resumen <- list()
for (s in if (SOLO_TEXTO) character(0) else AGLOS) {
  t0 <- Sys.time()
  a <- ag[ag$slug == base_de(s), ]
  if (s != a$slug) a$nombre <- sprintf("%s (%s)", a$nombre, sub(".*_", "", s))
  lado <- res_od$lado_km[res_od$slug == s]
  fmb <- file.path(OD, s, sprintf("mapbiomas_urbano_%d_%gkm.tif", ANIO, lado))
  if (!file.exists(fmb)) { cat(s, ": falta", basename(fmb), "(paso 29 con --mb-anio", ANIO, ")\n"); next }
  cj <- cajas[cajas$slug == s, ]
  c0 <- st_coordinates(st_centroid(st_geometry(st_transform(a, 4326))))
  crs <- utm(c0[1], c0[2])
  caja <- st_transform(st_as_sfc(st_bbox(c(xmin = cj$lon0, ymin = cj$lat0, xmax = cj$lon1, ymax = cj$lat1), crs = 4326)), crs)
  cuadrado <- st_buffer(caja, -10000, joinStyle = "MITRE", mitreLimit = 2)
  per <- st_transform(st_geometry(a), crs)
  d_out <- file.path(SAL, s); dir.create(d_out, showWarnings = FALSE)

  urb <- terra::crop(terra::rast(fmb), terra::vect(cuadrado))
  urb <- terra::extend(urb, 70)   # margen para que la dilatacion no toque el borde
  celda <- prod(terra::res(urb)) / 1e6
  es_urb <- !is.na(terra::values(urb, mat = FALSE))
  en_eph <- !is.na(terra::values(terra::rasterize(terra::vect(per), urb, field = 1), mat = FALSE))
  dist <- terra::distance(urb)   # 0 en las urbanas
  # radios 2022 sobre la misma grilla
  rad <- st_read(RADIOS, "radios_2022", quiet = TRUE, wkt_filter = st_as_text(st_transform(cuadrado, 4326)))
  rad <- st_make_valid(st_transform(rad, crs))
  rid <- terra::values(terra::rasterize(terra::vect(rad), urb, field = seq_len(nrow(rad))), mat = FALSE)
  n_area <- tabulate(rid, nrow(rad))
  rad$share_eph <- ifelse(n_area > 0, tabulate(rid[en_eph], nrow(rad)) / n_area, 0)
  n_urb <- tabulate(rid[es_urb], nrow(rad))
  rad$urbano_km2 <- round(n_urb * celda, 3)

  # la ciudad por percolacion de calles (paso 30) a su d cubre 99% (2000 m si no lo alcanza), y sus radios
  calles <- NULL; dc <- NA; en_calles <- rep(FALSE, length(es_urb)); rad$calles <- NA
  if (!is.null(res_perc) && s %in% res_perc$slug) {
    dc <- res_perc$d_cubre99[res_perc$slug == s]; if (is.na(dc)) dc <- 2000
    gp <- file.path(PERC, s, "percolacion.gpkg")
    if (paste0("ciudad_", dc) %in% st_layers(gp)$name) {
      calles <- st_transform(st_read(gp, paste0("ciudad_", dc), quiet = TRUE), crs)
      en_calles <- !is.na(terra::values(terra::rasterize(terra::vect(calles), urb, field = 1), mat = FALSE))
    }
    rc <- read.csv(file.path(PERC, s, "radios.csv"), colClasses = c(cod = "character"))
    col <- sprintf("share_d%g", dc)
    if (col %in% names(rc)) rad$calles <- rc[[col]][match(rad$cod, rc$cod)] >= PARTE
  }

  ciudad_a <- function(d) {
    m <- terra::patches(terra::classify(dist <= d / 2, cbind(0, NA)), directions = 8)
    v <- terra::values(m, mat = FALSE)
    tb <- table(v[es_urb & en_eph])
    list(r = m, id = as.integer(names(tb)[which.max(tb)]), v = v)
  }
  curva <- do.call(rbind, lapply(D_SERIE, function(d) {
    cc <- ciudad_a(d)
    en <- cc$v == cc$id & !is.na(cc$v)
    data.frame(d = d, manchas = length(unique(cc$v[es_urb])), urbano_ciudad_km2 = sum(es_urb & en) * celda,
               urbano_eph_en_ciudad_km2 = sum(es_urb & en_eph & en) * celda, urbano_eph_km2 = sum(es_urb & en_eph) * celda,
               urbano_total_km2 = sum(es_urb) * celda, huella_ciudad_km2 = sum(en) * celda,
               urbano_calles_km2 = sum(es_urb & en_calles) * celda,
               urbano_calles_en_ciudad_km2 = sum(es_urb & en_calles & en) * celda)
  }))
  curva$cobertura_eph <- curva$urbano_eph_en_ciudad_km2 / curva$urbano_eph_km2
  curva$cobertura_calles <- curva$urbano_calles_en_ciudad_km2 / curva$urbano_calles_km2
  d_cubre <- function(p, col = "cobertura_eph") { k <- which(curva[[col]] >= p); if (length(k)) curva$d[min(k)] else NA }
  d99 <- d_cubre(0.99); d100 <- d_cubre(1)
  # contra la ciudad de calles el umbral es 95%: la red de calles une caserios a lo largo de las rutas que
  # el construido no une ni a 2000 m, y el 99% casi nunca se alcanza. Si ni el 95%, el d de mayor cobertura.
  dk95 <- d_cubre(0.95, "cobertura_calles"); dk99 <- d_cubre(0.99, "cobertura_calles")
  dk <- if (!is.na(dk95)) dk95 else if (!is.na(dc)) curva$d[which.max(curva$cobertura_calles)] else NA
  write.csv(curva, file.path(d_out, "curva.csv"), row.names = FALSE)

  # radios a cada d mapeado y a los d de cobertura
  ee <- rad$share_eph >= PARTE
  ds <- sort(unique(na.omit(c(D_MAPA, d99, d100, dk))))
  polis <- list()
  por_d <- do.call(rbind, lapply(ds, function(d) {
    cc <- ciudad_a(d)
    en <- cc$v == cc$id & !is.na(cc$v)
    sh <- ifelse(n_urb > 0, tabulate(rid[es_urb & en], nrow(rad)) / n_urb, 0)
    rad[[sprintf("share_d%g", d)]] <<- round(sh, 3)
    ce <- sh >= PARTE
    k <- ifelse(ce & ee, "en los dos", ifelse(ce, "solo percolacion", ifelse(ee, "solo EPH", NA)))
    rad[[sprintf("clase_d%g", d)]] <<- k
    polis[[as.character(d)]] <<- st_as_sf(terra::as.polygons(terra::classify(cc$r == cc$id, cbind(0, NA)), dissolve = TRUE))
    data.frame(d = d,
               radios_los_dos = sum(k %in% "en los dos"), personas_los_dos = sum(rad$personas[k %in% "en los dos"], na.rm = TRUE),
               radios_solo_perc = sum(k %in% "solo percolacion"), personas_solo_perc = sum(rad$personas[k %in% "solo percolacion"], na.rm = TRUE),
               radios_solo_eph = sum(k %in% "solo EPH"), personas_solo_eph = sum(rad$personas[k %in% "solo EPH"], na.rm = TRUE))
  }))
  write.csv(por_d, file.path(d_out, "radios_por_d.csv"), row.names = FALSE)
  write.csv(st_drop_geometry(rad[, c("cod", "personas", "urbano_km2", "share_eph", "calles",
                                     grep("^(share|clase)_d", names(rad), value = TRUE))]),
            file.path(d_out, "radios.csv"), row.names = FALSE)

  # curva
  p <- ggplot(curva, aes(d)) +
    geom_vline(xintercept = na.omit(c(d99, d100)), colour = "#2a7fb8", linetype = 2, linewidth = 0.4) +
    geom_vline(xintercept = na.omit(dk), colour = "#127a7a", linetype = 2, linewidth = 0.4) +
    { if (!is.na(dc)) geom_line(aes(y = cobertura_calles, colour = "urbano de la ciudad de calles en la ciudad"), linewidth = 0.6) } +
    geom_line(aes(y = urbano_ciudad_km2 / urbano_total_km2, colour = "urbano del cuadrado en la ciudad"), linewidth = 0.8) +
    geom_line(aes(y = cobertura_eph, colour = "urbano del perimetro EPH en la ciudad"), linewidth = 0.6) +
    scale_colour_manual(values = c(`urbano del cuadrado en la ciudad` = "#7b1d3a",
                                   `urbano del perimetro EPH en la ciudad` = "#2a7fb8",
                                   `urbano de la ciudad de calles en la ciudad` = "#127a7a"), name = NULL) +
    scale_x_log10(breaks = c(30, 60, 100, 200, 500, 1000, 2000)) + scale_y_continuous(labels = scales::percent) +
    labs(title = sprintf("%s · percolacion del urbano de MapBiomas %d (%s km2 en el cuadrado)", a$nombre, ANIO,
                         fmt(round(curva$urbano_total_km2[1], 1))),
         subtitle = sprintf(paste("azules: cubre el 99%% del urbano del perimetro EPH a d = %s m (100%% a %s m).",
                                  "Verde: cubre el 95%% del urbano de la ciudad de calles a d = %s m"),
                            ifelse(is.na(d99), "> 2000", d99), ifelse(is.na(d100), "> 2000", d100),
                            ifelse(is.na(dk95), "> 2000", dk95)),
         x = "d, distancia maxima entre celdas urbanas (m, escala log)", y = NULL) +
    theme_minimal(base_size = 9) + theme(legend.position = "bottom")
  ggsave(file.path(d_out, "curva.png"), p, width = 8, height = 5, dpi = 150, bg = "white")

  # ciudad a cada d
  pc <- do.call(rbind, lapply(as.character(D_MAPA), function(d) st_sf(d = factor(paste0("d = ", d, " m"),
                    levels = paste0("d = ", D_MAPA, " m")), geometry = st_geometry(polis[[d]]))))
  p <- ggplot() +
    geom_sf(data = per, fill = "grey60", alpha = 0.25, colour = NA) +
    geom_sf(data = pc, fill = "#7b1d3a", alpha = 0.55, colour = NA) +
    geom_sf(data = per, fill = NA, colour = "black", linewidth = 0.35) +
    facet_wrap(~d, nrow = 2) +
    coord_sf(xlim = st_bbox(cuadrado)[c(1, 3)], ylim = st_bbox(cuadrado)[c(2, 4)], datum = crs) +
    labs(title = sprintf("%s · la ciudad por percolacion del urbano de MapBiomas %d, segun d", a$nombre, ANIO),
         caption = "Vino: mancha (urbano dilatado d/2) con mas urbano dentro del perimetro. Gris con borde negro: perimetro de analisis (EPH).") +
    theme_minimal(base_size = 8) + theme(axis.text = element_blank(), panel.grid = element_blank(),
                                         plot.caption = element_text(size = 6, colour = "grey40", hjust = 0))
  ggsave(file.path(d_out, "ciudad_d.png"), p, width = 10.8, height = 8, dpi = 150, bg = "white")

  # comparacion: radios a d cubre 99% de MapBiomas y la ciudad de calles (paso 30) a su d cubre 99%
  dm <- if (is.na(d99)) max(D_SERIE) else d99
  rad$clase <- factor(rad[[sprintf("clase_d%g", dm)]], levels = c("en los dos", "solo percolacion", "solo EPH"))
  t <- por_d[por_d$d == dm, ]
  rs <- rad[!is.na(rad$clase), ]
  urb_df <- as.data.frame(urb, xy = TRUE, na.rm = TRUE)
  p <- ggplot() +
    geom_sf(data = rs, aes(fill = clase), colour = "white", linewidth = 0.05) +
    scale_fill_manual(values = c(`en los dos` = "grey70", `solo percolacion` = "#e3a35c", `solo EPH` = "#8fb8d8"),
                      labels = sprintf("%s: %s radios, %s personas", c("en los dos", "solo percolacion MapBiomas", "solo EPH"),
                                       fmt(c(t$radios_los_dos, t$radios_solo_perc, t$radios_solo_eph)),
                                       fmt(c(t$personas_los_dos, t$personas_solo_perc, t$personas_solo_eph))),
                      name = NULL, drop = FALSE) +
    geom_tile(data = urb_df, aes(x = x, y = y), width = 30, height = 30, fill = "#7b1d3a") +
    { if (!is.null(calles)) geom_sf(data = calles, fill = NA, colour = "#127a7a", linewidth = 0.35) } +
    geom_sf(data = per, fill = NA, colour = "black", linewidth = 0.45) +
    coord_sf(xlim = st_bbox(rs)[c(1, 3)], ylim = st_bbox(rs)[c(2, 4)], datum = crs) +
    labs(title = sprintf("%s · radios 2022 por percolacion del urbano de MapBiomas %d (d = %g m) y del perimetro EPH",
                         a$nombre, ANIO, dm),
         subtitle = sprintf(paste("un radio entra si al menos %g%% de su urbano esta en la ciudad (radios sin urbano: afuera).",
                                  "Verde azulado: ciudad por percolacion de calles (paso 30) a d = %s m"), 100 * PARTE,
                            ifelse(is.na(dc), "-", dc)),
         caption = paste("Vino: urbano de MapBiomas. Negro: perimetro de analisis (EPH). Personas: censo 2022 por radio (paso 09)."), x = NULL, y = NULL) +
    theme_minimal(base_size = 8) + theme(axis.text = element_blank(), panel.grid = element_blank(),
                                         legend.position = "bottom", legend.direction = "vertical",
                                         plot.caption = element_text(size = 6, colour = "grey40", hjust = 0))
  ggsave(file.path(d_out, "comparacion.png"), p, width = 8.5, height = 9.4, dpi = 150, bg = "white")

  tk <- data.frame(clase = c("pixeles y calles", "solo pixeles", "solo calles"), radios = NA, personas = NA)
  if (!is.na(dk) && !all(is.na(rad$calles))) {
    cp <- rad[[sprintf("share_d%g", dk)]] >= PARTE; cl <- rad$calles %in% TRUE
    k <- factor(ifelse(cp & cl, "pixeles y calles", ifelse(cp, "solo pixeles", ifelse(cl, "solo calles", NA))),
                levels = tk$clase)
    tk$radios <- as.vector(table(k)); tk$personas <- tapply(rad$personas, k, sum, na.rm = TRUE)[tk$clase]
    tk$personas[is.na(tk$personas)] <- 0
    write.csv(tk, file.path(d_out, "radios_vs_calles.csv"), row.names = FALSE)
    rad$clase_k <- k
    rs <- rad[!is.na(rad$clase_k), ]
    p <- ggplot() +
      geom_sf(data = rs, aes(fill = clase_k), colour = "white", linewidth = 0.05) +
      scale_fill_manual(values = c(`pixeles y calles` = "grey70", `solo pixeles` = "#e3a35c", `solo calles` = "#5fb3a8"),
                        labels = sprintf("%s: %s radios, %s personas", tk$clase, fmt(tk$radios), fmt(tk$personas)),
                        name = NULL, drop = FALSE) +
      geom_tile(data = urb_df, aes(x = x, y = y), width = 30, height = 30, fill = "#7b1d3a") +
      { if (!is.null(calles)) geom_sf(data = calles, fill = NA, colour = "#127a7a", linewidth = 0.35) } +
      geom_sf(data = per, fill = NA, colour = "black", linewidth = 0.45) +
      coord_sf(xlim = st_bbox(rs)[c(1, 3)], ylim = st_bbox(rs)[c(2, 4)], datum = crs) +
      labs(title = sprintf("%s · radios por percolacion de pixeles (d = %g m) contra la ciudad de calles (d = %g m)",
                           a$nombre, dk, dc),
           subtitle = sprintf(paste("d de pixeles: el menor que cubre el 95%% del urbano de la ciudad de calles. Radio de",
                                    "pixeles: al menos %g%% de su urbano en la ciudad; radio de calles: al menos %g%% de su area."),
                              100 * PARTE, 100 * PARTE),
           caption = "Vino: urbano de MapBiomas. Verde azulado: ciudad de calles (paso 30). Negro: perimetro EPH. Personas: censo 2022 (paso 09).",
           x = NULL, y = NULL) +
      theme_minimal(base_size = 8) + theme(axis.text = element_blank(), panel.grid = element_blank(),
                                           legend.position = "bottom", legend.direction = "vertical",
                                           plot.caption = element_text(size = 6, colour = "grey40", hjust = 0))
    ggsave(file.path(d_out, "comparacion_calles.png"), p, width = 8.5, height = 9.4, dpi = 150, bg = "white")
  }

  resumen[[s]] <- data.frame(slug = s, nombre = a$nombre, anio = ANIO,
                             urbano_cuadrado_km2 = round(curva$urbano_total_km2[1], 1),
                             urbano_eph_km2 = round(curva$urbano_eph_km2[1], 1), radios_eph = sum(ee),
                             personas_eph = sum(rad$personas[ee], na.rm = TRUE), d_cubre99 = d99, d_cubre100 = d100,
                             radios_los_dos = t$radios_los_dos, personas_los_dos = t$personas_los_dos,
                             radios_solo_perc = t$radios_solo_perc, personas_solo_perc = t$personas_solo_perc,
                             radios_solo_eph = t$radios_solo_eph, personas_solo_eph = t$personas_solo_eph,
                             d_calles = dc, d_cubre95_ciudad_calles = dk95, d_cubre99_ciudad_calles = dk99,
                             d_vs_calles = dk, cobertura_max_calles = round(max(curva$cobertura_calles), 4),
                             urbano_ciudad_calles_km2 = round(curva$urbano_calles_km2[1], 1),
                             radios_pix_y_calles = tk$radios[1], personas_pix_y_calles = tk$personas[1],
                             radios_solo_pix = tk$radios[2], personas_solo_pix = tk$personas[2],
                             radios_solo_calles = tk$radios[3], personas_solo_calles = tk$personas[3])
  cat(sprintf("%-32s urbano %6.1f km2 · EPH 99%%: %s m · ciudad de calles (%s m) 95%%: %s m · vs calles: %s/%s/%s radios · %.0f s\n",
              s, curva$urbano_total_km2[1], d99, dc, dk95, tk$radios[1], tk$radios[2], tk$radios[3],
              as.numeric(Sys.time() - t0, units = "secs")))
}
if (length(resumen)) {
  x <- do.call(rbind, resumen)
  f <- file.path(SAL, "resumen.csv")
  if (file.exists(f)) { v <- read.csv(f); if (identical(names(v), names(x))) x <- rbind(v[!v$slug %in% x$slug, ], x) }
  write.csv(x, f, row.names = FALSE, fileEncoding = "UTF-8")
}


# ---- HALLAZGOS.md: de resumen.csv y de los CSV de cada aglomerado; nada escrito a mano ----------
f_res <- file.path(SAL, "resumen.csv")
if (file.exists(f_res)) {
  res <- read.csv(f_res, check.names = FALSE, encoding = "UTF-8")
  res <- res[order(match(res$slug, res_od$slug)), ]
  na_ <- function(x) ifelse(is.na(x), "> 2000", fmt(x))
  pc <- function(x) sprintf("%.1f%%", 100 * x)
  L <- c("# Percolacion del construido (MapBiomas): que radios forman el aglomerado", "",
    sprintf(paste("Generado por `Rpipe/scripts/33_percolacion_mapbiomas.R` el %s. Exploratorio: ningun numero es",
                  "cifra del proyecto. Todo sale de `resumen.csv` y de los CSV de cada aglomerado."), format(Sys.Date())), "",
    "## Metodo, paso a paso", "",
    sprintf(paste("1. **Construido.** Urbano de MapBiomas Argentina %d (coleccion 2, clase 24, 30 m) en el cuadrado",
                  "del paso 29 (70 km; 100 km en la ventana extra de Gran Buenos Aires)."), ANIO),
    paste("2. **Percolacion** (City Clustering Algorithm: Rozenfeld et al. 2008, PNAS 105: 18702; Rozenfeld,",
          "Rybski, Gabaix y Makse 2011, American Economic Review 101: 2205). Dos celdas urbanas estan en la misma",
          "ciudad si hay una cadena de celdas urbanas a menos de d entre si. Es la percolacion del paso 30 sobre",
          "pixeles construidos en lugar de intersecciones de calles. Se barre d de 30 a 2000 m."),
    "3. **La ciudad a cada d.** La mancha con mas urbano dentro del perimetro de analisis (EPH).",
    paste("4. **Dos objetivos para elegir d.** (a) **EPH**: el menor d al que la ciudad contiene el 99% del urbano",
          "dentro del perimetro EPH. (b) **Calles**: el menor d al que la ciudad contiene el 95% del urbano dentro",
          "de la ciudad por percolacion de calles del paso 30 (a su d cubre 99%). El (b) pregunta cuanto hay que",
          "dilatar lo construido para reproducir lo que la red de calles ya une. Es 95% y no 99%: la red de calles",
          "une caserios a lo largo de las rutas que lo construido no une ni a 2000 m."),
    sprintf(paste("5. **Radios 2022.** Un radio es de la ciudad de pixeles si al menos %g%% de sus celdas urbanas",
                  "estan en ella; los radios sin urbano no entran, asi que los radios rurales grandes no pesan por su",
                  "area. Se comparan con los del perimetro EPH (al menos %g%% del area dentro) y con los de la ciudad",
                  "de calles (al menos %g%% del area dentro, paso 30)."), 100 * PARTE, 100 * PARTE, 100 * PARTE), "",
    "## Resumen", "",
    paste("| aglomerado | urbano en el cuadrado (km2) | (a) d cubre 99% EPH | a ese d: solo pixeles / solo EPH (radios) |",
          "d de la ciudad de calles | (b) d cubre 95% calles | cobertura max. de calles | pixeles y calles (radios / personas) |",
          "solo pixeles | solo calles |"),
    "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    sprintf("| %s | %s | %s | %s / %s | %s | %s | %s | %s / %s | %s / %s | %s / %s |", res$nombre, fmt(res$urbano_cuadrado_km2),
            na_(res$d_cubre99), fmt(res$radios_solo_perc), fmt(res$radios_solo_eph), na_(res$d_calles),
            na_(res$d_cubre95_ciudad_calles), pc(res$cobertura_max_calles),
            na_(res$radios_pix_y_calles), na_(res$personas_pix_y_calles), na_(res$radios_solo_pix),
            na_(res$personas_solo_pix), na_(res$radios_solo_calles), na_(res$personas_solo_calles)),
    "", paste("En (a), los radios se cuentan al d cubre 99% EPH (o 2000 m). En (b), al d cubre 95% de la ciudad de calles;",
              "si no lo alcanza, al d de mayor cobertura."), "",
    "## Por aglomerado", "")
  for (i in seq_len(nrow(res))) {
    s <- res$slug[i]; r <- res[i, ]
    L <- c(L, sprintf("### %s", r$nombre), "",
           sprintf(paste("%s km2 de urbano en el cuadrado, %s km2 dentro del perimetro EPH y %s km2 dentro de la ciudad de",
                         "calles (d = %s m)."), fmt(r$urbano_cuadrado_km2), fmt(r$urbano_eph_km2),
                   fmt(r$urbano_ciudad_calles_km2), na_(r$d_calles)), "",
           sprintf(paste("**(a) Contra el EPH:** la ciudad cubre el 99%% del urbano del perimetro a d = %s m. A ese d, en los dos:",
                         "%s radios (%s personas); solo pixeles: %s (%s); solo EPH: %s (%s)."), na_(r$d_cubre99),
                   fmt(r$radios_los_dos), fmt(r$personas_los_dos), fmt(r$radios_solo_perc), fmt(r$personas_solo_perc),
                   fmt(r$radios_solo_eph), fmt(r$personas_solo_eph)), "",
           sprintf(paste("**(b) Contra la ciudad de calles:** cubre el 95%% de su urbano a d = %s m (maximo %s a 2000 m). A",
                         "d = %s m, pixeles y calles: %s radios (%s personas); solo pixeles: %s (%s); solo calles: %s (%s)."),
                   na_(r$d_cubre95_ciudad_calles), pc(r$cobertura_max_calles), na_(r$d_vs_calles),
                   na_(r$radios_pix_y_calles), na_(r$personas_pix_y_calles), na_(r$radios_solo_pix),
                   na_(r$personas_solo_pix), na_(r$radios_solo_calles), na_(r$personas_solo_calles)), "",
           sprintf("![curva](%s/curva.png)", s), "", sprintf("![ciudad segun d](%s/ciudad_d.png)", s), "",
           sprintf("![radios contra el EPH](%s/comparacion.png)", s), "",
           if (file.exists(file.path(SAL, s, "comparacion_calles.png")))
             c(sprintf("![radios contra la ciudad de calles](%s/comparacion_calles.png)", s), "") else NULL)
  }
  L <- c(L, "## Limitaciones", "",
         "- MapBiomas clasifica urbano a 30 m: barrios de baja densidad o con mucha vegetacion pueden quedar afuera.",
         "- La regla de radios cuenta celdas urbanas: un radio con poco construido pero conectado entra entero, aunque su area sea rural.",
         "- El objetivo (b) hereda los supuestos del paso 30 (calles de Overture, cruces a distinto nivel).",
         "- Personas: censo 2022 por radio (paso 09, copia CEUR-CONICET de los datos del INDEC).")
  writeLines(enc2utf8(L), file.path(SAL, "HALLAZGOS.md"), useBytes = TRUE)
  cat("HALLAZGOS.md escrito\n")
}
