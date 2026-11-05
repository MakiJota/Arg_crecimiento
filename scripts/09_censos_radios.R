# -*- coding: utf-8 -*-
# Paso 09 · Radios censales 1991, 2001, 2010 y 2022 con personas, hogares y viviendas.
# Traduce a R lo que hace el proyecto en scripts/ag_0_censos.py (descarga), ag_2_radios.py
# (personas) y ag_56_allegamiento.py (hogares y viviendas), con sus mismas definiciones.
#
# FUENTE. La cartografia censal por radio de CEUR-CONICET (handle 11336/149711),
# reempaquetada por Nissim Lebovits en Source Cooperative (CC BY 4.0), repo
# nlebovits/censo-argentino. Por anio: radios.parquet (poligonos, GeoParquet WKB, lon/lat
# WGS84) y census-data.parquet (tabulados por radio). Se baja del endpoint S3 path-style,
# como ag_0_censos.py, porque data.source.coop tuvo el certificado roto. NO es INDEC: toda
# cifra tiene que poder rehacerse contra INDEC.
#
# DEFINICIONES (las del proyecto, verificadas contra INDEC y DGEyC-CABA alli):
#            personas                      hogares                     viviendas (total)   viv_habitadas
#   1991     suma de PERSONA_SEXO          suma de HOGAR_TIPOH         B_VIV_TOT del radio  VIVIENDA_DESTINO = 1
#   2001     suma de PERSONA_P2            suma de VIVIENDA_CANTHOG    VIV_TOT del radio    VIVIENDA_CANTHOG >= 1
#                                          x cantidad (>= 1)
#   2010     B_POB_TOT del radio           REDATAM (ver abajo)         B_VIV_TOT del radio  REDATAM (ver abajo)
#   2022     POB_TOT_P del radio           suma de HOGAR_NHOGH         VIV_TOT_P del radio  HOGAR_NHOGH = 1
# - viviendas: todas (particulares y colectivas, habitadas o no). viv_habitadas: con
#   moradores presentes, que es la que se usa para hogares por vivienda.
# - 2010, hogares y viv_habitadas: el tabulado 2010 de esta fuente es la MUESTRA del
#   cuestionario ampliado y no sirve para totales. El proyecto los toma del cuestionario
#   basico de REDATAM (5_fuentes_crudas/censo2010_redatam_html.tar.gz, en el OneDrive):
#   hogares = suma de la tenencia (hog_<prov>.html), viv_habitadas = suma de la calidad de
#   los materiales (viv_<prov>.html). Si se pasa --redatam2010 <tar.gz> se leen de ahi;
#   si no, quedan NA.
# - TRAMPA DE 1991: el tabulado numera las provincias en un orden propio (01 = Salta);
#   el codigo del radio se arma traduciendo el NOMBRE de la provincia al codigo INDEC.
#   Aun asi, 128 codigos del tabulado de 1991 no tienen poligono en la cartografia (96 en
#   la provincia de Buenos Aires): sus personas quedan fuera de la capa y se informan en
#   totales.csv (personas_sin_poligono). Lo mismo se mide en 2001.
# - 2022: POB_TOT_P queda 0,93 % debajo del total INDEC; el deficit esta en la fuente.
# - B_POB_TOT + A_POB_TOT DUPLICA la poblacion: son dos estimaciones del total, no partes.
#
# SALIDAS
#   raw/censos/<anio>/{radios,census-data,metadata}.parquet   las descargas (~500 MB)
#   outputs/censos/radios_censos.gpkg   una capa por censo: radios_1991, radios_2001,
#       radios_2010, radios_2022. Campos: cod, prov, depto, fracc, radio, personas,
#       hogares, viviendas, viv_habitadas, km2 (POSGAR 2007 / Argentina 3, EPSG:5347).
#       Poligonos en EPSG:4326, como vienen.
#   outputs/censos/totales.csv          totales del pais por censo, con el de INDEC al lado
#
# Uso: Rscript Rpipe/scripts/09_censos_radios.R [--anios 1991,2001,2010,2022]
#        [--redatam2010 <ruta a censo2010_redatam_html.tar.gz>] [--sin-descarga]

Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))
options(warn = 1)
suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(sf)
  library(curl)
})

script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
RPIPE <- normalizePath(file.path(dirname(script), ".."), winslash = "/")
RAW <- file.path(RPIPE, "raw", "censos")
SAL <- file.path(RPIPE, "outputs", "censos")
GPKG <- file.path(SAL, "radios_censos.gpkg")

