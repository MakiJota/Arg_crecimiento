# -*- coding: utf-8 -*-
# Paso 31 · Mapa final por aglomerado: la ciudad de la percolacion (30) con las comunidades de
# localidades por tiempo de viaje (29). Exploratorio: ningun numero es cifra del proyecto.
#
# Dos mapas por aglomerado, uno por escala de Leiden (TAUS, por defecto tau 15 y 30 min):
#   - fondo: perimetro de analisis EPH (gris, borde negro) y, encima, la ciudad de la percolacion de
#     intersecciones de calles al d que cubre el 99 % del aglomerado EPH (d_cubre99 de 30). Si no
#     llega a cubrirlo a 2000 m, la ciudad a 2000 m, y el titulo lo dice.
#   - las sedes de gobierno local del paso 29, coloreadas por su grupo de Leiden, y una linea de cada
#     sede al nucleo de su grupo: la sede del grupo con menor tiempo total de viaje a las demas
#     (medoide, sobre od_tiempo_min.csv). Las lineas van en recta, no son el camino.
#
# ENTRADAS  outputs/percolacion/resumen.csv y <slug>/percolacion.gpkg (30),
#           outputs/od_aglomerados/od_aglomerados.gpkg capas puntos y cuadrados, <slug>/od_tiempo_min.csv (29),
#           raw/boundaries/aglomerados.gpkg (07)
# SALIDAS   outputs/percolacion/<slug>/mapa_final_leiden<tau>.png
#
# Uso: Rscript Rpipe/scripts/31_mapa_final.R [--aglomerados salta] [--tau 15,30]

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
TAUS <- as.numeric(strsplit(arg("--tau", "15,30"), ",")[[1]])
PERC <- file.path(RPIPE, "outputs", "percolacion")
OD <- file.path(RPIPE, "outputs", "od_aglomerados")
PERIM <- file.path(RPIPE, "raw", "boundaries", "aglomerados.gpkg")
D_MAX <- 2000

res <- read.csv(file.path(PERC, "resumen.csv"), check.names = FALSE, encoding = "UTF-8")
AGLOS <- strsplit(arg("--aglomerados", paste(res$slug, collapse = ",")), ",")[[1]]
ag <- st_read(PERIM, "perimetro", quiet = TRUE)
pts <- st_read(file.path(OD, "od_aglomerados.gpkg"), "puntos", quiet = TRUE)
cuad <- st_read(file.path(OD, "od_aglomerados.gpkg"), "cuadrados", quiet = TRUE)
base_de <- function(s) sub("_[0-9.]+km$", "", s)
MB_ANIO <- as.integer(arg("--mb-anio", "2022"))   # el urbano recortado y guardado por el paso 29
res_od <- read.csv(file.path(OD, "resumen.csv"), check.names = FALSE, encoding = "UTF-8")
fmt1 <- function(x) format(round(x, 1), big.mark = ",", nsmall = 1, trim = TRUE)
mb_tabla <- list()

