# -*- coding: utf-8 -*-
# Paso 15 · Datos del visor de las pruebas de densidad (docs/visor/index.html). Exploratorio:
# ningun numero es cifra del proyecto. Va solo al repo Arg_crecimiento, como el sitio (08).
#
# El visor calcula en el navegador las pruebas 1 y 2 y su comparacion para cualquier corte, a
# partir de lo que escribe 11. Por ciudad y anio, en Web Mercator (EPSG:3857) sobre la grilla
# del marco de 11 (la ciudad de 2020 mas 3 km):
#   clase_<anio>.png    R: bits 0-1 = codigo de 11 (1 construido de la ciudad, 2 franja o
#                       capturado de la ciudad, 3 construido fuera, 0 resto); en los pixeles 2,
#                       con las medidas de 16: bits 2-3 = distancia al borde (0 <= 100 m,
#                       1 <= 200, 2 <= 400, 3 mas), bits 4-5 = hueco (menor cierre que lo tapa:
#                       1 30 m, 2 60 m, 3 90 m, 0 ninguno), bits 6-7 = share construido en 150 m
#                       (0 < 60 %, 1 60-69, 2 70-79, 3 80 o mas). G*256 + B = fila del radio
#   landsat_<anio>.jpg  color verdadero del compuesto Landsat de 02, si existe, estirado 2-98 %
#   radios.json         por anio, una entrada por fila de radio: codigo, personas, km2 del
#                       radio, km2 construido y abierto de la ciudad en el radio, densidad sobre
#                       lo urbanizado
#   radios_<anio>.geojson  los radios como poligonos (recortados al marco, simplificados a 4 m,
#                       EPSG:4326), con el campo i que apunta a la fila de radios.json
# y datos/indice.json con nombre, limites, perimetro y que capas tiene cada ciudad.
#
#   mapbiomas_2020.png  comparacion con MapBiomas 2020 (paso 17), si existe
#   parches_<anio>.png  clases de parche del interior (paso 18) y solidez de lo construido; ver
#                       parches_png. --solo-parches rehace solo estos
#   bordesa/b/c_<anio>.png  franja de 0 a 500 m, parches hasta 100 ha, distancia al borde y huecos
#                       hasta 500 m (paso 18, version 2)
#                       para la pestana Reglas; ver bordes_png. --solo-bordes rehace solo estos
#   pedro_mb_<anio>.png las manchas GISD30 contra MapBiomas de Pedro (ag_43), por censo: R = b +
#                       4 c + 16 k (ver pedro_mb). Lee ../plataforma/datos/<contorno>/manchas_*.js
# ENTRADAS  outputs/densidad/<slug>/ (11), outputs/reglas/<slug>/ (16, opcional),
#           outputs/mapbiomas/<slug>/mapbiomas_2020.tif (17, opcional),
#           outputs/landsat/<slug>/landsat_<anio>.tif (02)
# SALIDAS   docs/visor/datos/
#
# Uso: Rscript Rpipe/scripts/15_visor_datos.R [--ciudades salta,jujuy]

Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))
options(warn = 1)
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
DENS <- file.path(RPIPE, "outputs", "densidad")
LANDSAT <- file.path(RPIPE, "outputs", "landsat")
REGLAS <- file.path(RPIPE, "outputs", "reglas")
SAL <- file.path(RPIPE, "docs", "visor", "datos")
TODAS <- sort(basename(dirname(list.files(DENS, "^ciudad\\.csv$", recursive = TRUE, full.names = TRUE))))
CIUDADES <- if (is.na(match("--ciudades", args))) TODAS else strsplit(arg("--ciudades", ""), ",")[[1]]
MERC <- "EPSG:3857"


