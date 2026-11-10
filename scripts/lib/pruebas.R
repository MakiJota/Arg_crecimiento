# -*- coding: utf-8 -*-
# Funciones comunes de las pruebas 12 (densidad por radio) y 13 (franja densa): leer la
# salida de 11, estilo de graficos y mapas, tablas markdown. Se carga con source().

suppressPackageStartupMessages({
  library(terra)
  library(ggplot2)
})

ANIOS <- c(1990, 2000, 2010, 2020)
CENSO <- c("1990" = "1991", "2000" = "2001", "2010" = "2010", "2020" = "2022")

FONDO <- "#fcfcfb"; TINTA <- "#0b0b0b"; TINTA2 <- "#52514e"; REJILLA <- "#e6e5df"
COL_ANIO <- c("1990" = "#8db3dd", "2000" = "#4f86c0", "2010" = "#1f4e79", "2020" = "#0b2642")
tema <- theme_minimal(base_size = 11) +
  theme(plot.background = element_rect(fill = FONDO, colour = NA),
        panel.background = element_rect(fill = FONDO, colour = NA),
        panel.grid.minor = element_blank(),
        panel.grid.major = element_line(colour = REJILLA, linewidth = 0.3),
        text = element_text(colour = TINTA), axis.text = element_text(colour = TINTA2),
        plot.title = element_text(face = "bold"), plot.caption = element_text(colour = TINTA2, hjust = 0),
        legend.position = "top")
PIE <- "GISD30 (Zhang et al. 2022) with Angel / Atlas 2016 classes; census tracts CEUR-CONICET via Source Cooperative. Exploratory."

f0 <- function(x) format(round(x), big.mark = ",", scientific = FALSE, trim = TRUE)
f1 <- function(x) formatC(x, format = "f", digits = 1, big.mark = ",")
f2 <- function(x) sprintf("%.2f", x)
tasa <- function(a, b, n) 100 * ((b / a)^(1 / n) - 1)
guardar <- function(g, dir, nombre, w = 9, h = 5.5)
  ggsave(file.path(dir, nombre), g, width = w, height = h, dpi = 130, bg = FONDO)
tabla <- function(cab, filas) c(paste0("| ", paste(cab, collapse = " | "), " |"),
                                 paste0("|", paste(rep("---", length(cab)), collapse = "|"), "|"),
                                 vapply(filas, function(f) paste0("| ", paste(f, collapse = " | "), " |"), ""))


cargar_densidad <- function(rpipe, slug) {
  # lo que escribe 11 para una ciudad: por anio, el codigo por pixel, los radios y su tabla
  dir <- file.path(rpipe, "outputs", "densidad", slug)
  if (!file.exists(file.path(dir, "ciudad.csv"))) return(NULL)
  ciu <- read.csv(file.path(dir, "ciudad.csv"))
  x <- lapply(setNames(ANIOS, ANIOS), function(a) list(
    code = rast(file.path(dir, sprintf("code_%d.tif", a))),
    v = vect(file.path(dir, sprintf("radios_%d.gpkg", a))),
    t = read.csv(file.path(dir, sprintf("radios_%d.csv", a)), colClasses = c(cod = "character", censo = "character")),
    ciudad_km2 = ciu$ciudad_km2[ciu$anio == a]))
  cont <- contorno_de(rpipe, slug)
  x$nombre <- cont$nombre
  x$cont <- crop(project(cont, crs(x[["2020"]]$code)), ext(x[["2020"]]$code))
  x
}


radios_con <- function(t, k) {
  # filas de los radios que tocan la ciudad con densidad urbanizada >= k (vacio si ninguno)
  t$i_fila[t$km2_urb > 0 & !is.na(t$dens_urb) & t$dens_urb >= k]
}


marcar <- function(rid, ids) if (length(ids)) rid %in% ids else rid < 0


indice_mapas <- function(base, res, tipos, cols = ANIOS, cab = as.character(cols), nota = "") {
  # seccion del indice con los mapas de cada aglomerado: una fila por aglomerado, una
  # columna por elemento de `cols` (anios por defecto); cada celda enlaza los mapas que
  # existen. tipos = c(etiqueta = patron de archivo en img/, con un %s o %d para la columna)
  L <- c("## Maps by agglomeration", "",
         paste("Each link opens the full map. All maps of an agglomeration share one frame: its 2020 city plus 3 km.", nota), "")
  filas <- lapply(seq_len(nrow(res)), function(i) {
    s <- res$slug[i]
    c(sprintf("[%s](%s/REPORTE.md)", res$nombre[i], s), vapply(cols, function(a) {
      l <- vapply(names(tipos), function(n) {
        f <- paste0(s, "/img/", sprintf(tipos[[n]], a))
        if (file.exists(file.path(base, f))) sprintf("[%s](%s)", n, f) else ""
      }, "")
      paste(l[nzchar(l)], collapse = " · ")
    }, ""))
  })
  c(L, tabla(c("Agglomeration", cab), filas), "")
}


mapa_paneles <- function(archivo, capas, pal, titulos, titulo, leyenda, cont) {
  # paneles de mapas categoricos, 4 por fila, con el perimetro y una leyenda abajo
  code <- capas[[1]]
  filas <- ceiling(nlyr(capas) / 4)
  w <- 2400; h <- min(round(w / 4 * nrow(code) / ncol(code)) * filas + 220, 5400)
  png(archivo, width = w, height = h, bg = FONDO)
  par(mfrow = c(filas, 4), oma = c(4, 0, 4, 0), bg = FONDO)
  for (n in seq_len(nlyr(capas))) {
    plot(capas[[n]], col = data.frame(value = seq_along(pal) - 1, color = pal), type = "classes", legend = FALSE,
         axes = FALSE, mar = c(0.3, 0.3, 2.6, 0.3), maxcell = 2e6, main = titulos[n], cex.main = 1.6)
    lines(cont, col = "#1d1d1b", lwd = 1.2)
  }
  mtext(titulo, outer = TRUE, cex = 2.1, font = 2, line = 1)
  par(fig = c(0, 1, 0, 1), oma = c(0, 0, 0, 0), mar = c(0, 0, 0, 0), new = TRUE)
  plot.new()
  legend("bottom", horiz = TRUE, bty = "n", border = NA, cex = 1.6, text.col = TINTA2, inset = 0.005,
         fill = pal[-1], legend = leyenda)
  dev.off()
}
