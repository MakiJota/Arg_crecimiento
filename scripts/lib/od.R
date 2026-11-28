# -*- coding: utf-8 -*-
# Funciones comunes de los pasos 28 y 29: red de calles de Overture como grafo, matriz
# origen-destino de tiempo y distancia, y comunidades sobre el tiempo. Se carga con source();
# necesita sf e igraph cargados. Los supuestos de la red estan en el encabezado del paso 28.

# velocidad supuesta por clase de Overture, km/h, flujo libre (no medida)
VEL <- c(motorway = 100, trunk = 90, primary = 80, secondary = 60, tertiary = 50,
         unclassified = 40, residential = 30, living_street = 20, service = 20, track = 20,
         unknown = 30)
FUERA <- c("footway", "path", "pedestrian", "steps", "cycleway", "bridleway")
ENGANCHE_MAX <- 1000   # m; mas lejos se avisa


utm <- function(lon, lat) sprintf("EPSG:%d", (if (lat < 0) 32700 else 32600) + floor((lon + 180) / 6) + 1)


leer_red <- function(calles, crs, verboso = TRUE) {
  # calles.gpkg del paso 20 -> list(g = grafo no dirigido de la componente mayor, ca = calles)
  if (!file.exists(calles)) stop("no existe ", calles, ": correr antes el paso 20 con --temas calles",
                                 call. = FALSE)
  ca <- st_read(calles, quiet = TRUE)
  ca <- ca[ca$subtype == "road" & !(ca$clase %in% FUERA), ]
  ca$clase[is.na(ca$clase) | !(ca$clase %in% names(VEL))] <- "unknown"
  ca <- st_transform(st_cast(st_zm(ca), "LINESTRING", warn = FALSE), crs)

  # nodado: se parte cada linea en cada cruce; la clase vuelve por el segmento original mas cercano
  tramos <- st_cast(st_node(st_union(st_geometry(ca))), "LINESTRING")
  tramos <- tramos[as.numeric(st_length(tramos)) > 0]
  medio <- st_cast(st_line_sample(tramos, sample = 0.5), "POINT")
  clase <- ca$clase[st_nearest_feature(medio, ca)]
  largo <- as.numeric(st_length(tramos))

  xy <- st_coordinates(tramos)
  ini <- xy[!duplicated(xy[, "L1"]), c("X", "Y")]
  fin <- xy[!duplicated(xy[, "L1"], fromLast = TRUE), c("X", "Y")]
  clave <- function(m) paste(round(m[, 1], 1), round(m[, 2], 1))
  k <- unique(c(clave(ini), clave(fin)))
  nodo <- data.frame(clave = k)
  nodo[, c("x", "y")] <- do.call(rbind, lapply(strsplit(k, " "), as.numeric))
  g <- graph_from_data_frame(data.frame(from = clave(ini), to = clave(fin), largo = largo,
                                        seg = largo / (VEL[clase] / 3.6), clase = clase),
                             directed = FALSE, vertices = nodo)
  comp <- components(g)
  mayor <- which.max(comp$csize)
  if (verboso)
    cat(sprintf("red: %d segmentos manejables -> %d nodos, %d tramos, %d componentes; la mayor tiene %.1f%% de los nodos\n",
                nrow(ca), vcount(g), ecount(g), comp$no, 100 * comp$csize[mayor] / vcount(g)))
  list(g = induced_subgraph(g, which(comp$membership == mayor)), ca = ca)
}


enganchar <- function(g, pt) {
  # nodo mas cercano de la red para cada punto, y a cuantos metros
  vx <- st_as_sf(data.frame(x = V(g)$x, y = V(g)$y), coords = c("x", "y"), crs = st_crs(pt))
  cerca <- st_nearest_feature(pt, vx)
  eng <- as.numeric(st_distance(pt, vx[cerca, ], by_element = TRUE))
  if (any(eng > ENGANCHE_MAX))
    message("AVISO: puntos a mas de ", ENGANCHE_MAX, " m de la red: ",
            paste(sprintf("%s (%.0f m)", pt$nombre[eng > ENGANCHE_MAX], eng[eng > ENGANCHE_MAX]),
                  collapse = ", "))
  list(cerca = cerca, eng = eng)
}