pedro_mb <- function(contorno, censo, plantilla) {
  # Las manchas de Pedro (scripts/ag_43_manchas_contraste.py, publicadas en
  # plataforma/datos/<contorno>/manchas_<censo>.js): huella de Angel sobre GISD30 contra la de
  # MapBiomas (clase 24, coleccion 2, anio del censo), recortadas al perimetro de analisis.
  # Vienen en bloques de hasta 1024 px ya en Web Mercator, un WebP RGBA por clase:
  #   b: 1 las dos, 2 solo MapBiomas, 3 solo GISD30
  #   c: borde de cada huella   (1 solo GISD30, 2 solo MapBiomas, 3 los dos)
  #   k: borde de lo construido (idem, sin la regla de Angel)
  # Devuelve b + 4 c + 16 k sobre la plantilla, o NULL si no hay archivo.
  f <- file.path(dirname(RPIPE), "plataforma", "datos", contorno, sprintf("manchas_%s.js", censo))
  if (!nzchar(contorno) || !file.exists(f)) return(NULL)
  s <- readChar(f, file.size(f), useBytes = TRUE)
  d <- jsonlite::fromJSON(substr(s, regexpr("{", s, fixed = TRUE), max(gregexpr("}", s, fixed = TRUE)[[1]])),
                          simplifyVector = FALSE)
  merc <- function(lat) 6378137 * log(tan(pi / 4 + lat * pi / 360))
  capa <- function(bloques) {
    out <- plantilla * 0
    for (b in bloques) {
      for (i in seq_along(b)[-(1:4)]) {
        if (!nzchar(b[[i]])) next
        tmp <- tempfile(fileext = ".webp")
        writeBin(jsonlite::base64_dec(b[[i]]), tmp)
        im <- rast(tmp)
        # alfa: 255 donde esta la clase. OJO: el WebP no trae georreferencia y terra lo lee
        # dado vuelta (fila 1 abajo; comprobado contra PIL el 2026-11-17), asi que se rearma
        # desde la matriz invertida, con la caja del bloque
        m <- as.matrix(im[[nlyr(im)]], wide = TRUE)
        a <- rast(ifelse(m[nrow(m):1, , drop = FALSE] > 0, i - 4, NA), crs = MERC,
                  extent = ext(6378137 * b[[2]] * pi / 180, 6378137 * b[[4]] * pi / 180, merc(b[[1]]), merc(b[[3]])))
        a <- resample(a, plantilla, method = "near")
        out <- cover(a, out)
        unlink(tmp)
      }
    }
    ifel(is.na(out), 0, out)
  }
  capa(d$b) + 4 * capa(d$c) + 16 * capa(d$k)
}


png_rgb <- function(r, archivo, tipo = "PNG", ...) {
  # escribe 3 bandas de 0-255 sin georreferencia (el visor usa los limites de indice.json)
  names(r) <- c("r", "g", "b")
  tmp <- tempfile(fileext = if (tipo == "PNG") ".png" else ".jpg")
  writeRaster(r, tmp, filetype = tipo, datatype = "INT1U", overwrite = TRUE, NAflag = NA, ...)
  file.copy(tmp, archivo, overwrite = TRUE)
  unlink(c(tmp, paste0(tmp, ".aux.xml")))
}


parches_png <- function(slug, x, plantilla, dir) {
  # parches_<anio>.png para el visor de cuatro ciudades (paso 18): R = clase del parche con
  # D = 100 + 8 * clase con D = 200, G = clase con D = 400 (0 no interior, 1-6 tamano, 7 agua),
  # B = % construido en 150 m de los pixeles construidos (codigos 1 y 3; paso 16; 0 en el resto),
  # que ordena que construido se conserva cuando la regla 3 recorta un radio
  hechos <- integer(0)
  for (a in ANIOS) {
    fp <- file.path(RPIPE, "outputs", "parches", slug, sprintf("parches_%d.tif", a))
    fr <- file.path(REGLAS, slug, sprintf("reglas_%d.tif", a))
    if (!file.exists(fp) || !file.exists(fr)) next
    p <- rast(fp); rr <- rast(fr); code <- x[[as.character(a)]]$code
    sol <- ifel(code == 1 | code == 3, rr$share, 0)
    r <- project(c(p$d100 + 8 * p$d200, p$d400, sol), plantilla, method = "near")
    r <- ifel(is.na(r), 0, r)
    png_rgb(r, file.path(dir, sprintf("parches_%d.png", a)), "PNG", gdal = "ZLEVEL=9")
    hechos <- c(hechos, a)
  }
  hechos
}


