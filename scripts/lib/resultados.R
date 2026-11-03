# -*- coding: utf-8 -*-
# Funciones de las salidas de resultados (el reporte, 06_reporte.R): leen los
# resultados de Angel, calculan lo que se publica, dibujan graficos y mapas y arman el
# texto compartido. Se carga con source(); no se corre sola.
#
# Lee:
#   outputs/angel/resumen.csv             metricas por ciudad y anio (paso 04)
#   outputs/angel/<slug>/angel_<anio>.tif clases 0-5 (paso 04), para los mapas
#   raw/boundaries/aglomerados.gpkg       perimetro, nombre y provincia (paso 07)
#   cajas.md                              que ciudad va con que aglomerado
# Solo aglomerados: las filas de cajas.md con contorno (Tandil queda afuera).
#
# NINGUNA CIFRA SE ESCRIBE A MANO. Todo numero sale de resumen.csv en la corrida, y las
# frases que clasifican ciudades salen de estas reglas:
#   ritmo   crecimiento anual del construido 1990-2020: >= 4 muy rapido, >= 2,5
#           rapido, >= 1,5 moderado, < 1,5 lento
#   forma   cambio de la saturacion 1990-2020: >= +0,03 se llena, <= -0,03 se
#           dispersa, en el medio estable
#   alerta  construido >= 4 % anual: revisar contra GHSL o imagenes (suelo desnudo)
# Exploratorio: NO son cifras del proyecto (no estan en CIFRAS_CANONICAS.json).

Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))
suppressPackageStartupMessages({
  library(ggplot2)
  library(terra)
  library(sf)
})
# requiere lib/cajas.R cargado antes (leer_cajas)

ANIOS <- c(1990, 2000, 2010, 2020)

# paleta categorica validada (validate_palette.js, modo claro); la misma en graficos y mapas
COL <- c(urbano = "#2a78d6", suburbano = "#eda100", capturado = "#1baf7a", franja = "#eb6834")
ETQ <- c(urbano = "urban built-up", suburbano = "suburban built-up",
         capturado = "captured open space", franja = "fringe open space")
MEDIDAS <- c(construido = "#2a78d6", sin_franja = "#1baf7a", con_franja = "#eb6834")
ETQ_MED <- c(construido = "built-up", sin_franja = "extent without fringe",
             con_franja = "extent with fringe")
# valor del raster de 04 -> color: 0 abierto rural, 1 urbano, 2 suburbano,
# 3 rural construido, 4 franja, 5 capturado
PAL_MAPA <- c("#f3f2ee", COL[["urbano"]], COL[["suburbano"]], "#8a8986", COL[["franja"]],
              COL[["capturado"]])
FONDO <- "#fcfcfb"
TINTA <- "#0b0b0b"
TINTA2 <- "#52514e"
REJILLA <- "#e6e5df"
PIE <- "Source: GISD30 (Zhang et al. 2022). Angel / Atlas of Urban Expansion 2016 classes. Exploratory."

tema <- theme_minimal(base_size = 11) +
  theme(plot.background = element_rect(fill = FONDO, colour = NA),
        panel.background = element_rect(fill = FONDO, colour = NA),
        panel.grid.major.x = element_blank(), panel.grid.minor = element_blank(),
        panel.grid.major.y = element_line(colour = REJILLA, linewidth = 0.3),
        text = element_text(colour = TINTA), axis.text = element_text(colour = TINTA2),
        strip.text = element_text(face = "bold", hjust = 0),
        plot.title = element_text(face = "bold"), plot.subtitle = element_text(colour = TINTA2),
        plot.caption = element_text(colour = TINTA2, hjust = 0),
        legend.position = "top", legend.justification = "left")
tema_h <- tema + theme(panel.grid.major.x = element_line(colour = REJILLA, linewidth = 0.3),
                       panel.grid.major.y = element_blank())


# ---- formato -----------------------------------------------------------------------

f0 <- function(x) formatC(x, format = "f", digits = 0, big.mark = ",")
f1 <- function(x) formatC(x, format = "f", digits = 1, big.mark = ",")
f2 <- function(x) formatC(x, format = "f", digits = 2, big.mark = ",")
fs <- function(x) ifelse(x >= 0, paste0("+", f2(x)), f2(x))   # con signo
tabla <- function(cab, filas) c(paste0("| ", paste(cab, collapse = " | "), " |"),
                                paste0("|", paste(rep("---", length(cab)), collapse = "|"), "|"),
                                vapply(filas, function(f) paste0("| ", paste(f, collapse = " | "), " |"), ""))
