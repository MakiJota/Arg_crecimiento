# -*- coding: utf-8 -*-
# Paso 28 · Matriz origen-destino de tiempo y distancia entre localidades, y comunidades (nuevo).
# Exploratorio: ningun numero es cifra del proyecto.
#
# Para cada par de puntos (cabeceras de municipio de BAHRA/IGN, u otros que se den), el camino
# mas rapido por la red de calles de Overture del paso 20: tiempo (min) y largo de ese camino
# (km), mas la distancia en linea recta. Sirve para discutir la extension del aglomerado: que
# localidades quedan "a un viaje corto" de la ciudad central.
#
# LA RED Y SUS SUPUESTOS (declarar al pie de cualquier uso):
#   - calles de Overture (transportation/segment, subtype road), sin footway/path/steps/
#     pedestrian/cycleway/bridleway. Se nodan todos los cruces: un puente o un paso bajo nivel
#     queda como cruce aunque no lo sea.
#   - red no dirigida: no hay manos unicas.
#   - velocidad por clase de calle, flujo libre, sin congestion, semaforos ni giros (VEL, abajo).
#     No es velocidad medida: es una tabla de supuestos. Los tiempos son una cota inferior del
#     viaje real en auto, no un tiempo observado.
#   - cada punto se engancha al nodo mas cercano de la componente conexa mayor; la distancia de
#     enganche se informa y no se suma al viaje.
#
# COMUNIDADES (sobre la matriz de tiempo, simetrica):
#   - jerarquico, enlace simple: dos localidades estan juntas si hay una cadena de saltos de a
#     lo sumo U minutos entre ellas. Es la percolacion de Arcaute et al. (2016) sobre una matriz
#     de viaje en lugar de la red de calles: cortar en U da los "aglomerados a U minutos".
#   - jerarquico, enlace promedio: mas conservador, no encadena localidades lejanas por medio
#     de una intermedia.
#   - Louvain y Leiden (modularidad) sobre el grafo completo con peso exp(-t/tau): la escala tau
#     (min) fija cuanto pesa la cercania. Louvain es aleatorio: semilla fija.
#   Ninguno usa flujos observados (viajes al trabajo) ni poblacion: son comunidades de
#   accesibilidad potencial, no de interaccion. Con poblacion por localidad se puede pasar a un
#   modelo de gravedad (peso P_i P_j f(t)); con flujos, a la regla de zonas de traslado (OECD).
#
# ENTRADAS  outputs/overture/<slug>/calles.gpkg (paso 20)
#             (--red <slug2> usa las calles de otra caja, p. ej. salta_rev)
#           raw/localidades/<slug>.gpkg, una capa de puntos (--puntos, --capa, --nombre)
# SALIDAS   outputs/od/<slug>/
#             od_tiempo_min.csv, od_distancia_km.csv  matrices cuadradas
#             od_pares.csv          un par por fila: tiempo, distancia por red, recta, rodeo, velocidad
#             puntos_enganche.csv   nodo y distancia de enganche de cada punto
#             comunidades.csv       pertenencia por metodo y umbral
#             matriz_tiempo.png, matriz_distancia.png, dispersion_tiempo_distancia.png,
#             dispersion_rodeo.png, dendrograma.png, mapa_comunidades.png
#             od.gpkg               capas puntos (con comunidades) y pares (lineas rectas con t y d)
#
# Uso: Rscript Rpipe/scripts/28_od_localidades.R --ciudad salta
#        [--red salta_rev] [--puntos raw/localidades/salta.gpkg] [--capa puntos_salta] [--nombre nam]
#        [--umbrales 15,20,30,45,60] [--tau 10,15,20,30] [--corte 30]

Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))
suppressPackageStartupMessages({ library(sf); library(igraph); library(ggplot2) })
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
SCRIPTS <- normalizePath(dirname(script), winslash = "/")
RPIPE <- dirname(SCRIPTS)

