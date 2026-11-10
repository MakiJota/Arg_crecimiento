# -*- coding: utf-8 -*-
# Paso 12 · Prueba 1: la mancha urbana con la densidad de los radios censales, 1990-2020.
# Exploratoria: ningun numero es cifra del proyecto. Generaliza a todos los aglomerados la
# prueba de Salta del 2026-11-08.
#
# LA PREGUNTA. La extension de Angel (construido + franja + capturado) cuenta como ciudad
# todo lo que se ve construido y su espacio abierto, viva gente o no. Si se queda solo la
# parte que cae en radios con densidad suficiente, ¿describe mejor la ciudad donde se vive?
#     dens_urb  = personas del radio / km2 de ciudad (construido + franja + capturado) en el radio
#     mancha(T) = la ciudad dentro de los radios con dens_urb >= T   (construido incluido:
#                 un radio por debajo del corte sale entero)
# Referencia "solo censo": radios enteros con densidad bruta (personas / km2 del radio) >= T.
# Cortes: 300, 500 y 1.000 hab/km2 (U_DENS del proyecto, scripts/rutas.py) y 2.000, 3.000,
# 3.250, 3.500, 3.750, 4.000, 4.500 y 5.000. Personas de la mancha = personas de sus radios enteros.
#
# ENTRADAS  outputs/densidad/<slug>/ (paso 11)
# SALIDAS   pruebas/densidad_radios/<slug>/REPORTE.md, img/, tablas/resultado.csv
#           pruebas/densidad_radios/REPORTE.md   indice y comparacion entre aglomerados
#
# Uso: Rscript Rpipe/scripts/12_prueba_densidad.R [--ciudades salta,jujuy] [--cortes 300,...]
#        [--sin-mapas]   sin --ciudades: todas las que tienen salida de 11

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
# entre 3.000 y 5.000 los cortes van mas finos: ahi es donde la mancha cambia de forma
CORTES <- as.numeric(strsplit(arg("--cortes", "300,500,1000,2000,3000,3250,3500,3750,4000,4500,5000"), ",")[[1]])
SIN_MAPAS <- "--sin-mapas" %in% args
BASE <- file.path(RPIPE, "pruebas", "densidad_radios")
DENS <- file.path(RPIPE, "outputs", "densidad")
CIUDADES <- if (is.na(match("--ciudades", args))) {
  sort(basename(dirname(list.files(DENS, "^ciudad\\.csv$", recursive = TRUE, full.names = TRUE))))
} else strsplit(arg("--ciudades", ""), ",")[[1]]
C <- if (500 %in% CORTES) 500 else CORTES[1]          # corte central del proyecto
# mapa: fondo, construido que queda, abierto que queda, construido que sale, abierto que
# sale, construido fuera de la ciudad
PAL <- c("#fcfcfb", "#1f4e79", "#8db3dd", "#c4622d", "#efb48f", "#cfcdc6")
etq <- function(k) ifelse(k == 0, "no cut", paste(f0(k), "p/km²"))


resumen_corte <- function(t, corte, ciudad_km2) {
  en <- t$km2_urb > 0
  queda <- en & !is.na(t$dens_urb) & t$dens_urb >= corte
  censo <- t$dens_bruta >= corte
  poco <- t$km2_urb / t$km2_radio < 0.1
  data.frame(anio = t$anio[1], censo = t$censo[1], corte = corte, ciudad_km2 = ciudad_km2,
             ciudad_radios = sum(en), ciudad_personas = sum(t$personas[en]),
             mancha_km2 = sum(t$km2_urb[queda]), mancha_construido_km2 = sum(t$km2_construido[queda]),
             mancha_abierto_km2 = sum(t$km2_abierto[queda]), mancha_radios = sum(queda),
             mancha_personas = sum(t$personas[queda]),
             sale_km2 = sum(t$km2_urb[en & !queda]), sale_personas = sum(t$personas[en & !queda]),
             censo_km2 = sum(t$km2_radio[censo]), censo_personas = sum(t$personas[censo]),
             censo_sin_huella_radios = sum(censo & poco), censo_sin_huella_personas = sum(t$personas[censo & poco]),
             mancha_poco_urb_km2 = sum(t$km2_urb[queda & poco]))
}


