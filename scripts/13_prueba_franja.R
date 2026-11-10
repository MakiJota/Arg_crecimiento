# -*- coding: utf-8 -*-
# Paso 13 · Prueba 2: ¿cuando cuenta la franja como ciudad? 1990-2020. Exploratoria: ningun
# numero es cifra del proyecto. Generaliza a todos los aglomerados la prueba de Salta del
# 2026-11-08.
#
# LA IDEA. Lo construido (urbano + suburbano de Angel) es ciudad siempre. La franja y el
# espacio capturado son suelo que GISD30 ve abierto, pero con imagenes viejas y gruesas
# (1990 sobre todo) parte puede estar construida y no detectarse. El censo decide:
#     ciudad(T) = construido  +  franja y capturado de los radios con dens_urb >= T
#     dens_urb  = personas del radio / km2 de ciudad (construido + franja + capturado) en el radio
# La franja va en el denominador a proposito: si aun contandola como urbanizada el radio
# es denso, la franja es ciudad. Sin corte es la extension de Angel; con corte infinito,
# solo lo construido. A diferencia de 12, lo construido nunca sale.
#
# CONTROL DE LA PREMISA. Si 1990 detecta menos construido del que hay, las personas por km2
# CONSTRUIDO tienen que salir mas altas en 1990 que despues. No separa "construido no
# visto" de "ciudad mas densa": solo dice si los numeros son compatibles con la idea.
#
# ENTRADAS  outputs/densidad/<slug>/ (paso 11)
# SALIDAS   pruebas/franja_densa/<slug>/REPORTE.md, img/, tablas/{resultado,premisa}.csv
#           pruebas/franja_densa/REPORTE.md   indice y comparacion entre aglomerados
#
# Uso: Rscript Rpipe/scripts/13_prueba_franja.R [--ciudades salta,jujuy] [--cortes 300,...]
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
CORTES <- as.numeric(strsplit(arg("--cortes", "300,500,1000,2000,3000,3250,3500,3750,4000,4500,5000"), ",")[[1]])
SIN_MAPAS <- "--sin-mapas" %in% args
BASE <- file.path(RPIPE, "pruebas", "franja_densa")
DENS <- file.path(RPIPE, "outputs", "densidad")
CIUDADES <- if (is.na(match("--ciudades", args))) {
  sort(basename(dirname(list.files(DENS, "^ciudad\\.csv$", recursive = TRUE, full.names = TRUE))))
} else strsplit(arg("--ciudades", ""), ",")[[1]]
C <- if (500 %in% CORTES) 500 else CORTES[1]
TODOS <- c(0, CORTES, Inf)
# mapa: fondo, construido, franja/capturado que entra, franja/capturado que no, construido fuera
PAL <- c("#fcfcfb", "#1f4e79", "#8db3dd", "#efb48f", "#cfcdc6")
etq <- function(k) ifelse(k == 0, "no cut (Angel)", ifelse(is.infinite(k), "built only", paste(f0(k), "p/km²")))