args <- commandArgs(trailingOnly = TRUE)
arg <- function(nombre, defecto) {
  i <- match(nombre, args)
  if (is.na(i) || i == length(args)) defecto else args[i + 1]
}
SLUG <- arg("--ciudad", "salta")
PUNTOS <- arg("--puntos", file.path(RPIPE, "raw", "localidades", paste0(SLUG, ".gpkg")))
CAPA <- arg("--capa", NA)
NOMBRE <- arg("--nombre", "nam")
UMBRALES <- as.numeric(strsplit(arg("--umbrales", "15,20,30,45,60"), ",")[[1]])
TAUS <- as.numeric(strsplit(arg("--tau", "10,15,20,30"), ",")[[1]])
CORTE <- as.numeric(arg("--corte", "30"))   # umbral (min) que se dibuja en el mapa y la dispersion
RED <- arg("--red", SLUG)   # carpeta de outputs/overture/ con las calles (p. ej. salta_rev, caja mas grande)
CALLES <- file.path(RPIPE, "outputs", "overture", RED, "calles.gpkg")
SAL <- file.path(RPIPE, "outputs", "od", SLUG)
SEMILLA <- 28

source(file.path(SCRIPTS, "lib", "od.R"))   # VEL, FUERA, utm, leer_red, enganchar, matriz_od, comunidades

# ---- puntos ------------------------------------------------------------------------------
if (!file.exists(PUNTOS)) stop("no existe ", PUNTOS, call. = FALSE)
if (is.na(CAPA)) CAPA <- st_layers(PUNTOS)$name[1]
pt <- st_read(PUNTOS, CAPA, quiet = TRUE)
if (!(NOMBRE %in% names(pt))) stop("la capa ", CAPA, " no tiene el campo '", NOMBRE, "'. Campos: ",
                                   paste(setdiff(names(pt), attr(pt, "sf_column")), collapse = ", "),
                                   call. = FALSE)
pt <- st_cast(st_zm(pt), "POINT", warn = FALSE)
pt$nombre <- as.character(pt[[NOMBRE]])
if (anyDuplicated(pt$nombre)) pt$nombre <- make.unique(pt$nombre, sep = " #")
if (any(grepl("�", pt$nombre)))
  message("AVISO: hay nombres con caracteres rotos (U+FFFD) en ", basename(PUNTOS),
          ": vienen asi del archivo, no se corrigen aca.")
c0 <- st_coordinates(st_transform(st_geometry(pt), 4326))
CRS <- utm(mean(c0[, 1]), mean(c0[, 2]))
pt <- st_transform(pt, CRS)
n <- nrow(pt)
cat(sprintf("%d puntos de %s (capa %s), CRS %s\n", n, basename(PUNTOS), CAPA, CRS))

# ---- red ---------------------------------------------------------------------------------
red <- leer_red(CALLES, CRS)
g <- red$g; ca <- red$ca
# fuera de la caja de calles, el punto no tiene red
afuera <- !lengths(st_intersects(pt, st_as_sfc(st_bbox(ca))))
if (any(afuera)) stop("puntos fuera de la caja de calles de ", RED, " (probar --red <slug> con una caja mayor): ",
                      paste(pt$nombre[afuera], collapse = ", "), call. = FALSE)

# ---- enganche y OD -----------------------------------------------------------------------
en <- enganchar(g, pt)
eng <- en$eng
enganche <- data.frame(nombre = pt$nombre, nodo = V(g)$name[en$cerca], enganche_m = round(eng, 1))
od <- matriz_od(g, en$cerca, pt)
Tm <- od$Tm; Dk <- od$Dk; ij <- od$ij; pares <- od$pares

dir.create(SAL, recursive = TRUE, showWarnings = FALSE)
escribir <- function(x, f) write.csv(x, file.path(SAL, f), row.names = TRUE, fileEncoding = "UTF-8")
escribir(round(Tm, 1), "od_tiempo_min.csv")
escribir(round(Dk, 2), "od_distancia_km.csv")
write.csv(enganche, file.path(SAL, "puntos_enganche.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(transform(pares, tiempo_min = round(tiempo_min, 1), distancia_km = round(distancia_km, 2),
                    recta_km = round(recta_km, 2), rodeo = round(rodeo, 3), vel_kmh = round(vel_kmh, 1)),
          file.path(SAL, "od_pares.csv"), row.names = FALSE, fileEncoding = "UTF-8")