for (s in AGLOS) {
  r <- res[res$slug == s, ]
  a <- ag[ag$slug == base_de(s), ]
  cu <- cuad[cuad$slug == s, ]
  c0 <- st_coordinates(st_centroid(st_geometry(st_transform(a, 4326))))
  crs <- utm(c0[1], c0[2])
  cu <- st_transform(cu, crs)
  per <- st_transform(st_geometry(a), crs)
  d <- if (is.na(r$d_cubre99)) D_MAX else r$d_cubre99
  gp <- file.path(PERC, s, "percolacion.gpkg")
  capa <- paste0("ciudad_", d)
  if (!capa %in% st_layers(gp)$name) { cat(s, ": falta la capa", capa, "\n"); next }
  ciudad <- st_transform(st_read(gp, capa, quiet = TRUE), crs)
  p_s <- st_transform(pts[pts$slug == s, ], crs)
  Tm <- if (nrow(p_s) >= 2) as.matrix(read.csv(file.path(OD, s, "od_tiempo_min.csv"), row.names = 1,
                                                check.names = FALSE, encoding = "UTF-8")) else NULL
  sub_d <- if (is.na(r$d_cubre99)) sprintf("no cubre el 99%% del aglomerado EPH a %g m: ciudad a %g m", D_MAX, D_MAX) else
    sprintf("d = %g m, el menor que cubre el 99%% de las intersecciones del aglomerado EPH", d)

  for (tau in TAUS) {
    col <- sprintf("leiden_tau%g", tau)
    lineas <- NULL
    if (nrow(p_s)) {
      g <- p_s[[col]]
      if (is.null(g) || all(is.na(g))) g <- rep(1L, nrow(p_s))   # menos de 3 sedes: un solo grupo
      p_s$grupo <- factor(g)
      if (!is.null(Tm)) {
        xy <- st_coordinates(p_s)
        lin <- lapply(levels(p_s$grupo), function(k) {
          i <- which(p_s$grupo == k)
          if (length(i) < 2) return(NULL)
          sub <- Tm[p_s$nombre[i], p_s$nombre[i], drop = FALSE]
          h <- i[which.min(rowSums(sub))]   # medoide: menor tiempo total al resto del grupo
          st_sf(grupo = factor(k, levels = levels(p_s$grupo)), hub = p_s$nombre[h],
                geometry = st_sfc(lapply(setdiff(i, h), function(j) st_linestring(xy[c(j, h), ])), crs = crs))
        })
        lineas <- do.call(rbind, lin[!vapply(lin, is.null, TRUE)])
        hubs <- unique(lineas$hub)
        p_s$nucleo <- p_s$nombre %in% hubs
      } else p_s$nucleo <- FALSE
    }
    ng <- if (nrow(p_s)) nlevels(p_s$grupo) else 1
    paleta <- if (ng <= 8) scale_colour_brewer(palette = "Dark2", aesthetics = c("colour", "fill")) else
      scale_colour_hue(aesthetics = c("colour", "fill"))
    p <- ggplot() +
      geom_sf(data = per, fill = "grey60", alpha = 0.25, colour = NA) +
      geom_sf(data = ciudad, fill = "#7b1d3a", alpha = 0.5, colour = NA) +
      geom_sf(data = per, fill = NA, colour = "black", linewidth = 0.4) +
      geom_sf(data = cu, fill = NA, colour = "grey40", linetype = 2, linewidth = 0.3) +
      { if (!is.null(lineas) && nrow(lineas)) geom_sf(data = lineas, aes(colour = grupo), linewidth = 0.55, alpha = 0.85,
                                                      show.legend = FALSE) } +
      { if (nrow(p_s)) list(
          geom_sf(data = p_s, aes(fill = grupo, size = nucleo), shape = 21, colour = "black", stroke = 0.35),
          scale_size_manual(values = c(`FALSE` = 2.1, `TRUE` = 3.8), guide = "none"),
          geom_sf_text(data = p_s, aes(label = nombre), size = 2, nudge_y = 900, colour = "grey10")) } +
      paleta +
      guides(fill = guide_legend(override.aes = list(size = 3.5)), colour = "none") +
      coord_sf(xlim = st_bbox(cu)[c(1, 3)], ylim = st_bbox(cu)[c(2, 4)], datum = crs) +
      labs(title = sprintf("%s · ciudad por percolacion de calles y comunidades de localidades (Leiden, tau %g min)",
                           r$nombre, tau),
           subtitle = paste0(sub_d, if (nrow(p_s)) sprintf(". %d sedes en %d grupos; punto grande: nucleo de cada grupo",
                                                         nrow(p_s), ng) else ". Menos de 2 sedes: sin comunidades"),
           fill = "grupo", x = NULL, y = NULL,
           caption = paste("Vino: ciudad por percolacion de intersecciones de calles de Overture (paso 30). Gris con borde",
                           "negro: perimetro de analisis (EPH); punteado: el cuadrado del paso 29.\nPuntos: sedes de",
                           "gobierno local BAHRA/IGN; lineas: de cada sede al nucleo de su grupo (la sede con menor tiempo",
                           "total de viaje al resto), en recta. Grupos: Leiden sobre el tiempo de viaje por calles (paso 29).")) +
      theme_minimal(base_size = 8) +
      theme(axis.text = element_blank(), panel.grid = element_blank(),
            plot.caption = element_text(size = 6, colour = "grey40", hjust = 0))
    ggsave(file.path(PERC, s, sprintf("mapa_final_leiden%g.png", tau)), p, width = 9, height = 9.4, dpi = 150, bg = "white")
  }
  # tercer mapa: lo construido segun MapBiomas contra la ciudad de la percolacion y el perimetro EPH
  lado <- res_od$lado_km[res_od$slug == s]
  fmb <- file.path(OD, s, sprintf("mapbiomas_urbano_%d_%gkm.tif", MB_ANIO, lado))
  if (file.exists(fmb)) {
    mb <- terra::crop(terra::rast(fmb), terra::vect(cu))
    km2 <- function(v) if (is.null(v)) sum(!is.na(terra::values(mb))) * prod(terra::res(mb)) / 1e6 else
      sum(!is.na(terra::values(terra::mask(mb, terra::vect(v))))) * prod(terra::res(mb)) / 1e6
    u_cuad <- km2(NULL); u_eph <- km2(st_sf(geometry = per)); u_ciudad <- km2(ciudad)
    u_los_dos <- km2(st_sf(geometry = st_intersection(st_union(per), st_union(st_geometry(ciudad)))))
    mb_tabla[[s]] <- data.frame(slug = s, nombre = r$nombre, anio = MB_ANIO, d = d,
                                urbano_cuadrado_km2 = round(u_cuad, 1), urbano_eph_km2 = round(u_eph, 1),
                                urbano_ciudad_km2 = round(u_ciudad, 1), urbano_los_dos_km2 = round(u_los_dos, 1),
                                urbano_solo_ciudad_km2 = round(u_ciudad - u_los_dos, 1),
                                urbano_solo_eph_km2 = round(u_eph - u_los_dos, 1),
                                share_cuadrado_en_eph = round(u_eph / u_cuad, 3),
                                share_cuadrado_en_ciudad = round(u_ciudad / u_cuad, 3))
    f <- max(1L, as.integer(round(lado / 50)))
    mbd <- as.data.frame(if (f > 1) terra::aggregate(mb, f, fun = "max", na.rm = TRUE) else mb, xy = TRUE, na.rm = TRUE)
    celda <- terra::res(mb)[1] * f
    p <- ggplot() +
      geom_sf(data = per, fill = "grey60", alpha = 0.25, colour = NA) +
      geom_tile(data = mbd, aes(x = x, y = y), width = celda, height = celda, fill = "#7b1d3a") +
      geom_sf(data = ciudad, fill = "#1b9e9e", alpha = 0.12, colour = "#127a7a", linewidth = 0.35) +
      geom_sf(data = per, fill = NA, colour = "black", linewidth = 0.45) +
      geom_sf(data = cu, fill = NA, colour = "grey40", linetype = 2, linewidth = 0.3) +
      { if (nrow(p_s)) list(geom_sf(data = p_s, size = 1.3, colour = "black"),
                            geom_sf_text(data = p_s, aes(label = nombre), size = 2, nudge_y = 900, colour = "grey10")) } +
      coord_sf(xlim = st_bbox(cu)[c(1, 3)], ylim = st_bbox(cu)[c(2, 4)], datum = crs) +
      labs(title = sprintf("%s · lo construido segun MapBiomas %d, la ciudad por percolacion y el perimetro EPH",
                           r$nombre, MB_ANIO),
           subtitle = sprintf(paste("Urbano MapBiomas en el cuadrado: %s km2. Dentro del perimetro EPH: %s km2 (%s%%);",
                                    "dentro de la ciudad por percolacion (d = %g m): %s km2 (%s%%).\nEn la ciudad y fuera del",
                                    "perimetro: %s km2; en el perimetro y fuera de la ciudad: %s km2."),
                              fmt1(u_cuad), fmt1(u_eph), fmt1(100 * u_eph / u_cuad), d, fmt1(u_ciudad),
                              fmt1(100 * u_ciudad / u_cuad), fmt1(u_ciudad - u_los_dos), fmt1(u_eph - u_los_dos)),
           x = NULL, y = NULL,
           caption = paste(sprintf("Vino: urbano de MapBiomas Argentina %d (coleccion 2, clase 24, 30 m).", MB_ANIO),
                           "Verde azulado: ciudad por percolacion de intersecciones de calles (paso 30) a", sub_d, ".",
                           "\nGris con borde negro: perimetro de analisis (EPH); punteado: el cuadrado; puntos: sedes de",
                           "gobierno local BAHRA/IGN.")) +
      theme_minimal(base_size = 8) +
      theme(axis.text = element_blank(), panel.grid = element_blank(),
            plot.caption = element_text(size = 6, colour = "grey40", hjust = 0))
    ggsave(file.path(PERC, s, "mapa_final_mapbiomas.png"), p, width = 9, height = 9.4, dpi = 150, bg = "white")
  } else cat(s, ": falta", basename(fmb), "(paso 29)\n")
  cat(sprintf("%-32s d = %s, %d sedes\n", s, d, nrow(p_s)))
}

if (length(mb_tabla)) {
  x <- do.call(rbind, mb_tabla)
  f <- file.path(PERC, "mapbiomas_resumen.csv")
  if (file.exists(f)) { v <- read.csv(f); if (identical(names(v), names(x))) x <- rbind(v[!v$slug %in% x$slug, ], x) }
  write.csv(x[order(match(x$slug, res$slug)), ], f, row.names = FALSE, fileEncoding = "UTF-8")
}
