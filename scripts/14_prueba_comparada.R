# -*- coding: utf-8 -*-
# Paso 14 · Las pruebas 1 y 2 lado a lado, al mismo corte. Exploratoria: ningun numero es
# cifra del proyecto.
#
# A IGUAL CORTE T, LAS DOS PRUEBAS TRATAN IGUAL LA FRANJA (y el capturado): entra solo la
# de los radios con dens_urb >= T. Difieren en una sola cosa, lo construido de los radios
# por debajo del corte: la prueba 1 (paso 12) lo saca, la prueba 2 (paso 13) lo deja.
#     prueba 1(T) = construido y franja de los radios densos
#     prueba 2(T) = todo lo construido + franja de los radios densos
#     prueba 2(T) - prueba 1(T) = construido de los radios ralos
# El mapa pinta cada pixel de la ciudad de Angel segun en cual de las dos queda.
#
# ENTRADAS  outputs/densidad/<slug>/ (paso 11)
# SALIDAS   pruebas/comparacion/<slug>/REPORTE.md, img/comparado_<corte>.png, tablas/resultado.csv
#           pruebas/comparacion/REPORTE.md   indice y comparacion entre aglomerados
#
# Uso: Rscript Rpipe/scripts/14_prueba_comparada.R [--ciudades salta,jujuy] [--cortes 300,...]
#        [--cortes-mapa 500,3000,3500,4000] [--sin-mapas]

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
CORTES <- as.numeric(strsplit(arg("--cortes", "300,500,1000,2000,3000,3250,3500,3750,4000,4500,5000"), ",")[[1]])
CORTES_MAPA <- as.numeric(strsplit(arg("--cortes-mapa", "500,3000,3500,4000"), ",")[[1]])
SIN_MAPAS <- "--sin-mapas" %in% args
BASE <- file.path(RPIPE, "pruebas", "comparacion")
DENS <- file.path(RPIPE, "outputs", "densidad")
CIUDADES <- if (is.na(match("--ciudades", args))) {
  sort(basename(dirname(list.files(DENS, "^ciudad\\.csv$", recursive = TRUE, full.names = TRUE))))
} else strsplit(arg("--ciudades", ""), ",")[[1]]
C <- if (500 %in% CORTES) 500 else CORTES[1]
# mapa: fondo, construido en las dos, construido solo en la 2, franja en las dos, franja en ninguna, construido fuera
PAL <- c("#fcfcfb", "#1f4e79", "#c4622d", "#8db3dd", "#e3cbb3", "#cfcdc6")
LEYENDA <- c("built, dense tract: both tests", "built, sparse tract: test 2 only",
             "fringe/captured, dense tract: both tests", "fringe/captured, sparse tract: neither", "built outside the city")


