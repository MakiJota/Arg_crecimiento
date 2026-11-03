# -*- coding: utf-8 -*-
# Funciones comunes: la tabla de cajas (Rpipe/cajas.md) y el contorno EPH de una ciudad.
# Se carga con source() desde los pasos numerados; no se corre sola.


leer_cajas <- function(rpipe) {
  # la tabla de Rpipe/cajas.md: las filas que empiezan con "| " salvo encabezado y regla
  l <- readLines(file.path(rpipe, "cajas.md"), encoding = "UTF-8")
  l <- l[startsWith(l, "| ") & !startsWith(l, "| slug") & !startsWith(l, "|---")]
  m <- do.call(rbind, lapply(strsplit(l, "|", fixed = TRUE), function(x) trimws(x[2:8])))
  d <- data.frame(slug = m[, 1], contorno = m[, 2], lat0 = as.numeric(m[, 3]),
                  lon0 = as.numeric(m[, 4]), lat1 = as.numeric(m[, 5]),
                  lon1 = as.numeric(m[, 6]), origen = m[, 7])
  if (anyDuplicated(d$slug)) stop("slug repetido en cajas.md", call. = FALSE)
  d
}


caja_de <- function(rpipe, slug) {
  d <- leer_cajas(rpipe)
  if (!(slug %in% d$slug))
    stop("'", slug, "' no esta en Rpipe/cajas.md. Ciudades: ", paste(d$slug, collapse = ", "),
         call. = FALSE)
  d[d$slug == slug, ]
}


contorno_de <- function(rpipe, slug) {
  # perimetro del aglomerado como SpatVector en EPSG:4326, o NULL si la ciudad no tiene
  # contorno. Sale de raw/boundaries/aglomerados.gpkg (capa perimetro), que arma
  # 07_limites_aglomerados.R y esta en el repo: no hace falta plataforma/.
  c <- caja_de(rpipe, slug)$contorno
  if (!nzchar(c)) return(NULL)
  f <- file.path(rpipe, "raw", "boundaries", "aglomerados.gpkg")
  if (!file.exists(f)) stop("no esta ", f, ": correr antes 07_limites_aglomerados.R", call. = FALSE)
  p <- terra::vect(f, layer = "perimetro")
  p <- p[p$slug == c, ]
  if (nrow(p) != 1) stop("el contorno '", c, "' no esta en ", f, call. = FALSE)
  p
}


otros_de <- function(rpipe, slug) {
  # perimetros de OTROS aglomerados que caen en la caja de la ciudad (SpatVector en
  # EPSG:4326, quiza vacio), o NULL si la ciudad no tiene contorno
  cj <- caja_de(rpipe, slug)
  if (!nzchar(cj$contorno)) return(NULL)
  p <- terra::vect(file.path(rpipe, "raw", "boundaries", "aglomerados.gpkg"), layer = "perimetro")
  caja <- terra::vect(terra::ext(cj$lon0, cj$lon1, cj$lat0, cj$lat1), crs = "EPSG:4326")
  p <- p[p$slug != cj$contorno, ]
  p[terra::relate(p, caja, "intersects")[, 1], ]
}