lista <- function(x) if (!length(x)) "none" else paste(x, collapse = ", ")
tasa <- function(x0, x1, anios) 100 * ((x1 / x0)^(1 / anios) - 1)
leyenda_png <- function(archivo) {
  # leyenda de los mapas como imagen: GitHub no deja pasar estilos en el markdown
  et <- c("urban built-up", "suburban built-up", "fringe open space", "captured open space",
          "rural built-up", "rural open space", "agglomerate perimeter")
  co <- PAL_MAPA[c(2, 3, 5, 6, 4, 1)]
  png(archivo, width = 1000, height = 70, bg = FONDO)
  par(mar = c(0, 0, 0, 0))
  plot.new()
  plot.window(c(0, 1000), c(0, 70))
  x <- c(10, 170, 345, 520, 705, 850)
  for (i in 1:6) {
    rect(x[i], 42, x[i] + 22, 62, col = co[i], border = "#c9c8c2")
    text(x[i] + 30, 52, et[i], adj = 0, cex = 1.1, col = TINTA)
  }
  segments(10, 18, 32, 18, col = "#1d1d1b", lwd = 2)
  text(40, 18, et[7], adj = 0, cex = 1.1, col = TINTA)
  dev.off()
}


# ---- datos -------------------------------------------------------------------------

cargar_resultados <- function(rpipe) {
  angel <- file.path(rpipe, "outputs", "angel")
  cj <- leer_cajas(rpipe)
  cj <- cj[nzchar(cj$contorno), c("slug", "contorno")]
  per <- st_read(file.path(rpipe, "raw", "boundaries", "aglomerados.gpkg"), layer = "perimetro", quiet = TRUE)
  info <- merge(cj, st_drop_geometry(per), by.x = "contorno", by.y = "slug")

  d <- read.csv(file.path(angel, "resumen.csv"))
  d <- d[d$ciudad %in% info$slug & d$anio %in% ANIOS, ]
  completas <- names(which(table(d$ciudad) == length(ANIOS)))
  faltan <- setdiff(info$slug, completas)
  if (length(faltan)) cat("AVISO  sin las cuatro epocas, quedan afuera:", paste(faltan, collapse = ", "), "\n")
  d <- d[d$ciudad %in% completas, ]
  info <- info[info$slug %in% completas, ]
  info <- info[order(info$nombre), ]
  if (length(unique(d$u_rural)) != 1) stop("resumen.csv mezcla umbrales rurales", call. = FALSE)

  d$sin_franja <- d$urbano_ciudad_km2 + d$suburbano_ciudad_km2 + d$capturado_ciudad_km2
  d$pct_franja <- 100 * d$franja_ciudad_km2 / d$extension_ciudad_km2
  d$nombre <- info$nombre[match(d$ciudad, info$slug)]
  d <- d[order(d$ciudad, d$anio), ]
  val <- function(slug, anio, col) d[[col]][d$ciudad == slug & d$anio == anio]

  # una fila por ciudad con todo lo que se publica
  fichas <- do.call(rbind, lapply(info$slug, function(s) {
    data.frame(slug = s,
               nombre = info$nombre[info$slug == s],
               provincia = info$provincia[info$slug == s],
               partes = info$n_partes[info$slug == s],
               construido_1990 = val(s, 1990, "construido_ciudad_km2"),
               construido_2020 = val(s, 2020, "construido_ciudad_km2"),
               extension_1990 = val(s, 1990, "extension_ciudad_km2"),
               extension_2020 = val(s, 2020, "extension_ciudad_km2"),
               t_construido = tasa(val(s, 1990, "construido_ciudad_km2"), val(s, 2020, "construido_ciudad_km2"), 30),
               t_sin = tasa(val(s, 1990, "sin_franja"), val(s, 2020, "sin_franja"), 30),
               t_con = tasa(val(s, 1990, "extension_ciudad_km2"), val(s, 2020, "extension_ciudad_km2"), 30),
               franja_1990 = val(s, 1990, "pct_franja"), franja_2020 = val(s, 2020, "pct_franja"),
               suma_franja_2020 = 100 * val(s, 2020, "franja_ciudad_km2") / val(s, 2020, "sin_franja"),
               sat_1990 = val(s, 1990, "saturacion"), sat_2020 = val(s, 2020, "saturacion"),
               ape_1990 = val(s, 1990, "apertura"), ape_2020 = val(s, 2020, "apertura"))
  }))
  fichas$dif <- fichas$t_con - fichas$t_sin
  fichas$ritmo <- cut(fichas$t_construido, c(-Inf, 1.5, 2.5, 4, Inf), right = FALSE,
                      labels = c("slow", "moderate", "fast", "very fast"))
  dsat <- fichas$sat_2020 - fichas$sat_1990
  fichas$forma <- ifelse(dsat >= 0.03, "filling in", ifelse(dsat <= -0.03, "spreading out", "stable"))
  fichas$alerta <- fichas$t_construido >= 4

  # agregados: todos y sin Gran Buenos Aires
  n <- nrow(info)
  t_todos <- sprintf("All %d agglomerations", n)
  t_sin <- sprintf("%d agglomerations, without Gran Buenos Aires", n - 1)
  gba <- info$slug[info$contorno == "gran_buenos_aires"]
  suma <- function(x, grupo) {
    cols <- c(paste0(names(COL), "_ciudad_km2"), "extension_ciudad_km2", "construido_ciudad_km2", "sin_franja")
    a <- aggregate(x[cols], list(anio = x$anio), sum)
    a$pct_franja <- 100 * a$franja_ciudad_km2 / a$extension_ciudad_km2
    a$ciudad <- a$nombre <- a$grupo <- grupo
    a
  }
  ag <- rbind(suma(d, t_todos), suma(d[!d$ciudad %in% gba, ], t_sin))
  ag$grupo <- factor(ag$grupo, levels = c(t_todos, t_sin))

  # que grilla uso cada ciudad: la del compuesto Landsat (04) o la caja de cajas.md (04b)
  fichas$grilla <- ifelse(file.exists(file.path(rpipe, "outputs", "landsat", fichas$slug, "landsat_2020.tif")),
                          "Landsat (04)", "box (04b)")

  list(d = d, info = info, fichas = fichas, per = per, ag = ag, angel = angel, n = n,
       t_todos = t_todos, t_sin = t_sin, u_rural = unique(d$u_rural))
}