matriz_od <- function(g, cerca, pt) {
  # camino mas rapido entre cada par: tiempo (min) y largo de ese camino (km); y linea recta (km)
  n <- length(cerca)
  Tm <- distances(g, v = cerca, to = cerca, weights = E(g)$seg) / 60
  Dk <- matrix(0, n, n)
  for (i in seq_len(n)) {
    ep <- shortest_paths(g, from = cerca[i], to = cerca, weights = E(g)$seg, output = "epath")$epath
    Dk[i, ] <- vapply(ep, function(e) sum(E(g)$largo[e]), 0) / 1000
  }
  if (any(!is.finite(Tm))) stop("hay pares sin camino en la red", call. = FALSE)
  Tm <- (Tm + t(Tm)) / 2   # la red es no dirigida; se fuerza la simetria numerica
  Dk <- (Dk + t(Dk)) / 2
  Er <- as.matrix(dist(st_coordinates(pt))) / 1000
  dimnames(Tm) <- dimnames(Dk) <- dimnames(Er) <- list(pt$nombre, pt$nombre)
  ij <- which(upper.tri(Tm), arr.ind = TRUE)
  pares <- data.frame(origen = pt$nombre[ij[, 1]], destino = pt$nombre[ij[, 2]],
                      tiempo_min = Tm[ij], distancia_km = Dk[ij], recta_km = Er[ij])
  pares$rodeo <- pares$distancia_km / pares$recta_km
  pares$vel_kmh <- pares$distancia_km / (pares$tiempo_min / 60)
  list(Tm = Tm, Dk = Dk, Er = Er, ij = ij, pares = pares)
}


comunidades <- function(Tm, umbrales, taus, semilla = 28) {
  # pertenencia por metodo: enlace simple y promedio cortados en cada umbral (min), y Louvain /
  # Leiden (modularidad) sobre exp(-t/tau). Con menos de 3 puntos solo los jerarquicos.
  n <- nrow(Tm)
  com <- data.frame(nombre = rownames(Tm))
  hs <- ha <- NULL
  if (n >= 2) {
    hs <- hclust(as.dist(Tm), method = "single")
    ha <- hclust(as.dist(Tm), method = "average")
  }
  for (u in umbrales) {
    com[[sprintf("simple_%gmin", u)]] <- if (n >= 2) cutree(hs, h = u) else 1L
    com[[sprintf("promedio_%gmin", u)]] <- if (n >= 2) cutree(ha, h = u) else 1L
  }
  set.seed(semilla)
  modul <- data.frame()
  for (tau in taus) {
    if (n < 3) {
      com[[sprintf("louvain_tau%g", tau)]] <- com[[sprintf("leiden_tau%g", tau)]] <- NA_integer_
      next
    }
    W <- exp(-Tm / tau); diag(W) <- 0
    gw <- graph_from_adjacency_matrix(W, mode = "undirected", weighted = TRUE, diag = FALSE)
    lv <- cluster_louvain(gw, weights = E(gw)$weight)
    ld <- cluster_leiden(gw, objective_function = "modularity", weights = E(gw)$weight,
                         n_iterations = -1)
    com[[sprintf("louvain_tau%g", tau)]] <- as.integer(membership(lv))
    com[[sprintf("leiden_tau%g", tau)]] <- as.integer(membership(ld))
    modul <- rbind(modul, data.frame(tau = tau, louvain_grupos = max(membership(lv)),
                                     louvain_Q = round(modularity(lv), 3),
                                     leiden_grupos = max(membership(ld)),
                                     leiden_Q = round(modularity(gw, membership(ld),
                                                                 weights = E(gw)$weight), 3)))
  }
  # renumerar cada columna para que el grupo 1 sea el de la primera localidad que aparece
  for (c in names(com)[-1]) if (!all(is.na(com[[c]]))) com[[c]] <- match(com[[c]], unique(com[[c]]))
  list(com = com, hs = hs, ha = ha, modul = modul)
}