una <- function(slug) {
  x <- cargar_densidad(RPIPE, slug)
  if (is.null(x)) { cat("  sin salida de 11:", slug, "\n"); return(NULL) }
  NOMBRE <- x$nombre
  dir <- file.path(BASE, slug); img <- file.path(dir, "img"); tab <- file.path(dir, "tablas")
  dir.create(img, recursive = TRUE, showWarnings = FALSE); dir.create(tab, showWarnings = FALSE)

  r <- do.call(rbind, lapply(ANIOS, function(a) {
    y <- x[[as.character(a)]]
    do.call(rbind, lapply(c(0, CORTES), function(k) resumen_corte(y$t, k, y$ciudad_km2)))
  }))
  r$pct_area <- 100 * r$mancha_km2 / r$ciudad_km2
  r$pct_personas <- 100 * r$mancha_personas / r$ciudad_personas
  r$dens_mancha <- r$mancha_personas / r$mancha_km2
  r$pct_abierto <- 100 * r$mancha_abierto_km2 / r$mancha_km2
  r$etiqueta <- etq(r$corte)
  r$anio_f <- factor(r$anio)
  write.csv(r[, names(r) != "anio_f"], file.path(tab, "resultado.csv"), row.names = FALSE)
  g <- function(a, k, col) r[[col]][r$anio == a & r$corte == k]

  # ---- graficos
  ejes_corte <- scale_x_continuous(breaks = c(0, CORTES), labels = c("none", f0(CORTES)))
  guardar(ggplot(r, aes(corte, mancha_km2, colour = anio_f)) + geom_line(linewidth = 0.9) + geom_point(size = 2.4) +
    scale_colour_manual(values = COL_ANIO) + ejes_corte + scale_y_continuous(limits = c(0, NA), labels = f0) +
    labs(x = "Density cut (persons per km² of urbanized land in the tract)", y = "km²", colour = NULL,
         title = sprintf("%s · size of the urban patch by density cut", NOMBRE),
         subtitle = "Urban extent (built + fringe + captured) kept inside tracts at or above the cut", caption = PIE) + tema,
    img, "area_por_corte.png")
  guardar(ggplot(r, aes(pct_area, pct_personas, colour = anio_f)) +
    geom_abline(slope = 1, intercept = 0, colour = REJILLA, linewidth = 0.4) +
    geom_path(linewidth = 0.8) + geom_point(size = 2.4) +
    geom_text(data = r[r$anio == 2020, ], aes(label = ifelse(corte == 0, "none", f0(corte))),
              colour = TINTA2, size = 3, nudge_x = -2.5, nudge_y = 0.6) +
    scale_colour_manual(values = COL_ANIO) + coord_cartesian(xlim = c(min(r$pct_area) - 5, 101)) +
    labs(x = "% of the satellite urban extent kept", y = "% of the city's population kept", colour = NULL,
         title = sprintf("%s · what each cut costs", NOMBRE),
         subtitle = "Each point is a cut. Far from the diagonal = drops land, not people. Labels: cut in 2020",
         caption = PIE) + tema, img, "area_vs_personas.png")
  guardar(ggplot(r, aes(corte, dens_mancha, colour = anio_f)) + geom_line(linewidth = 0.9) + geom_point(size = 2.4) +
    scale_colour_manual(values = COL_ANIO) + ejes_corte + scale_y_continuous(limits = c(0, NA), labels = f0) +
    labs(x = "Density cut (persons per km² of urbanized land)", y = "persons per km²", colour = NULL,
         title = sprintf("%s · density of the resulting patch", NOMBRE),
         subtitle = "Persons of the kept tracts / km² of the kept patch", caption = PIE) + tema, img, "densidad_mancha.png")
  crec <- r; crec$etiqueta <- factor(crec$etiqueta, levels = unique(r$etiqueta))
  guardar(ggplot(crec, aes(anio, mancha_km2, colour = etiqueta)) + geom_line(linewidth = 0.9) + geom_point(size = 2.2) +
    scale_colour_manual(values = c("#c4622d", colorRampPalette(c("#0b2642", "#a9c6e6"))(length(CORTES)))) +
    scale_x_continuous(breaks = ANIOS) + scale_y_continuous(limits = c(0, NA), labels = f0) +
    labs(x = NULL, y = "km²", colour = "cut", title = sprintf("%s · growth of the urban patch, 1990-2020, by cut", NOMBRE),
         subtitle = "GISD30 decade paired with census: 1990-1991, 2000-2001, 2010-2010, 2020-2022", caption = PIE) +
    tema + theme(legend.position = "right"), img, "crecimiento_por_corte.png")
  rad <- do.call(rbind, lapply(ANIOS, function(a) { t <- x[[as.character(a)]]$t; t[t$km2_urb > 0, ] }))
  rad$anio_f <- factor(rad$anio)
  guardar(ggplot(rad, aes(pmax(dens_urb, 10), weight = km2_urb)) +
    geom_histogram(bins = 40, fill = "#1f4e79", colour = FONDO, linewidth = 0.2) +
    geom_vline(xintercept = CORTES, colour = "#c4622d", linewidth = 0.4, linetype = "22") +
    scale_x_log10(labels = f0) + facet_wrap(~anio_f, nrow = 1) +
    labs(x = "persons per km² of urbanized land (log)", y = "km² of urban extent",
         title = sprintf("%s · how the urban extent is spread across tract densities", NOMBRE),
         subtitle = "Histogram of urbanized km² by the density of its tract. Dashed: the cuts", caption = PIE) + tema,
    img, "histograma_densidad.png", w = 11, h = 4.5)

  # ---- mapas
  if (!SIN_MAPAS) for (a in ANIOS) {
    y <- x[[as.character(a)]]
    rid <- rasterize(y$v, y$code, field = "i")
    capas <- rast(lapply(c(0, CORTES), function(k) {
      ok <- marcar(rid, radios_con(y$t, k))
      ifel(y$code == 1, ifel(ok, 1, 3), ifel(y$code == 2, ifel(ok, 2, 4), ifel(y$code == 3, 5, 0)))
    }))
    tit <- vapply(c(0, CORTES), function(k) sprintf("%s · %s km² (%s%%) · %s%% of people", etq(k),
                  f1(g(a, k, "mancha_km2")), f0(g(a, k, "pct_area")), f1(g(a, k, "pct_personas"))), "")
    mapa_paneles(file.path(img, sprintf("mapa_%d.png", a)), capas, PAL, tit,
                 sprintf("%s · %d (census %s): urban extent kept by density cut", NOMBRE, a, CENSO[[as.character(a)]]),
                 c("built, kept", "fringe/captured, kept", "built, dropped", "fringe/captured, dropped", "built outside the city"),
                 x$cont)

    # densidad del radio pintada solo sobre la ciudad
    cl <- cut(y$t$dens_urb, c(0, CORTES, Inf), right = FALSE)
    pal_d <- colorRampPalette(c("#dbe7f4", "#0b2642"))(length(levels(cl)))
    clase <- ifel(y$code %in% c(1, 2), classify(rid, cbind(y$t$i_fila, as.integer(cl))), NA)
    poco <- y$t$i_fila[y$t$km2_urb > 0 & y$t$km2_urb / y$t$km2_radio < 0.1]
    w <- 1300; h <- min(round(w * nrow(y$code) / ncol(y$code)) + 160, 2600)
    png(file.path(img, sprintf("densidad_%d.png", a)), width = w, height = h, bg = FONDO)
    par(mar = c(0.3, 0.3, 3.5, 0.3), oma = c(6, 0, 0, 0), bg = FONDO)
    plot(ifel(y$code == 3, 1, NA), col = PAL[6], legend = FALSE, axes = FALSE, maxcell = 3e6, ext = ext(y$code),
         main = sprintf("%s · %d (census %s): tract density on its urbanized land", NOMBRE, a, CENSO[[as.character(a)]]),
         cex.main = 1.6)
    plot(clase, col = data.frame(value = seq_along(pal_d), color = pal_d), type = "classes", legend = FALSE,
         add = TRUE, maxcell = 3e6)
    plot(y$v, col = NA, border = "#9c9a92", lwd = 0.25, add = TRUE)
    if (length(poco)) plot(y$v[y$v$i %in% poco], col = NA, border = "#c4622d", lwd = 1.4, add = TRUE)
    lines(x$cont, col = "#1d1d1b", lwd = 1.2)
    par(fig = c(0, 1, 0, 1), oma = c(0, 0, 0, 0), mar = c(0, 0, 0, 0), new = TRUE)
    plot.new()
    legend("bottom", ncol = 4, bty = "n", border = NA, cex = 1.4, text.col = TINTA2, inset = 0.005,
           fill = c(pal_d, NA), col = c(rep(NA, length(pal_d)), "#c4622d"), lty = c(rep(NA, length(pal_d)), 1),
           lwd = c(rep(NA, length(pal_d)), 2),
           legend = c(paste("<", f0(CORTES[1])), paste0(f0(head(CORTES, -1)), "-", f0(CORTES[-1])),
                      paste0(f0(tail(CORTES, 1)), "+"), "tract <10% in the city"))
    dev.off()
  }

  # ---- reporte
  p0 <- function(a) g(a, 0, "ciudad_km2")
  L <- c(sprintf("# %s · the urban patch with census density, 1990-2020", NOMBRE), "",
    sprintf("Exploratory test 1. None of these numbers are project figures (they are not in `CIFRAS_CANONICAS.json`). Generated by `Rpipe/scripts/12_prueba_densidad.R` from the tract tables of step 11. Run of %s. [All agglomerations](../REPORTE.md).", format(Sys.Date())), "",
    "**Question.** The satellite urban extent (GISD30 with the Angel / Atlas 2016 classes) counts as city everything that is built, plus its fringe and captured open space, whether people live there or not. If we keep only the part of that extent that sits in census tracts with enough people, does the patch describe the city better? A tract below the cut leaves entirely, built land included. Method in the [index](../REPORTE.md#method).", "",
    "## What each cut keeps", "")
  for (a in ANIOS) {
    z <- r[r$anio == a, ]
    L <- c(L, sprintf("**%d (census %s).** City: %s km², %s tracts, %s persons.", a, CENSO[[as.character(a)]],
                      f1(z$ciudad_km2[1]), f0(z$ciudad_radios[1]), f0(z$ciudad_personas[1])), "",
           tabla(c("Cut (p/km²)", "Patch km²", "% of extent", "of which fringe/captured %", "Tracts", "Persons", "% of persons", "Density p/km²", "Dropped km²", "Dropped persons", "Census only km²"),
                 lapply(seq_len(nrow(z)), function(i) with(z[i, ], c(ifelse(corte == 0, "none", f0(corte)), f1(mancha_km2), f1(pct_area), f1(pct_abierto),
                   f0(mancha_radios), f0(mancha_personas), f1(pct_personas), f0(dens_mancha), f1(sale_km2), f0(sale_personas),
                   ifelse(corte == 0, "—", f1(censo_km2)))))), "")
  }
  L <- c(L, "![Patch size by cut](img/area_por_corte.png)", "", "![Area kept vs persons kept](img/area_vs_personas.png)", "",
    "![Density of the patch](img/densidad_mancha.png)", "", "![Distribution of tract densities](img/histograma_densidad.png)", "",
    "## Growth by cut", "",
    tabla(c("Cut (p/km²)", paste0(ANIOS, " km²"), "1990-2000 %/yr", "2000-2010 %/yr", "2010-2020 %/yr", "1990-2020 %/yr"),
          lapply(c(0, CORTES), function(k) {
            v <- vapply(ANIOS, function(a) g(a, k, "mancha_km2"), 1)
            c(ifelse(k == 0, "none", f0(k)), f1(v), f2(tasa(v[1:3], v[2:4], 10)), f2(tasa(v[1], v[4], 30)))
          })), "",
    "![Growth by cut](img/crecimiento_por_corte.png)", "",
    "## Dense tracts the satellite barely sees", "",
    "Tracts with gross density at or above the cut but less than 10 % of their area in the satellite city.", "",
    tabla(c("Cut (p/km²)", paste0(ANIOS, " tracts (persons)")),
          lapply(CORTES, function(k) c(f0(k), vapply(ANIOS, function(a) sprintf("%s (%s)",
            f0(r$censo_sin_huella_radios[r$anio == a & r$corte == k]), f0(g(a, k, "censo_sin_huella_personas"))), "")))), "")
  if (file.exists(file.path(dir, "img", "mapa_2020.png"))) {   # tambien con --sin-mapas si ya estan
    L <- c(L, "## Maps", "", "Same frame in the four years: the 2020 city plus 3 km. Blue is kept, orange is dropped; dark is built, light is fringe or captured open space. Black line: the analysis perimeter. On the density maps, tracts outlined in orange have under 10 % of their area in the satellite city.", "")
    for (a in ANIOS) L <- c(L, sprintf("### %d", a), "", sprintf("![Patch by cut, %d](img/mapa_%d.png)", a, a), "",
                            sprintf("![Tract density, %d](img/densidad_%d.png)", a, a), "")
  }
  L <- c(L, "## Reading", "",
    sprintf("- **At %s p/km²** the patch keeps %s %% of the satellite extent in 1990 and %s %% in 2020, and %s %% / %s %% of the persons of the city's tracts.",
            f0(C), f1(g(1990, C, "pct_area")), f1(g(2020, C, "pct_area")), f1(g(1990, C, "pct_personas")), f1(g(2020, C, "pct_personas"))),
    sprintf("- **Growth 1990-2020**: %s %%/yr with no cut, %s %%/yr at %s, %s %%/yr at %s.", f2(tasa(p0(1990), p0(2020), 30)),
            f2(tasa(g(1990, C, "mancha_km2"), g(2020, C, "mancha_km2"), 30)), f0(C),
            f2(tasa(g(1990, max(CORTES), "mancha_km2"), g(2020, max(CORTES), "mancha_km2"), 30)), f0(max(CORTES))),
    sprintf("- **2010-2020.** With no cut the extent grows by %s km²; at %s p/km² by %s km². The gap, %s km², is roughly new extent that landed in tracts below the cut.",
            f1(p0(2020) - p0(2010)), f0(C), f1(g(2020, C, "mancha_km2") - g(2010, C, "mancha_km2")),
            f1((p0(2020) - p0(2010)) - (g(2020, C, "mancha_km2") - g(2010, C, "mancha_km2")))),
    sprintf("- **Tracts mostly outside the city** (under 10 %% of their area in it) keep their sliver of city because their residents raise its density: %s km² at %s p/km² in 2020.",
            f1(g(2020, C, "mancha_poco_urb_km2")), f0(C)), "")
  writeLines(enc2utf8(L), file.path(dir, "REPORTE.md"), useBytes = TRUE)
  cat(sprintf("  %-22s listo\n", slug))
  data.frame(slug = slug, nombre = NOMBRE,
             ciudad_1990 = p0(1990), ciudad_2020 = p0(2020),
             pct_area_1990 = g(1990, C, "pct_area"), pct_area_2020 = g(2020, C, "pct_area"),
             pct_personas_2020 = g(2020, C, "pct_personas"),
             tasa_sin = tasa(p0(1990), p0(2020), 30), tasa_c = tasa(g(1990, C, "mancha_km2"), g(2020, C, "mancha_km2"), 30),
             dens_sin_2020 = g(2020, 0, "dens_mancha"), dens_c_2020 = g(2020, C, "dens_mancha"))
}