decadas <- function(r, s) {
  x <- r$d[r$d$ciudad == s, ]
  do.call(rbind, lapply(1:3, function(i) data.frame(
    decada = sprintf("%d-%d", ANIOS[i], ANIOS[i + 1]), medida = names(MEDIDAS),
    tasa = c(tasa(x$construido_ciudad_km2[i], x$construido_ciudad_km2[i + 1], 10),
             tasa(x$sin_franja[i], x$sin_franja[i + 1], 10),
             tasa(x$extension_ciudad_km2[i], x$extension_ciudad_km2[i + 1], 10)))))
}


# ---- graficos ----------------------------------------------------------------------

largo <- function(x) {
  l <- do.call(rbind, lapply(names(COL), function(k)
    data.frame(ciudad = x$ciudad, nombre = x$nombre, anio = factor(x$anio), clase = k,
               km2 = x[[paste0(k, "_ciudad_km2")]])))
  l$clase <- factor(l$clase, levels = rev(names(COL)))
  l
}

barras <- function(x, titulo, facetas = FALSE) {
  g <- ggplot(largo(x), aes(anio, km2, fill = clase)) +
    geom_col(width = 0.7, colour = FONDO, linewidth = 0.4) +
    geom_text(data = x, aes(factor(anio), extension_ciudad_km2, label = sprintf("%.0f%% fringe", pct_franja)),
              inherit.aes = FALSE, vjust = -0.5, size = 3, colour = TINTA2) +
    scale_fill_manual(values = COL, breaks = names(COL), labels = ETQ) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.14)), labels = function(v) f0(v)) +
    labs(x = NULL, y = "km²", fill = NULL, title = titulo,
         subtitle = "Urban extent by component. Label: share of the extent that is fringe open space",
         caption = PIE) + tema +
    guides(fill = guide_legend(nrow = 2))
  if (facetas) g <- g + facet_wrap(~grupo, scales = "free_y")
  g
}

graf_decadas <- function(r, s, titulo) {
  x <- decadas(r, s)
  x$medida <- factor(x$medida, levels = names(MEDIDAS))
  ggplot(x, aes(decada, tasa, fill = medida)) +
    geom_hline(yintercept = 0, colour = TINTA2, linewidth = 0.3) +
    geom_col(position = position_dodge(width = 0.78), width = 0.72, colour = FONDO, linewidth = 0.4) +
    geom_text(aes(label = sprintf("%.1f", tasa), vjust = ifelse(tasa >= 0, -0.4, 1.3)),
              position = position_dodge(width = 0.78), size = 2.8, colour = TINTA2) +
    scale_fill_manual(values = MEDIDAS, labels = ETQ_MED) +
    scale_y_continuous(expand = expansion(mult = c(0.08, 0.14))) +
    labs(x = NULL, y = "% per year", fill = NULL, title = titulo,
         subtitle = "Annual compound growth in each decade", caption = PIE) + tema
}