una <- function(slug) {
  x <- cargar_densidad(RPIPE, slug)
  if (is.null(x)) { cat("  sin salida de 11:", slug, "\n"); return(NULL) }
  NOMBRE <- x$nombre
  dir <- file.path(BASE, slug); img <- file.path(dir, "img"); tab <- file.path(dir, "tablas")
  dir.create(img, recursive = TRUE, showWarnings = FALSE); dir.create(tab, showWarnings = FALSE)

  res <- do.call(rbind, lapply(ANIOS, function(a) {
    t <- x[[as.character(a)]]$t
    en <- t$km2_urb > 0
    do.call(rbind, lapply(TODOS, function(k) {
      entra <- en & !is.na(t$dens_urb) & t$dens_urb >= k
      data.frame(anio = a, corte = k, construido_km2 = sum(t$km2_construido[en]),
                 franja_total_km2 = sum(t$km2_abierto[en]), franja_entra_km2 = sum(t$km2_abierto[entra]),
                 radios_franja = sum(entra & t$km2_abierto > 0), personas = sum(t$personas[en]))
    }))
  }))
  res$ciudad_km2 <- res$construido_km2 + res$franja_entra_km2
  res$pct_franja_entra <- 100 * res$franja_entra_km2 / res$franja_total_km2
  res$pct_franja_en_ciudad <- 100 * res$franja_entra_km2 / res$ciudad_km2
  res$dens_ciudad <- res$personas / res$ciudad_km2
  res$etiqueta <- etq(res$corte)
  write.csv(res, file.path(tab, "resultado.csv"), row.names = FALSE)
  g <- function(a, k, col) res[[col]][res$anio == a & res$corte == k]

  premisa <- do.call(rbind, lapply(ANIOS, function(a) {
    t <- x[[as.character(a)]]$t
    t <- t[t$km2_construido > 0, ]
    o <- order(t$dens_construido)
    w <- cumsum(t$km2_construido[o]) / sum(t$km2_construido)
    data.frame(anio = a, personas = sum(t$personas), construido_km2 = sum(t$km2_construido),
               dens_construido = sum(t$personas) / sum(t$km2_construido),
               mediana_radio = t$dens_construido[o][which(w >= 0.5)[1]],
               pct_franja = 100 * sum(t$km2_abierto) / sum(t$km2_urb))
  }))
  write.csv(premisa, file.path(tab, "premisa.csv"), row.names = FALSE)
  p <- function(a) premisa$dens_construido[premisa$anio == a]

  # ---- graficos
  r <- res[is.finite(res$corte), ]; r$anio_f <- factor(r$anio)
  ejes_corte <- scale_x_continuous(breaks = c(0, CORTES), labels = c("none", f0(CORTES)))
  guardar(ggplot(r, aes(corte, ciudad_km2, colour = anio_f)) + geom_line(linewidth = 0.9) + geom_point(size = 2.4) +
    geom_hline(data = res[is.infinite(res$corte), ], aes(yintercept = ciudad_km2, colour = factor(anio)), linetype = "22", linewidth = 0.4) +
    scale_colour_manual(values = COL_ANIO) + ejes_corte + scale_y_continuous(limits = c(0, NA), labels = f0) +
    labs(x = "Density cut for adding a tract's fringe and captured land (persons per km² urbanized)", y = "km²", colour = NULL,
         title = sprintf("%s · city size when fringe counts only in dense tracts", NOMBRE),
         subtitle = "Built-up always counts. Dashed: built-up only (no fringe at all)", caption = PIE) + tema,
    img, "ciudad_por_corte.png")
  guardar(ggplot(r, aes(corte, pct_franja_entra, colour = anio_f)) + geom_line(linewidth = 0.9) + geom_point(size = 2.4) +
    scale_colour_manual(values = COL_ANIO) + ejes_corte + scale_y_continuous(limits = c(0, 100)) +
    labs(x = "Density cut (persons per km² urbanized)", y = "% of fringe + captured land added", colour = NULL,
         title = sprintf("%s · how much of the fringe each cut lets in", NOMBRE),
         subtitle = "If a year's fringe sits in dense tracts, it survives high cuts: it is probably built and unseen",
         caption = PIE) + tema, img, "franja_que_entra.png")
  crec <- res; crec$etiqueta <- factor(crec$etiqueta, levels = unique(res$etiqueta))
  guardar(ggplot(crec, aes(anio, ciudad_km2, colour = etiqueta)) + geom_line(linewidth = 0.9) + geom_point(size = 2.2) +
    scale_colour_manual(values = c("#0b0b0b", colorRampPalette(c("#0b2642", "#a9c6e6"))(length(CORTES)), "#c4622d")) +
    scale_x_continuous(breaks = ANIOS) + scale_y_continuous(limits = c(0, NA), labels = f0) +
    labs(x = NULL, y = "km²", colour = "fringe added at", title = sprintf("%s · growth of the city, 1990-2020, by cut", NOMBRE),
         subtitle = "Built-up always counts; fringe and captured land only in tracts at or above the cut", caption = PIE) +
    tema + theme(legend.position = "right"), img, "crecimiento_por_corte.png")
  guardar(ggplot(premisa, aes(factor(anio), dens_construido)) + geom_col(width = 0.6, fill = "#1f4e79") +
    geom_text(aes(label = f0(dens_construido)), vjust = -0.5, colour = TINTA2, size = 3.5) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.12)), labels = f0) +
    labs(x = NULL, y = "persons per km² built", title = sprintf("%s · persons per km² of built-up land", NOMBRE),
         subtitle = "Persons of tracts with built land / built-up km² the satellite sees in the city", caption = PIE) + tema,
    img, "premisa.png", w = 7, h = 4.5)

  # ---- mapas
  if (!SIN_MAPAS) for (a in ANIOS) {
    y <- x[[as.character(a)]]
    rid <- rasterize(y$v, y$code, field = "i")
    capas <- rast(lapply(TODOS, function(k) {
      ok <- marcar(rid, radios_con(y$t, k))
      ifel(y$code == 1, 1, ifel(y$code == 2, ifel(ok, 2, 3), ifel(y$code == 3, 4, 0)))
    }))
    tit <- vapply(TODOS, function(k) sprintf("%s · %s km² · %s%% of fringe in", etq(k), f1(g(a, k, "ciudad_km2")),
                                             f0(g(a, k, "pct_franja_entra"))), "")
    mapa_paneles(file.path(img, sprintf("mapa_%d.png", a)), capas, PAL, tit,
                 sprintf("%s · %d (census %s): built-up plus the fringe of dense tracts", NOMBRE, a, CENSO[[as.character(a)]]),
                 c("built-up (always city)", "fringe/captured, added", "fringe/captured, left out", "built outside the city"),
                 x$cont)
  }

  # ---- reporte
  L <- c(sprintf("# %s · when does the fringe count as city? 1990-2020", NOMBRE), "",
    sprintf("Exploratory test 2. None of these numbers are project figures (they are not in `CIFRAS_CANONICAS.json`). Generated by `Rpipe/scripts/13_prueba_franja.R` from the tract tables of step 11. Run of %s. [All agglomerations](../REPORTE.md).", format(Sys.Date())), "",
    "**Idea.** Built-up land is always city. Fringe and captured open space join the city **only in dense tracts**, where they are probably built and unseen by the older imagery. No cut gives the full Angel extent; an infinite cut, built-up only. Method in the [index](../REPORTE.md#method).", "",
    "## Is the early imagery under-detecting?", "",
    "If the older imagery misses buildings, persons per km² of *built* land should come out higher in the early years.", "",
    tabla(c("Year", "Persons (tracts with built land)", "Built km²", "Persons / km² built", "Median tract, persons / km² built", "Fringe + captured, % of extent"),
          lapply(seq_len(nrow(premisa)), function(i) with(premisa[i, ], c(sprintf("%d (census %s)", anio, CENSO[[as.character(anio)]]),
            f0(personas), f1(construido_km2), f0(dens_construido), f0(mediana_radio), f1(pct_franja))))), "",
    "![Persons per km² built](img/premisa.png)", "", "## Results", "")
  for (a in ANIOS) {
    z <- res[res$anio == a, ]
    L <- c(L, sprintf("**%d (census %s).** Built-up %s km²; fringe + captured %s km²; %s persons in the city's tracts.",
                      a, CENSO[[as.character(a)]], f1(z$construido_km2[1]), f1(z$franja_total_km2[1]), f0(z$personas[1])), "",
           tabla(c("Fringe added at", "City km²", "Fringe added km²", "% of fringe added", "Fringe % of city", "Tracts adding fringe", "Persons / km² city"),
                 lapply(seq_len(nrow(z)), function(i) with(z[i, ], c(etiqueta, f1(ciudad_km2), f1(franja_entra_km2), f1(pct_franja_entra),
                   f1(pct_franja_en_ciudad), f0(radios_franja), f0(dens_ciudad))))), "")
  }
  L <- c(L, "![City by cut](img/ciudad_por_corte.png)", "", "![Fringe let in](img/franja_que_entra.png)", "",
    "### Growth by cut", "",
    tabla(c("Fringe added at", paste0(ANIOS, " km²"), "1990-2000 %/yr", "2000-2010 %/yr", "2010-2020 %/yr", "1990-2020 %/yr"),
          lapply(TODOS, function(k) {
            v <- vapply(ANIOS, function(a) g(a, k, "ciudad_km2"), 1)
            c(etq(k), f1(v), f2(tasa(v[1:3], v[2:4], 10)), f2(tasa(v[1], v[4], 30)))
          })), "",
    "![Growth by cut](img/crecimiento_por_corte.png)", "")
  if (file.exists(file.path(dir, "img", "mapa_2020.png"))) {   # tambien con --sin-mapas si ya estan
    L <- c(L, "## Maps", "", "Same frame in the four years: the 2020 city plus 3 km. Dark blue is built-up, always city; light blue is fringe or captured land added because its tract is dense; light orange is fringe left out. Black line: the analysis perimeter.", "")
    for (a in ANIOS) L <- c(L, sprintf("### %d", a), "", sprintf("![City by cut, %d](img/mapa_%d.png)", a, a), "")
  }
  L <- c(L, "## Reading", "",
    sprintf("- **The premise.** Persons per km² of built land: %s in 1990, %s in 2000, %s in 2010, %s in 2020. %s",
            f0(p(1990)), f0(p(2000)), f0(p(2010)), f0(p(2020)),
            if (p(1990) > 1.15 * p(2010)) "1990 is clearly higher than 2010: consistent with built land missed in 1990, though it also fits a denser city that later spread out."
            else "1990 is not clearly higher than 2010: the census does not point to much built land missed in 1990."),
    sprintf("- **At %s p/km²** the fringe that joins the city is %s %% of all fringe in 1990 and %s %% in 2020.",
            f0(C), f1(g(1990, C, "pct_franja_entra")), f1(g(2020, C, "pct_franja_entra"))),
    sprintf("- **Growth 1990-2020**: %s %%/yr with the full Angel extent, %s %%/yr at %s, %s %%/yr built-up only.",
            f2(tasa(g(1990, 0, "ciudad_km2"), g(2020, 0, "ciudad_km2"), 30)),
            f2(tasa(g(1990, C, "ciudad_km2"), g(2020, C, "ciudad_km2"), 30)), f0(C),
            f2(tasa(g(1990, Inf, "ciudad_km2"), g(2020, Inf, "ciudad_km2"), 30))), "")
  writeLines(enc2utf8(L), file.path(dir, "REPORTE.md"), useBytes = TRUE)
  cat(sprintf("  %-22s listo\n", slug))
  data.frame(slug = slug, nombre = NOMBRE,
             dens_constr_1990 = p(1990), dens_constr_2020 = p(2020),
             franja_1990 = g(1990, C, "pct_franja_entra"), franja_2020 = g(2020, C, "pct_franja_entra"),
             ciudad_c_2020 = g(2020, C, "ciudad_km2"), angel_2020 = g(2020, 0, "ciudad_km2"),
             tasa_angel = tasa(g(1990, 0, "ciudad_km2"), g(2020, 0, "ciudad_km2"), 30),
             tasa_c = tasa(g(1990, C, "ciudad_km2"), g(2020, C, "ciudad_km2"), 30),
             tasa_constr = tasa(g(1990, Inf, "ciudad_km2"), g(2020, Inf, "ciudad_km2"), 30))
}


