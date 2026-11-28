# -*- coding: utf-8 -*-
# Paso 29 · Comunidades de localidades alrededor de cada aglomerado (nuevo). Exploratorio:
# ningun numero es cifra del proyecto.
#
# El paso 28 aplicado a los 31 aglomerados, con una ventana fija: un cuadrado de LADO km
# (50 por defecto) centrado en el aglomerado. Dentro del cuadrado, las sedes de gobierno local
# de BAHRA/IGN (municipios, comunas, comisiones, juntas); entre ellas, la matriz de tiempo por
# la red de calles de Overture y las comunidades (enlace simple y promedio por umbral, Louvain y
# Leiden por tau). Mismos supuestos de red que el paso 28 (velocidades por clase, sin congestion,
# no dirigida): ver su encabezado.
#
# Centro: el centroide de la parte mas grande del perimetro de analisis (paso 07). En los
# aglomerados de partes lejanas (Ushuaia - Rio Grande, Rawson - Trelew) el cuadrado queda sobre
# la parte mayor y la otra puede quedar afuera: se informa en resumen.csv (partes_fuera).
# Las calles se bajan para el cuadrado mas MARGEN km por lado, para que los caminos entre puntos
# del cuadrado puedan salir de el.
#
# Dos pasadas:
#   1. Rscript 29_od_aglomerados.R --solo-cajas  -> outputs/od_aglomerados/cajas.csv
#      python 20_overture_edificios.py --cajas-csv Rpipe/outputs/od_aglomerados/cajas.csv
#             --salida Rpipe/outputs/overture_od --temas calles
#   2. Rscript 29_od_aglomerados.R               -> OD, comunidades y mapas
#   Sin calles para un aglomerado, la pasada 2 lo saltea y lo dice.
#
# Un tercer paso, cuando se elija metodo y umbral: la "extension por accesibilidad" de cada
# aglomerado es el grupo que contiene a la sede mas cercana al centro (columnas central_*).
#
# ENTRADAS  raw/boundaries/aglomerados.gpkg (07), raw/localidades/all_arg.gpkg (--puntos),
#           outputs/overture_od/<slug>/calles.gpkg (20 con --cajas-csv),
#           outputs/od_aglomerados/localidades_aglomerados_eph.xls (--lista; INDEC, localidades censales
#           2010 de cada aglomerado EPH): control de que esten los 31 y validacion por nombre
# SALIDAS   outputs/od_aglomerados/
#             cajas.csv                     cuadrado + margen, lat/lon, por aglomerado
#             <slug>/od_tiempo_min.csv, od_distancia_km.csv, od_pares.csv, comunidades.csv,
#                    modularidad.csv, mapa.png
#             resumen.csv                   por aglomerado: puntos, grupos por metodo, grupo central
#             HALLAZGOS.md                  metodo, resumen, tabla y grupos por aglomerado, con los mapas
#             validacion_eph.csv            cada localidad INDEC: sede que coincide y si cae en el grupo central
#             mapas.pdf, metodo.png         solo con --pdf
#             od_aglomerados.gpkg           capas cuadrados, puntos (con comunidades), pares
#
# --solo-texto rehace HALLAZGOS.md sin recalcular. --pdf agrega mapas.pdf (pagina de metodo + los
# mapa.rds guardados) y metodo.png. --extra slug:lado_km agrega otra ventana para un aglomerado
# (por defecto gran_buenos_aires:100), que va despues de su cuadrado de base.
#
# Uso: Rscript Rpipe/scripts/29_od_aglomerados.R [--solo-cajas] [--solo-texto] [--pdf] [--extra gran_buenos_aires:100] [--aglomerados salta,posadas]
#        [--lado 70] [--margen 10] [--corte 30] [--tau-mapa 15] [--umbrales 15,20,30,45,60]
#        [--tau 10,15,20,30] [--puntos raw/localidades/all_arg.gpkg] [--nombre nam]

Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))
suppressPackageStartupMessages({ library(sf); library(igraph); library(ggplot2) })
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
SCRIPTS <- normalizePath(dirname(script), winslash = "/")
RPIPE <- dirname(SCRIPTS)
source(file.path(SCRIPTS, "lib", "od.R"))

args <- commandArgs(trailingOnly = TRUE)
arg <- function(nombre, defecto) {
  i <- match(nombre, args)
  if (is.na(i) || i == length(args)) defecto else args[i + 1]
}
SOLO_CAJAS <- "--solo-cajas" %in% args
SOLO_TEXTO <- "--solo-texto" %in% args   # rehace HALLAZGOS.md (y mapas.pdf con --pdf) sin recalcular
PDF <- "--pdf" %in% args   # mapas.pdf (pagina de metodo + mapas guardados) y metodo.png; opcional
LADO <- as.numeric(arg("--lado", "70")) * 1000
MARGEN <- as.numeric(arg("--margen", "10")) * 1000
CORTE <- as.numeric(arg("--corte", "30"))
TAU_MAPA <- as.numeric(arg("--tau-mapa", "15"))
UMBRALES <- sort(unique(c(as.numeric(strsplit(arg("--umbrales", "15,20,30,45,60"), ",")[[1]]), CORTE)))
TAUS <- sort(unique(c(as.numeric(strsplit(arg("--tau", "10,15,20,30"), ",")[[1]]), TAU_MAPA)))
PUNTOS <- arg("--puntos", file.path(RPIPE, "raw", "localidades", "all_arg.gpkg"))
NOMBRE <- arg("--nombre", "nam")
PERIM <- file.path(RPIPE, "raw", "boundaries", "aglomerados.gpkg")
CALLES <- file.path(RPIPE, "outputs", "overture_od")
SAL <- file.path(RPIPE, "outputs", "od_aglomerados")
SEMILLA <- 29

# ventanas adicionales "slug:lado_km,...": el mismo aglomerado con otro cuadrado, como
# <slug>_<lado>km, justo despues del original en todas las salidas. "no" para ninguna.
EXTRA <- arg("--extra", "gran_buenos_aires:100")
ex <- if (EXTRA %in% c("", "no")) list() else strsplit(strsplit(EXTRA, ",")[[1]], ":")

ag0 <- st_read(PERIM, "perimetro", quiet = TRUE)
if (length(x <- setdiff(vapply(ex, `[`, "", 1), ag0$slug)))
  stop("--extra: no estan en ", basename(PERIM), ": ", paste(x, collapse = ", "), call. = FALSE)
expandir <- function(a) {
  a$lado <- LADO
  filas <- list()
  for (i in seq_len(nrow(a))) {
    filas[[length(filas) + 1]] <- a[i, ]
    for (e in ex) if (e[1] == a$slug[i]) {
      r <- a[i, ]
      r$lado <- as.numeric(e[2]) * 1000
      r$slug <- sprintf("%s_%gkm", e[1], as.numeric(e[2]))
      r$nombre <- sprintf("%s (%g km)", r$nombre, as.numeric(e[2]))
      filas[[length(filas) + 1]] <- r
    }
  }
  do.call(rbind, filas)
}
VENTANA_EXTRA <- if (length(ex)) paste0(" (ademas, ", paste(vapply(ex, function(e) sprintf("%s km x %s km para %s",
  e[2], e[2], ag0$nombre[ag0$slug == e[1]]), ""), collapse = "; "), ", que van despues de su cuadrado de base)") else ""