args <- commandArgs(trailingOnly = TRUE)
arg <- function(nombre, defecto) {
  i <- match(nombre, args)
  if (is.na(i) || i == length(args)) defecto else args[i + 1]
}
ANIOS <- strsplit(arg("--anios", "1991,2001,2010,2022"), ",")[[1]]
REDATAM <- arg("--redatam2010", "")
SIN_DESCARGA <- "--sin-descarga" %in% args

BUCKET <- "https://s3.us-west-2.amazonaws.com/us-west-2.opendata.source.coop/nlebovits/censo-argentino"
ARCHIVOS <- c("radios.parquet", "census-data.parquet", "metadata.parquet")
# totales de poblacion INDEC y radios esperados (los mismos controles de ag_2_radios.py)
INDEC_PERSONAS <- c("1991" = 32615528, "2001" = 36260130, "2010" = 40117096, "2022" = 46044703)
RADIOS_ESPERADOS <- c("1991" = 40099, "2001" = 46582, "2010" = 52406, "2022" = 66502)
CRS_METRICO <- 5347

# codificacion INDEC de provincia, para traducir el tabulado de 1991
PROV_INDEC <- c(
  "buenos aires" = "06", "ciudad autonoma de buenos aires" = "02", "catamarca" = "10",
  "chaco" = "22", "chubut" = "26", "cordoba" = "14", "corrientes" = "18",
  "entre rios" = "30", "formosa" = "34", "jujuy" = "38", "la pampa" = "42",
  "la rioja" = "46", "mendoza" = "50", "misiones" = "54", "neuquen" = "58",
  "rio negro" = "62", "salta" = "66", "san juan" = "70", "san luis" = "74",
  "santa cruz" = "78", "santa fe" = "82", "santiago del estero" = "86",
  "tierra del fuego" = "94", "tucuman" = "90")
sin_tildes <- function(x) trimws(tolower(chartr("áéíóúüñÁÉÍÓÚÜÑ", "aeiouunAEIOUUN", enc2utf8(x))))


# ---- descarga ----------------------------------------------------------------------

descargar <- function() {
  for (y in ANIOS) for (f in ARCHIVOS) {
    dir.create(file.path(RAW, y), recursive = TRUE, showWarnings = FALSE)
    destino <- file.path(RAW, y, f)
    url <- file.path(BUCKET, y, f)
    esperado <- as.numeric(curl_fetch_memory(url, handle = new_handle(nobody = TRUE))$headers |>
                             parse_headers_list() |> (\(h) h[["content-length"]])())
    if (file.exists(destino) && file.size(destino) == esperado) next
    for (intento in 1:4) {
      r <- tryCatch(multi_download(url, destino, resume = TRUE, progress = FALSE),
                    error = function(e) data.frame(success = FALSE))
      if (isTRUE(r$success[1]) && file.size(destino) == esperado) break
      Sys.sleep(3 * intento)
    }
    if (file.size(destino) != esperado) stop("no se pudo bajar ", url, call. = FALSE)
    cat(sprintf("  bajado %s/%s (%.1f MB)\n", y, f, esperado / 1e6))
  }
}


# ---- lectura -----------------------------------------------------------------------

radios <- function(y) {
  # poligonos del censo como sf (EPSG:4326) con cod, prov, depto, fracc, radio y lo que
  # el radio trae de personas y viviendas
  f <- file.path(RAW, y, "radios.parquet")
  t <- read_parquet(f, as_data_frame = FALSE)
  geo <- jsonlite::fromJSON(t$metadata$geo)$primary_column
  crs <- jsonlite::fromJSON(t$metadata$geo)$columns[[geo]]$crs
  if (!is.null(crs)) stop(y, ": el GeoParquet declara un CRS; revisar antes de asumir 4326", call. = FALSE)
  cod <- paste0("COD_", y)
  extra <- intersect(names(t), c("B_POB_TOT", "B_VIV_TOT", "VIV_TOT", "POB_TOT", "VIV_TOT_P", "POB_TOT_P"))
  d <- as.data.frame(t[, c(cod, "PROV", "DEPTO", "FRACC", "RADIO", extra)])
  names(d)[1:5] <- c("cod", "prov", "depto", "fracc", "radio")
  wkb <- t[[geo]]$as_vector()
  st_sf(d, geometry = st_as_sfc(structure(as.list(wkb), class = "WKB"), crs = 4326))
}