bordes_png <- function(slug, x, plantilla, dir) {
  # bordesa/b/c_<anio>.png para la pestana Reglas (paso 18, bordes2_<anio>.tif, version 2).
  # Clases de parche de 4 bits (0 no interior, 1-9 tamano, 15 agua) para D = 0, 50, ..., 500:
  #   a = R * 65536 + G * 256 + B: D 0-250 (d0 en los bits 0-3)
  #   b = lo mismo para D 300-500
  #   c: R = distancia al borde en clases de 50 m, 0-10, tope 10 (solo en la ciudad)
  #        + 16 * hueco (indice 0-12 de GAP_M del paso 18)
  hechos <- integer(0)
  for (a in ANIOS) {
    fb <- file.path(RPIPE, "outputs", "parches", slug, sprintf("bordes2_%d.tif", a))
    fr <- file.path(REGLAS, slug, sprintf("reglas_%d.tif", a))
    if (!file.exists(fb) || !file.exists(fr)) next
    bo <- rast(fb); rr <- rast(fr); code <- x[[as.character(a)]]$code
    ciudad <- code == 1 | code == 2
    d50 <- ifel(ciudad, min(rr$dist %/% 50, 10), 0)
    va <- bo$d0; vb <- bo$d300
    for (j in 1:5) va <- va + bo[[paste0("d", 50 * j)]] * 16^j
    for (j in 1:4) vb <- vb + bo[[paste0("d", 300 + 50 * j)]] * 16^j
    vc <- d50 + 16 * bo$hueco
    for (n in c("a", "b", "c")) {
      v <- switch(n, a = va, b = vb, c = vc)
      r <- project(c(v %/% 65536, (v %/% 256) %% 256, v %% 256), plantilla, method = "near")
      r <- ifel(is.na(r), 0, r)
      png_rgb(r, file.path(dir, sprintf("bordes%s_%d.png", n, a)), "PNG", gdal = "ZLEVEL=9")
    }
    hechos <- c(hechos, a)
  }
  hechos
}


