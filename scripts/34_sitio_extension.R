# -*- coding: utf-8 -*-
# Paso 34 · Seccion "Extension del aglomerado" del sitio (docs/, Just the Docs). Exploratorio: ningun
# numero es cifra del proyecto. Va al repo Arg_crecimiento, como el sitio (08).
#
# Arma una coleccion de Jekyll (docs/_extension/) con su propio bloque en el panel de navegacion:
#   Metodos      los "Metodo, paso a paso" de los HALLAZGOS.md de 29, 30 y 33, mas el mapa combinado (31)
#   Aglomerados  una pagina por ventana (31 aglomerados + la de 100 km de Gran Buenos Aires), con la
#                comparacion de los metodos, y debajo cuatro paginas:
#                  1 · Localidades   comunidades por tiempo de viaje (29)
#                  2 · Calles        percolacion de intersecciones de calles (30)
#                  3 · Pixeles       percolacion del construido de MapBiomas (33)
#                  4 · Combinado     la ciudad de calles con las comunidades y con MapBiomas (31)
# El texto de cada pagina sale de las secciones de los HALLAZGOS.md y de los CSV de resumen: no hay
# numeros escritos a mano. Las imagenes pasan a WebP en docs/assets/extension/<slug>/.
# La configuracion de la coleccion esta en docs/_config.yml, que escribe el paso 08.
#
# ENTRADAS  outputs/od_aglomerados/ (29), outputs/percolacion/ (30, 31), outputs/percolacion_mb/ (33)
# SALIDAS   docs/_extension/*.md, docs/assets/extension/<slug>/*.webp
#
# Uso: Rscript Rpipe/scripts/34_sitio_extension.R

script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
RPIPE <- dirname(dirname(normalizePath(script, winslash = "/")))
OUT <- file.path(RPIPE, "outputs")
DOCS <- file.path(RPIPE, "docs")
COL <- file.path(DOCS, "_extension")
ASSETS <- file.path(DOCS, "assets", "extension")
FUENTES <- c(localidades = "od_aglomerados", calles = "percolacion", pixeles = "percolacion_mb")
ANCHO <- 1400

unlink(COL, recursive = TRUE); unlink(ASSETS, recursive = TRUE)
dir.create(COL, recursive = TRUE); dir.create(ASSETS, recursive = TRUE)
escribir <- function(lineas, f) writeLines(enc2utf8(lineas), file.path(COL, f), useBytes = TRUE)
leer <- function(f) readLines(f, encoding = "UTF-8", warn = FALSE)
fmt <- function(x) ifelse(is.na(x), "-", format(x, big.mark = ",", scientific = FALSE, trim = TRUE))
na_ <- function(x) ifelse(is.na(x), "> 2000", fmt(x))
yaml <- function(...) { x <- list(...); c("---", sprintf('%s: %s', names(x), unlist(x)), "---", "") }
q <- function(x) sprintf('"%s"', gsub('"', "'", x))

md <- lapply(FUENTES, function(f) leer(file.path(OUT, f, "HALLAZGOS.md")))
res_od <- read.csv(file.path(OUT, "od_aglomerados", "resumen.csv"), check.names = FALSE, encoding = "UTF-8")
res_c <- read.csv(file.path(OUT, "percolacion", "resumen.csv"), check.names = FALSE, encoding = "UTF-8")
res_p <- read.csv(file.path(OUT, "percolacion_mb", "resumen.csv"), check.names = FALSE, encoding = "UTF-8")
res_mb <- read.csv(file.path(OUT, "percolacion", "mapbiomas_resumen.csv"), check.names = FALSE, encoding = "UTF-8")
ORDEN <- res_od$slug


# ---- secciones de los md ------------------------------------------------------------------
bloque <- function(lineas, desde, hasta = "^## ") {
  # lineas de un "## titulo" hasta el proximo "## " (sin el titulo)
  i <- grep(desde, lineas)[1]
  if (is.na(i)) return(character(0))
  j <- grep(hasta, lineas); j <- j[j > i]
  lineas[(i + 1):(if (length(j)) j[1] - 1 else length(lineas))]
}
secciones <- function(lineas) {
  # "### nombre" de "## Por aglomerado": lista nombrada por el slug de sus imagenes
  cuerpo <- bloque(lineas, "^## Por aglomerado")
  ini <- grep("^### ", cuerpo)
  out <- list()
  for (k in seq_along(ini)) {
    fin <- if (k < length(ini)) ini[k + 1] - 1 else length(cuerpo)
    sec <- cuerpo[(ini[k] + 1):fin]
    img <- regmatches(sec, regexpr("\\]\\(([a-z0-9_]+)/", sec))
    slug <- if (length(img)) sub("\\]\\(([a-z0-9_]+)/", "\\1", img[1]) else NA
    if (!is.na(slug)) out[[slug]] <- sec
  }
  out
}
sec <- lapply(md, secciones)

