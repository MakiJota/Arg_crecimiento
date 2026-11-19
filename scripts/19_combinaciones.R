# -*- coding: utf-8 -*-
# Paso 19 · Combinaciones de las reglas sobre las clases de Angel, por pixel, para varias ciudades
# y los cuatro anios: mapas y tablas para compararlas. Exploratorio: ningun numero es cifra del
# proyecto. Las reglas son las del visor de cuatro ciudades (docs/visor/cuatro.html) mas el tope
# por vivienda (regla 3A) discutido el 2026-11-19.
#
# Todas usan la franja del borde de 200 m (regla 1). Combinaciones:
#   A  GISD30 tal cual (clases de Angel, sin reglas)
#   B  percentiles: rellena parches interiores <= 2 ha en radios con densidad urbanizada >= p25;
#      recorta los radios con personas por km2 construido < p10 hasta personas / p10 km2,
#      sin tocar pixeles con >= 80 % construido en 150 m
#   C  B + rellena los huecos angostos (<= 60 m, cierre del paso 16) en los mismos radios
#   D  fisica, k = 1: relleno segun densidad (>= p50 parches <= 5 ha, p25-p50 <= 1 ha, < p25 nada)
#      + huecos <= 60 m en radios >= p25; tope de construido = viviendas x 1 pixel (900 m2) por radio
#   E  igual que D con k = 2 pixeles por vivienda
# El recorte (B-C) y el tope (D-E) conservan primero los pixeles con mas construido alrededor.
# Los percentiles son de cada ciudad y anio (tipo 7), sobre los radios con >= 10 % de su area en
# la ciudad. En D-E el tope vale para todo pixel construido del radio (codigos 1 y 3).
#
# ENTRADAS  outputs/densidad/<slug>/ (11), outputs/reglas/<slug>/ (16), outputs/parches/<slug>/ (18)
# SALIDAS   pruebas/combinaciones/REPORTE.md, img/, combinaciones.csv
#
# Uso: Rscript Rpipe/scripts/19_combinaciones.R [--ciudades salta,rosario]

Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"),
           PROJ_DATA = system.file("proj", package = "terra"),
           GDAL_DATA = system.file("gdal", package = "terra"))
options(warn = 1)
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
SCRIPTS <- normalizePath(dirname(script), winslash = "/")
RPIPE <- dirname(SCRIPTS)
source(file.path(SCRIPTS, "lib", "cajas.R"))
source(file.path(SCRIPTS, "lib", "pruebas.R"))
suppressPackageStartupMessages(library(data.table))

args <- commandArgs(trailingOnly = TRUE)
i <- match("--ciudades", args)
CIUDADES <- if (is.na(i)) c("salta", "rosario", "santa_rosa", "mendoza", "corrientes", "formosa") else
  strsplit(args[i + 1], ",")[[1]]
SAL <- file.path(RPIPE, "pruebas", "combinaciones"); IMG <- file.path(SAL, "img")
dir.create(IMG, recursive = TRUE, showWarnings = FALSE)
MIN_CIUDAD <- 0.10
COMB <- c(A = "A · GISD30 as is", B = "B · percentiles", C = "C · B + gaps <= 60 m",
          D = "D · dwelling cap, 1 px", E = "E · dwelling cap, 2 px")
# 0 fondo, 1 construido, 2 rellenado, 3 recortado, 4 franja del borde, 5 abierto interior, 6 construido fuera
PAL <- c("#ffffff", "#1f4e79", "#2a9d8f", "#f08a24", "#9ecae1", "#c7a4dd", "#f2c500")
LEY <- c("built-up (GISD30)", "filled (rule 2)", "trimmed (rule 3)", "edge ring (200 m)",
         "interior open kept", "built outside the city")

q7 <- function(x, p) if (length(x)) as.numeric(quantile(x, p / 100, type = 7, names = FALSE)) else NA