# ---- todas e indice ----------------------------------------------------------------

cat(sprintf("Prueba 2 · franja densa · %d aglomerados\n", length(CIUDADES)))
dir.create(BASE, recursive = TRUE, showWarnings = FALSE)
res <- do.call(rbind, lapply(CIUDADES, function(s) tryCatch(una(s), error = function(e) {
  cat("  ERROR", s, ":", conditionMessage(e), "\n"); NULL })))
res <- res[order(res$nombre), ]
write.csv(res, file.path(BASE, "resumen.csv"), row.names = FALSE)

img <- file.path(BASE, "img"); dir.create(img, showWarnings = FALSE)
largo <- rbind(data.frame(nombre = res$nombre, anio = "1990", v = res$franja_1990),
               data.frame(nombre = res$nombre, anio = "2020", v = res$franja_2020))
largo$nombre <- factor(largo$nombre, levels = res$nombre[order(res$franja_2020)])
guardar(ggplot(largo, aes(v, nombre, colour = anio)) + geom_point(size = 2.6) +
  scale_colour_manual(values = COL_ANIO[c("1990", "2020")]) + scale_x_continuous(limits = c(0, 100)) +
  labs(x = sprintf("%% of fringe + captured land in tracts at or above %s p/km²", f0(C)), y = NULL, colour = NULL,
       title = "How much of the fringe sits in dense tracts, 1990 and 2020",
       subtitle = "High = the fringe behaves like city (probably built and unseen); low = empty land around new development",
       caption = PIE) + tema, img, "franja_1990_2020.png", w = 9, h = 8)