# imagenes: png de outputs/<fuente>/<slug>/x.png -> docs/assets/extension/<slug>/<metodo>_x.webp
imagenes <- function(lineas, metodo) {
  patron <- "!\\[([^]]*)\\]\\(([a-z0-9_]+)/([^)]+)\\.png\\)"
  for (k in grep(patron, lineas)) {
    m <- regmatches(lineas[k], regexec(patron, lineas[k]))[[1]]
    src <- file.path(OUT, FUENTES[[metodo]], m[3], paste0(m[4], ".png"))
    nombre <- sprintf("%s_%s.webp", metodo, m[4])
    dst <- file.path(ASSETS, m[3], nombre)
    if (file.exists(src) && !file.exists(dst)) {
      dir.create(dirname(dst), showWarnings = FALSE)
      im <- magick::image_read(src)
      if (magick::image_info(im)$width > ANCHO) im <- magick::image_resize(im, as.character(ANCHO))
      magick::image_write(im, dst, format = "webp", quality = 80)
    }
    lineas[k] <- sprintf("![%s]({{ '/assets/extension/%s/%s' | relative_url }})", m[2], m[3], nombre)
  }
  lineas
}


# ---- Metodos ------------------------------------------------------------------------------
metodo <- function(lineas) {
  b <- bloque(lineas, "^## Metodo")
  b[!grepl("^Lectura:", b)]
}
combinado_txt <- bloque(md$calles, "^## Metodo")
combinado_txt <- grep("^8\\. \\*\\*Mapa final", combinado_txt, value = TRUE)
escribir(c(yaml(title = q("Métodos"), nav_order = 1),
  "# Extensión del aglomerado: métodos", "",
  paste("Cuatro maneras de discutir hasta dónde llega cada uno de los 31 aglomerados EPH y qué radios censales",
        "2022 le corresponden. Exploratorio: ningún número es cifra del proyecto."), "",
  "1. TOC", "{:toc}", "",
  "## 1 · Localidades: comunidades por tiempo de viaje", "", metodo(md$localidades), "",
  "## 2 · Calles: percolación de intersecciones", "", metodo(md$calles), "",
  "## 3 · Píxeles: percolación del construido de MapBiomas", "", metodo(md$pixeles), "",
  "## 4 · Combinado", "", sub("^8\\. ", "", combinado_txt), "",
  "## Limitaciones", "",
  bloque(md$calles, "^## Limitaciones"), bloque(md$pixeles, "^## Limitaciones")), "metodos.md")


# ---- Aglomerados --------------------------------------------------------------------------
nombre_de <- function(s) res_od$nombre[res_od$slug == s]
escribir(c(yaml(title = q("Aglomerados"), nav_order = 2, has_children = "true"),
  "# Aglomerados", "",
  "Una página por aglomerado (y la ventana de 100 km de Gran Buenos Aires), con cuatro subpáginas: 1 · Localidades, 2 · Calles, 3 · Píxeles y 4 · Combinado.", "",
  "| aglomerado | calles: d cubre 99% EPH | radios que agrega / quita (calles) | píxeles: d cubre 99% EPH | radios que agrega / quita (píxeles) | píxeles: d cubre 95% de la ciudad de calles |",
  "|---|---:|---:|---:|---:|---:|",
  vapply(ORDEN, function(s) {
    c_ <- res_c[res_c$slug == s, ]; p_ <- res_p[res_p$slug == s, ]
    pd <- read.csv(file.path(OUT, "percolacion", s, "radios_por_d.csv"))
    t <- if (nrow(c_) && !is.na(c_$d_cubre99)) pd[pd$d == c_$d_cubre99, ] else pd[0, ]
    sprintf("| [%s]({{ site.baseurl }}/extension/%s/) | %s | %s / %s | %s | %s / %s | %s |", nombre_de(s), s,
            if (nrow(c_)) na_(c_$d_cubre99) else "-",
            if (nrow(t)) fmt(t$radios_solo_perc) else "-", if (nrow(t)) fmt(t$radios_solo_eph) else "-",
            if (nrow(p_)) na_(p_$d_cubre99) else "-",
            if (nrow(p_)) fmt(p_$radios_solo_perc) else "-", if (nrow(p_)) fmt(p_$radios_solo_eph) else "-",
            if (nrow(p_)) na_(p_$d_cubre95_ciudad_calles) else "-")
  }, "")), "aglomerados.md")