puntos <- function(x, titulo, eje, subtitulo = NULL) {
  ggplot(x, aes(v, nombre)) +
    geom_line(aes(group = nombre), colour = "#d6d5cf", linewidth = 0.6) +
    geom_point(aes(colour = anio), size = 2.4) +
    scale_colour_manual(values = c("1990" = "#86b6ef", "2020" = "#1c5cab")) +
    labs(x = eje, y = NULL, colour = NULL, title = titulo, subtitle = subtitulo, caption = PIE) + tema_h
}

graficos <- function(r, dir) {
  # escribe en dir: argentina_*.png y agl/<slug>_{composicion,decadas}.png
  dir.create(file.path(dir, "agl"), recursive = TRUE, showWarnings = FALSE)
  guardar <- function(g, nombre, w, h) ggsave(file.path(dir, nombre), g, width = w, height = h, dpi = 120, bg = FONDO)
  fi <- r$fichas
  alto <- 0.3 * r$n + 2

  guardar(barras(r$ag, "Urban extent of Argentina's agglomerations", facetas = TRUE),
          "argentina_composicion.png", 10, 5.2)

  cre <- rbind(data.frame(nombre = fi$nombre, medida = "construido", tasa = fi$t_construido),
               data.frame(nombre = fi$nombre, medida = "sin_franja", tasa = fi$t_sin),
               data.frame(nombre = fi$nombre, medida = "con_franja", tasa = fi$t_con))
  cre$nombre <- factor(cre$nombre, levels = fi$nombre[order(fi$t_construido)])
  cre$medida <- factor(cre$medida, levels = names(MEDIDAS))
  guardar(ggplot(cre, aes(tasa, nombre, colour = medida)) +
            geom_line(aes(group = nombre), colour = "#d6d5cf", linewidth = 0.6) +
            geom_point(size = 2.4) +
            scale_colour_manual(values = MEDIDAS, labels = ETQ_MED) +
            labs(x = "annual growth 1990-2020 (%)", y = NULL, colour = NULL,
                 title = "How fast each agglomeration grew, by what is counted",
                 subtitle = "Annual compound growth of the surface, 1990 to 2020", caption = PIE) + tema_h,
          "argentina_crecimiento.png", 8.5, alto)

  fr <- rbind(data.frame(nombre = fi$nombre, anio = "1990", v = fi$franja_1990),
              data.frame(nombre = fi$nombre, anio = "2020", v = fi$franja_2020))
  fr$nombre <- factor(fr$nombre, levels = fi$nombre[order(fi$franja_2020)])
  guardar(puntos(fr, "Weight of the fringe open space, 1990 and 2020",
                 "% of the urban extent that is fringe open space"), "argentina_franja.png", 8, alto)

  df <- data.frame(nombre = factor(fi$nombre, levels = fi$nombre[order(fi$dif)]), v = fi$dif)
  guardar(ggplot(df, aes(v, nombre)) +
            geom_vline(xintercept = 0, colour = TINTA2, linewidth = 0.3) +
            geom_col(fill = "#6f6e69", width = 0.65) +
            labs(x = "growth with fringe minus growth without fringe (percentage points per year)", y = NULL,
                 title = "How much counting the fringe changes the growth rate",
                 subtitle = "Negative: the city fills its old fringe. Positive: new scattered patches add new fringe",
                 caption = PIE) + tema_h,
          "argentina_efecto_franja.png", 8.5, alto)

  ix <- rbind(data.frame(nombre = fi$nombre, anio = "1990", indice = "saturation", v = fi$sat_1990),
              data.frame(nombre = fi$nombre, anio = "2020", indice = "saturation", v = fi$sat_2020),
              data.frame(nombre = fi$nombre, anio = "1990", indice = "openness", v = fi$ape_1990),
              data.frame(nombre = fi$nombre, anio = "2020", indice = "openness", v = fi$ape_2020))
  ix$nombre <- factor(ix$nombre, levels = fi$nombre[order(fi$sat_2020)])
  guardar(puntos(ix, "Saturation and openness, 1990 and 2020", NULL,
                 "Saturation: built-up / urban extent. Openness: unbuilt share of the 1 km² circle") +
            facet_wrap(~indice, scales = "free_x"), "argentina_indices.png", 9.5, alto)

  for (s in r$info$slug) {
    nm <- r$info$nombre[r$info$slug == s]
    guardar(barras(r$d[r$d$ciudad == s, ], nm), sprintf("agl/%s_composicion.png", s), 7.5, 4.8)
    guardar(graf_decadas(r, s, nm), sprintf("agl/%s_decadas.png", s), 7.5, 4.4)
  }
  cat("graficos listos en", dir, "\n")
}