una <- function(slug) {
  t0 <- Sys.time()
  x <- cargar_densidad(RPIPE, slug)
  dir <- file.path(SAL, slug); dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  plantilla <- project(x[["2020"]]$code, MERC, method = "near")
  radios <- list(); landsat <- integer(0)
  for (a in ANIOS) {
    y <- x[[as.character(a)]]
    # R = codigo de 11 + 4 * clase de distancia al borde + 16 * hueco + 64 * clase de share (16)
    rr <- file.path(REGLAS, slug, sprintf("reglas_%d.tif", a))
    r <- y$code
    if (file.exists(rr)) {
      rr <- rast(rr)
      dcl <- (rr$dist > 100) + (rr$dist > 200) + (rr$dist > 400)
      scl <- (rr$share >= 60) + (rr$share >= 70) + (rr$share >= 80)
      r <- ifel(y$code == 2, y$code + 4 * dcl + 16 * rr$hueco + 64 * scl, y$code)
    }
    code <- project(r, plantilla, method = "near")
    rid <- project(rasterize(y$v, y$code, field = "i"), plantilla, method = "near")
    code <- ifel(is.na(code), 0, code); rid <- ifel(is.na(rid), 0, rid)
    if (global(rid, "max")[[1]] > 65535) stop("mas de 65535 radios en el marco")
    png_rgb(c(code, rid %/% 256, rid %% 256), file.path(dir, sprintf("clase_%d.png", a)), "PNG", gdal = "ZLEVEL=9")

    t <- y$t[order(y$t$i_fila), ]
    radios[[as.character(a)]] <- list(censo = CENSO[[as.character(a)]], ciudad_km2 = round(y$ciudad_km2, 3),
      cod = I(t$cod), personas = I(t$personas), construido = I(round(t$km2_construido, 4)), abierto = I(round(t$km2_abierto, 4)),
      area = I(round(t$km2_radio, 4)), dens = I(ifelse(is.na(t$dens_urb), -1, round(t$dens_urb, 1))),
      viv = I(ifelse(is.na(t$viviendas), -1, t$viviendas)))

    # los radios como poligonos: recortados al marco, simplificados a 4 m, en grados con 5
    # decimales (~1 m); solo el campo i, que apunta a la fila de radios.json
    v <- simplifyGeom(crop(y$v[, "i"], ext(y$code)), tolerance = 4, preserveTopology = TRUE)
    v <- project(v[!is.empty(v), ], "EPSG:4326")
    tmp <- tempfile(fileext = ".geojson")
    writeVector(v, tmp, filetype = "GeoJSON", options = c("COORDINATE_PRECISION=5", "RFC7946=YES"))
    file.copy(tmp, file.path(dir, sprintf("radios_%d.geojson", a)), overwrite = TRUE); unlink(tmp)

    f <- file.path(LANDSAT, slug, sprintf("landsat_%d.tif", a))
    if (file.exists(f)) {
      l <- project(rast(f)[[c("red", "green", "blue")]], plantilla, method = "bilinear")
      q <- global(l, quantile, probs = c(0.02, 0.98), na.rm = TRUE)
      l <- rast(lapply(1:3, function(b) {
        v <- (l[[b]] - q[b, 1]) / (q[b, 2] - q[b, 1])
        round(255 * clamp(v, 0, 1)^0.85)
      }))
      l <- ifel(is.na(l), 250, l)
      png_rgb(l, file.path(dir, sprintf("landsat_%d.jpg", a)), "JPEG", gdal = "QUALITY=82")
      landsat <- c(landsat, a)
    }
  }
  jsonlite::write_json(radios, file.path(dir, "radios.json"), auto_unbox = TRUE, digits = NA)

  # MapBiomas 2020 (paso 17) contra la ciudad de 2020: R = clase de la comparacion (1 urbano en los
  # dos, 2 construido GISD30 que MapBiomas llama cultivo, 3 construido GISD30 con otra cobertura,
  # 4 urbano MapBiomas sobre franja, 5 urbano MapBiomas fuera de la ciudad), G = codigo de MapBiomas
  f_mb <- file.path(RPIPE, "outputs", "mapbiomas", slug, "mapbiomas_2020.tif")
  mapbiomas <- file.exists(f_mb)
  if (mapbiomas) {
    mb <- rast(f_mb); cd <- x[["2020"]]$code
    urb <- mb == 24; cult <- mb %in% c(9, 15, 19, 21, 36)
    cl <- ifel(cd == 1, ifel(urb, 1, ifel(cult, 2, 3)), ifel(urb, ifel(cd == 2, 4, 5), 0))
    cl <- project(c(cl, mb), plantilla, method = "near")
    cl <- ifel(is.na(cl), 0, cl)
    png_rgb(c(cl[[1]], cl[[2]], cl[[1]] * 0), file.path(dir, "mapbiomas_2020.png"), "PNG", gdal = "ZLEVEL=9")
  }

  parches <- parches_png(slug, x, plantilla, dir)
  bordes <- bordes_png(slug, x, plantilla, dir)

  # las manchas de Pedro para los cuatro censos (ver pedro_mb)
  pedro <- integer(0)
  for (a in ANIOS) {
    p <- pedro_mb(caja_de(RPIPE, slug)$contorno, CENSO[[as.character(a)]], plantilla)
    if (is.null(p)) next
    png_rgb(c(p, p * 0, p * 0), file.path(dir, sprintf("pedro_mb_%d.png", a)), "PNG", gdal = "ZLEVEL=9")
    pedro <- c(pedro, a)
  }

  e <- as.vector(ext(plantilla))
  esq <- project(vect(rbind(c(e[["xmin"]], e[["ymin"]]), c(e[["xmax"]], e[["ymax"]])), crs = MERC), "EPSG:4326")
  esq <- crds(esq)
  cont <- simplifyGeom(contorno_de(RPIPE, slug), tolerance = 0.0005)
  tmp <- tempfile(fileext = ".geojson"); writeVector(cont[, 0], tmp, filetype = "GeoJSON")
  cat(sprintf("  %-22s %s x %s px, landsat %s (%.1f min)\n", slug, ncol(plantilla), nrow(plantilla),
              if (length(landsat)) paste(landsat, collapse = ",") else "no",
              as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  list(slug = slug, nombre = x$nombre, ancho = ncol(plantilla), alto = nrow(plantilla),
       limites = list(c(esq[1, 2], esq[1, 1]), c(esq[2, 2], esq[2, 1])), landsat = I(landsat), mapbiomas = mapbiomas, pedro_mb = I(pedro), parches = I(parches), bordes = I(bordes),
       perimetro = jsonlite::fromJSON(tmp, simplifyVector = FALSE))
}


dir.create(SAL, recursive = TRUE, showWarnings = FALSE)
f_ind <- file.path(SAL, "indice.json")

if ("--solo-bordes" %in% args) {
  # solo los bordes<a|b>_<anio>.png (paso 18); marca el indice
  ind <- jsonlite::read_json(f_ind)
  for (s in CIUDADES) {
    x <- cargar_densidad(RPIPE, s)
    plantilla <- project(x[["2020"]]$code, MERC, method = "near")
    h <- bordes_png(s, x, plantilla, file.path(SAL, s))
    for (k in seq_along(ind$ciudades)) if (ind$ciudades[[k]]$slug == s) ind$ciudades[[k]]$bordes <- I(h)
    cat(sprintf("  %-22s bordes %s
", s, paste(h, collapse = ",")))
  }
  jsonlite::write_json(ind, f_ind, auto_unbox = TRUE, digits = NA)
  quit(save = "no")
}

if ("--solo-parches" %in% args) {
  # solo los parches_<anio>.png (paso 18) y las viviendas de radios.json, sin rehacer el resto;
  # marca el indice
  ind <- jsonlite::read_json(f_ind)
  for (s in CIUDADES) {
    x <- cargar_densidad(RPIPE, s)
    plantilla <- project(x[["2020"]]$code, MERC, method = "near")
    h <- parches_png(s, x, plantilla, file.path(SAL, s))
    # viviendas por radio (tope de la regla 3 del visor) en el radios.json existente
    fr <- file.path(SAL, s, "radios.json"); rj <- jsonlite::read_json(fr)
    for (a in ANIOS) {
      t <- x[[as.character(a)]]$t; t <- t[order(t$i_fila), ]
      rj[[as.character(a)]]$viv <- I(ifelse(is.na(t$viviendas), -1, t$viviendas))
    }
    jsonlite::write_json(rj, fr, auto_unbox = TRUE, digits = NA)
    for (k in seq_along(ind$ciudades)) if (ind$ciudades[[k]]$slug == s) ind$ciudades[[k]]$parches <- I(h)
    cat(sprintf("  %-22s parches %s\n", s, paste(h, collapse = ",")))
  }
  jsonlite::write_json(ind, f_ind, auto_unbox = TRUE, digits = NA)
  quit(save = "no")
}

cat(sprintf("Datos del visor · %d aglomerados\n", length(CIUDADES)))
nuevas <- lapply(CIUDADES, function(s) tryCatch(una(s), error = function(e) {
  cat("  ERROR", s, ":", conditionMessage(e), "\n"); NULL }))
names(nuevas) <- CIUDADES
ind <- if (file.exists(f_ind)) jsonlite::read_json(f_ind) else list(ciudades = list())
previas <- setNames(ind$ciudades, vapply(ind$ciudades, `[[`, "", "slug"))
for (s in names(nuevas)) if (!is.null(nuevas[[s]])) previas[[s]] <- nuevas[[s]]
previas <- previas[order(vapply(previas, `[[`, "", "nombre"))]
jsonlite::write_json(list(generado = format(Sys.Date()), anios = ANIOS, censos = unname(CENSO),
                          ciudades = unname(previas)), f_ind, auto_unbox = TRUE, digits = NA)
cat("Escrito", f_ind, "\n")
