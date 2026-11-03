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
  # contorno del aglomerado EPH (plataforma/datos/<contorno>/base.js) como SpatVector
  # en EPSG:4326, o NULL si la ciudad no tiene contorno
  c <- caja_de(rpipe, slug)$contorno
  if (!nzchar(c)) return(NULL)
  f <- file.path(dirname(rpipe), "plataforma", "datos", c, "base.js")
  if (!file.exists(f)) stop("no esta el contorno ", f, call. = FALSE)
  s <- paste(readLines(f, encoding = "UTF-8", warn = FALSE), collapse = "")
  j <- jsonlite::fromJSON(substr(s, regexpr("{", s, fixed = TRUE),
                                 max(gregexpr("}", s, fixed = TRUE)[[1]])),
                          simplifyVector = FALSE)
  gj <- jsonlite::toJSON(list(type = "Feature", properties = structure(list(), names = character()),
                              geometry = list(type = j$contorno$t, coordinates = j$contorno$c)),
                         auto_unbox = TRUE, digits = NA)
  terra::vect(sf::st_read(as.character(gj), quiet = TRUE))
}