sin <- function(x, patrones) x[!Reduce(`|`, lapply(patrones, grepl, x))]
for (k in seq_along(ORDEN)) {
  s <- ORDEN[k]; nm <- nombre_de(s)
  c_ <- res_c[res_c$slug == s, ]; p_ <- res_p[res_p$slug == s, ]; o_ <- res_od[res_od$slug == s, ]
  m_ <- res_mb[res_mb$slug == s, ]
  pd <- read.csv(file.path(OUT, "percolacion", s, "radios_por_d.csv"))
  t <- if (nrow(c_) && !is.na(c_$d_cubre99)) pd[pd$d == c_$d_cubre99, ] else pd[0, ]
  fila <- function(metodo, d, x) sprintf("| %s | %s | %s / %s | %s / %s | %s / %s |", metodo, d,
                                         fmt(x[1]), fmt(x[2]), fmt(x[3]), fmt(x[4]), fmt(x[5]), fmt(x[6]))
  tabla <- c("| método | d (m) | en los dos (radios / personas) | agrega (radios / personas) | quita (radios / personas) |",
             "|---|---:|---:|---:|---:|",
             if (nrow(t)) fila("2 · Calles, cubre 99% EPH", na_(c_$d_cubre99),
                               c(t$radios_los_dos, t$personas_los_dos, t$radios_solo_perc, t$personas_solo_perc,
                                 t$radios_solo_eph, t$personas_solo_eph)) else NULL,
             if (nrow(p_)) fila("3 · Píxeles, cubre 99% EPH", na_(p_$d_cubre99),
                                c(p_$radios_los_dos, p_$personas_los_dos, p_$radios_solo_perc, p_$personas_solo_perc,
                                  p_$radios_solo_eph, p_$personas_solo_eph)) else NULL)
  escribir(c(yaml(title = q(nm), parent = q("Aglomerados"), nav_order = k, has_children = "true"),
    sprintf("# %s", nm), "",
    if (nrow(o_) && o_$estado == "ok")
      sprintf(paste("**1 · Localidades.** %s sedes de gobierno local en el cuadrado de %s km; con Leiden (tau 15 min) forman",
                    "%s grupos y el de la sede central (%s) tiene %s."), o_$puntos, o_$lado_km,
              fmt(o_$grupos_leiden_tau15), o_$sede_central, fmt(o_$central_leiden_tau15))
    else sprintf("**1 · Localidades.** Menos de 2 sedes en el cuadrado de %s km: sin comunidades.", o_$lado_km), "",
    "**Radios 2022 respecto del perímetro EPH**, según el método:", "", tabla, "",
    if (nrow(p_) && !is.na(p_$radios_pix_y_calles))
      sprintf(paste("**Píxeles contra calles.** Lo construido cubre el 95%% del urbano de la ciudad de calles a d = %s m; a",
                    "d = %s m comparten %s radios, los píxeles agregan %s y la ciudad de calles tiene %s más."),
              na_(p_$d_cubre95_ciudad_calles), na_(p_$d_vs_calles), fmt(p_$radios_pix_y_calles),
              fmt(p_$radios_solo_pix), fmt(p_$radios_solo_calles)) else NULL, "",
    if (nrow(m_))
      sprintf(paste("**Lo construido (MapBiomas %d).** %s km² de urbano en el cuadrado: %s dentro del perímetro EPH y %s",
                    "dentro de la ciudad de calles."), m_$anio, fmt(m_$urbano_cuadrado_km2), fmt(m_$urbano_eph_km2),
              fmt(m_$urbano_ciudad_km2)) else NULL, ""), sprintf("%s.md", s))

  pagina <- function(titulo, orden, cuerpo, f)
    escribir(c(yaml(title = q(titulo), parent = q(nm), grand_parent = q("Aglomerados"), nav_order = orden),
               sprintf("# %s · %s", nm, sub("^[0-9] · ", "", titulo)), "", cuerpo), f)
  final <- c("^Mapa final", "mapa_final", "^Lo construido \\(MapBiomas")
  pagina("1 · Localidades", 1, imagenes(sec$localidades[[s]], "localidades"), sprintf("%s_1_localidades.md", s))
  pagina("2 · Calles", 2, imagenes(sin(sec$calles[[s]], final), "calles"), sprintf("%s_2_calles.md", s))
  pagina("3 · Píxeles", 3, if (is.null(sec$pixeles[[s]])) "Sin resultados de este método." else
           imagenes(sec$pixeles[[s]], "pixeles"), sprintf("%s_3_pixeles.md", s))
  comb <- sec$calles[[s]][Reduce(`|`, lapply(final, grepl, sec$calles[[s]]))]
  pagina("4 · Combinado", 4, c(
    "La ciudad por percolación de calles al d que cubre el 99% del aglomerado EPH, con las comunidades de localidades por tiempo de viaje y con lo construido de MapBiomas.", "",
    "**Radios 2022 respecto del perímetro EPH:**", "", tabla, "",
    unlist(lapply(comb, function(l) c(l, "")))) |> imagenes("calles"), sprintf("%s_4_combinado.md", s))
}
n_img <- length(list.files(ASSETS, recursive = TRUE))
cat(sprintf("docs/_extension: %d paginas; %d imagenes (%.1f MB)\n", length(list.files(COL)), n_img,
            sum(file.size(list.files(ASSETS, recursive = TRUE, full.names = TRUE))) / 1e6))