# ---- mapas -------------------------------------------------------------------------

mapas <- function(r, dir) {
  # escribe en dir: maps/<slug>_<anio>.png, el perimetro mas 5 km, mismo encuadre en las
  # cuatro epocas
  dir.create(file.path(dir, "maps"), recursive = TRUE, showWarnings = FALSE)
  leyenda_png(file.path(dir, "maps", "leyenda.png"))
  for (s in r$info$slug) {
    cont <- vect(r$per[r$per$slug == r$info$contorno[r$info$slug == s], ])
    r0 <- rast(file.path(r$angel, s, "angel_2020.tif"))
    marco <- intersect(ext(project(cont, crs(r0))) + 5000, ext(r0))
    for (a in ANIOS) {
      x <- crop(rast(file.path(r$angel, s, sprintf("angel_%d.tif", a))), marco)
      coltab(x) <- data.frame(value = 0:5, col = PAL_MAPA)
      w <- 900
      h <- round(w * nrow(x) / ncol(x))
      if (h > 1100) { w <- round(w * 1100 / h); h <- 1100 }
      png(file.path(dir, "maps", sprintf("%s_%d.png", s, a)), width = w, height = h + 40, bg = FONDO)
      plot(x, legend = FALSE, axes = FALSE, mar = c(0, 0, 2, 0), maxcell = 4e6,
           main = sprintf("%s · %d", r$info$nombre[r$info$slug == s], a), cex.main = 1.3)
      lines(project(cont, crs(x)), col = "#1d1d1b", lwd = 1.3)
      dev.off()
    }
    cat("  mapas", s, "\n")
  }
}


# ---- texto compartido --------------------------------------------------------------
# img(ruta, alt) y enlace(slug) los pone quien llama: cada salida resuelve sus rutas y
# enlaces (el reporte, rutas relativas y anclas).

resumen_md <- function(r) {
  fi <- r$fichas
  tot <- r$ag[r$ag$grupo == r$t_todos, ]
  sin <- r$ag[r$ag$grupo == r$t_sin, ]
  ta <- function(x, col) tasa(x[[col]][x$anio == 1990], x[[col]][x$anio == 2020], 30)
  sprintf("Across the %d agglomerations, built-up land inside the urban extent grew from %s km² in 1990 to %s km² in 2020 (%s %% a year); without Gran Buenos Aires, from %s to %s km² (%s %% a year). The fringe open space is %s %% of the total urban extent in 2020, and between %s %% and %s %% city by city. Counting it adds %s-%s %% to the area of each city, but moves its 1990-2020 growth rate by less than 0.2 points a year in %d of the %d.",
          r$n, f0(tot$construido_ciudad_km2[tot$anio == 1990]), f0(tot$construido_ciudad_km2[tot$anio == 2020]),
          f2(ta(tot, "construido_ciudad_km2")), f0(sin$construido_ciudad_km2[sin$anio == 1990]),
          f0(sin$construido_ciudad_km2[sin$anio == 2020]), f2(ta(sin, "construido_ciudad_km2")),
          f1(tot$pct_franja[tot$anio == 2020]), f1(min(fi$franja_2020)), f1(max(fi$franja_2020)),
          f0(min(fi$suma_franja_2020)), f0(max(fi$suma_franja_2020)), sum(abs(fi$dif) < 0.2), r$n)
}

