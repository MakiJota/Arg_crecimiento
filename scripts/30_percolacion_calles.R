# -*- coding: utf-8 -*-
# Paso 30 · Percolacion sobre las intersecciones de calles: que radios censales forman el
# aglomerado (nuevo). Exploratorio: ningun numero es cifra del proyecto.
#
# METODO (Arcaute et al. 2015, "Constructing cities, deconstructing scaling laws", J. R. Soc.
# Interface 12: 20140745): las ciudades se arman uniendo las intersecciones de calles que estan a
# menos de d metros; cada componente conexa es una "ciudad". El tamano de las ciudades y las
# leyes de escala cambian con d, y la curva del tamano contra d tiene saltos (transiciones) que
# sirven para justificar el d elegido.
#
#   1. Intersecciones: nodos de la red de calles de Overture donde se juntan 3 o mas tramos
#      (grado >= 3), en el cuadrado del paso 29 (LADO km). Calles manejables, como en 28-29: sin
#      footway/path/pedestrian/steps/cycleway/bridleway. Las lineas se nodan en cada cruce: un
#      puente o un paso bajo nivel cuenta como interseccion.
#   2. Percolacion: el enlace simple sobre la distancia euclidea entre intersecciones. Se calcula
#      con el arbol de expansion minima euclideo (sale de la triangulacion de Delaunay): las
#      componentes a d son las del arbol sin las aristas mas largas que d. Se barre d de 20 a
#      2000 m (cada 10 m hasta 500, cada 50 hasta 2000).
#   3. La ciudad a cada d: la componente con mas intersecciones dentro del perimetro de analisis
#      del aglomerado (paso 07). Su area: las intersecciones con un buffer de d/2 (celdas de
#      CELDA m a menos de d/2), que es el area que la percolacion considera continua.
#   4. Radios 2022: un radio es de la ciudad si al menos PARTE de su area cae en la ciudad a d.
#      Se compara con los radios que caen al menos PARTE dentro del perimetro EPH: en los dos,
#      solo percolacion, solo EPH; con radios y personas (censo 2022, paso 09).
#
# ENTRADAS  outputs/overture_od/<slug>/calles.gpkg (20 con el cuadrado de 29),
#           outputs/od_aglomerados/cajas.csv (29), raw/boundaries/aglomerados.gpkg (07),
#           outputs/censos/radios_censos.gpkg capa radios_2022 (09)
# SALIDAS   outputs/percolacion/<slug>/
#             curva.csv           por d: intersecciones de la ciudad, de la mayor componente,
#                                 componentes, km2 de la ciudad, radios y personas
#             curva.png           la curva con los saltos marcados
#             ciudad_d.png        la ciudad a varios d (D_MAPA) sobre el perimetro EPH
#             radios.png          radios a D_ELEGIDO: en los dos, solo percolacion, solo EPH
#             radios.csv          cada radio: personas, share en el perimetro, share en la ciudad a cada D_MAPA
#             percolacion.gpkg    capas ciudad_<d> (poligono) y radios (con los shares)
#           outputs/percolacion/HALLAZGOS.md, resumen.csv
#
# Uso: Rscript Rpipe/scripts/30_percolacion_calles.R [--aglomerados salta] [--d 200]
#        [--d-mapa 100,150,200,300] [--parte 0.5]

Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))
suppressPackageStartupMessages({ library(sf); library(igraph); library(ggplot2) })
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
SCRIPTS <- normalizePath(dirname(script), winslash = "/")
RPIPE <- dirname(SCRIPTS)
source(file.path(SCRIPTS, "lib", "od.R"))   # FUERA, utm

args <- commandArgs(trailingOnly = TRUE)
arg <- function(nombre, defecto) {
  i <- match(nombre, args)
  if (is.na(i) || i == length(args)) defecto else args[i + 1]
}
PERIM <- file.path(RPIPE, "raw", "boundaries", "aglomerados.gpkg")
CAJAS <- file.path(RPIPE, "outputs", "od_aglomerados", "cajas.csv")
CALLES <- file.path(RPIPE, "outputs", "overture_od")
RADIOS <- file.path(RPIPE, "outputs", "censos", "radios_censos.gpkg")
SAL <- file.path(RPIPE, "outputs", "percolacion")
# barrido de d: cada 10 m hasta 500, cada 50 m hasta 2000
D_SERIE <- c(seq(20, 500, 10), seq(550, 2000, 50))
D_MAPA <- as.numeric(strsplit(arg("--d-mapa", "150,200,500,800,1000,1500,2000"), ",")[[1]])
D_ELEGIDO <- as.numeric(arg("--d", "200"))
PARTE <- as.numeric(arg("--parte", "0.5"))
SOLO_TEXTO <- "--solo-texto" %in% args   # rehace HALLAZGOS.md de los CSV, sin recalcular
CELDA <- 20   # m, raster del area de la ciudad y de los shares de los radios