ORDEN <- expandir(ag0)$slug   # orden de mapas.pdf y de HALLAZGOS.md
AGLOS <- strsplit(arg("--aglomerados", paste(ag0$slug, collapse = ",")), ",")[[1]]
if (length(x <- setdiff(AGLOS, ag0$slug)))
  stop("no estan en ", basename(PERIM), ": ", paste(x, collapse = ", "), call. = FALSE)
ag <- expandir(ag0[match(AGLOS, ag0$slug), ])
dir.create(SAL, recursive = TRUE, showWarnings = FALSE)


# ---- cuadrados ---------------------------------------------------------------------------
cuadrado <- function(p) {
  # centro = centroide de la parte mas grande, en la UTM del aglomerado
  c0 <- st_coordinates(st_centroid(st_geometry(st_transform(p, 4326))))
  crs <- utm(c0[1], c0[2])
  partes <- st_cast(st_geometry(st_transform(p, crs)), "POLYGON")
  cen <- st_coordinates(st_centroid(partes[which.max(st_area(partes))]))
  h <- p$lado / 2
  cu <- st_sfc(st_polygon(list(rbind(cen + c(-h, -h), cen + c(h, -h), cen + c(h, h),
                                      cen + c(-h, h), cen + c(-h, -h)))), crs = crs)
  list(crs = crs, lado = p$lado, centro = st_sfc(st_point(cen), crs = crs), cuadrado = cu,
       caja = st_bbox(st_transform(st_buffer(cu, MARGEN, joinStyle = "MITRE", mitreLimit = 2), 4326)),
       partes_fuera = sum(!st_within(partes, cu, sparse = FALSE)[, 1]))
}
CU <- lapply(seq_len(nrow(ag)), function(i) cuadrado(ag[i, ]))
names(CU) <- ag$slug
cajas <- data.frame(slug = ag$slug,
                    lat0 = sapply(CU, function(x) round(x$caja[["ymin"]], 4)),
                    lon0 = sapply(CU, function(x) round(x$caja[["xmin"]], 4)),
                    lat1 = sapply(CU, function(x) round(x$caja[["ymax"]], 4)),
                    lon1 = sapply(CU, function(x) round(x$caja[["xmax"]], 4)))
f_cajas <- file.path(SAL, "cajas.csv")
if (file.exists(f_cajas)) {   # se fusiona: una corrida parcial no borra las otras filas
  viejo <- read.csv(f_cajas)
  cajas <- rbind(viejo[!(viejo$slug %in% cajas$slug), ], cajas)
}
write.csv(cajas[order(cajas$slug), ], f_cajas, row.names = FALSE)
cat(sprintf("cajas: %s (%d aglomerados, cuadrado %g km + %g km de margen)\n", f_cajas, nrow(ag),
            LADO / 1000, MARGEN / 1000))
if (SOLO_CAJAS) {
  cat("siguiente: python Rpipe/scripts/20_overture_edificios.py --cajas-csv", f_cajas,
      "--salida", CALLES, "--temas calles\n")
  quit(status = 0)
}


# ---- pagina de metodo --------------------------------------------------------------------
# Todo numero que aparece sale de los parametros de la corrida o de resumen.csv.
pagina_metodo <- function(res, n_sedes, release) {
  ok <- res[res$estado == "ok", ]
  salt <- res[res$estado != "ok", ]
  vel <- paste(sprintf("%s %g", names(VEL), VEL), collapse = ", ")
  bloques_izq <- list(
    c("Que muestra", sprintf(paste(
      "Para cada aglomerado, que localidades de su entorno quedan unidas por viajes cortos y cuales",
      "forman nucleos aparte. Es una medida de accesibilidad potencial por la red vial: sirve para",
      "discutir hasta donde llega el aglomerado, no para fijarlo. Exploratorio: ningun numero es cifra",
      "del proyecto. %d de %d aglomerados tienen mapa."), nrow(ok), nrow(res))),
    c("1 · Ventana", sprintf(paste(
      "Un cuadrado de %g x %g km centrado en el centroide de la parte mas grande del perimetro de",
      "analisis del aglomerado (paso 07). En aglomerados de partes lejanas la otra parte puede quedar",
      "afuera (columna partes_fuera de resumen.csv).%s"), LADO / 1000, LADO / 1000, VENTANA_EXTRA)),
    c("2 · Puntos", sprintf(paste(
      "Las sedes de gobierno local de BAHRA/IGN (municipios, comunas, comisiones, juntas; %d en el",
      "archivo) que caen dentro del cuadrado. Cada sede es un punto, no una poblacion: una ciudad",
      "grande y un pueblo pesan igual. La densidad de sedes cambia por provincia (Buenos Aires tiene",
      "una por partido). Con menos de 2 sedes el aglomerado se saltea%s."), n_sedes,
      if (nrow(salt)) paste0(": ", paste(salt$nombre, collapse = ", ")) else "")),
    c("3 · Red vial", sprintf(paste(
      "Calles de Overture Maps (release %s) en el cuadrado mas %g km por lado, para que los caminos",
      "puedan salir de el. Sin sendas, veredas ni ciclovias. Las lineas se cortan en cada cruce (un",
      "puente cuenta como cruce), la red es no dirigida (sin manos unicas) y se usa su componente",
      "conexa mayor. Velocidad supuesta por clase de calle, en km/h, a flujo libre, sin congestion ni",
      "semaforos: %s. No es velocidad medida: los tiempos son una cota inferior del viaje en auto."),
      release, MARGEN / 1000, vel)),
    c("4 · Tiempo y distancia", paste(
      "Cada sede se engancha al nodo mas cercano de la red (la distancia de enganche no se suma). Entre",
      "cada par de sedes se busca el camino mas rapido (Dijkstra): su tiempo en minutos y su largo en km.",
      "Eso da la matriz origen-destino del aglomerado (od_tiempo_min.csv, od_distancia_km.csv)."))
  )
  bloques_der <- list(
    c("5 · Comunidades", sprintf(paste(
      "Tres maneras de agrupar las sedes a partir de la matriz de tiempo.|",
      "(a) Enlace simple a U min: dos sedes van juntas si hay una cadena de viajes de a lo sumo U min",
      "que las une. Es la percolacion de Arcaute et al. (2016). Puede encadenar pueblos lejanos a",
      "traves de uno intermedio.|",
      "(b) Enlace promedio a U min: dos grupos se unen solo si el tiempo promedio entre todos sus",
      "miembros es de a lo sumo U min. Mas conservador que (a). El mapa usa U = %g.|",
      "(c) Leiden (Traag et al. 2019): cada par se une con un peso exp(-t/tau) que decae con el tiempo",
      "(con tau = %g, un viaje de %g min pesa 0,37). El algoritmo elige la particion que maximiza la",
      "modularidad, es decir mas peso dentro de los grupos que el esperable al azar, y decide solo",
      "cuantos grupos hay. Un tau chico da grupos chicos y apretados; uno grande los junta.|",
      "comunidades.csv tiene los tres metodos para U = %s min y tau = %s."),
      CORTE, TAU_MAPA, TAU_MAPA, paste(UMBRALES, collapse = ", "), paste(TAUS, collapse = ", "))),
    c("Como leer cada mapa", sprintf(paste(
      "Panel izquierdo: enlace promedio a %g min. Panel derecho: Leiden con tau = %g. El color del",
      "punto es el grupo; la numeracion es propia de cada panel y no se compara entre paneles. Las",
      "lineas son el arbol de expansion minima del tiempo: el conjunto de viajes mas cortos que conecta",
      "todas las sedes, dibujado en recta (no es el camino). Su color es el tiempo del tramo, con tope",
      "en %g min; cortar los tramos de mas de U min da el enlace simple a U. Punto grande: la sede mas",
      "cercana al centro del cuadrado; el tamano de su grupo esta en resumen.csv (central_*). Gris: el",
      "perimetro de analisis; punteado: el cuadrado; lineas grises: red principal."),
      CORTE, TAU_MAPA, CORTE)),
    c("Limitaciones", paste(
      "Sin poblacion ni viajes observados: son comunidades de accesibilidad, no de interaccion. Con",
      "poblacion por localidad se puede pasar a un modelo de gravedad (peso Pi x Pj x exp(-t/tau)); con",
      "flujos censales hogar-trabajo, a la definicion de zonas de traslado. Los nombres con letras",
      "acentuadas llegan rotos desde el archivo de BAHRA."))
  )
  grid::grid.newpage()
  grid::grid.text("Comunidades de localidades por tiempo de viaje · metodo", x = 0.035, y = 0.955,
                  just = c("left", "top"), gp = grid::gpar(fontsize = 14, fontface = "bold"))
  # cada bloque: titulo y texto; "|" separa parrafos. La altura de cada texto se mide, no se estima.
  alto <- function(g) grid::convertHeight(grid::grobHeight(g), "npc", valueOnly = TRUE)
  columna <- function(bloques, x0) {
    y <- 0.89
    for (b in bloques) {
      tg <- grid::textGrob(b[1], x = x0, y = y, just = c("left", "top"),
                           gp = grid::gpar(fontsize = 8.6, fontface = "bold"))
      grid::grid.draw(tg)
      y <- y - alto(tg) - 0.012
      for (par_ in trimws(strsplit(b[2], "|", fixed = TRUE)[[1]])) {
        tg <- grid::textGrob(paste(strwrap(par_, width = 92), collapse = "\n"), x = x0, y = y,
                             just = c("left", "top"),
                             gp = grid::gpar(fontsize = 7.4, lineheight = 1.2, col = "grey15"))
        grid::grid.draw(tg)
        y <- y - alto(tg) - 0.01
      }
      y <- y - 0.02
    }
  }
  columna(bloques_izq, 0.035)
  columna(bloques_der, 0.52)
}