pr <- rbind(data.frame(nombre = res$nombre, anio = "1990", v = res$dens_constr_1990),
            data.frame(nombre = res$nombre, anio = "2020", v = res$dens_constr_2020))
pr$nombre <- factor(pr$nombre, levels = res$nombre[order(res$dens_constr_1990 / res$dens_constr_2020)])
guardar(ggplot(pr, aes(v, nombre, colour = anio)) + geom_point(size = 2.6) +
  scale_colour_manual(values = COL_ANIO[c("1990", "2020")]) + scale_x_continuous(labels = f0) +
  labs(x = "persons per km² of built-up land", y = NULL, colour = NULL,
       title = "Persons per km² of built-up land, 1990 and 2020",
       subtitle = "Sorted by the 1990 / 2020 ratio: top = biggest drop, where under-detection in 1990 is most plausible",
       caption = PIE) + tema, img, "premisa.png", w = 9, h = 8)

ancla <- function(s) sprintf("[%s](%s/REPORTE.md)", res$nombre[res$slug == s], s)
L <- c("# Test 2 · when does the fringe count as city? All agglomerations", "",
  sprintf("Exploratory. None of these numbers are project figures (they are not in `CIFRAS_CANONICAS.json`). Generated by `Rpipe/scripts/13_prueba_franja.R` from step 11. Run of %s. Both tests and how they differ: [METODOS.md](../METODOS.md).", format(Sys.Date())), "",
  "## Method", "",
  "- **The city**, as in step 04: 8-connected patches of urban + suburban built-up, fringe open space and captured open space that touch the analysis perimeter (with step 04's shared-patch rule).",
  "- **Built-up** (urban + suburban) is always city.",
  "- **Fringe and captured** land join the city only in tracts whose density on urbanized land (persons / km² of built + fringe + captured in the tract) is at or above the cut. If the tract is dense even counting its fringe as urban, that fringe is probably built and unseen.",
  sprintf("- **Cuts**: %s persons/km² (300, 500 and 1,000 are the project's `U_DENS`), plus no cut (the Angel extent) and built-up only.", paste(f0(CORTES), collapse = ", ")),
  "- **Premise check**: persons per km² of built-up land by year. Higher in 1990 than later is compatible with buildings missed by the older imagery, but also with a denser city that later spread out.",
  "- **Pairs**: GISD30 1990 with the 1991 census, 2000-2001, 2010-2010, 2020-2022. Areas from whole 30 m pixels (step 11).", "",
  sprintf("## All agglomerations at %s p/km²", f0(C)), "",
  tabla(c("Agglomeration", "Persons/km² built 1990", "Persons/km² built 2020", "% fringe added 1990", "% fringe added 2020", "City 2020 km²", "Angel 2020 km²",
          "Growth Angel %/yr", sprintf("Growth at %s %%/yr", f0(C)), "Growth built only %/yr"),
        lapply(res$slug, function(s) with(res[res$slug == s, ], c(ancla(s), f0(dens_constr_1990), f0(dens_constr_2020), f1(franja_1990), f1(franja_2020),
          f1(ciudad_c_2020), f1(angel_2020), f2(tasa_angel), f2(tasa_c), f2(tasa_constr))))), "",
  "![Fringe in dense tracts](img/franja_1990_2020.png)", "", "![Persons per km² built](img/premisa.png)", "",
  indice_mapas(BASE, res, c(city = "mapa_%d.png"),
               nota = sprintf("Each map has %s panels: the Angel extent, every cut, and built-up only.", length(CORTES) + 2)))
writeLines(enc2utf8(L), file.path(BASE, "REPORTE.md"), useBytes = TRUE)
cat("Escrito", file.path(BASE, "REPORTE.md"), "\n")