ag <- st_read(PERIM, "perimetro", quiet = TRUE)
cajas <- read.csv(CAJAS)
base_de <- function(s) sub("_[0-9.]+km$", "", s)
# por defecto: los 31 perimetros y las ventanas extra del paso 29 (p. ej. gran_buenos_aires_100km),
# cada una despues de su aglomerado
ORDEN <- unlist(lapply(ag$slug, function(b) c(b, cajas$slug[base_de(cajas$slug) == b & cajas$slug != b])))
AGLOS <- strsplit(arg("--aglomerados", paste(ORDEN, collapse = ",")), ",")[[1]]
dir.create(SAL, showWarnings = FALSE, recursive = TRUE)


intersecciones <- function(fc, crs) {
  ca <- st_read(fc, quiet = TRUE)
  ca <- ca[ca$subtype == "road" & !(ca$clase %in% FUERA), ]
  ca <- st_transform(st_cast(st_zm(ca), "LINESTRING", warn = FALSE), crs)
  tramos <- st_cast(st_node(st_union(st_geometry(ca))), "LINESTRING")
  xy <- st_coordinates(tramos)
  ext <- rbind(xy[!duplicated(xy[, "L1"]), c("X", "Y")], xy[!duplicated(xy[, "L1"], fromLast = TRUE), c("X", "Y")])
  k <- paste(round(ext[, 1], 1), round(ext[, 2], 1))
  grado <- table(k)
  nodos <- names(grado)[grado >= 3]
  m <- do.call(rbind, lapply(strsplit(nodos, " "), as.numeric))
  colnames(m) <- c("x", "y")
  m
}


arbol_euclideo <- function(m, crs) {
  # arbol de expansion minima euclideo: esta contenido en la triangulacion de Delaunay
  pts <- st_sfc(st_multipoint(m), crs = crs)
  ar <- st_cast(st_triangulate(pts, bOnlyEdges = TRUE), "LINESTRING")
  xy <- st_coordinates(ar)
  a <- xy[!duplicated(xy[, "L1"]), c("X", "Y")]; b <- xy[!duplicated(xy[, "L1"], fromLast = TRUE), c("X", "Y")]
  clave <- function(z) paste(round(z[, 1], 1), round(z[, 2], 1))
  id <- setNames(seq_len(nrow(m)), clave(m))
  e <- data.frame(from = id[clave(a)], to = id[clave(b)], w = sqrt(rowSums((a - b)^2)))
  e <- e[!is.na(e$from) & !is.na(e$to) & e$from != e$to, ]
  g <- graph_from_data_frame(e, directed = FALSE, vertices = data.frame(name = seq_len(nrow(m))))
  t <- mst(g, weights = E(g)$w)
  data.frame(as_edgelist(t, names = FALSE), w = E(t)$w) |> setNames(c("from", "to", "w"))
}


componentes_a <- function(n, arbol, d) {
  g <- make_empty_graph(n, directed = FALSE)
  e <- arbol[arbol$w <= d, ]
  g <- add_edges(g, as.vector(t(as.matrix(e[, 1:2]))))
  components(g)$membership
}


area_ciudad <- function(m, crs, d, plantilla) {
  # las celdas a menos de d/2 de alguna interseccion de la ciudad (1, NA el resto)
  r <- terra::rasterize(terra::vect(as.data.frame(m), geom = c("x", "y"), crs = crs), plantilla, field = 1)
  dist <- terra::distance(r)
  terra::classify(dist <= d / 2, cbind(0, NA))
}


