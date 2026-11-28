---
title: "Métodos"
nav_order: 1
---

# Extensión del aglomerado: métodos

Cuatro maneras de discutir hasta dónde llega cada uno de los 31 aglomerados EPH y qué radios censales 2022 le corresponden. Exploratorio: ningún número es cifra del proyecto.

1. TOC
{:toc}

## 1 · Localidades: comunidades por tiempo de viaje


1. **Ventana.** Un cuadrado de 70 x 70 km (ademas, 100 km x 100 km para Gran Buenos Aires, que van despues de su cuadrado de base), centrado en el centroide de la parte mas grande del perimetro de analisis del aglomerado (paso 07). En aglomerados de partes lejanas la otra parte puede quedar afuera (`partes_fuera` en resumen.csv).
2. **Puntos.** Las sedes de gobierno local de BAHRA/IGN (municipios, comunas, comisiones, juntas; 2313 en el archivo) que caen dentro del cuadrado. Cada sede es un punto, no una poblacion: una ciudad grande y un pueblo pesan igual. Con menos de 2 sedes el aglomerado se saltea.
3. **Red vial.** Calles de Overture Maps (release 2026-11-18.0) en el cuadrado mas 10 km por lado, para que los caminos puedan salir de el. Sin sendas, veredas ni ciclovias. Las lineas se cortan en cada cruce (un puente cuenta como cruce), la red es no dirigida (sin manos unicas) y se usa su componente conexa mayor. Velocidad supuesta por clase de calle, km/h, flujo libre: motorway 100, trunk 90, primary 80, secondary 60, tertiary 50, unclassified 40, residential 30, living_street 20, service 20, track 20, unknown 30. No es velocidad medida: los tiempos son una cota inferior del viaje en auto.
4. **Matriz origen-destino.** Cada sede se engancha al nodo mas cercano de la red (la distancia de enganche no se suma). Entre cada par se busca el camino mas rapido (Dijkstra): tiempo en minutos y largo de ese camino en km (`od_tiempo_min.csv`, `od_distancia_km.csv`, `od_pares.csv`).
5. **Comunidades**, tres maneras de agrupar las sedes a partir de la matriz de tiempo:
   - *Enlace simple a U min*: dos sedes van juntas si hay una cadena de viajes de a lo sumo U min que las une (percolacion, Arcaute et al. 2016). Puede encadenar pueblos lejanos a traves de uno intermedio.
   - *Enlace promedio a U min*: dos grupos se unen solo si el tiempo promedio entre todos sus miembros es de a lo sumo U min. Mas conservador. Aca U = 30.
   - *Leiden* (Traag et al. 2019): cada par se une con peso exp(-t/tau), que decae con el tiempo (con tau = 15, un viaje de 15 min pesa 0,37). Elige la particion que maximiza la modularidad (mas peso dentro de los grupos que el esperable al azar) y decide solo cuantos grupos hay. Tau chico da grupos chicos; tau grande los junta. Aca tau = 15.
   - `comunidades.csv` tiene los tres metodos para U = 15, 20, 30, 45, 60 min y tau = 10, 15, 20, 30.
6. **Grupo central.** El grupo de la sede mas cercana al centro del cuadrado; su tamano es una primera medida de hasta donde llega el aglomerado (`central_*` en resumen.csv).
7. **Lo construido.** Urbano de MapBiomas Argentina 2022 (coleccion 2, clase 24, 30 m), en vino en los mapas. Las manchas son el urbano conectado, uniendo las que estan a menos de 200 m (a 30 m el urbano se corta en avenidas, rios y plazas). Cada sede toma la mancha que mas aparece a 300 m de ella. Si una sede esta en la misma mancha que la sede central, el aglomerado es fisicamente continuo hasta ahi; si esta en el mismo grupo pero en otra mancha, la une el viaje y no lo construido.
8. **Validacion contra INDEC.** La lista de localidades censales 2010 que forman cada aglomerado EPH (INDEC, `localidades_aglomerados_eph.xls`) se cruza por nombre con las sedes del cuadrado. Para cada localidad que coincide con una sede se mira si cae en el grupo central: si el metodo reproduce el aglomerado oficial, todas deberian caer ahi. Las localidades que no son sede de gobierno local (barrios, parajes) no tienen punto y quedan sin validar (`validacion_eph.csv`).

Cada mapa: a la izquierda enlace promedio, a la derecha Leiden; el color es el grupo (la numeracion es propia de cada panel). Las lineas son el arbol de expansion minima del tiempo, el conjunto de viajes mas cortos que conecta todas las sedes, dibujado en recta: cortar sus tramos de mas de U min da el enlace simple a U. Gris: perimetro de analisis; punteado: el cuadrado.


## 2 · Calles: percolación de intersecciones