una <- function(slug) {
  x <- cargar_densidad(RPIPE, slug)
  if (is.null(x)) { cat("  sin salida de 11:", slug, "\n"); return(NULL) }
  NOMBRE <- x$nombre
  dir <- file.path(BASE, slug); img <- file.path(dir, "img"); tab <- file.path(dir, "tablas")
  dir.create(img, recursive = TRUE, showWarnings = FALSE); dir.create(tab, showWarnings = FALSE)

  res <- do.call(rbind, lapply(ANIOS, function(a) {
    t <- x[[as.character(a)]]$t
    en <- t$km2_urb > 0
    do.call(rbind, lapply(CORTES, function(k) {
      d <- en & !is.na(t$dens_urb) & t$dens_urb >= k
      data.frame(anio = a, corte = k, angel_km2 = sum(t$km2_urb[en]),
                 construido_denso_km2 = sum(t$km2_construido[d]), construido_ralo_km2 = sum(t$km2_construido[en & !d]),
                 franja_densa_km2 = sum(t$km2_abierto[d]), franja_rala_km2 = sum(t$km2_abierto[en & !d]),
                 personas_densos = sum(t$personas[d]), personas = sum(t$personas[en]))
    }))
  }))
  res$prueba1_km2 <- res$construido_denso_km2 + res$franja_densa_km2
  res$prueba2_km2 <- res$prueba1_km2 + res$construido_ralo_km2
  res$pct_construido_ralo <- 100 * res$construido_ralo_km2 / (res$construido_denso_km2 + res$construido_ralo_km2)
  write.csv(res, file.path(tab, "resultado.csv"), row.names = FALSE)
  g <- function(a, k, col) res[[col]][res$anio == a & res$corte == k]
  crec <- function(k, col) tasa(g(1990, k, col), g(2020, k, col), 30)

  # ---- grafico: tamanio de la ciudad por corte, las dos pruebas, por anio
  largo <- rbind(data.frame(anio = factor(res$anio), corte = res$corte, prueba = "test 1 (built can leave)", km2 = res$prueba1_km2),
                 data.frame(anio = factor(res$anio), corte = res$corte, prueba = "test 2 (built always stays)", km2 = res$prueba2_km2))
  angel <- unique(res[, c("anio", "angel_km2")]); angel$anio <- factor(angel$anio)
  guardar(ggplot(largo, aes(corte, km2, colour = anio, linetype = prueba)) + geom_line(linewidth = 0.8) + geom_point(size = 1.8) +
    geom_hline(data = angel, aes(yintercept = angel_km2, colour = anio), linewidth = 0.3, linetype = "13") +
    scale_colour_manual(values = COL_ANIO) + scale_linetype_manual(values = c("22", "solid")) +
    scale_x_continuous(breaks = CORTES[CORTES != 3250 & CORTES != 3750], labels = f0) + scale_y_continuous(limits = c(0, NA), labels = f0) +
    labs(x = "Density cut (persons per km² urbanized)", y = "km²", colour = NULL, linetype = NULL,
         title = sprintf("%s · city size by cut, test 1 and test 2", NOMBRE),
         subtitle = "The gap between the two lines is built-up land in tracts below the cut. Dotted: the Angel extent",
         caption = PIE) + tema + theme(legend.box = "vertical"), img, "pruebas_por_corte.png", h = 6)

  # ---- mapas: un archivo por corte, un panel por anio
  if (!SIN_MAPAS) for (k in CORTES_MAPA) {
    capas <- rast(lapply(ANIOS, function(a) {
      y <- x[[as.character(a)]]
      ok <- marcar(rasterize(y$v, y$code, field = "i"), radios_con(y$t, k))
      ifel(y$code == 1, ifel(ok, 1, 2), ifel(y$code == 2, ifel(ok, 3, 4), ifel(y$code == 3, 5, 0)))
    }))
    tit <- vapply(ANIOS, function(a) sprintf("%d · test 1 %s km² · test 2 %s km²", a,
                                             f1(g(a, k, "prueba1_km2")), f1(g(a, k, "prueba2_km2"))), "")
    mapa_paneles(file.path(img, sprintf("comparado_%s.png", k)), capas, PAL, tit,
                 sprintf("%s · tests 1 and 2 at %s persons/km²", NOMBRE, f0(k)), LEYENDA, x$cont)
  }

  # ---- reporte
  L <- c(sprintf("# %s · tests 1 and 2 at the same cut, 1990-2020", NOMBRE), "",
    sprintf("Exploratory. None of these numbers are project figures (they are not in `CIFRAS_CANONICAS.json`). Generated by `Rpipe/scripts/14_prueba_comparada.R` from the tract tables of step 11. Run of %s. [All agglomerations](../REPORTE.md) · [test 1](../../densidad_radios/%s/REPORTE.md) · [test 2](../../franja_densa/%s/REPORTE.md) · [methods](../../METODOS.md).", format(Sys.Date()), slug, slug), "",
    "**At the same cut the two tests keep the same fringe and captured land**: that of the tracts at or above the cut. They differ only in the **built-up land of tracts below the cut**: test 1 drops it, test 2 keeps it. Test 2 minus test 1 is exactly that land.", "",
    "## City size by cut", "")
  for (a in ANIOS) {
    L <- c(L, sprintf("**%d (census %s).** Angel extent %s km².", a, CENSO[[as.character(a)]], f1(g(a, CORTES[1], "angel_km2"))), "",
      tabla(c("Cut (p/km²)", "Test 1 km²", "Test 2 km²", "Built in sparse tracts km² (test 2 only)", "% of built-up in sparse tracts",
              "Fringe in dense tracts km² (both)", "Fringe in sparse tracts km² (neither)"),
            lapply(CORTES, function(k) c(f0(k), f1(g(a, k, "prueba1_km2")), f1(g(a, k, "prueba2_km2")), f1(g(a, k, "construido_ralo_km2")),
                                         f1(g(a, k, "pct_construido_ralo")), f1(g(a, k, "franja_densa_km2")), f1(g(a, k, "franja_rala_km2"))))), "")
  }
  L <- c(L, "![City size by cut, both tests](img/pruebas_por_corte.png)", "", "## Growth 1990-2020 by cut", "",
    sprintf("Angel extent: %s %%/yr.", f2(tasa(g(1990, CORTES[1], "angel_km2"), g(2020, CORTES[1], "angel_km2"), 30))), "",
    tabla(c("Cut (p/km²)", "Test 1 %/yr", "Test 2 %/yr"),
          lapply(CORTES, function(k) c(f0(k), f2(crec(k, "prueba1_km2")), f2(crec(k, "prueba2_km2"))))), "")
  mapas <- CORTES_MAPA[file.exists(file.path(img, sprintf("comparado_%s.png", CORTES_MAPA)))]
  if (length(mapas)) {
    L <- c(L, "## Maps", "", "Same frame in the four years: the 2020 city plus 3 km. Dark blue and light blue are in both tests; orange is built-up in tracts below the cut, which only test 2 keeps; beige is fringe or captured land in tracts below the cut, which neither keeps. Black line: the analysis perimeter.", "")
    for (k in mapas) L <- c(L, sprintf("### %s persons/km²", f0(k)), "", sprintf("![Both tests at %s](img/comparado_%s.png)", f0(k), k), "")
  }
  writeLines(enc2utf8(L), file.path(dir, "REPORTE.md"), useBytes = TRUE)
  cat(sprintf("  %-22s listo\n", slug))
  data.frame(slug = slug, nombre = NOMBRE, angel_2020 = g(2020, C, "angel_km2"),
             p1_2020 = g(2020, C, "prueba1_km2"), p2_2020 = g(2020, C, "prueba2_km2"),
             ralo_1990 = g(1990, C, "pct_construido_ralo"), ralo_2020 = g(2020, C, "pct_construido_ralo"),
             tasa_angel = tasa(g(1990, C, "angel_km2"), g(2020, C, "angel_km2"), 30),
             tasa_p1 = crec(C, "prueba1_km2"), tasa_p2 = crec(C, "prueba2_km2"))
}