resumen <- list()
for (s in if (SOLO_TEXTO) character(0) else AGLOS) {
  t0 <- Sys.time()
  a <- ag[ag$slug == base_de(s), ]
  if (s != a$slug) a$nombre <- sprintf("%s (%s)", a$nombre, sub(".*_", "", s))
  cj <- cajas[cajas$slug == s, ]
  fc <- file.path(CALLES, s, "calles.gpkg")
  if (!nrow(cj) || !file.exists(fc)) { cat(s, ": falta la caja o las calles (pasos 29 y 20)\n"); next }
  c0 <- st_coordinates(st_centroid(st_geometry(st_transform(a, 4326))))
  crs <- utm(c0[1], c0[2])
  # el cuadrado del paso 29, sin el margen de las calles
  caja <- st_transform(st_as_sfc(st_bbox(c(xmin = cj$lon0, ymin = cj$lat0, xmax = cj$lon1, ymax = cj$lat1),
                                         crs = 4326)), crs)
  cuadrado <- st_buffer(caja, -10000, joinStyle = "MITRE", mitreLimit = 2)
  per <- st_transform(st_geometry(a), crs)
  d_out <- file.path(SAL, s); dir.create(d_out, showWarnings = FALSE)

  m <- intersecciones(fc, crs)
  m <- m[lengths(st_intersects(st_as_sf(as.data.frame(m), coords = c("x", "y"), crs = crs), cuadrado)) > 0, ]
  n <- nrow(m)
  dentro <- lengths(st_intersects(st_as_sf(as.data.frame(m), coords = c("x", "y"), crs = crs), per)) > 0
  arbol <- arbol_euclideo(m, crs)

  # radios 2022 que tocan el cuadrado
  rad <- st_read(RADIOS, "radios_2022", quiet = TRUE, wkt_filter = st_as_text(st_transform(cuadrado, 4326)))
  rad <- st_make_valid(st_transform(rad, crs))
  rad$km2_r <- as.numeric(st_area(rad)) / 1e6
  # shares en raster de CELDA m: celdas del radio dentro de la mascara / celdas del radio. Los
  # radios mas chicos que una celda toman el valor de la mascara en un punto interior.
  plantilla <- terra::rast(terra::ext(as.vector(st_bbox(st_union(st_geometry(rad), cuadrado)))[c(1, 3, 2, 4)]),
                           resolution = CELDA, crs = crs)
  rid <- terra::rasterize(terra::vect(rad), plantilla, field = seq_len(nrow(rad)))
  n_r <- tabulate(terra::values(rid, mat = FALSE), nrow(rad))
  interior <- terra::vect(st_point_on_surface(st_geometry(rad)))
  share <- function(masc) {
    z <- tabulate(terra::values(terra::mask(rid, masc), mat = FALSE), nrow(rad))
    out <- ifelse(n_r > 0, z / n_r, !is.na(terra::extract(masc, interior, ID = FALSE)[[1]]))
    as.numeric(out)
  }
  rad$share_eph <- share(terra::rasterize(terra::vect(per), plantilla, field = 1))

  # barrido de d
  curva <- do.call(rbind, lapply(D_SERIE, function(d) {
    cl <- componentes_a(n, arbol, d)
    tb <- table(cl[dentro])
    cc <- as.integer(names(tb)[which.max(tb)])
    data.frame(d = d, componentes = max(cl), mayor = max(table(cl)), ciudad = sum(cl == cc),
               ciudad_en_eph = max(tb), eph_total = sum(dentro))
  }))
  # salto = intersecciones que se suman a la ciudad al pasar al d siguiente de la serie (absoluto: el
  # relativo infla los saltos de componentes chicas a d bajo)
  curva$salto <- c(NA, diff(curva$ciudad))
  # criterio principal: el menor d al que la ciudad cubre el aglomerado EPH, medido en sus
  # intersecciones (100 % y 99 %, este ultimo no depende de un fragmento lejano). NA si no llega a 2000 m.
  curva$cobertura_eph <- curva$ciudad_en_eph / curva$eph_total
  d_cubre <- function(p) { k <- which(curva$cobertura_eph >= p); if (length(k)) curva$d[min(k)] else NA }
  d100 <- d_cubre(1); d99 <- d_cubre(0.99)
  D_TODOS <- sort(unique(c(D_MAPA, D_ELEGIDO, d99, d100)))
  # los mapas: ciudad a cada D_MAPA (y a D_ELEGIDO)
  polis <- list(); km2 <- list()
  for (d in D_TODOS) {
    cl <- componentes_a(n, arbol, d)
    tb <- table(cl[dentro]); cc <- as.integer(names(tb)[which.max(tb)])
    masc <- area_ciudad(m[cl == cc, , drop = FALSE], crs, d, plantilla)
    rad[[sprintf("share_d%g", d)]] <- share(masc)
    km2[[as.character(d)]] <- sum(!is.na(terra::values(masc))) * CELDA^2 / 1e6
    polis[[as.character(d)]] <- st_as_sf(terra::as.polygons(masc, dissolve = TRUE))
  }
  curva$km2_ciudad <- NA; curva$radios <- NA; curva$personas <- NA
  for (d in names(polis)) {
    i <- curva$d == as.numeric(d)
    curva$km2_ciudad[i] <- round(km2[[d]], 1)
    sel <- rad[[paste0("share_d", d)]] >= PARTE
    curva$radios[i] <- sum(sel); curva$personas[i] <- sum(rad$personas[sel], na.rm = TRUE)
  }
  write.csv(curva, file.path(d_out, "curva.csv"), row.names = FALSE)
  write.csv(st_drop_geometry(rad[, c("cod", "personas", "km2_r", "share_eph", grep("^share_d", names(rad), value = TRUE))]),
            file.path(d_out, "radios.csv"), row.names = FALSE)
  gp <- file.path(d_out, "percolacion.gpkg"); if (file.exists(gp)) invisible(file.remove(gp))
  for (d in names(polis)) st_write(st_transform(polis[[d]], 4326), gp, paste0("ciudad_", d), quiet = TRUE)

  # curva
  saltos <- head(curva[order(-curva$salto), c("d", "salto")], 3)
  p <- ggplot(curva, aes(d)) +
    geom_vline(xintercept = saltos$d, colour = "grey75", linetype = 3) +
    geom_vline(xintercept = na.omit(c(d99, d100)), colour = "#2a7fb8", linetype = 2, linewidth = 0.4) +
    geom_line(aes(y = ciudad / n, colour = "ciudad (componente del aglomerado)"), linewidth = 0.8) +
    geom_line(aes(y = mayor / n, colour = "componente mayor del cuadrado"), linewidth = 0.5, linetype = 2) +
    geom_line(aes(y = ciudad_en_eph / eph_total, colour = "intersecciones del perimetro EPH en la ciudad"), linewidth = 0.5) +
    scale_x_log10(breaks = c(20, 50, 100, 200, 500, 1000, 2000)) +
    scale_colour_manual(values = c("#7b1d3a", "grey40", "#2a7fb8"), name = NULL) +
    scale_y_continuous(labels = scales::percent) +
    labs(title = sprintf("%s · percolacion de %s intersecciones en %s",
                         a$nombre, format(n, big.mark = "."), "el cuadrado del paso 29"),
         subtitle = sprintf(paste("punteadas grises: los tres saltos mas grandes (d = %s m). Azules: la ciudad cubre",
                                  "el 99%% de las intersecciones EPH a d = %s m y el 100%% a d = %s m"),
                            paste(saltos$d, collapse = ", "), ifelse(is.na(d99), "> 2000", d99),
                            ifelse(is.na(d100), "> 2000", d100)),
         x = "d, distancia maxima entre intersecciones (m, escala log)", y = "share de intersecciones") +
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
    labs(title = sprintf("%s · la ciudad por percolacion de intersecciones, segun d", a$nombre),
         caption = "Vino: componente que contiene la mayor parte del perimetro, con buffer d/2. Gris con borde negro: perimetro de analisis (EPH).") +
    theme_minimal(base_size = 8) + theme(axis.text = element_blank(), panel.grid = element_blank(),
                                         plot.caption = element_text(size = 6, colour = "grey40", hjust = 0))
  ggsave(file.path(d_out, "ciudad_d.png"), p, width = 3.6 * ceiling(length(D_MAPA) / 2), height = 8, dpi = 150, bg = "white")

  # radios: comparacion con el perimetro EPH a cada d
  ee <- rad$share_eph >= PARTE
  clase_a <- function(d) {
    ce <- rad[[sprintf("share_d%g", d)]] >= PARTE
    factor(ifelse(ce & ee, "en los dos", ifelse(ce, "solo percolacion", ifelse(ee, "solo EPH", NA))),
           levels = c("en los dos", "solo percolacion", "solo EPH"))
  }
  ds <- D_TODOS
  por_d <- do.call(rbind, lapply(ds, function(d) {
    k <- clase_a(d); rad[[sprintf("clase_d%g", d)]] <<- as.character(k)
    data.frame(d = d,
               radios_los_dos = sum(k %in% "en los dos"), personas_los_dos = sum(rad$personas[k %in% "en los dos"], na.rm = TRUE),
               radios_solo_perc = sum(k %in% "solo percolacion"), personas_solo_perc = sum(rad$personas[k %in% "solo percolacion"], na.rm = TRUE),
               radios_solo_eph = sum(k %in% "solo EPH"), personas_solo_eph = sum(rad$personas[k %in% "solo EPH"], na.rm = TRUE))
  }))
  # d que mejor reproduce el perimetro EPH: menos personas en radios que difieren (solo perc. + solo EPH)
  por_d$personas_difieren <- por_d$personas_solo_perc + por_d$personas_solo_eph
  d_mejor <- por_d$d[which.min(por_d$personas_difieren)]
  write.csv(por_d, file.path(d_out, "radios_por_d.csv"), row.names = FALSE)
  st_write(st_transform(rad, 4326), gp, "radios", quiet = TRUE, append = TRUE)

  mapa_radios <- function(d, f) {
    rad$clase <- clase_a(d)
    t <- por_d[por_d$d == d, ]
    et <- sprintf("%s: %d radios, %s personas", c("en los dos", "solo percolacion", "solo EPH"),
                  c(t$radios_los_dos, t$radios_solo_perc, t$radios_solo_eph),
                  format(c(t$personas_los_dos, t$personas_solo_perc, t$personas_solo_eph), big.mark = ","))
    rs <- rad[!is.na(rad$clase), ]
    p <- ggplot() +
      geom_sf(data = rs, aes(fill = clase), colour = "white", linewidth = 0.05) +
      scale_fill_manual(values = c(`en los dos` = "grey55", `solo percolacion` = "#7b1d3a", `solo EPH` = "#2a7fb8"),
                        labels = et, name = NULL, drop = FALSE) +
      geom_sf(data = polis[[as.character(d)]], fill = NA, colour = "#7b1d3a", linewidth = 0.3) +
      geom_sf(data = per, fill = NA, colour = "black", linewidth = 0.35) +
      coord_sf(xlim = st_bbox(rs)[c(1, 3)], ylim = st_bbox(rs)[c(2, 4)], datum = crs) +
      labs(title = sprintf("%s · radios 2022 de la ciudad por percolacion (d = %g m) y del perimetro EPH", a$nombre, d),
           subtitle = sprintf("un radio entra si al menos %g%% de su area cae dentro", 100 * PARTE),
           caption = "Personas: censo 2022 por radio (paso 09). Linea vino: la ciudad a d; negra: perimetro EPH.") +
      theme_minimal(base_size = 8) + theme(axis.text = element_blank(), panel.grid = element_blank(),
                                           legend.position = "bottom", legend.direction = "vertical",
                                           plot.caption = element_text(size = 6, colour = "grey40", hjust = 0))
    ggsave(file.path(d_out, f), p, width = 8, height = 9, dpi = 150, bg = "white")
  }
  for (d in unique(na.omit(c(d100, d99, d_mejor, D_ELEGIDO)))) mapa_radios(d, sprintf("radios_d%g.png", d))
  if (file.exists(file.path(d_out, "radios.png"))) invisible(file.remove(file.path(d_out, "radios.png")))
  if (file.exists(file.path(d_out, "radios_d200.csv")) && D_ELEGIDO != 200) invisible(file.remove(file.path(d_out, "radios_d200.csv")))
  tabla <- por_d[por_d$d == D_ELEGIDO, ]

  resumen[[s]] <- data.frame(slug = s, nombre = a$nombre, intersecciones = n, eph_intersecciones = sum(dentro),
                             radios_eph = sum(ee), personas_eph = sum(rad$personas[ee], na.rm = TRUE),
                             saltos_d = paste(saltos$d, collapse = ";"), d = D_ELEGIDO,
                             radios_los_dos = tabla$radios_los_dos, radios_solo_perc = tabla$radios_solo_perc,
                             radios_solo_eph = tabla$radios_solo_eph, personas_los_dos = tabla$personas_los_dos,
                             personas_solo_perc = tabla$personas_solo_perc, personas_solo_eph = tabla$personas_solo_eph,
                             d_mejor = d_mejor, personas_difieren_d_mejor = min(por_d$personas_difieren),
                             d_cubre99 = d99, d_cubre100 = d100,
                             cubre100_solo_perc_radios = if (is.na(d100)) NA else por_d$radios_solo_perc[por_d$d == d100],
                             cubre100_solo_perc_personas = if (is.na(d100)) NA else por_d$personas_solo_perc[por_d$d == d100],
                             cubre100_solo_eph_radios = if (is.na(d100)) NA else por_d$radios_solo_eph[por_d$d == d100],
                             cubre100_solo_eph_personas = if (is.na(d100)) NA else por_d$personas_solo_eph[por_d$d == d100])
  cat(sprintf("%-32s %7d intersecciones · saltos en d = %s · a d=%g: %d radios en los dos, %d solo perc., %d solo EPH · cubre 99%%/100%% EPH a %s/%s m · %.0f s\n",
              s, n, paste(saltos$d, collapse = ", "), D_ELEGIDO, tabla$radios_los_dos, tabla$radios_solo_perc, tabla$radios_solo_eph,
              d99, d100, as.numeric(Sys.time() - t0, units = "secs")))
}
if (length(resumen)) {
  res <- do.call(rbind, resumen)
  f <- file.path(SAL, "resumen.csv")
  if (file.exists(f)) { v <- read.csv(f); if (identical(names(v), names(res))) res <- rbind(v[!v$slug %in% res$slug, ], res) }
  write.csv(res, f, row.names = FALSE, fileEncoding = "UTF-8")
}