# ---- comunidades -------------------------------------------------------------------------
cm <- comunidades(Tm, UMBRALES, TAUS, SEMILLA)
com <- cm$com; hs <- cm$hs; ha <- cm$ha; modul <- cm$modul
write.csv(com, file.path(SAL, "comunidades.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(modul, file.path(SAL, "modularidad.csv"), row.names = FALSE)

# ---- graficos ----------------------------------------------------------------------------
orden <- pt$nombre[ha$order]
matriz_png <- function(M, titulo, unidad, f, dec) {
  d <- as.data.frame(as.table(M))
  names(d) <- c("origen", "destino", "v")
  d$origen <- factor(d$origen, levels = orden)
  d$destino <- factor(d$destino, levels = rev(orden))
  d$txt <- ifelse(d$origen == d$destino, "", formatC(d$v, format = "f", digits = dec))
  p <- ggplot(d, aes(origen, destino, fill = v)) +
    geom_tile(colour = "white", linewidth = 0.3) +
    geom_text(aes(label = txt, colour = v > max(v) * 0.55), size = 2.6, show.legend = FALSE) +
    scale_colour_manual(values = c(`TRUE` = "white", `FALSE` = "grey15")) +
    scale_fill_viridis_c(option = "rocket", direction = -1, name = unidad) +
    labs(title = titulo, x = NULL, y = NULL,
         caption = paste("Camino mas rapido por la red de calles de Overture, velocidades supuestas",
                         "por clase de calle, flujo libre. Orden: enlace promedio sobre el tiempo.")) +
    theme_minimal(base_size = 10) +
    theme(axis.text.x = element_text(angle = 50, hjust = 1), panel.grid = element_blank(),
          plot.caption = element_text(size = 7, colour = "grey40", hjust = 0))
  ggsave(file.path(SAL, f), p, width = 10, height = 8.5, dpi = 150, bg = "white")
}
matriz_png(Tm, sprintf("%s · tiempo de viaje entre localidades", SLUG), "min", "matriz_tiempo.png", 0)
matriz_png(Dk, sprintf("%s · distancia por red entre localidades", SLUG), "km", "matriz_distancia.png", 0)

pares$junto <- ifelse(com[[sprintf("promedio_%gmin", CORTE)]][match(pares$origen, com$nombre)] ==
                        com[[sprintf("promedio_%gmin", CORTE)]][match(pares$destino, com$nombre)],
                      "mismo grupo", "grupos distintos")
ajuste <- lm(tiempo_min ~ distancia_km, data = pares)
b <- coef(ajuste)
p <- ggplot(pares, aes(distancia_km, tiempo_min)) +
  geom_hline(yintercept = CORTE, linetype = 3, colour = "grey50") +
  geom_smooth(method = "lm", formula = y ~ x, se = FALSE, colour = "grey40", linewidth = 0.5) +
  geom_point(aes(fill = vel_kmh, shape = junto), size = 2.6, colour = "grey20", stroke = 0.3) +
  scale_shape_manual(values = c(`mismo grupo` = 21, `grupos distintos` = 24),
                     name = sprintf("enlace promedio a %g min", CORTE)) +
  scale_fill_viridis_c(name = "velocidad media\ndel camino, km/h") +
  labs(title = sprintf("%s · tiempo y distancia por red, %d pares", SLUG, nrow(pares)),
       subtitle = sprintf("recta: t = %.1f + %.2f d  (pendiente equivale a %.0f km/h), R2 = %.3f",
                          b[1], b[2], 60 / b[2], summary(ajuste)$r.squared),
       x = "distancia por red (km)", y = "tiempo (min)",
       caption = "Por encima de la recta: caminos mas lentos que el promedio (calles locales, rutas secundarias).") +
  theme_minimal(base_size = 10) + theme(plot.caption = element_text(size = 7, colour = "grey40", hjust = 0))
ggsave(file.path(SAL, "dispersion_tiempo_distancia.png"), p, width = 8.5, height = 6, dpi = 150, bg = "white")

p <- ggplot(pares, aes(recta_km, distancia_km)) +
  geom_abline(slope = 1, intercept = 0, linetype = 3, colour = "grey50") +
  geom_point(aes(fill = rodeo), shape = 21, size = 2.6, colour = "grey20", stroke = 0.3) +
  scale_fill_viridis_c(option = "magma", direction = -1, name = "rodeo\n(red / recta)") +
  labs(title = sprintf("%s · distancia por red y en linea recta", SLUG),
       subtitle = sprintf("rodeo mediano %.2f; la linea punteada es red = recta", median(pares$rodeo)),
       x = "linea recta (km)", y = "por red, camino mas rapido (km)") +
  theme_minimal(base_size = 10)
ggsave(file.path(SAL, "dispersion_rodeo.png"), p, width = 7.5, height = 6, dpi = 150, bg = "white")

png(file.path(SAL, "dendrograma.png"), width = 1500, height = 1300, res = 150)
op <- par(mfrow = c(2, 1), mar = c(1, 4, 2.5, 1))
for (h in list(list(hs, "enlace simple (percolacion)"), list(ha, "enlace promedio"))) {
  plot(h[[1]], hang = -1, cex = 0.65, xlab = "", sub = "", ylab = "minutos",
       main = sprintf("%s · %s sobre el tiempo de viaje", SLUG, h[[2]]))
  abline(h = UMBRALES, col = "grey60", lty = 3)
  axis(4, at = UMBRALES, labels = UMBRALES, las = 1, cex.axis = 0.6, col.axis = "grey40", tick = FALSE, line = -1)
}
par(op); invisible(dev.off())

# mapa: red principal, pares a <= CORTE, puntos coloreados por el grupo a CORTE
xyp <- st_coordinates(pt)
lineas <- st_sfc(lapply(seq_len(nrow(ij)), function(r) st_linestring(xyp[ij[r, ], ])), crs = CRS)
pl <- st_sf(pares[, c("origen", "destino", "tiempo_min", "distancia_km", "recta_km", "rodeo", "vel_kmh")],
            geometry = lineas)
pt$grupo <- factor(com[[sprintf("promedio_%gmin", CORTE)]])
red <- ca[ca$clase %in% c("motorway", "trunk", "primary", "secondary"), ]
p <- ggplot() +
  geom_sf(data = red, colour = "grey75", linewidth = 0.25) +
  geom_sf(data = pl[pl$tiempo_min <= CORTE, ], aes(colour = tiempo_min), linewidth = 0.6, alpha = 0.8) +
  scale_colour_viridis_c(option = "rocket", direction = -1, name = "min", limits = c(0, CORTE)) +
  geom_sf(data = pt, aes(fill = grupo), shape = 21, size = 3.2, colour = "black", stroke = 0.4) +
  geom_sf_text(data = pt, aes(label = nombre), size = 2.3, nudge_y = 1800) +
  labs(title = sprintf("%s · pares a %g min o menos, grupos por enlace promedio a %g min", SLUG, CORTE, CORTE),
       fill = "grupo", x = NULL, y = NULL,
       caption = "Gris: red principal de Overture (motorway a secondary). Lineas: pares, en recta, no el camino.") +
  theme_minimal(base_size = 9) + theme(plot.caption = element_text(size = 7, colour = "grey40", hjust = 0))
ggsave(file.path(SAL, "mapa_comunidades.png"), p, width = 9, height = 9, dpi = 150, bg = "white")

# ---- gpkg para QGIS ----------------------------------------------------------------------
gp <- file.path(SAL, "od.gpkg")
if (file.exists(gp)) invisible(file.remove(gp))
pt_out <- cbind(pt[, c("nombre")], com[, -1], enganche_m = enganche$enganche_m)
st_write(st_transform(pt_out, 4326), gp, "puntos", quiet = TRUE)
st_write(st_transform(pl, 4326), gp, "pares", quiet = TRUE, append = TRUE)

# ---- resumen -----------------------------------------------------------------------------
cat(sprintf("\nenganche: mediana %.0f m, maximo %.0f m (%s)\n", median(eng), max(eng),
            pt$nombre[which.max(eng)]))
cat(sprintf("tiempo: %.1f a %.1f min; distancia por red: %.1f a %.1f km; rodeo mediano %.2f\n",
            min(pares$tiempo_min), max(pares$tiempo_min), min(pares$distancia_km),
            max(pares$distancia_km), median(pares$rodeo)))
cat(sprintf("t = %.1f + %.2f d, R2 %.3f (%d pares)\n", b[1], b[2], summary(ajuste)$r.squared, nrow(pares)))
cat("\ngrupos por umbral (cantidad de grupos):\n")
print(data.frame(umbral_min = UMBRALES,
                 simple = sapply(UMBRALES, function(u) max(com[[sprintf("simple_%gmin", u)]])),
                 promedio = sapply(UMBRALES, function(u) max(com[[sprintf("promedio_%gmin", u)]]))),
      row.names = FALSE)
cat("\nmodularidad:\n"); print(modul, row.names = FALSE)
cat("\nsalidas en ", SAL, "\n", sep = "")
