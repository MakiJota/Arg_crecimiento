# -*- coding: utf-8 -*-
# Paso 32 · Publica un HALLAZGOS.md de outputs/ (que git ignora) en pruebas/ (que se versiona), para
# que se lea en el repo. Copia el md, las imagenes que cita y los CSV de resultados; las imagenes se
# pasan a WebP (GitHub las muestra) a lo sumo ANCHO px de ancho, para no inflar el repo, y el md se
# reescribe con esos nombres. No copia GeoPackages ni rasters: se rehacen con los pasos.
#
# ENTRADAS  outputs/<origen>/HALLAZGOS.md, sus imagenes, los CSV de CSVS
# SALIDAS   pruebas/<destino>/ con la misma estructura de carpetas
#
# Uso: Rscript Rpipe/scripts/32_publicar_hallazgos.R [--origen percolacion] [--destino percolacion]

script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
RPIPE <- dirname(dirname(normalizePath(script, winslash = "/")))
args <- commandArgs(trailingOnly = TRUE)
arg <- function(nombre, defecto) {
  i <- match(nombre, args)
  if (is.na(i) || i == length(args)) defecto else args[i + 1]
}
ORIGEN <- file.path(RPIPE, "outputs", arg("--origen", "percolacion"))
DESTINO <- file.path(RPIPE, "pruebas", arg("--destino", "percolacion"))
ANCHO <- 1400
CALIDAD <- 80
# CSV de resultados: los de la raiz de origen y, por aglomerado, estos
CSVS <- c("radios.csv", "radios_por_d.csv", "curva.csv", "comunidades.csv", "od_tiempo_min.csv", "od_pares.csv")

md <- readLines(file.path(ORIGEN, "HALLAZGOS.md"), encoding = "UTF-8")
patron <- "!\\[([^]]*)\\]\\(([^)]+\\.png)\\)"
imgs <- unique(unlist(regmatches(md, gregexpr(patron, md))))
imgs <- sub(patron, "\\2", imgs)
dir.create(DESTINO, recursive = TRUE, showWarnings = FALSE)
cat(sprintf("%s: %d imagenes\n", basename(ORIGEN), length(imgs)))
for (f in imgs) {
  dst <- file.path(DESTINO, sub("\\.png$", ".webp", f))
  dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
  im <- magick::image_read(file.path(ORIGEN, f))
  if (magick::image_info(im)$width > ANCHO) im <- magick::image_resize(im, as.character(ANCHO))
  magick::image_write(im, dst, format = "webp", quality = CALIDAD)
}
writeLines(enc2utf8(gsub("(!\\[[^]]*\\]\\([^)]+)\\.png\\)", "\\1.webp)", md)), file.path(DESTINO, "HALLAZGOS.md"),
           useBytes = TRUE)

n <- 0
for (f in list.files(ORIGEN, "\\.csv$")) { file.copy(file.path(ORIGEN, f), DESTINO, overwrite = TRUE); n <- n + 1 }
for (d in list.dirs(ORIGEN, recursive = FALSE)) for (f in CSVS) {
  src <- file.path(d, f)
  if (file.exists(src)) {
    dir.create(file.path(DESTINO, basename(d)), showWarnings = FALSE)
    file.copy(src, file.path(DESTINO, basename(d), f), overwrite = TRUE); n <- n + 1
  }
}
tam <- sum(file.size(list.files(DESTINO, recursive = TRUE, full.names = TRUE))) / 1e6
cat(sprintf("%d CSV; %s ocupa %.1f MB\n", n, DESTINO, tam))