# ---- HALLAZGOS.md: de resumen.csv, radios_por_d.csv y curva.csv; nada escrito a mano ---------
f_res <- file.path(SAL, "resumen.csv")
if (file.exists(f_res)) {
  res <- read.csv(f_res, check.names = FALSE, encoding = "UTF-8")
  res <- res[order(match(res$slug, ORDEN)), ]
  fmt <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
  L <- c("# Percolacion de intersecciones de calles: que radios forman el aglomerado", "",
    sprintf(paste("Generado por `Rpipe/scripts/30_percolacion_calles.R` el %s. Exploratorio: ningun numero es",
                  "cifra del proyecto. Todo sale de `resumen.csv` y de cada `<aglomerado>/radios_por_d.csv` y",
                  "`curva.csv`."), format(Sys.Date())), "",
    "## Metodo, paso a paso", "",
    paste("1. **Intersecciones.** Nodos de la red de calles de Overture donde se juntan 3 o mas tramos, en el",
          "cuadrado del paso 29 (calles manejables: sin sendas, veredas ni ciclovias; un puente cuenta como cruce)."),
    paste("2. **Percolacion** (Arcaute et al. 2015, J. R. Soc. Interface 12: 20140745). Dos intersecciones se",
          "unen si estan a menos de d metros; cada componente conexa es una ciudad. Se barre d de 20 a 2000 m",
          "(cada 10 m hasta 500, cada 50 hasta 2000). El tamano de la ciudad crece a saltos: los saltos marcan",
          "los d donde cambia lo que se esta llamando ciudad, y las mesetas entre saltos son los d defendibles."),
    paste("3. **La ciudad a cada d.** La componente con mas intersecciones dentro del perimetro de analisis",
          sprintf("(EPH, paso 07). Su area: las celdas de %g m a menos de d/2 de una de sus intersecciones.", CELDA)),
    sprintf(paste("4. **Radios censales 2022.** Un radio es de la ciudad si al menos %g%% de su area cae en ella, y",
                  "del perimetro EPH si al menos %g%% cae en el perimetro. A cada d se cuentan radios y personas",
                  "en los dos, solo en la percolacion y solo en el EPH."), 100 * PARTE, 100 * PARTE),
    paste("5. **Criterio principal (propuesto): d cubre 99%.** El menor d al que la ciudad contiene el 99% de las",
          "intersecciones del perimetro EPH. Se calcula sobre todo el barrido, no solo los d mapeados. A ese d, los",
          "radios \"solo percolacion\" son lo que la red de calles agrega al aglomerado oficial, y los \"solo EPH\" lo que",
          "el perimetro tiene y la red no une al nucleo."),
    paste("6. **Diagnostico: d cubre 100%.** El menor d que contiene todas las intersecciones del perimetro. Es fragil:",
          "si el perimetro tiene un fragmento lejano o mucho campo vacio, solo se alcanza a d muy alto, y para llegar",
          "la percolacion encadena localidades vecinas. Cuando d cubre 100% queda muy por encima de d cubre 99%,",
          "el perimetro EPH tiene partes que conviene revisar a mano."),
    paste("7. **Referencia: el d que mejor reproduce el EPH.** Entre los d mapeados, el que deja menos personas en",
          "radios que difieren (solo percolacion + solo EPH)."),
    paste("8. **Mapa final** (paso 31). La ciudad a d cubre 99% (a 2000 m si no lo alcanza) con las sedes de gobierno",
          "local del paso 29, coloreadas por su comunidad de Leiden (tau 15 y 30 min) y unidas al nucleo de su grupo:",
          "la sede con menor tiempo total de viaje al resto, sin ponderar por poblacion. Muestra donde la continuidad",
          "fisica de las calles y las comunidades por tiempo de viaje coinciden y donde no."), "",
    paste("Lectura: a d bajo (alrededor de 150-200 m) la percolacion da la ciudad compacta; a d de varios cientos",
          "de metros se suman las localidades vecinas y aparece el aglomerado. Los radios \"solo percolacion\" son",
          "los candidatos a agregar al aglomerado; los \"solo EPH\", los que la red de calles no une al nucleo."), "",
    "## Resumen", "",
    paste("| aglomerado | intersecciones | radios EPH | personas EPH | saltos mas grandes (d, m) | **d cubre 99%** |",
          "a d cubre 99%: solo percolacion (radios / personas) | solo EPH (radios / personas) | d cubre 100% |",
          "a d cubre 100%: solo percolacion | solo EPH | d mejor |"),
    "|---|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|")
  na_ <- function(x) ifelse(is.na(x), "> 2000", fmt(x))
  en_d <- function(pd, d, col) if (is.na(d) || !any(pd$d == d)) NA else pd[[col]][pd$d == d]
  for (i in seq_len(nrow(res))) {
    pd <- read.csv(file.path(SAL, res$slug[i], "radios_por_d.csv"))
    d99 <- res$d_cubre99[i]
    L <- c(L, sprintf("| %s | %s | %s | %s | %s | **%s** | %s / %s | %s / %s | %s | %s / %s | %s / %s | %g |", res$nombre[i],
                      fmt(res$intersecciones[i]), fmt(res$radios_eph[i]), fmt(res$personas_eph[i]),
                      gsub(";", ", ", res$saltos_d[i]), na_(d99),
                      na_(en_d(pd, d99, "radios_solo_perc")), na_(en_d(pd, d99, "personas_solo_perc")),
                      na_(en_d(pd, d99, "radios_solo_eph")), na_(en_d(pd, d99, "personas_solo_eph")),
                      na_(res$d_cubre100[i]),
                      na_(res$cubre100_solo_perc_radios[i]), na_(res$cubre100_solo_perc_personas[i]),
                      na_(res$cubre100_solo_eph_radios[i]), na_(res$cubre100_solo_eph_personas[i]), res$d_mejor[i]))
  }
  # lo construido (paso 31): urbano de MapBiomas dentro del perimetro EPH y de la ciudad a d cubre 99%
  f_mb <- file.path(SAL, "mapbiomas_resumen.csv")
  mbr <- if (file.exists(f_mb)) read.csv(f_mb, check.names = FALSE, encoding = "UTF-8") else NULL
  if (!is.null(mbr)) {
    mbr <- mbr[order(match(mbr$slug, res$slug)), ]
    pc <- function(x) sprintf("%.1f%%", 100 * x)
    L <- c(L, "", sprintf("## Lo construido segun MapBiomas %d", mbr$anio[1]), "",
           paste("Urbano de MapBiomas Argentina (coleccion 2, clase 24, 30 m) en el cuadrado, y cuanto de el cae dentro",
                 "del perimetro EPH y dentro de la ciudad por percolacion al d que cubre el 99% (2000 m si no lo alcanza).",
                 "Si la ciudad captura mucho mas urbano que el perimetro, lo construido ya excede al aglomerado oficial."), "",
           paste("| aglomerado | d (m) | urbano en el cuadrado (km2) | en el perimetro EPH | en la ciudad por percolacion |",
                 "en la ciudad y fuera del perimetro (km2) | en el perimetro y fuera de la ciudad (km2) |"),
           "|---|---:|---:|---:|---:|---:|---:|",
           sprintf("| %s | %g | %s | %s (%s) | %s (%s) | %s | %s |", mbr$nombre, mbr$d, fmt(mbr$urbano_cuadrado_km2),
                   fmt(mbr$urbano_eph_km2), pc(mbr$share_cuadrado_en_eph), fmt(mbr$urbano_ciudad_km2),
                   pc(mbr$share_cuadrado_en_ciudad), fmt(mbr$urbano_solo_ciudad_km2), fmt(mbr$urbano_solo_eph_km2)))
  }
  L <- c(L, "", "## Por aglomerado", "")
  for (i in seq_len(nrow(res))) {
    s <- res$slug[i]
    pd <- read.csv(file.path(SAL, s, "radios_por_d.csv"))
    cv <- read.csv(file.path(SAL, s, "curva.csv"))
    L <- c(L, sprintf("### %s", res$nombre[i]), "",
           sprintf(paste("%s intersecciones en el cuadrado, %s dentro del perimetro EPH. Perimetro EPH: %s radios,",
                         "%s personas. Saltos mas grandes del tamano de la ciudad en d = %s m."),
                   fmt(res$intersecciones[i]), fmt(res$eph_intersecciones[i]), fmt(res$radios_eph[i]),
                   fmt(res$personas_eph[i]), gsub(";", ", ", res$saltos_d[i])), "",
           if (is.na(res$d_cubre99[i])) "**La ciudad no llega a cubrir el 99% del aglomerado EPH a 2000 m.**" else
             sprintf(paste("**La ciudad cubre el 99%% del aglomerado EPH a d = %g m.** A ese d, la percolacion agrega %s",
                           "radios (%s personas) fuera del perimetro y deja %s radios del perimetro (%s personas) con menos",
                           "del %g%% de su area dentro."), res$d_cubre99[i],
                     na_(en_d(pd, res$d_cubre99[i], "radios_solo_perc")), na_(en_d(pd, res$d_cubre99[i], "personas_solo_perc")),
                     na_(en_d(pd, res$d_cubre99[i], "radios_solo_eph")), na_(en_d(pd, res$d_cubre99[i], "personas_solo_eph")),
                     100 * PARTE), "",
           if (is.na(res$d_cubre100[i])) "Diagnostico: no cubre el 100% a 2000 m." else
             sprintf("Diagnostico: cubre el 100%% a d = %g m (agrega %s radios, %s personas; deja %s radios, %s personas).",
                     res$d_cubre100[i], fmt(res$cubre100_solo_perc_radios[i]), fmt(res$cubre100_solo_perc_personas[i]),
                     fmt(res$cubre100_solo_eph_radios[i]), fmt(res$cubre100_solo_eph_personas[i])), "",
           sprintf("![curva](%s/curva.png)", s), "",
           sprintf("![ciudad segun d](%s/ciudad_d.png)", s), "",
           "| d (m) | intersecciones de la ciudad | km2 | en los dos (radios / personas) | solo percolacion | solo EPH |",
           "|---:|---:|---:|---:|---:|---:|",
           sprintf("| %s%g%s | %s | %s | %s / %s | %s / %s | %s / %s |",
                   ifelse(pd$d %in% c(res$d_cubre99[i], res$d_cubre100[i]), "**", ""), pd$d,
                   ifelse(pd$d %in% c(res$d_cubre99[i], res$d_cubre100[i]), "**", ""),
                   fmt(cv$ciudad[match(pd$d, cv$d)]), cv$km2_ciudad[match(pd$d, cv$d)],
                   fmt(pd$radios_los_dos), fmt(pd$personas_los_dos), fmt(pd$radios_solo_perc),
                   fmt(pd$personas_solo_perc), fmt(pd$radios_solo_eph), fmt(pd$personas_solo_eph)), "",
           sprintf("En negrita, los d que cubren el 99%% y el 100%% del aglomerado EPH. El que mejor lo reproduce (menos personas en radios que difieren) es d = %g m.",
                   res$d_mejor[i]), "",
           unlist(lapply(unique(na.omit(c(res$d_cubre99[i], res$d_cubre100[i]))), function(d)
             c(sprintf("![radios a d = %g m](%s/radios_d%g.png)", d, s, d), ""))),
           unlist(lapply(c(15, 30), function(tau) {
             f <- sprintf("mapa_final_leiden%g.png", tau)
             if (file.exists(file.path(SAL, s, f)))
               c(sprintf("Mapa final, comunidades de Leiden con tau %g min:", tau), "",
                 sprintf("![mapa final, Leiden tau %g](%s/%s)", tau, s, f), "") else NULL
           })),
           if (!is.null(mbr) && s %in% mbr$slug && file.exists(file.path(SAL, s, "mapa_final_mapbiomas.png"))) {
             m <- mbr[mbr$slug == s, ]
             c(sprintf(paste("Lo construido (MapBiomas %d): %s km2 de urbano en el cuadrado; %s km2 dentro del perimetro EPH",
                             "y %s km2 dentro de la ciudad a d = %g m. La ciudad suma %s km2 de urbano fuera del perimetro;",
                             "el perimetro tiene %s km2 de urbano fuera de la ciudad."), m$anio, fmt(m$urbano_cuadrado_km2),
                       fmt(m$urbano_eph_km2), fmt(m$urbano_ciudad_km2), m$d, fmt(m$urbano_solo_ciudad_km2),
                       fmt(m$urbano_solo_eph_km2)), "",
               sprintf("![lo construido segun MapBiomas](%s/mapa_final_mapbiomas.png)", s), "")
           } else NULL)
  }
  L <- c(L, "## Limitaciones", "",
         "- Overture junta OpenStreetMap y otras fuentes: donde el mapeo de calles es pobre, la percolacion subestima la ciudad.",
         "- Los cruces a distinto nivel (puentes, autopistas) cuentan como intersecciones.",
         "- El buffer d/2 redondea los bordes: a d grande un radio rural grande puede pasar el corte del area solo por el buffer.",
         "- La regla del area penaliza los radios grandes del borde, que pueden tener un barrio en una esquina.",
         "- Personas: censo 2022 por radio (paso 09, copia CEUR-CONICET de los datos del INDEC).")
  writeLines(enc2utf8(L), file.path(SAL, "HALLAZGOS.md"), useBytes = TRUE)
  cat("HALLAZGOS.md escrito\n")
}