# ---------- una ciudad, un anio: clase por pixel para cada combinacion ----------
anio_ciudad <- function(y, rr, pa, a) {
  t <- as.data.table(y$t)
  t[, u := km2_construido + km2_abierto]
  ok <- t$u > 0 & t$u >= MIN_CIUDAD * t$km2_radio
  d25 <- q7(t$dens_urb[ok & !is.na(t$dens_urb)], 25)
  d50 <- q7(t$dens_urb[ok & !is.na(t$dens_urb)], 50)
  db <- t$personas / t$km2_construido
  d10 <- q7(db[ok & t$km2_construido > 0], 10)

  rid <- rasterize(y$v, y$code, field = "i")
  P <- data.table(code = values(y$code, mat = FALSE), share = values(rr$share, mat = FALSE),
                  hueco = values(rr$hueco, mat = FALSE), parche = values(pa$d200, mat = FALSE),
                  r = values(rid, mat = FALSE))
  P[, cell := .I]
  P[is.na(share), share := 0L]
  setkey(t, i_fila)
  P[, `:=`(dens = t$dens_urb[match(r, t$i_fila)], viv = t$viviendas[match(r, t$i_fila)],
           pers = t$personas[match(r, t$i_fila)], kmc = t$km2_construido[match(r, t$i_fila)])]
  px <- prod(res(y$code)) / 1e6

  base <- integer(nrow(P))
  base[P$code == 1] <- 1L; base[P$code == 3] <- 6L
  base[P$code == 2 & P$parche == 0] <- 4L; base[P$code == 2 & P$parche >= 1] <- 5L

  rellena <- function(maxcl_alta, maxcl_media, gaps, umbral_alto) {
    dens <- ifelse(is.na(P$dens), -1, P$dens)
    lim <- ifelse(dens >= umbral_alto, maxcl_alta, ifelse(dens >= d25, maxcl_media, 0))
    int <- P$code == 2 & P$parche >= 1 & P$parche <= 6
    int & (P$parche <= lim | (gaps & dens >= d25 & P$hueco >= 1 & P$hueco <= 2))
  }
  # recorte por piso de percentil: el radio conserva personas / d10 km2, primero share >= 80
  recorte_piso <- function() {
    B <- P[code == 1 & !is.na(r) & kmc > 0 & pers / kmc < d10, .(cell, r, share, pers)]
    if (!nrow(B)) return(integer(0))
    setorder(B, r, -share, cell)
    B[, n := seq_len(.N), by = r]
    B[, keep := share >= 80 | n <= floor(pers / d10 / px)]
    B$cell[!B$keep]
  }
  # tope por vivienda: el radio conserva a lo sumo viviendas x k pixeles construidos (1 y 3)
  recorte_tope <- function(k) {
    B <- P[code %in% c(1, 3) & !is.na(r) & !is.na(viv), .(cell, r, share, viv)]
    setorder(B, r, -share, cell)
    B[, n := seq_len(.N), by = r]
    B$cell[B$n > floor(B$viv * k)]
  }

  arma <- function(fill, quita) { z <- base; z[fill] <- 2L; z[quita] <- 3L; z }
  fillB <- rellena(3, 3, FALSE, d25); fillC <- rellena(3, 3, TRUE, d25)
  fillD <- rellena(4, 2, TRUE, d50)
  cortes <- recorte_piso()
  clases <- list(A = base, B = arma(fillB, cortes), C = arma(fillC, cortes),
                 D = arma(fillD, recorte_tope(1)), E = arma(fillD, recorte_tope(2)))

  pop <- sum(t$personas[t$u > 0])
  res <- rbindlist(lapply(names(clases), function(k) {
    z <- clases[[k]]; c1 <- P$code == 1
    b0 <- sum(c1) * px; fl <- sum(z == 2) * px; tr <- sum(z == 3 & c1) * px
    data.table(anio = a, comb = k, construido0 = b0, rellenado = fl, recortado = tr,
               construido1 = b0 + fl - tr, recortado_fuera = sum(z == 3 & P$code == 3) * px,
               franja = sum(z == 4) * px, abierto = sum(z == 5) * px, personas = pop,
               dens0 = pop / b0, dens1 = pop / (b0 + fl - tr),
               radios_rellenados = uniqueN(P$r[z == 2 & !is.na(P$r)]),
               radios_recortados = uniqueN(P$r[z == 3 & !is.na(P$r)]),
               radios_ciudad = sum(t$u > 0), p10 = d10, p25 = d25, p50 = d50)
  }))
  capas <- rast(lapply(clases, function(z) { r <- rast(y$code); values(r) <- z; r }))
  names(capas) <- names(clases)
  list(res = res, capas = capas)
}


# ---------- mapas ----------
panel <- function(r, titulo, cont, ext_) {
  plot(r, col = data.frame(value = 0:6, color = PAL), type = "classes", legend = FALSE, axes = FALSE,
       mar = c(0.2, 0.2, 2.4, 0.2), maxcell = 4e6, main = titulo, cex.main = 2, ext = ext_)
  lines(cont, col = "#1d1d1b", lwd = 1)
}
leyenda <- function() {
  par(fig = c(0, 1, 0, 1), oma = c(0, 0, 0, 0), mar = c(0, 0, 0, 0), new = TRUE)
  plot.new()
  legend("bottom", horiz = TRUE, bty = "n", border = NA, cex = 2.3, text.col = TINTA2, inset = 0.004,
         fill = PAL[-1], legend = LEY)
}
mapa_grilla <- function(archivo, capas, ext_, cont, titulo, filas) {
  w <- 3000; asp <- (ext_$ymax - ext_$ymin) / (ext_$xmax - ext_$xmin)
  h <- round(w / 5 * asp) * length(filas) + 60 * length(filas) + 260
  png(archivo, width = w, height = h, bg = FONDO)
  par(mfrow = c(length(filas), 5), oma = c(4, 0, 4, 0), bg = FONDO)
  for (a in filas) for (k in names(COMB)) panel(capas[[a]][[k]], paste0(a, " · ", COMB[[k]]), cont, ext_)
  mtext(titulo, outer = TRUE, cex = 2.6, font = 2, line = 1)
  leyenda(); dev.off()
}