# ---- todas e indice ----------------------------------------------------------------

cat(sprintf("Pruebas 1 y 2 comparadas · %d aglomerados\n", length(CIUDADES)))
dir.create(BASE, recursive = TRUE, showWarnings = FALSE)
res <- do.call(rbind, lapply(CIUDADES, function(s) tryCatch(una(s), error = function(e) {
  cat("  ERROR", s, ":", conditionMessage(e), "\n"); NULL })))
res <- res[order(res$nombre), ]
write.csv(res, file.path(BASE, "resumen.csv"), row.names = FALSE)

img <- file.path(BASE, "img"); dir.create(img, showWarnings = FALSE)
largo <- rbind(data.frame(nombre = res$nombre, medida = "Angel extent", tasa = res$tasa_angel),
               data.frame(nombre = res$nombre, medida = sprintf("test 1 at %s", f0(C)), tasa = res$tasa_p1),
               data.frame(nombre = res$nombre, medida = sprintf("test 2 at %s", f0(C)), tasa = res$tasa_p2))
largo$medida <- factor(largo$medida, levels = unique(largo$medida))
largo$nombre <- factor(largo$nombre, levels = res$nombre[order(res$tasa_angel)])
guardar(ggplot(largo, aes(tasa, nombre, colour = medida)) + geom_point(size = 2.6) +
  scale_colour_manual(values = c("#0b0b0b", "#c4622d", "#1f4e79")) +
  labs(x = "% a year, 1990-2020", y = NULL, colour = NULL,
       title = sprintf("Growth of the city: Angel, test 1 and test 2 at %s p/km²", f0(C)), caption = PIE) + tema,
  img, "crecimiento.png", w = 9, h = 8)

ancla <- function(s) sprintf("[%s](%s/REPORTE.md)", res$nombre[res$slug == s], s)
L <- c("# Tests 1 and 2 side by side, all agglomerations", "",
  sprintf("Exploratory. None of these numbers are project figures (they are not in `CIFRAS_CANONICAS.json`). Generated by `Rpipe/scripts/14_prueba_comparada.R` from step 11. Run of %s. Both tests and how they differ: [METODOS.md](../METODOS.md).", format(Sys.Date())), "",
  "## Method", "",
  "- **Same cut, same fringe.** At a cut T both tests keep the fringe and captured land of tracts with density on urbanized land ≥ T, and drop the rest.",
  "- **The one difference** is built-up land in tracts below the cut: test 1 drops it, test 2 keeps it. Test 2 − test 1 = that land.",
  sprintf("- **Cuts**: %s persons/km². Maps at %s.", paste(f0(CORTES), collapse = ", "), paste(f0(CORTES_MAPA), collapse = ", ")), "",
  sprintf("## All agglomerations at %s p/km²", f0(C)), "",
  tabla(c("Agglomeration", "Angel 2020 km²", "Test 1 2020 km²", "Test 2 2020 km²", "% of built-up in sparse tracts 1990", "% in sparse tracts 2020",
          "Growth Angel %/yr", "Growth test 1 %/yr", "Growth test 2 %/yr"),
        lapply(res$slug, function(s) with(res[res$slug == s, ], c(ancla(s), f1(angel_2020), f1(p1_2020), f1(p2_2020), f1(ralo_1990), f1(ralo_2020),
          f2(tasa_angel), f2(tasa_p1), f2(tasa_p2))))), "",
  "![Growth: Angel, test 1 and test 2](img/crecimiento.png)", "",
  indice_mapas(BASE, res, c(map = "comparado_%s.png"), cols = CORTES_MAPA, cab = paste(f0(CORTES_MAPA), "p/km²"),
               nota = "Each map has the four years as panels."))
writeLines(enc2utf8(L), file.path(BASE, "REPORTE.md"), useBytes = TRUE)
cat("Escrito", file.path(BASE, "REPORTE.md"), "\n")