# ---- puntos ------------------------------------------------------------------------------
loc <- st_cast(st_zm(st_read(PUNTOS, quiet = TRUE)), "POINT", warn = FALSE)
loc$nombre <- as.character(loc[[NOMBRE]])
if (any(grepl("�", loc$nombre)))
  message("AVISO: hay nombres con caracteres rotos (U+FFFD) en ", basename(PUNTOS),
          ": vienen asi del archivo, no se corrigen aca.")
cat(sprintf("%d sedes en %s\n\n", nrow(loc), basename(PUNTOS)))


# ---- MapBiomas: lo construido ------------------------------------------------------------
# Urbano de MapBiomas Argentina (coleccion 2, clase 24, 30 m), del COG de Source Cooperative que
# usa el paso 17, recortado al cuadrado + MARGEN/2. Se guarda en <slug>/mapbiomas_urbano_<anio>.tif
# (UTM, 1 urbano, NA resto). Manchas: urbano conectado en 8 direcciones. Cada sede toma la mancha
# mas frecuente en un radio de MB_RADIO m (la sede suele estar en una plaza o un edificio publico).
MB_ANIO <- as.integer(arg("--mb-anio", "2022"))
MB_URL <- sprintf("/vsicurl/https://data.source.coop/tristangruppwri/mapbiomas/mapbiomas-argentina/mapbiomas_argentina_%d/mapbiomas_argentina_%d.tif",
                  MB_ANIO, MB_ANIO)
MB_RADIO <- 300
MB_COLOR <- "#7b1d3a"   # vino