metodo_md <- function(r, h = "##") {
  # el metodo, con encabezados de nivel h
  h2 <- paste0(h, "#")
  c(paste(h, "Data"), "",
    "- **GISD30** (Zhang et al. 2022, *Earth System Science Data* 14:1831-1856, CC BY 4.0): global impervious surface at 30 m from Landsat. Each pixel stores the period of its first detection: 0 never, 1 before 1985, 2-8 five-year periods 1985-2020. The record is cumulative: a pixel never stops being built.",
    "- **Decades** (`01_gisd30_decadas.R`): built-up by 1990 = values 1-2, by 2000 = 1-4, by 2010 = 1-6, by 2020 = 1-8.",
    "- **Agglomerate perimeters** (`07_limites_aglomerados.R`): the analysis perimeter of the *Bolsones de pobreza* project, i.e. the EPH agglomerate plus the continuous 2022 city that spills over it, simplified to about 200 m.",
    "- **Boxes** (`cajas.md`): the perimeter's bounding box plus 10 km on every side, so the 1 km² neighbourhood never runs out of data at the edge of the city. Salta and Gran Tucumán use hand-drawn boxes that also cover the whole perimeter.",
    "- Each box is reprojected to its UTM zone at 30 m (nearest neighbour) so that distances are metric.",
    sprintf("- **Grid**: %d agglomerations were cut on the grid of their Landsat composite (`04_angel_atlas.R`) and %d directly with their box (`04b_angel_sin_landsat.R`). Landsat is only a grid template, never an input to the classes, and the composite has the same box, so the two grids differ by a fraction of a pixel at the edge. On the box grid: %s.",
            sum(r$fichas$grilla == "Landsat (04)"), sum(r$fichas$grilla == "box (04b)"),
            lista(r$fichas$nombre[r$fichas$grilla == "box (04b)"])), "",
    paste(h, "Classes"), "",
    sprintf("Each 30 m pixel looks at the circle of 1 km² around it (radius 564 m) and the share of that circle that is built-up. Rural cut used here: **%s** (Atlas 2016 edition).", f2(r$u_rural)), "",
    tabla(c("Value", "Class", "Rule", "In the urban extent?"), list(
      c("0", "rural open space", "not built-up, none of the below", "no"),
      c("1", "urban built-up", "built-up, circle > 50 % built", "yes"),
      c("2", "suburban built-up", sprintf("built-up, circle %s-50 %% built", f0(100 * r$u_rural)), "yes"),
      c("3", "rural built-up", sprintf("built-up, circle < %s %% built", f0(100 * r$u_rural)), "no"),
      c("4", "fringe open space", "not built-up, within 100 m of urban or suburban built-up", "yes"),
      c("5", "captured open space", "open patch (4-connected) under 200 ha, fully enclosed, not touching the box edge", "yes"))), "",
    "**Urban extent** = urban + suburban + fringe + captured.", "",
    paste(h2, "How the fringe is drawn"), "",
    "A 100 m circle on the 30 m grid is centred on every urban and suburban pixel; every pixel that is not built-up and falls inside one of those circles is fringe. On the grid the circle reaches 3 pixels straight out (90 m) and 85-95 m on the diagonals. Rural built-up pixels do not make fringe. Captured open space is assigned after the fringe, so the two never overlap.", "",
    "Because each built edge brings its own ring, the fringe grows with the *length of the city's edge*, not with its area: fragmented cities carry the most fringe, and a city that builds on its old fringe loses fringe as it grows.", "",
    paste(h, "\"The city\""), "",
    "Inside each box, the city is the set of urban-extent patches (8-connected) that touch the agglomerate perimeter. A town inside the box that never touches the perimeter is left out; the two cities of a two-city agglomerate (Ushuaia and Río Grande, Viedma and Carmen de Patagones) count together.", "",
    "When one patch touches the perimeters of two agglomerates, each of its pixels goes to the nearer perimeter. Without that rule the patch would count twice. Of the 31 agglomerates, it applies only to Gran Buenos Aires and Gran La Plata, whose built-up areas join (checked on the 2020 extent); patches that are not shared are not affected.", "",
    paste(h, "Metrics"), "",
    tabla(c("Metric", "Definition"), list(
      c("built-up", "built-up pixels inside the city's urban extent"),
      c("saturation", "built-up / urban extent"),
      c("openness", "average unbuilt share of the 1 km² circle around the city's urban and suburban pixels"),
      c("fringe share", "fringe open space / urban extent"),
      c("growth", "annual compound rate, (x1 / x0)^(1 / years) - 1"),
      c("project footprint", "the *Bolsones de pobreza* definition (Angel, Parent & Civco 2007; rural cut 0.10): built-up with ≥ 10 % of its circle built, plus unbuilt pixels with > 50 % built around them or within 100 m of that built-up; patches touching the perimeter"))), "",
    paste(h, "Rules used to describe the cities"), "",
    "- **Pace** (built-up growth 1990-2020 per year): very fast ≥ 4 %, fast ≥ 2.5 %, moderate ≥ 1.5 %, slow < 1.5 %.",
    "- **Shape** (saturation change 1990-2020): filling in ≥ +0.03, spreading out ≤ -0.03, stable in between.",
    "- **Check**: built-up growth ≥ 4 % a year is flagged for review against GHSL or imagery.", "",
    paste(h, "Caveats"), "",
    "- **GISD30 is the only input.** Its 1985-2000 detection is the weakest of the series (few Landsat 5 scenes), so part of the post-2000 acceleration may come from the data. In arid cities bare soil is read as impervious surface; very fast growth in the arid west and northwest should be checked against GHSL or imagery before being used.",
    "- **Water counts as open space.** GISD30 has no water mask, so riverbanks and coasts next to the city become fringe or captured open space. The Atlas removes water from open space; this pipeline does not yet.",
    "- **The perimeter is simplified** to about 200 m. It decides which patches are \"the city\"; it is not used to cut pixels.",
    "- **Proximity is not reported**: measured to the centroid it is meaningless for multi-part agglomerates.",
    "- **Rural cut**: the Atlas 2016 edition puts suburban at 25-50 %; the *Bolsones de pobreza* project uses the 2007-2010 definition (rural below 10 %), so its footprint is larger than the extent measured here.",
    "- **No density yet**: it needs census population per tract.")
}