tabulado <- function(y, variables) {
  # filas del tabulado de esas variables, con el codigo del radio (cod) y la categoria
  # numerica (v)
  cols <- c("id_geo", "codigo_variable", "valor_categoria", "conteo")
  if (y == "1991") cols <- c(cols, "etiqueta_provincia", "valor_departamento", "valor_fraccion", "valor_radio")
  t <- open_dataset(file.path(RAW, y, "census-data.parquet")) |>
    filter(codigo_variable %in% variables) |> select(all_of(cols)) |> collect()
  if (y == "1991") {
    p <- PROV_INDEC[sin_tildes(t$etiqueta_provincia)]
    if (anyNA(p)) stop("1991: provincias sin traducir: ",
                       paste(unique(t$etiqueta_provincia[is.na(p)]), collapse = ", "), call. = FALSE)
    t$cod <- paste0(p, t$valor_departamento, t$valor_fraccion, t$valor_radio)
  } else {
    t$cod <- t$id_geo
  }
  t$v <- suppressWarnings(as.numeric(t$valor_categoria))
  t
}

suma <- function(t, filtro = TRUE, peso = 1) {
  # suma de conteo (por peso) por radio, para las filas que cumplen el filtro
  x <- t[filtro, ]
  w <- if (length(peso) == 1) peso else peso[filtro]
  tapply(x$conteo * w, x$cod, sum)
}

redatam_2010 <- function(tar) {
  # hogares y viviendas habitadas por radio del cuestionario basico 2010 (lo mismo que
  # redatam_2010() de ag_56): tras cada codigo de 9 digitos vienen primero las columnas
  # que importan, la tenencia (6) en hog_*.html y la calidad de los materiales (4) en
  # viv_*.html
  tmp <- tempfile("redatam_")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  todos <- untar(tar, list = TRUE)
  quiero <- todos[grepl("^(hog|viv)_\\d+\\.html$", basename(todos))]
  untar(tar, files = quiero, exdir = tmp)
  hog <- viv <- c()
  for (n in quiero) {
    s <- paste(readLines(file.path(tmp, n), encoding = "latin1", warn = FALSE), collapse = " ")
    s <- gsub("&[a-zA-Z#0-9]+;", " ", gsub("<[^>]+>", " ", s))
    tok <- strsplit(trimws(s), "\\s+")[[1]]
    k <- if (startsWith(basename(n), "hog")) 6 else 4
    for (i in which(grepl("^\\d{9}$", tok))) {
      sig <- tok[i + seq_len(k)]
      if (length(sig) == k && all(grepl("^\\d+$", sig))) {
        if (k == 6) hog[tok[i]] <- sum(as.numeric(sig)) else viv[tok[i]] <- sum(as.numeric(sig))
      }
    }
  }
  list(hog = hog, viv = viv)
}


# ---- un censo ----------------------------------------------------------------------