# ---- todas e indice ----------------------------------------------------------------

cat(sprintf("Prueba 1 · densidad por radio · %d aglomerados\n", length(CIUDADES)))
dir.create(BASE, recursive = TRUE, showWarnings = FALSE)
res <- do.call(rbind, lapply(CIUDADES, function(s) tryCatch(una(s), error = function(e) {
  cat("  ERROR", s, ":", conditionMessage(e), "\n"); NULL })))
res <- res[order(res$nombre), ]
write.csv(res, file.path(BASE, "resumen.csv"), row.names = FALSE)

img <- file.path(BASE, "img"); dir.create(img, showWarnings = FALSE)
largo <- rbind(data.frame(nombre = res$nombre, medida = "no cut", tasa = res$tasa_sin),
               data.frame(nombre = res$nombre, medida = paste0(f0(C), " p/km²"), tasa = res$tasa_c))
largo$nombre <- factor(largo$nombre, levels = res$nombre[order(res$tasa_sin)])
guardar(ggplot(largo, aes(tasa, nombre, colour = medida)) + geom_point(size = 2.6) +
  scale_colour_manual(values = c("#c4622d", "#1f4e79")) +
  labs(x = "% a year, 1990-2020", y = NULL, colour = NULL, title = "Growth of the urban patch, with and without the density cut",
       subtitle = sprintf("No cut = Angel urban extent. %s p/km² = only tracts at or above the cut", f0(C)), caption = PIE) + tema,
  img, "crecimiento.png", w = 9, h = 8)