mb_urbano <- function(x, d) {
  f <- file.path(d, sprintf("mapbiomas_urbano_%d_%gkm.tif", MB_ANIO, x$lado / 1000))
  if (!file.exists(f)) {
    Sys.setenv(GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR")
    caja <- terra::ext(as.vector(st_bbox(st_transform(st_buffer(x$cuadrado, MARGEN / 2), 4326)))[c(1, 3, 2, 4)])
    r <- terra::crop(terra::rast(MB_URL), caja)
    r <- terra::classify(r, cbind(24, 1), others = NA)
    r <- terra::project(r, x$crs, method = "near", res = 30)
    terra::writeRaster(r, f, overwrite = TRUE, datatype = "INT1U", gdal = "COMPRESS=DEFLATE")
  }
  terra::rast(f)
}

MB_BRECHA <- as.numeric(arg("--mb-brecha", "200"))   # m: dos manchas a menos de esto son una

mancha_de <- function(r, pt) {
  # id de mancha de cada sede (NA si no hay urbano a MB_RADIO m) y km2 de urbano de la mancha.
  # El urbano de 30 m se corta en calles anchas, rios y plazas: se dilata MB_BRECHA/2 para que las
  # brechas de hasta MB_BRECHA m no separen, se arman las manchas 8-conexas sobre lo dilatado y el
  # area se cuenta solo en las celdas urbanas originales.
  k <- ceiling(MB_BRECHA / 2 / terra::res(r)[1])
  w <- terra::focalMat(r, k * terra::res(r)[1], "circle"); w[w > 0] <- 1; w[w == 0] <- NA
  dil <- terra::focal(!is.na(r), w, fun = "max", na.rm = TRUE)
  m <- terra::patches(terra::classify(dil, cbind(0, NA)), directions = 8)
  b <- terra::vect(st_buffer(st_geometry(pt), MB_RADIO))
  moda <- function(v, ...) { v <- v[!is.na(v)]; if (length(v)) as.numeric(names(which.max(table(v)))) else NA }
  id <- terra::extract(terra::mask(m, r), b, fun = moda, ID = FALSE)[[1]]
  area <- terra::zonal(!is.na(r), m, fun = "sum", na.rm = TRUE)
  list(id = id, km2 = area[[2]][match(id, area[[1]])] * prod(terra::res(r)) / 1e6)
}

mb_df <- function(r, lado) {
  # celdas urbanas como data.frame para geom_raster; a 60 m en ventanas de 100 km para aliviar
  f <- max(1L, as.integer(round(lado / 50000)))
  if (f > 1) r <- terra::aggregate(r, f, fun = "max", na.rm = TRUE)
  d <- as.data.frame(r, xy = TRUE, na.rm = TRUE)[, 1:2]
  attr(d, "celda") <- terra::res(r)[1]
  d
}

dibujar <- function(a, x, pt, grupos, lp, ic, mb, d) {
  # grupos: lista con las pertenencias de los dos paneles (NULL o NA = un solo grupo)
  metodos <- c(sprintf("enlace promedio, corte %g min", CORTE), sprintf("Leiden, tau %g min", TAU_MAPA))
  pl <- do.call(rbind, lapply(seq_along(metodos), function(k) {
    v <- grupos[[k]]
    st_sf(metodo = metodos[k], nombre = pt$nombre,
          grupo = factor(if (is.null(v) || all(is.na(v))) rep(1, nrow(pt)) else v),
          central = seq_len(nrow(pt)) == ic, geometry = st_geometry(pt))
  }))
  pl$metodo <- factor(pl$metodo, levels = metodos)
  if (!is.null(lp) && nrow(lp))
    lp <- do.call(rbind, lapply(metodos, function(m) cbind(lp, metodo = factor(m, levels = metodos))))
  fc <- file.path(CALLES, a$slug, "calles.gpkg")
  red_p <- NULL
  if (file.exists(fc)) {
    red_p <- st_read(fc, quiet = TRUE,
                     query = "SELECT clase, geom FROM calles WHERE clase IN ('motorway','trunk','primary','secondary')")
    red_p <- st_intersection(st_transform(red_p, x$crs), st_buffer(x$cuadrado, MARGEN / 2))
  }
  ng <- max(as.integer(as.character(pl$grupo)))
  p <- ggplot() +
    geom_sf(data = st_transform(a, x$crs), fill = "grey60", alpha = 0.25, colour = NA) +
    { if (!is.null(mb) && nrow(mb)) geom_tile(data = mb, aes(x = x, y = y), width = attr(mb, "celda"), height = attr(mb, "celda"),
                                                   fill = MB_COLOR, alpha = 0.45) } +
    { if (!is.null(red_p)) geom_sf(data = red_p, colour = "grey55", linewidth = 0.2) } +
    geom_sf(data = st_transform(a, x$crs), fill = NA, colour = "black", linewidth = 0.45) +
    geom_sf(data = x$cuadrado, fill = NA, colour = "grey30", linetype = 2, linewidth = 0.3) +
    { if (!is.null(lp) && nrow(lp)) list(
        geom_sf(data = lp, aes(colour = pmin(tiempo_min, CORTE)), linewidth = 0.8),
        scale_colour_viridis_c(option = "rocket", direction = -1, limits = c(0, CORTE),
                               name = sprintf("min, tramo\ndel arbol\n(tope %g)", CORTE))) } +
    geom_sf(data = pl, aes(fill = grupo, size = central), shape = 21, colour = "black", stroke = 0.35) +
    scale_size_manual(values = c(`FALSE` = 2.2, `TRUE` = 3.6), guide = "none") +
    { if (ng <= 8) scale_fill_brewer(palette = "Set2") else if (ng <= 12) scale_fill_brewer(palette = "Set3")
      else scale_fill_hue() } +
    guides(fill = guide_legend(override.aes = list(size = 3.5))) +
    geom_sf_text(data = pl, aes(label = nombre), size = 1.9, nudge_y = x$lado / 80, colour = "grey10") +
    facet_wrap(~metodo) +
    coord_sf(xlim = st_bbox(x$cuadrado)[c(1, 3)], ylim = st_bbox(x$cuadrado)[c(2, 4)], expand = TRUE,
             datum = x$crs) +
    labs(title = sprintf("%s · %d sede(s) en %g x %g km · comunidades por tiempo de viaje",
                         a$nombre, nrow(pt), x$lado / 1000, x$lado / 1000),
         subtitle = if (nrow(pt) >= 2)
           sprintf(paste("lineas: arbol de expansion minima del tiempo (en recta, no el camino);",
                         "cortar sus tramos de mas de U min da el enlace simple a U min.",
                         "Punto grande: sede mas cercana al centro (%s)"), pt$nombre[ic])
         else "Menos de 2 sedes en el cuadrado: no hay pares para agrupar; se muestra lo construido.",
         fill = "grupo", x = NULL, y = NULL,
         caption = sprintf(paste("Sedes de gobierno local BAHRA/IGN. Tiempo: camino mas rapido por la red de calles",
                                 "de Overture, velocidad supuesta por clase, flujo libre.\nVino: urbano de MapBiomas",
                                 "Argentina %d (clase 24). Gris con borde negro: perimetro de analisis del aglomerado",
                                 "(EPH); punteado: el cuadrado; lineas grises: red principal."), MB_ANIO)) +
    theme_minimal(base_size = 8) +
    theme(axis.text = element_blank(), panel.grid = element_blank(),
          plot.caption = element_text(size = 6, colour = "grey40", hjust = 0),
          strip.text = element_text(face = "bold"))
  ggsave(file.path(d, "mapa.png"), p, width = 11, height = 6.4, dpi = 150, bg = "white")
  saveRDS(p, file.path(d, "mapa.rds"))   # para --pdf / --solo-texto
  p
}


# ---- por aglomerado ----------------------------------------------------------------------
col_prom <- sprintf("promedio_%gmin", CORTE)
col_simple <- sprintf("simple_%gmin", CORTE)
col_leiden <- sprintf("leiden_tau%g", TAU_MAPA)
resumen <- list(); mapas <- list(); capa_pt <- list(); capa_pa <- list(); capa_cu <- list()

for (s in if (SOLO_TEXTO) character(0) else ag$slug) {
  a <- ag[ag$slug == s, ]
  x <- CU[[s]]
  capa_cu[[s]] <- st_sf(slug = s, nombre = a$nombre, geometry = st_transform(x$cuadrado, 4326))
  pt <- st_transform(loc, x$crs)
  pt <- pt[lengths(st_intersects(pt, x$cuadrado)) > 0, ]
  if (anyDuplicated(pt$nombre)) pt$nombre <- make.unique(pt$nombre, sep = " #")
  fila <- data.frame(slug = s, nombre = a$nombre, lado_km = x$lado / 1000, puntos = nrow(pt),
                     partes_fuera = x$partes_fuera)
  fc <- file.path(CALLES, s, "calles.gpkg")
  d <- file.path(SAL, s)
  dir.create(d, showWarnings = FALSE)
  mbr <- tryCatch(mb_urbano(x, d), error = function(e) { message("AVISO MapBiomas ", s, ": ", conditionMessage(e)); NULL })
  mb <- if (is.null(mbr)) NULL else mb_df(mbr, x$lado)
  if (!is.null(mbr)) {
    sq <- terra::crop(mbr, terra::vect(x$cuadrado))
    fila$mb_urbano_km2 <- round(sum(!is.na(terra::values(sq))) * prod(terra::res(sq)) / 1e6, 1)
  }
  if (nrow(pt) < 2 || !file.exists(fc)) {
    motivo <- if (nrow(pt) < 2) sprintf("%d sede(s) en el cuadrado", nrow(pt)) else "sin calles (paso 20)"
    cat(sprintf("%-32s sin comunidades: %s; mapa solo con lo construido\n", s, motivo))
    resumen[[s]] <- cbind(fila, estado = motivo)
    if (nrow(pt) >= 1) {
      ic <- which.min(as.numeric(st_distance(pt, x$centro)))
      mapas[[s]] <- dibujar(a, x, pt, list(NULL, NULL), NULL, ic, mb, d)
    }
    next
  }
  t0 <- Sys.time()
  red <- leer_red(fc, x$crs, verboso = FALSE)
  en <- enganchar(red$g, pt)
  od <- matriz_od(red$g, en$cerca, pt)
  cm <- comunidades(od$Tm, UMBRALES, TAUS, SEMILLA)
  com <- cm$com

  d <- file.path(SAL, s)
  dir.create(d, showWarnings = FALSE)
  write.csv(round(od$Tm, 1), file.path(d, "od_tiempo_min.csv"), fileEncoding = "UTF-8")
  write.csv(round(od$Dk, 2), file.path(d, "od_distancia_km.csv"), fileEncoding = "UTF-8")
  pa <- od$pares
  write.csv(transform(pa, tiempo_min = round(tiempo_min, 1), distancia_km = round(distancia_km, 2),
                      recta_km = round(recta_km, 2), rodeo = round(rodeo, 3), vel_kmh = round(vel_kmh, 1)),
            file.path(d, "od_pares.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  # grupo central: el de la sede mas cercana al centro
  ic <- which.min(as.numeric(st_distance(pt, x$centro)))
  # lo construido: mancha urbana de MapBiomas de cada sede y si es la misma que la de la sede central
  if (!is.null(mbr)) {
    mm <- mancha_de(mbr, pt)
    com$mancha_mb <- mm$id
    com$mancha_mb_km2 <- round(mm$km2, 2)
    com$misma_mancha_central <- if (is.na(mm$id[ic])) NA else mm$id %in% mm$id[ic]
  }
  write.csv(cbind(com, enganche_m = round(en$eng, 1)), file.path(d, "comunidades.csv"),
            row.names = FALSE, fileEncoding = "UTF-8")
  if (nrow(cm$modul)) write.csv(cm$modul, file.path(d, "modularidad.csv"), row.names = FALSE)
  central <- function(col) if (all(is.na(com[[col]]))) NA else sum(com[[col]] == com[[col]][ic])
  fila <- cbind(fila, estado = "ok", sede_central = pt$nombre[ic],
                enganche_max_m = round(max(en$eng)),
                tiempo_max_min = round(max(od$Tm), 1),
                grupos_simple = max(com[[col_simple]]), central_simple = central(col_simple),
                grupos_promedio = max(com[[col_prom]]), central_promedio = central(col_prom),
                grupos_leiden = if (all(is.na(com[[col_leiden]]))) NA else max(com[[col_leiden]]),
                central_leiden = central(col_leiden),
                misma_mancha_central = if (is.null(com$misma_mancha_central)) NA else
                  sum(com$misma_mancha_central, na.rm = TRUE))
  names(fila) <- sub("_simple$", sprintf("_simple_%gmin", CORTE), names(fila))
  names(fila) <- sub("_promedio$", sprintf("_promedio_%gmin", CORTE), names(fila))
  names(fila) <- sub("_leiden$", sprintf("_leiden_tau%g", TAU_MAPA), names(fila))
  resumen[[s]] <- fila

  # capas
  pt_out <- cbind(st_sf(slug = s, nombre = pt$nombre, geometry = st_geometry(pt)), com[, -1],
                  enganche_m = round(en$eng, 1), central = seq_len(nrow(pt)) == ic)
  capa_pt[[s]] <- st_transform(pt_out, 4326)
  xyp <- st_coordinates(pt)
  lin <- st_sfc(lapply(seq_len(nrow(od$ij)), function(r) st_linestring(xyp[od$ij[r, ], ])), crs = x$crs)
  capa_pa[[s]] <- st_transform(st_sf(slug = s, pa, geometry = lin), 4326)

  # mapa: arbol de expansion minima sobre el tiempo, el esqueleto que encadena el enlace simple
  gc <- graph_from_adjacency_matrix(od$Tm, mode = "undirected", weighted = TRUE, diag = FALSE)
  am <- as_edgelist(mst(gc, weights = E(gc)$weight), names = FALSE)
  am <- t(apply(am, 1, sort))
  lp <- st_transform(capa_pa[[s]][paste(od$ij[, 1], od$ij[, 2]) %in% paste(am[, 1], am[, 2]), ], x$crs)
  mapas[[s]] <- dibujar(a, x, pt, list(com[[col_prom]], com[[col_leiden]]), lp, ic, mb, d)
  cat(sprintf("%-32s %3d sedes, %3d grupos promedio/%gmin, %2s Leiden/tau%g, central %s: %d / %s · %.0f s\n",
              s, nrow(pt), max(com[[col_prom]]), CORTE,
              if (all(is.na(com[[col_leiden]]))) "-" else max(com[[col_leiden]]), TAU_MAPA,
              pt$nombre[ic], central(col_prom), central(col_leiden),
              as.numeric(Sys.time() - t0, units = "secs")))
}


# ---- salidas nacionales ------------------------------------------------------------------
f_res <- file.path(SAL, "resumen.csv")
if (SOLO_TEXTO) {
  if (!file.exists(f_res)) stop("--solo-texto necesita una corrida previa (falta resumen.csv)", call. = FALSE)
  res <- read.csv(f_res, check.names = FALSE)
} else {
  todas <- unique(unlist(lapply(resumen, names)))
  res <- do.call(rbind, lapply(resumen, function(f) { f[setdiff(todas, names(f))] <- NA; f[todas] }))
  if (file.exists(f_res)) {
    viejo <- read.csv(f_res, check.names = FALSE)
    if (identical(names(viejo), names(res))) res <- rbind(viejo[!(viejo$slug %in% res$slug), ], res)
  }
  write.csv(res[order(match(res$slug, ORDEN)), ], f_res, row.names = FALSE, fileEncoding = "UTF-8")
}
res <- res[order(match(res$slug, ORDEN)), ]   # cada ventana extra despues de su aglomerado
release <- file.path(CALLES, "release.txt")
release <- if (file.exists(release)) trimws(readLines(release, n = 1)) else "?"

# mapas.pdf (solo con --pdf): pagina 1 = metodo; despues, todos los mapas guardados (no solo los
# de esta corrida), en ORDEN
if (PDF) {
  rds <- file.path(SAL, ORDEN, "mapa.rds")
  rds <- rds[file.exists(rds)]
  pdf(file.path(SAL, "mapas.pdf"), width = 11, height = 6.4)
  pagina_metodo(res, nrow(loc), release)
  for (f in rds) print(readRDS(f))
  invisible(dev.off())
  png(file.path(SAL, "metodo.png"), width = 11, height = 6.4, units = "in", res = 150)
  pagina_metodo(res, nrow(loc), release)
  invisible(dev.off())
  cat(sprintf("mapas.pdf: metodo + %d mapas\n", length(rds)))
}

# ---- lista INDEC: localidades censales 2010 que forman cada aglomerado EPH ----------------
# El xls trae el nombre del aglomerado solo en la primera fila de cada bloque. CABA y Partidos
# del GBA vienen separados; aca son un solo perimetro.
ALIAS <- c("ciudad autonoma de buenos aires" = "gran_buenos_aires",
           "partidos de gran buenos aires" = "gran_buenos_aires",
           "mar del plata" = "mar_del_plata__batan",
           "san nicolas de los arroyos - villa constitucion" = "san_nicolas__villa_constitucion")
sin_tilde <- function(x) tolower(chartr("áéíóúüñÁÉÍÓÚÜÑ", "aeiouunAEIOUUN", trimws(x)))
leer_lista <- function(f) {
  if (!file.exists(f)) { message("AVISO: no esta la lista INDEC ", f, "; el md sale sin validacion"); return(NULL) }
  d <- as.data.frame(suppressMessages(readxl::read_excel(f, col_names = FALSE, col_types = "text")))
  ini <- which(d[[2]] == "Localidades censales 2010")
  if (length(ini) != 1) stop("no reconozco el formato de ", basename(f), call. = FALSE)
  d <- d[(ini + 1):nrow(d), 1:2]
  names(d) <- c("aglomerado", "localidad")
  for (i in seq_len(nrow(d))[-1]) if (is.na(d$aglomerado[i])) d$aglomerado[i] <- d$aglomerado[i - 1]
  d <- d[!is.na(d$localidad), ]
  clave <- sin_tilde(d$aglomerado)
  d$slug <- ifelse(clave %in% names(ALIAS), ALIAS[clave], ag0$slug[match(clave, sin_tilde(ag0$nombre))])
  if (any(is.na(d$slug)))
    stop("aglomerados de la lista sin perimetro: ", paste(unique(d$aglomerado[is.na(d$slug)]), collapse = ", "),
         call. = FALSE)
  if (length(x <- setdiff(ag0$slug, d$slug)))
    stop("perimetros sin aglomerado en la lista: ", paste(x, collapse = ", "), call. = FALSE)
  d
}
LISTA <- leer_lista(arg("--lista", file.path(SAL, "localidades_aglomerados_eph.xls")))
if (!is.null(LISTA))
  cat(sprintf("lista INDEC: %d localidades, %d aglomerados EPH -> los %d perimetros\n", nrow(LISTA),
              length(unique(LISTA$aglomerado)), length(unique(LISTA$slug))))

# localidad INDEC -> sede del cuadrado con el mismo nombre. Los nombres de BAHRA traen U+FFFD en
# lugar de cada letra acentuada: ese caracter vale como comodin de una letra.
sede_de <- function(localidad, sedes) {
  patron <- paste0("^", gsub("�", ".", gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1",
                                                   sin_tilde(sedes), perl = TRUE)), "$")
  vapply(sin_tilde(localidad), function(l) {
    k <- which(vapply(patron, function(p) grepl(p, l), TRUE))
    if (length(k)) sedes[k[1]] else NA_character_
  }, "", USE.NAMES = FALSE)
}

# HALLAZGOS.md: generado de resumen.csv y de cada comunidades.csv; nada escrito a mano
hallazgos <- function(res) {
  ok <- res[res$estado == "ok", ]
  salt <- res[res$estado != "ok", ]
  cp <- sprintf("promedio_%gmin", CORTE); cl <- sprintf("leiden_tau%g", TAU_MAPA)
  gp_ <- sprintf("grupos_promedio_%gmin", CORTE); gl_ <- sprintf("grupos_leiden_tau%g", TAU_MAPA)
  gs_ <- sprintf("grupos_simple_%gmin", CORTE)
  cpc <- sprintf("central_promedio_%gmin", CORTE); clc <- sprintf("central_leiden_tau%g", TAU_MAPA)
  grupos_txt <- function(com, col, central) {
    # el grupo de la sede central primero, despues los demas, cada uno con sus sedes
    if (all(is.na(com[[col]]))) return("sin Leiden (menos de 3 sedes)")
    g0 <- com[[col]][com$nombre == central]
    otros <- setdiff(sort(unique(com[[col]])), g0)
    c(sprintf("**grupo central** (%d): %s", sum(com[[col]] == g0),
              paste(com$nombre[com[[col]] == g0], collapse = ", ")),
      vapply(otros, function(k) sprintf("aparte (%d): %s", sum(com[[col]] == k),
                                        paste(com$nombre[com[[col]] == k], collapse = ", ")), ""))
  }
  # validacion contra la lista INDEC: una fila por ventana y localidad censal del aglomerado
  base_de <- function(s) sub("_[0-9.]+km$", "", s)
  coms <- lapply(setNames(res$slug, res$slug), function(s) {
    f <- file.path(SAL, s, "comunidades.csv")
    if (res$estado[res$slug == s] == "ok" && file.exists(f))
      read.csv(f, check.names = FALSE, encoding = "UTF-8") else NULL
  })
  val <- NULL
  if (!is.null(LISTA)) {
    val <- do.call(rbind, lapply(res$slug, function(s) {
      l <- LISTA[LISTA$slug == base_de(s), ]
      com <- coms[[s]]
      v <- data.frame(ventana = s, aglomerado_eph = l$aglomerado, localidad = l$localidad,
                      sede = if (is.null(com)) NA_character_ else sede_de(l$localidad, com$nombre))
      central <- res$sede_central[res$slug == s]
      for (m in c(cp, cl)) {
        g <- if (is.null(com)) rep(NA, nrow(v)) else com[[m]][match(v$sede, com$nombre)]
        g0 <- if (is.null(com) || all(is.na(com[[m]]))) NA else com[[m]][com$nombre == central]
        v[[paste0("grupo_", m)]] <- g
        v[[paste0("central_", m)]] <- g == g0
      }
      v
    }))
    write.csv(val, file.path(SAL, "validacion_eph.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  }
  n_val <- function(s, que) {
    if (is.null(val)) return(NA)
    v <- val[val$ventana == s, ]
    switch(que, loc = nrow(v), sede = sum(!is.na(v$sede)),
           prom = sum(v[[paste0("central_", cp)]], na.rm = TRUE),
           leid = sum(v[[paste0("central_", cl)]], na.rm = TRUE))
  }
  ok$loc <- sapply(ok$slug, n_val, "loc"); ok$con_sede <- sapply(ok$slug, n_val, "sede")
  ok$en_prom <- sapply(ok$slug, n_val, "prom"); ok$en_leid <- sapply(ok$slug, n_val, "leid")

  L <- c(
    "# Comunidades de localidades por tiempo de viaje · hallazgos", "",
    sprintf(paste("Generado por `Rpipe/scripts/29_od_aglomerados.R` el %s. Exploratorio: ningun numero",
                  "es cifra del proyecto. Todo lo que sigue sale de `resumen.csv` y de cada",
                  "`<aglomerado>/comunidades.csv`."), format(Sys.Date())), "",
    "## Que muestra", "",
    paste("Para cada aglomerado, que localidades de su entorno quedan unidas por viajes cortos y cuales",
          "forman nucleos aparte. Es una medida de accesibilidad potencial por la red vial: sirve para",
          "discutir hasta donde llega el aglomerado, no para fijarlo."), "",
    "## Metodo, paso a paso", "",
    sprintf(paste("1. **Ventana.** Un cuadrado de %g x %g km%s, centrado en el centroide de la parte mas",
                  "grande del perimetro de analisis del aglomerado (paso 07). En aglomerados de partes",
                  "lejanas la otra parte puede quedar afuera (`partes_fuera` en resumen.csv)."),
            LADO / 1000, LADO / 1000, VENTANA_EXTRA),
    sprintf(paste("2. **Puntos.** Las sedes de gobierno local de BAHRA/IGN (municipios, comunas, comisiones,",
                  "juntas; %d en el archivo) que caen dentro del cuadrado. Cada sede es un punto, no una",
                  "poblacion: una ciudad grande y un pueblo pesan igual. Con menos de 2 sedes el aglomerado",
                  "se saltea."), nrow(loc)),
    sprintf(paste("3. **Red vial.** Calles de Overture Maps (release %s) en el cuadrado mas %g km por lado,",
                  "para que los caminos puedan salir de el. Sin sendas, veredas ni ciclovias. Las lineas se",
                  "cortan en cada cruce (un puente cuenta como cruce), la red es no dirigida (sin manos",
                  "unicas) y se usa su componente conexa mayor. Velocidad supuesta por clase de calle, km/h,",
                  "flujo libre: %s. No es velocidad medida: los tiempos son una cota inferior del viaje en auto."),
            release, MARGEN / 1000, paste(sprintf("%s %g", names(VEL), VEL), collapse = ", ")),
    paste("4. **Matriz origen-destino.** Cada sede se engancha al nodo mas cercano de la red (la distancia",
          "de enganche no se suma). Entre cada par se busca el camino mas rapido (Dijkstra): tiempo en",
          "minutos y largo de ese camino en km (`od_tiempo_min.csv`, `od_distancia_km.csv`, `od_pares.csv`)."),
    "5. **Comunidades**, tres maneras de agrupar las sedes a partir de la matriz de tiempo:",
    paste("   - *Enlace simple a U min*: dos sedes van juntas si hay una cadena de viajes de a lo sumo U",
          "min que las une (percolacion, Arcaute et al. 2016). Puede encadenar pueblos lejanos a traves",
          "de uno intermedio."),
    sprintf(paste("   - *Enlace promedio a U min*: dos grupos se unen solo si el tiempo promedio entre todos",
                  "sus miembros es de a lo sumo U min. Mas conservador. Aca U = %g."), CORTE),
    sprintf(paste("   - *Leiden* (Traag et al. 2019): cada par se une con peso exp(-t/tau), que decae con el",
                  "tiempo (con tau = %g, un viaje de %g min pesa 0,37). Elige la particion que maximiza la",
                  "modularidad (mas peso dentro de los grupos que el esperable al azar) y decide solo cuantos",
                  "grupos hay. Tau chico da grupos chicos; tau grande los junta. Aca tau = %g."),
            TAU_MAPA, TAU_MAPA, TAU_MAPA),
    sprintf("   - `comunidades.csv` tiene los tres metodos para U = %s min y tau = %s.",
            paste(UMBRALES, collapse = ", "), paste(TAUS, collapse = ", ")),
    paste("6. **Grupo central.** El grupo de la sede mas cercana al centro del cuadrado; su tamano es una",
          "primera medida de hasta donde llega el aglomerado (`central_*` en resumen.csv)."),
    sprintf(paste("7. **Lo construido.** Urbano de MapBiomas Argentina %d (coleccion 2, clase 24, 30 m), en",
                  "vino en los mapas. Las manchas son el urbano conectado, uniendo las que estan a menos de %g m",
                  "(a 30 m el urbano se corta en avenidas, rios y plazas). Cada sede toma la mancha que mas",
                  "aparece a %g m de ella. Si una sede esta en la misma mancha que la sede central, el",
                  "aglomerado es fisicamente continuo hasta ahi; si esta en el mismo grupo pero en otra mancha,",
                  "la une el viaje y no lo construido."), MB_ANIO, MB_BRECHA, MB_RADIO),
    if (!is.null(LISTA)) paste("8. **Validacion contra INDEC.** La lista de localidades censales 2010 que forman cada",
          "aglomerado EPH (INDEC, `localidades_aglomerados_eph.xls`) se cruza por nombre con las sedes del",
          "cuadrado. Para cada localidad que coincide con una sede se mira si cae en el grupo central: si",
          "el metodo reproduce el aglomerado oficial, todas deberian caer ahi. Las localidades que no son",
          "sede de gobierno local (barrios, parajes) no tienen punto y quedan sin validar",
          "(`validacion_eph.csv`).") else NULL, "",
    paste("Cada mapa: a la izquierda enlace promedio, a la derecha Leiden; el color es el grupo (la",
          "numeracion es propia de cada panel). Las lineas son el arbol de expansion minima del tiempo,",
          "el conjunto de viajes mas cortos que conecta todas las sedes, dibujado en recta: cortar sus",
          "tramos de mas de U min da el enlace simple a U. Gris: perimetro de analisis; punteado: el cuadrado."), "",
    "## Resumen", "",
    sprintf("- %d de %d ventanas tienen mapa (%d aglomerados%s).%s", nrow(ok), nrow(res),
            sum(res$lado_km == LADO / 1000), if (any(res$lado_km != LADO / 1000))
              sprintf(" y %d ventana(s) extra", sum(res$lado_km != LADO / 1000)) else "",
            if (nrow(salt)) sprintf(" Sin mapa por tener menos de 2 sedes en el cuadrado: %s.",
                                    paste(salt$nombre, collapse = ", ")) else ""),
    sprintf("- Con enlace simple a %g min, %d de %d quedan en un solo grupo: la cadena de viajes cortos une todo el cuadrado.",
            CORTE, sum(ok[[gs_]] == 1), nrow(ok)),
    sprintf("- Con enlace promedio a %g min, %d de %d quedan en un solo grupo; con Leiden (tau %g), %d de %d.",
            CORTE, sum(ok[[gp_]] == 1), nrow(ok), TAU_MAPA, sum(ok[[gl_]] == 1, na.rm = TRUE),
            sum(!is.na(ok[[gl_]]))),
    sprintf(paste("- A esta escala un corte de %g min discrimina poco; Leiden o cortes mas bajos (%s min, en",
                  "comunidades.csv) separan mas."), CORTE,
            paste(UMBRALES[UMBRALES < CORTE], collapse = ", ")),
    if (!is.null(LISTA)) {
      vb <- val[val$ventana %in% ok$slug & !is.na(val$sede), ]
      c(sprintf(paste("- Lista INDEC: %d localidades censales 2010 en %d aglomerados EPH (CABA y Partidos del GBA",
                      "por separado), que corresponden a los %d perimetros: no falta ninguno."),
                nrow(LISTA), length(unique(LISTA$aglomerado)), length(unique(LISTA$slug))),
        sprintf(paste("- Validacion, en las ventanas con mapa: %d localidades INDEC coinciden con una sede del",
                      "cuadrado. Caen en el grupo central %d con enlace promedio a %g min y %d con Leiden (tau %g)."),
                nrow(vb), sum(vb[[paste0("central_", cp)]], na.rm = TRUE), CORTE,
                sum(vb[[paste0("central_", cl)]], na.rm = TRUE), TAU_MAPA))
    } else NULL, "",
    sprintf(paste("| aglomerado | lado (km) | sedes | grupos simple %g | grupos promedio %g | grupos Leiden %g |",
                  "sede central | su grupo, promedio | su grupo, Leiden | tiempo max (min) |",
                  "localidades INDEC | con sede | en grupo central, promedio | en grupo central, Leiden |",
                  "en la mancha construida central | urbano MapBiomas en el cuadrado (km2) |"),
            CORTE, CORTE, TAU_MAPA),
    "|---|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    sprintf("| %s | %g | %d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |", ok$nombre, ok$lado_km,
            ok$puntos, ok[[gs_]], ok[[gp_]], ifelse(is.na(ok[[gl_]]), "-", ok[[gl_]]), ok$sede_central,
            ok[[cpc]], ifelse(is.na(ok[[clc]]), "-", ok[[clc]]), ok$tiempo_max_min,
            ok$loc, ok$con_sede, ok$en_prom, ifelse(is.na(ok[[gl_]]), "-", ok$en_leid),
            ifelse(is.na(ok$misma_mancha_central), "-", ok$misma_mancha_central),
            ifelse(is.na(ok$mb_urbano_km2), "-", ok$mb_urbano_km2)),
    "",
    "## Por aglomerado", "",
    paste("El grupo central es el de la sede mas cercana al centro del cuadrado. Las sedes \"aparte\" son",
          "las que el metodo separa del nucleo. Cada aglomerado lista sus localidades censales segun INDEC",
          "y, para las que son sede, en que grupo cayeron."), ""
  )
  for (i in seq_len(nrow(res))) {
    s <- res$slug[i]
    L <- c(L, sprintf("### %s", res$nombre[i]), "")
    if (!is.null(LISTA)) {
      v <- val[val$ventana == s, ]
      L <- c(L, sprintf("Localidades censales 2010 que lo forman segun INDEC (%d): %s.", nrow(v),
                        paste(v$localidad, collapse = ", ")), "")
    }
    if (res$estado[i] != "ok") {
      L <- c(L, sprintf("**Sin mapa**: cuadrado de %g km, %s. No hay pares para agrupar.",
                        res$lado_km[i], res$estado[i]), "")
      next
    }
    com <- coms[[s]]
    central <- res$sede_central[i]
    L <- c(L, sprintf("Cuadrado de %g km, %d sedes; sede central: %s.", res$lado_km[i], res$puntos[i], central), "",
           sprintf("![%s](%s/mapa.png)", res$nombre[i], s), "",
           sprintf("Enlace promedio a %g min:", CORTE), "",
           paste0("- ", grupos_txt(com, cp, central)), "",
           sprintf("Leiden, tau %g min:", TAU_MAPA), "",
           paste0("- ", grupos_txt(com, cl, central)), "",
           if (!is.null(com$misma_mancha_central)) {
             en_m <- com$nombre[com$misma_mancha_central %in% TRUE]
             otra <- com$nombre[!(com$misma_mancha_central %in% TRUE)]
             c(sprintf("Lo construido (MapBiomas %d): en la misma mancha que %s (%s km2 de urbano): %s.",
                       MB_ANIO, central, com$mancha_mb_km2[com$nombre == central], paste(en_m, collapse = ", ")),
               if (length(otra)) sprintf("En otra mancha o sin urbano cerca: %s.", paste(otra, collapse = ", ")) else NULL, "")
           } else NULL)
    if (!is.null(LISTA)) {
      v <- val[val$ventana == s & !is.na(val$sede), ]
      fuera <- function(m) { x <- v$localidad[!v[[paste0("central_", m)]] %in% TRUE]
                             if (length(x)) paste0(" Fuera: ", paste(x, collapse = ", "), ".") else "" }
      L <- c(L, if (!nrow(v)) "Validacion INDEC: ninguna localidad del aglomerado coincide con una sede del cuadrado." else
        c(sprintf("Validacion INDEC: %d de %d localidades son sede en el cuadrado (%s).", nrow(v),
                  sum(val$ventana == s), paste(v$localidad, collapse = ", ")),
          sprintf("- en el grupo central, enlace promedio: %d de %d.%s",
                  sum(v[[paste0("central_", cp)]], na.rm = TRUE), nrow(v), fuera(cp)),
          if (all(is.na(com[[cl]]))) "- Leiden: no corre con menos de 3 sedes." else
            sprintf("- en el grupo central, Leiden: %d de %d.%s",
                    sum(v[[paste0("central_", cl)]], na.rm = TRUE), nrow(v), fuera(cl))), "")
    }
  }
  L <- c(L, "## Limitaciones", "",
         "- Sin poblacion ni viajes observados: comunidades de accesibilidad potencial, no de interaccion.",
         "- Cada sede pesa lo mismo, sea ciudad o pueblo; la densidad de sedes cambia por provincia (Buenos Aires: una por partido).",
         "- Velocidades supuestas, sin congestion, red no dirigida, puentes como cruces.",
         "- El centro sale del perimetro, no de la ciudad cabecera: en algunos aglomerados la sede central no es la capital.",
         "- Los nombres con letras acentuadas llegan rotos desde el archivo de BAHRA.")
  writeLines(enc2utf8(L), file.path(SAL, "HALLAZGOS.md"), useBytes = TRUE)
}
hallazgos(res)
cat("HALLAZGOS.md escrito\n")
if (length(capa_pt)) {
  gp <- file.path(SAL, "od_aglomerados.gpkg")
  if (file.exists(gp) && length(AGLOS) == nrow(st_read(PERIM, "perimetro", quiet = TRUE)))
    invisible(file.remove(gp))
  escribir_capa <- function(lista, capa) {
    x <- do.call(rbind, lista)
    if (file.exists(gp) && capa %in% st_layers(gp)$name) {   # corrida parcial: reemplaza sus aglomerados
      viejo <- st_read(gp, capa, quiet = TRUE)
      viejo <- viejo[!(viejo$slug %in% x$slug), ]
      st_geometry(viejo) <- "geometry"
      if (identical(names(viejo), names(x))) x <- rbind(viejo, x)
    }
    st_write(x, gp, capa, quiet = TRUE, delete_layer = TRUE)
  }
  escribir_capa(capa_cu, "cuadrados")
  escribir_capa(capa_pt, "puntos")
  escribir_capa(capa_pa, "pares")
}
cat("\nresumen:\n")
print(res[, intersect(c("slug", "puntos", "estado", names(res)[grepl("^(grupos|central)_", names(res))]), names(res))],
      row.names = FALSE)
cat("\nsalidas en ", SAL, "\n", sep = "")