argentina_md <- function(r, img, enlace, h = "##") {
  fi <- r$fichas
  h2 <- paste0(h, "#")
  tot <- r$ag[r$ag$grupo == r$t_todos, ]
  sin <- r$ag[r$ag$grupo == r$t_sin, ]
  ta <- function(x, col) tasa(x[[col]][x$anio == 1990], x[[col]][x$anio == 2020], 30)
  grupo <- function(col, valor) lista(vapply(fi$slug[fi[[col]] == valor], enlace, ""))
  tabla_ag <- function(x) tabla(c("", "urban", "suburban", "captured", "fringe", "extent", "% fringe", "built-up"),
    lapply(seq_len(nrow(x)), function(i) with(x[i, ], c(anio, f1(urbano_ciudad_km2), f1(suburbano_ciudad_km2),
      f1(capturado_ciudad_km2), f1(franja_ciudad_km2), f1(extension_ciudad_km2), f1(pct_franja),
      f1(construido_ciudad_km2)))))
  neg <- fi$slug[order(fi$dif)]
  neg <- head(neg[fi$dif[match(neg, fi$slug)] < 0], 3)
  pos <- fi$slug[order(-fi$dif)]
  pos <- head(pos[fi$dif[match(pos, fi$slug)] > 0], 3)
  c(paste(h, "Totals"), "",
    img("argentina_composicion.png", "Urban extent of Argentina's agglomerations by component"), "",
    sprintf("%s %s (km²)", h2, r$t_todos), "", tabla_ag(tot), "",
    sprintf("%s %s (km²)", h2, r$t_sin), "", tabla_ag(sin), "",
    sprintf("Annual growth 1990-2020: built-up %s %%, extent without fringe %s %%, extent with fringe %s %% (all %d); %s, %s and %s %% without Gran Buenos Aires.",
            f2(ta(tot, "construido_ciudad_km2")), f2(ta(tot, "sin_franja")), f2(ta(tot, "extension_ciudad_km2")), r$n,
            f2(ta(sin, "construido_ciudad_km2")), f2(ta(sin, "sin_franja")), f2(ta(sin, "extension_ciudad_km2"))), "",
    paste(h, "How each agglomeration is growing"), "",
    img("argentina_crecimiento.png", "Annual growth 1990-2020 of each agglomeration"), "",
    tabla(c("Pace", "Agglomerations"), lapply(rev(levels(fi$ritmo)), function(x) c(sprintf("**%s**", x), grupo("ritmo", x)))), "",
    tabla(c("Shape", "Agglomerations"), lapply(c("filling in", "stable", "spreading out"), function(x) c(sprintf("**%s**", x), grupo("forma", x)))), "",
    sprintf("**To check** (built-up ≥ 4 %% a year, see the caveats): %s.", lista(vapply(fi$slug[fi$alerta], enlace, ""))), "",
    img("argentina_indices.png", "Saturation and openness, 1990 and 2020"), "",
    paste(h, "How much the fringe open space matters"), "",
    paste(h2, "On the size of the city: a lot"), "",
    sprintf("In 2020 the fringe is between %s %% and %s %% of the urban extent; counting it adds %s-%s %% to the area of everything else. Anything divided by the urban extent (population density, share of the city in a given condition) moves by that much depending on whether the fringe is in.",
            f1(min(fi$franja_2020)), f1(max(fi$franja_2020)), f0(min(fi$suma_franja_2020)), f0(max(fi$suma_franja_2020))), "",
    img("argentina_franja.png", "Fringe share 1990 and 2020"), "",
    paste(h2, "On growth: little in most, a lot in a few"), "",
    sprintf("Counting the fringe moves the 1990-2020 growth rate by less than 0.2 points a year in %d of the %d agglomerations. It lowers growth most where the city fills in its old fringe (%s) and raises it where new scattered patches add new fringe (%s).",
            sum(abs(fi$dif) < 0.2), r$n, lista(vapply(neg, enlace, "")), lista(vapply(pos, enlace, ""))), "",
    img("argentina_efecto_franja.png", "Effect of the fringe on growth"), "",
    paste(h, "All agglomerations"), "",
    "Growth in % per year, 1990-2020. Extent in km², 2020.", "",
    tabla(c("Agglomeration", "Province", "extent 2020", "built-up", "without fringe", "with fringe", "difference",
            "% fringe 2020", "saturation", "pace", "shape"),
          lapply(seq_len(nrow(fi)), function(i) with(fi[i, ], c(enlace(slug), provincia, f1(extension_2020),
            f2(t_construido), f2(t_sin), f2(t_con), fs(dif), f1(franja_2020),
            sprintf("%s → %s", f2(sat_1990), f2(sat_2020)), as.character(ritmo), forma)))))
}