1. **Intersecciones.** Nodos de la red de calles de Overture donde se juntan 3 o mas tramos, en el cuadrado del paso 29 (calles manejables: sin sendas, veredas ni ciclovias; un puente cuenta como cruce).
2. **Percolacion** (Arcaute et al. 2015, J. R. Soc. Interface 12: 20140745). Dos intersecciones se unen si estan a menos de d metros; cada componente conexa es una ciudad. Se barre d de 20 a 2000 m (cada 10 m hasta 500, cada 50 hasta 2000). El tamano de la ciudad crece a saltos: los saltos marcan los d donde cambia lo que se esta llamando ciudad, y las mesetas entre saltos son los d defendibles.
3. **La ciudad a cada d.** La componente con mas intersecciones dentro del perimetro de analisis (EPH, paso 07). Su area: las celdas de 20 m a menos de d/2 de una de sus intersecciones.
4. **Radios censales 2022.** Un radio es de la ciudad si al menos 50% de su area cae en ella, y del perimetro EPH si al menos 50% cae en el perimetro. A cada d se cuentan radios y personas en los dos, solo en la percolacion y solo en el EPH.
5. **Criterio principal (propuesto): d cubre 99%.** El menor d al que la ciudad contiene el 99% de las intersecciones del perimetro EPH. Se calcula sobre todo el barrido, no solo los d mapeados. A ese d, los radios "solo percolacion" son lo que la red de calles agrega al aglomerado oficial, y los "solo EPH" lo que el perimetro tiene y la red no une al nucleo.
6. **Diagnostico: d cubre 100%.** El menor d que contiene todas las intersecciones del perimetro. Es fragil: si el perimetro tiene un fragmento lejano o mucho campo vacio, solo se alcanza a d muy alto, y para llegar la percolacion encadena localidades vecinas. Cuando d cubre 100% queda muy por encima de d cubre 99%, el perimetro EPH tiene partes que conviene revisar a mano.
7. **Referencia: el d que mejor reproduce el EPH.** Entre los d mapeados, el que deja menos personas en radios que difieren (solo percolacion + solo EPH).
8. **Mapa final** (paso 31). La ciudad a d cubre 99% (a 2000 m si no lo alcanza) con las sedes de gobierno local del paso 29, coloreadas por su comunidad de Leiden (tau 15 y 30 min) y unidas al nucleo de su grupo: la sede con menor tiempo total de viaje al resto, sin ponderar por poblacion. Muestra donde la continuidad fisica de las calles y las comunidades por tiempo de viaje coinciden y donde no.



## 3 · Píxeles: percolación del construido de MapBiomas


1. **Construido.** Urbano de MapBiomas Argentina 2022 (coleccion 2, clase 24, 30 m) en el cuadrado del paso 29 (70 km; 100 km en la ventana extra de Gran Buenos Aires).
2. **Percolacion** (City Clustering Algorithm: Rozenfeld et al. 2008, PNAS 105: 18702; Rozenfeld, Rybski, Gabaix y Makse 2011, American Economic Review 101: 2205). Dos celdas urbanas estan en la misma ciudad si hay una cadena de celdas urbanas a menos de d entre si. Es la percolacion del paso 30 sobre pixeles construidos en lugar de intersecciones de calles. Se barre d de 30 a 2000 m.
3. **La ciudad a cada d.** La mancha con mas urbano dentro del perimetro de analisis (EPH).
4. **Dos objetivos para elegir d.** (a) **EPH**: el menor d al que la ciudad contiene el 99% del urbano dentro del perimetro EPH. (b) **Calles**: el menor d al que la ciudad contiene el 95% del urbano dentro de la ciudad por percolacion de calles del paso 30 (a su d cubre 99%). El (b) pregunta cuanto hay que dilatar lo construido para reproducir lo que la red de calles ya une. Es 95% y no 99%: la red de calles une caserios a lo largo de las rutas que lo construido no une ni a 2000 m.
5. **Radios 2022.** Un radio es de la ciudad de pixeles si al menos 50% de sus celdas urbanas estan en ella; los radios sin urbano no entran, asi que los radios rurales grandes no pesan por su area. Se comparan con los del perimetro EPH (al menos 50% del area dentro) y con los de la ciudad de calles (al menos 50% del area dentro, paso 30).


## 4 · Combinado

**Mapa final** (paso 31). La ciudad a d cubre 99% (a 2000 m si no lo alcanza) con las sedes de gobierno local del paso 29, coloreadas por su comunidad de Leiden (tau 15 y 30 min) y unidas al nucleo de su grupo: la sede con menor tiempo total de viaje al resto, sin ponderar por poblacion. Muestra donde la continuidad fisica de las calles y las comunidades por tiempo de viaje coinciden y donde no.

## Limitaciones


- Overture junta OpenStreetMap y otras fuentes: donde el mapeo de calles es pobre, la percolacion subestima la ciudad.
- Los cruces a distinto nivel (puentes, autopistas) cuentan como intersecciones.
- El buffer d/2 redondea los bordes: a d grande un radio rural grande puede pasar el corte del area solo por el buffer.
- La regla del area penaliza los radios grandes del borde, que pueden tener un barrio en una esquina.
- Personas: censo 2022 por radio (paso 09, copia CEUR-CONICET de los datos del INDEC).

- MapBiomas clasifica urbano a 30 m: barrios de baja densidad o con mucha vegetacion pueden quedar afuera.
- La regla de radios cuenta celdas urbanas: un radio con poco construido pero conectado entra entero, aunque su area sea rural.
- El objetivo (b) hereda los supuestos del paso 30 (calles de Overture, cruces a distinto nivel).
- Personas: censo 2022 por radio (paso 09, copia CEUR-CONICET de los datos del INDEC).