# ---------- una ciudad ----------
una <- function(slug) {
  t0 <- Sys.time()
  x <- cargar_densidad(RPIPE, slug)
  out <- lapply(setNames(ANIOS, ANIOS), function(a) {
    y <- x[[as.character(a)]]
    rr <- rast(file.path(RPIPE, "outputs", "reglas", slug, sprintf("reglas_%d.tif", a)))
    pa <- rast(file.path(RPIPE, "outputs", "parches", slug, sprintf("parches_%d.tif", a)))
    anio_ciudad(y, rr, pa, a)
  })
  res <- rbindlist(lapply(out, `[[`, "res")); res[, `:=`(slug = slug, nombre = x$nombre)]
  capas <- lapply(out, `[[`, "capas")

  # marco: la ciudad 2020 mas 3 km
  c20 <- x[["2020"]]$code
  e <- ext(trim(ifel(c20 == 1 | c20 == 2, 1, NA))) + 3000
  mapa_grilla(file.path(IMG, paste0(slug, "_anios.png")), capas, e, x$cont,
              paste0(x$nombre, " · five combinations, four years (200 m edge ring)"), as.character(ANIOS))

  # detalle: ventana de 6 km donde mas cambia D en 1990
  z <- capas[["1990"]][["D"]]
  ch <- aggregate(z == 2 | z == 3, fact = 100, fun = "sum", na.rm = TRUE)
  m <- where.max(ch)[1, ]
  cx <- xFromCell(ch, m[["cell"]]); cy <- yFromCell(ch, m[["cell"]])
  ez <- ext(cx - 3000, cx + 3000, cy - 3000, cy + 3000)
  mapa_grilla(file.path(IMG, paste0(slug, "_detalle.png")), capas, ez, x$cont,
              paste0(x$nombre, " · 6 km detail where rules change most (1990 and 2020)"), c("1990", "2020"))
  cat(sprintf("  %-14s (%.1f min)\n", slug, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  res
}


cat(sprintf("Combinaciones de reglas · %d aglomerados\n", length(CIUDADES)))
R <- rbindlist(lapply(CIUDADES, una))
fwrite(R, file.path(SAL, "combinaciones.csv"))


# ---------- grafico: construido por anio y combinacion ----------
COLC <- c(A = "#8a8985", B = "#8db3dd", C = "#1f4e79", D = "#e0954a", E = "#9a4a10")
g <- ggplot(R, aes(anio, construido1, colour = comb)) + geom_line(linewidth = 0.7) + geom_point(size = 1.8) +
  facet_wrap(~nombre, scales = "free_y", ncol = 3) +
  scale_colour_manual(values = COLC, labels = COMB, name = NULL) +
  labs(x = NULL, y = "built-up km2 in the city", title = "Built-up by year under each combination", caption = PIE) + tema
guardar(g, IMG, "construido.png", w = 11, h = 6.5)
g <- ggplot(R, aes(anio, dens1, colour = comb)) + geom_line(linewidth = 0.7) + geom_point(size = 1.8) +
  facet_wrap(~nombre, scales = "free_y", ncol = 3) +
  scale_colour_manual(values = COLC, labels = COMB, name = NULL) +
  labs(x = NULL, y = "persons per km2 built", title = "Density on built-up under each combination", caption = PIE) + tema
guardar(g, IMG, "densidad.png", w = 11, h = 6.5)


# ---------- reporte ----------
L <- c("# Rule combinations on the Angel classes: six cities, four years", "",
       "Exploratory. No number here is a project figure. Generated by `scripts/19_combinaciones.R`; do not edit by hand.",
       "Bariloche is not one of the 31 agglomerations in the pipeline (no EPH outline, no tract table), so it is not here.", "",
       "## The combinations", "",
       "All keep open land within 200 m of the city edge as fringe (rule 1).", "",
       tabla(c("", "Rule 2 · fill interior open land", "Rule 3 · trim built-up"), list(
         c("A", "no", "no"),
         c("B", "patches <= 2 ha in tracts with urbanized density >= p25", "tracts below p10 of persons per km2 built keep persons / p10 km2"),
         c("C", "B + narrow gaps <= 60 m in the same tracts", "as B"),
         c("D", "density >= p50: patches <= 5 ha; p25-p50: <= 1 ha; below p25: none; + gaps <= 60 m from p25", "each tract keeps at most dwellings x 1 pixel (900 m2)"),
         c("E", "as D", "each tract keeps at most dwellings x 2 pixels (1,800 m2)"))), "",
       "- Percentiles are per city and year (type 7), over tracts with at least 10 % of their area in the city.",
       "- Trimming keeps the pixels with the most built-up within 150 m first, so solid clusters survive and scattered pixels go.",
       "- B and C never trim pixels with >= 80 % built-up around them. D and E have no such protection: the cap is the cap, and it also applies to built-up outside the city (yellow).",
       "- Water and its shore are never filled. The interior class and the gaps come from steps 16 and 18.", "",
       "## Across cities", "", "![built-up](img/construido.png)", "", "![density](img/densidad.png)", "")

ff <- function(v) f1(v)
crec <- R[anio %in% c(1990, 2020), .(c90 = construido1[anio == 1990], c20 = construido1[anio == 2020]), by = .(nombre, comb)]
crec[, tasa := tasa(c90, c20, 30)]
L <- c(L, "Annual growth of city built-up 1990-2020 (%):", "",
       tabla(c("City", names(COMB)), lapply(unique(crec$nombre), function(n)
         c(n, sprintf("%.2f", crec[nombre == n][match(names(COMB), comb)]$tasa)))), "")

L <- c(L, "## What the combinations imply", "",
  "Read with the growth table and the maps below; every figure is in the tables.", "",
  "1. **Filling (rule 2) is small everywhere.** It adds at most a few km2 per city. Gaps <= 60 m add about as much as the patch rule: the missed pixels form connected webs, not separate holes. Mendoza gains the most (the detail map shows its tree-lined blocks turning teal).",
  "2. **Trimming (rule 3) grows with the year, so the rules flatten growth.** In 1990 little is trimmed; in 2020 whole low-density belts go orange (Salta, Rosario, Mendoza). Every combination gives a lower 1990-2020 growth rate than GISD30 as is, except Formosa, where they are about equal. The rules correct the recent over-detection more than the 1990 under-detection.",
  "3. **The dwelling cap without protection (D, E) also trims solid blocks.** In the Salta 2020 detail a compact block is removed whole: a tract with few dwellings but a real built mass (industry, institutions, a new subdivision not yet occupied in 2022). B and C keep such pixels through the >= 80 % rule. A cap needs that protection, or a cluster-size one.",
  "4. **The cap does what the percentile cannot outside the city.** D and E trim scattered built-up outside the city (orange outside the perimeter in Salta's south), which B and C never touch. That is the arid-farmland problem.",
  "5. **k matters more than the type of rule.** In 2020 the 1-pixel cap (D) trims as much as the p10 floor or more in every city but Corrientes; in 1990 it trims less. The 2-pixel cap (E) always trims less than D, and in Mendoza 2020 its filling and trimming cancel out. Corrientes and Formosa move little under any combination.",
  "6. **Caveats.** Dwellings come from the census nearest the image year (1991 for 1990, 2022 for 2020). A tract trimmed in 2020 may have been built after 2022's count or be non-residential. Dwellings include unoccupied ones.", "")

for (s in CIUDADES) {
  r <- R[slug == s]; n <- r$nombre[1]
  L <- c(L, paste0("## ", n), "", sprintf("![%s years](img/%s_anios.png)", n, s), "",
         sprintf("![%s detail](img/%s_detalle.png)", n, s), "")
  for (a in ANIOS) {
    q <- r[anio == a]
    L <- c(L, sprintf("**%d** · %s persons in %s city tracts · p10 %s persons per km2 built · p25 / p50 urbanized density %s / %s", a,
                      f0(q$personas[1]), f0(q$radios_ciudad[1]), f0(q$p10[1]), f0(q$p25[1]), f0(q$p50[1])), "",
           tabla(c("", "GISD30 km2", "+ filled", "- trimmed", "= built-up km2", "trimmed outside", "edge ring", "interior open",
                   "persons / km2 built", "tracts filled", "tracts trimmed"),
                 lapply(seq_len(nrow(q)), function(j) with(q[j], c(comb, f1(construido0), f1(rellenado), f1(recortado),
                   f1(construido1), f1(recortado_fuera), f1(franja), f1(abierto), f0(dens1),
                   f0(radios_rellenados), f0(radios_recortados))))), "")
  }
}
writeLines(L, file.path(SAL, "REPORTE.md"), useBytes = TRUE)
cat("Listo:", file.path(SAL, "REPORTE.md"), "\n")