guardar(ggplot(res, aes(pct_area_2020, pct_personas_2020)) + geom_point(size = 2.6, colour = "#1f4e79") +
  geom_text(aes(label = nombre), size = 2.8, colour = TINTA2, nudge_y = 0.25, check_overlap = TRUE) +
  labs(x = "% of the 2020 urban extent kept", y = "% of the 2022 population kept",
       title = sprintf("What the %s p/km² cut costs in 2020, agglomeration by agglomeration", f0(C)),
       caption = PIE) + tema, img, "costo_2020.png", w = 9, h = 6.5)

ancla <- function(s) sprintf("[%s](%s/REPORTE.md)", res$nombre[res$slug == s], s)
L <- c("# Test 1 · the urban patch with census density, all agglomerations", "",
  sprintf("Exploratory. None of these numbers are project figures (they are not in `CIFRAS_CANONICAS.json`). Generated by `Rpipe/scripts/12_prueba_densidad.R` from step 11. Run of %s. Both tests and how they differ: [METODOS.md](../METODOS.md).", format(Sys.Date())), "",
  "## Method", "",
  "- **The city**, as in step 04: 8-connected patches of urban + suburban built-up, fringe open space and captured open space that touch the analysis perimeter (with step 04's shared-patch rule for agglomerations whose patches touch). Fringe and captured are unbuilt land that Angel counts as part of the city, and they count as urbanized land here.",
  "- **Pairs**: GISD30 1990 with the 1991 census, 2000-2001, 2010-2010, 2020-2022 (the project rule).",
  "- **Density of a tract** = its persons / km² of the city inside it. It is density on urbanized land, not on the whole tract. Areas come from whole 30 m pixels assigned to the tract that holds their centre (step 11); in Salta this matches exact pixel fractions to within 0.03 km².",
  sprintf("- **Patch at cut T** = the city inside tracts with density ≥ T. A tract below the cut leaves entirely, its built land included. Cuts: %s persons/km² (300, 500 and 1,000 are the project's `U_DENS`, `scripts/rutas.py`).", paste(f0(CORTES), collapse = ", ")),
  "- **Persons of the patch** = persons of its whole tracts.", "",
  sprintf("## All agglomerations at %s p/km²", f0(C)), "",
  tabla(c("Agglomeration", "Extent 1990 km²", "Extent 2020 km²", "% kept 1990", "% kept 2020", "% persons kept 2022", "Growth no cut %/yr", sprintf("Growth at %s %%/yr", f0(C)), "Density 2020 no cut", sprintf("Density 2020 at %s", f0(C))),
        lapply(res$slug, function(s) with(res[res$slug == s, ], c(ancla(s), f1(ciudad_1990), f1(ciudad_2020), f1(pct_area_1990), f1(pct_area_2020),
          f1(pct_personas_2020), f2(tasa_sin), f2(tasa_c), f0(dens_sin_2020), f0(dens_c_2020))))), "",
  "![Growth with and without the cut](img/crecimiento.png)", "", "![Cost of the cut in 2020](img/costo_2020.png)", "",
  indice_mapas(BASE, res, c(patch = "mapa_%d.png", density = "densidad_%d.png"),
               nota = sprintf("*patch*: the extent kept at each cut (%s panels, no cut to %s p/km²); *density*: persons per km² urbanized by tract.",
                              length(CORTES) + 1, f0(max(CORTES)))))
writeLines(enc2utf8(L), file.path(BASE, "REPORTE.md"), useBytes = TRUE)
cat("Escrito", file.path(BASE, "REPORTE.md"), "\n")