censo <- function(y) {
  cat(sprintf("\n%s\n", y))
  g <- radios(y)
  cuantos <- function(x) as.numeric(x[g$cod])
  # personas del tabulado en codigos que la cartografia no tiene: quedan fuera de la capa
  # y se informan (en 2010 y 2022 las personas vienen del propio poligono)
  sin_poligono <- function(per) sum(per[!(names(per) %in% g$cod)])
  fuera <- 0
  enganche <- NA
  if (y == "1991") {
    t <- tabulado(y, c("PERSONA_SEXO", "HOGAR_TIPOH", "VIVIENDA_DESTINO"))
    per <- suma(t, t$codigo_variable == "PERSONA_SEXO")
    g$personas <- cuantos(per)
    g$hogares <- cuantos(suma(t, t$codigo_variable == "HOGAR_TIPOH"))
    g$viviendas <- g$B_VIV_TOT
    g$viv_habitadas <- cuantos(suma(t, t$codigo_variable == "VIVIENDA_DESTINO" & t$v %in% 1))
    enganche <- mean(g$cod %in% names(per))
    fuera <- sin_poligono(per)
  } else if (y == "2001") {
    t <- tabulado(y, c("PERSONA_P2", "VIVIENDA_CANTHOG"))
    per <- suma(t, t$codigo_variable == "PERSONA_P2")
    g$personas <- cuantos(per)
    ch <- t$codigo_variable == "VIVIENDA_CANTHOG" & t$v >= 1 & !is.na(t$v)
    g$hogares <- cuantos(suma(t, ch, peso = t$v))
    g$viviendas <- g$VIV_TOT
    g$viv_habitadas <- cuantos(suma(t, ch))
    enganche <- mean(g$cod %in% names(per))
    fuera <- sin_poligono(per)
  } else if (y == "2010") {
    g$personas <- g$B_POB_TOT
    g$viviendas <- g$B_VIV_TOT
    if (nzchar(REDATAM)) {
      if (!file.exists(REDATAM)) stop("no esta ", REDATAM, call. = FALSE)
      r <- redatam_2010(REDATAM)
      g$hogares <- cuantos(r$hog)
      g$viv_habitadas <- cuantos(r$viv)
      enganche <- mean(g$cod %in% names(r$hog))
      # en REDATAM un radio sin hogares no aparece: es 0, no falta el dato
      g$hogares[is.na(g$hogares)] <- 0
      g$viv_habitadas[is.na(g$viv_habitadas)] <- 0
    } else {
      cat("  sin --redatam2010: hogares y viv_habitadas de 2010 quedan NA\n")
      g$hogares <- NA_real_
      g$viv_habitadas <- NA_real_
    }
  } else if (y == "2022") {
    t <- tabulado(y, "HOGAR_NHOGH")
    g$personas <- g$POB_TOT_P
    g$hogares <- cuantos(suma(t, t$v >= 1 & !is.na(t$v)))
    g$viviendas <- g$VIV_TOT_P
    g$viv_habitadas <- cuantos(suma(t, t$v %in% 1))
    enganche <- mean(g$cod %in% t$cod)
  }
  # un radio que el tabulado no nombra no tiene personas, hogares ni viviendas: 0
  for (k in c("personas", "hogares", "viviendas", "viv_habitadas")) {
    if (!(y == "2010" && k %in% c("hogares", "viv_habitadas") && !nzchar(REDATAM)))
      g[[k]][is.na(g[[k]])] <- 0
  }
  g$km2 <- round(as.numeric(st_area(st_transform(st_make_valid(g), CRS_METRICO))) / 1e6, 4)
  g <- g[, c("cod", "prov", "depto", "fracc", "radio", "personas", "hogares", "viviendas",
             "viv_habitadas", "km2")]

  # controles
  if (nrow(g) != RADIOS_ESPERADOS[[y]])
    cat(sprintf("  AVISO  %d radios, se esperaban %d\n", nrow(g), RADIOS_ESPERADOS[[y]]))
  if (anyDuplicated(g$cod)) cat("  AVISO  codigos de radio repetidos\n")
  tot <- data.frame(censo = as.integer(y), radios = nrow(g), personas = sum(g$personas),
                    personas_indec = INDEC_PERSONAS[[y]],
                    dif_pct = round(100 * (sum(g$personas) / INDEC_PERSONAS[[y]] - 1), 3),
                    personas_sin_poligono = fuera,
                    hogares = sum(g$hogares), viviendas = sum(g$viviendas),
                    viv_habitadas = sum(g$viv_habitadas),
                    radios_con_tabulado_pct = round(100 * enganche, 2))
  with(tot, cat(sprintf("  %d radios  personas %s (INDEC %s, %+.3f %%)  hogares %s  viviendas %s  habitadas %s\n",
                        radios, format(personas, big.mark = ".", decimal.mark = ","), format(personas_indec, big.mark = ".", decimal.mark = ","),
                        dif_pct, format(hogares, big.mark = ".", decimal.mark = ","), format(viviendas, big.mark = ".", decimal.mark = ","),
                        format(viv_habitadas, big.mark = ".", decimal.mark = ","))))
  if (!is.na(enganche)) cat(sprintf("  radios que engancha el tabulado: %.2f %%\n", 100 * enganche))
  if (fuera > 0) cat(sprintf("  personas del tabulado en codigos sin poligono (fuera de la capa): %s\n",
                             format(fuera, big.mark = ".", decimal.mark = ",")))
  st_write(g, GPKG, layer = paste0("radios_", y), quiet = TRUE, delete_layer = TRUE)
  cat(sprintf("  capa radios_%s escrita\n", y))
  tot
}


# ---- principal ---------------------------------------------------------------------

dir.create(SAL, recursive = TRUE, showWarnings = FALSE)
if (!SIN_DESCARGA) descargar()
tot <- do.call(rbind, lapply(ANIOS, censo))
csv <- file.path(SAL, "totales.csv")
if (file.exists(csv)) {
  viejo <- read.csv(csv)
  tot <- rbind(viejo[!viejo$censo %in% tot$censo, ], tot)
}
write.csv(tot[order(tot$censo), ], csv, row.names = FALSE)
cat(sprintf("\nEscrito %s\nEscrito %s\n", GPKG, csv))