aglomerado_md <- function(r, s, img, mapas_html, h = "##") {
  # el cuerpo de una ciudad (sin su titulo). mapas_html(s): el bloque de los cuatro mapas
  f <- r$fichas[r$fichas$slug == s, ]
  x <- r$d[r$d$ciudad == s, ]
  dc <- decadas(r, s)
  notas <- c(
    if (f$alerta) sprintf("- **Check:** built-up grows %s %% a year, at or above the 4 %% flag. In arid areas GISD30 reads bare soil as impervious; confirm against GHSL or imagery before using these numbers.", f2(f$t_construido)),
    if (f$partes > 1) sprintf("- The perimeter has %d parts; patches touching any of them count as the city.", f$partes))
  c(sprintf("Province: %s.", f$provincia), "",
    sprintf("Built-up land in the city's urban extent grew from **%s km²** in 1990 to **%s km²** in 2020, **%s %% a year** (pace: **%s**). The urban extent went from %s to %s km². Saturation moved from %s to %s (shape: **%s**).",
            f1(f$construido_1990), f1(f$construido_2020), f2(f$t_construido), f$ritmo, f1(f$extension_1990),
            f1(f$extension_2020), f2(f$sat_1990), f2(f$sat_2020), f$forma), "",
    sprintf("The fringe open space was %s %% of the urban extent in 1990 and %s %% in 2020; in 2020 it adds %s %% to the rest of the extent. Counting it changes the 1990-2020 growth rate from %s %% to %s %% a year (%s points).",
            f1(f$franja_1990), f1(f$franja_2020), f0(f$suma_franja_2020), f2(f$t_sin), f2(f$t_con), fs(f$dif)), "",
    if (length(notas)) c(notas, "") else character(),
    paste(h, "Growth by class"), "",
    img(sprintf("agl/%s_composicion.png", s), sprintf("%s: urban extent by class", f$nombre)), "",
    tabla(c("", "urban", "suburban", "captured", "fringe", "extent", "% fringe", "built-up", "saturation", "openness",
            "project footprint"),
          lapply(seq_len(nrow(x)), function(j) with(x[j, ], c(anio, f1(urbano_ciudad_km2), f1(suburbano_ciudad_km2),
            f1(capturado_ciudad_km2), f1(franja_ciudad_km2), f1(extension_ciudad_km2), f1(pct_franja),
            f1(construido_ciudad_km2), f2(saturacion), f2(apertura), f1(huella_proyecto_ciudad_km2))))), "",
    "km². Rural built-up and rural open space lie outside the urban extent; they appear on the maps.", "",
    paste(h, "Growth by decade"), "",
    img(sprintf("agl/%s_decadas.png", s), sprintf("%s: growth by decade", f$nombre)), "",
    tabla(c("Decade", "built-up", "extent without fringe", "extent with fringe"),
          lapply(unique(dc$decada), function(k) c(k, f2(dc$tasa[dc$decada == k & dc$medida == "construido"]),
            f2(dc$tasa[dc$decada == k & dc$medida == "sin_franja"]), f2(dc$tasa[dc$decada == k & dc$medida == "con_franja"])))), "",
    "% per year.", "",
    paste(h, "Maps"), "", img("maps/leyenda.png", "Map legend"), "", mapas_html(s), "",
    sprintf("Maps are framed on the perimeter plus 5 km; the metrics use the larger box of `cajas.md` (slug `%s`).", s))
}
