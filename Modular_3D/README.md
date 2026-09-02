# Modular_3D 4.8.6-beta.1 · Frentes de cajón: 3mm fijos entre sí, sin importar la fuga mecánica

**Autor:** Lenin Vladimir Peñafiel Buestán  
**Versión:** 4.8.6-beta.1  

## Cambios 4.8.6-beta.1

- **Corregidos los huecos enormes entre frentes de cajón:** cada frente se dimensionaba y posicionaba pegado a su propia caja de cajón, cuya fuga mecánica con la caja vecina es de 30mm por defecto (`drawerGap`) — como el frente solo restaba 1.5mm por lado a partir de ahí, el hueco visible entre dos frentes vecinos terminaba siendo de 30+1.5+1.5 = 33mm en vez de 3mm. Ahora cada frente se calcula por su propia zona, que llega hasta la MITAD de la fuga mecánica con el cajón vecino (no hasta el borde de su propia caja): así el frente se "traga" el hueco mecánico completo por fuera y solo queda una junta fina y fija de 3mm (1.5mm de cada frente) entre frentes vecinos, sin importar cuánta fuga mecánica se pida entre cajones. Contra el borde real del espacio (arriba del todo o abajo del todo, por ejemplo contra una puerta o el casco) deja 1.5mm, igual que un frente vecino en otro espacio — dando 3mm también ahí. Aplica igual a "Uno por cajón" y a "Único · acoplado al cajón de abajo" (que ahora cubre el espacio completo con 1.5mm arriba y abajo, en vez de solo la altura sumada de las cajas). Reflejado también en la vista previa 3D.

## Cambios 4.8.5-beta.1

- **"Puerta del espacio" ya no compite en silencio con "Cajones con frentes":** ese campo (y sus dependientes: Apertura, Cantidad externa) ahora se oculta automáticamente cuando el contenido del espacio es "Cajones con frentes" — en ese modo una puerta real nunca tenía sentido ahí (competían por el mismo plano), así que ya no aparece para evitar que alguien lo toque por costumbre y desactive el frente adosado sin darse cuenta. Al volver a un contenido con puerta, reaparece normal.
- **Nueva opción "Frente de cajón"** (solo visible con "Cajones con frentes"), con tres estilos:
  - **Uno por cajón** (el de siempre): cada cajón tiene su propio frente.
  - **Único · acoplado al cajón de abajo**: un solo frente cubre toda la pila de cajones de esa columna y se desliza junto con el cajón más bajo al interactuar; los demás cajones de esa columna se siguen abriendo de forma independiente, pero sin frente propio (quedan ocultos detrás del frente único mientras están cerrados).
  - **Falso · fijo, sin cajón**: un panel fijo (no es componente dinámico, no se abre) que cubre todo el espacio; en ese caso no se crea ningún cajón real detrás.
- Reflejado también en la vista previa 3D (MODULAR-3D VIEW) para que coincida con lo que se va a construir.

## Cambios 4.8.4-beta.1

- **Corregido el frente exterior de cajón (jerarquía):** reutilizaba por error la misma fuga de 30mm del espacio mecánico entre cajones (`drawerGap`) como si fuera también su luz de acabado contra el casco, dejándolo 60mm más angosto de lo debido y con un reveal enorme entre frentes vecinos. Ahora tiene su propia luz fina, independiente del espacio mecánico entre cajones: la mitad de "Fuga perimetral" del espacio (1.5mm por lado por defecto, igual que una puerta), en los cuatro lados. Si el resultado no deja tamaño positivo, se omite en silencio en vez de dibujar una pieza inválida.
- **Tipo de bisagra según el solape real de cada puerta**, siguiendo la convención estándar de herrajes (recta / semicodada / codada): se mide cuánto solapa el borde de la puerta donde va la bisagra contra el panel real de ese lado (lateral propio del casco, división central compartida con otra puerta, o ninguno) y se compara con las dos referencias de la industria — solape ≈ espesor − 1.5mm → **recta**, solape ≈ espesor / 2 → **semicodada** —, tomando la más cercana como tolerancia natural en vez de cortes fijos. Puertas embutidas o internas siempre son **codada**. La columna "Bisagrado" del despiece ahora muestra, por ejemplo, "3 bisagras Recta (3 perf. Ø35mm)".

## Cambios 4.8.3-beta.1

- **Corregido el bug de subtotales en "Cantos" y "Herrajes estimados" del Presupuesto (siempre mostraban 0.00):** la función `numero()` del script de recalculo leía `.value`, pero esas celdas (metros de canto, cantidad de bisagras/correderas/jaladores) son `<td>` de solo texto, sin `.value` — siempre daba `NaN` y caía a 0. Se agregó `numeroTexto()` para leerlas por `.textContent`; "Tableros por material" no tenía este problema porque ya usaba `.value` de inputs reales.
- **Nueva opción "Por costo total del tablero" en cada fila de material:** además del "Precio por m²" de siempre (que sigue funcionando exactamente igual si no se toca), se puede activar un enlace por fila que pide ancho x largo del tablero completo y su costo total, y calcula el precio por m² a partir de eso (`costo_total / área_tablero`) reusando el mismo cálculo de subtotal de siempre.
- **Bisagras calculadas automáticamente según la altura real de cada puerta**, en vez de un fijo "2 por puerta": 2 hasta 900mm, 3 hasta 1600mm, 4 hasta 2200mm, 5 en puertas más altas. Solo cuentan puertas reales (código "PT") — un frente de cajón exterior, aunque salga a la altura de la puerta, no es una puerta y no suma bisagras.
- **Despiece: nueva columna "Bisagrado"** que indica, pieza por pieza, cuántas bisagras lleva cada puerta y cuántas perforaciones de Ø35mm implica, según su altura real (independiente del orden de las medidas 1/2, que se ordenan para el listado de corte). Piezas que no son puertas quedan en blanco. Incluida también en la exportación a Excel/CSV.

## Cambios 4.8.2-beta.1

- **Corregido el cajón que aparecía lejos del módulo (con una arista larguísima uniéndolo):** el grupo que contiene todo el cajón fijaba su posición ANTES de convertirse en componente en vez de después; `to_component` no conserva esa transformación puesta sobre el `Group` original, así que el cajón terminaba colocado cerca del origen del mundo en vez de en su lugar real dentro del módulo. Se corrigió el orden (igual que ya hace `crear_pieza` en todos lados: primero convertir a componente, después fijar la posición sobre la instancia resultante).
- **Espacio entre cajones ahora es de 30 mm por defecto** (antes 3 mm, heredado del campo de fuga de puertas) — aplicado siempre entre cajón y cajón, y entre el primero/último cajón y la base, techo o repisa que los encierra. Es su propio campo ("Espacio entre cajones"), independiente del usado para puertas.
- **Nueva opción "Altura de cajón (mm)"** para fijar manualmente la altura de cada cajón en vez del reparto automático; si el valor pedido no entra junto con las fugas de 30 mm, se ignora en silencio y se usa la altura automática (nunca se solapan cajones).

## Cambios 4.8.1-beta.1

- **Corregida la puerta con bisagra derecha (Dynamic Components):** el mecanismo de la versión anterior movía la geometría ya construida y la compensaba con una transformación — frágil, y era la causa real de la puerta rota / "algo más grande invisible" al crecer el módulo a dos puertas. Se reemplazó por construcción directa espejada (mismo patrón ya probado que usaba el generador de puertas antiguo, con `face.reverse!` si la normal queda mirando hacia abajo), verificada con un guion numérico (Newell + comparación de rango en el mundo) antes de integrarla. Sin mover geometría después de creada.
- **"Hueco delantero/trasero" ahora es "Sobremedida delantera/trasera"**, con el signo que se pidió: positivo agranda esa pieza hacia ese lado (sobresale), negativo la achica (se retranquea) — resta/suma directa sobre el fondo de la pieza, igual criterio que la sobremedida por pieza individual.
- **Cajón: frente interno vs. frente exterior.** Si un espacio con cajones "con frentes" tiene además su propia puerta, el frente exterior del cajón ya no se construye (competía por el mismo plano) — el cajón se queda con su frente interno, que nunca sobresale.
- **Botón "Actualizar módulo" ya no queda tapado por el cubo de navegación** (ambos vivían en la misma esquina del visor con el cubo por delante); se movió a la esquina opuesta.
- **Despiece: nombres legibles, "Canto duro" en vez de "HARD", color por nombre en vez de hex.** Los códigos internos de pieza (LAT, BAS, PT, REP...) no reconocían los nombres nuevos generados desde la jerarquía (`H_PUERTA_...`, `H_CJ_...`) y se mostraban tal cual, ilegibles — además esto hacía que el presupuesto subcontara puertas y cajones de módulos hechos con la jerarquía. Corregido en la raíz (`codigo_pieza` ahora reconoce los prefijos `H_`/`G_`), con una etiqueta legible en español para mostrar en la tabla.
- **Corregido el "S/P" (sin puerta) en despiece** cuando el módulo sí tenía puertas: el conteo seguía leyendo un campo legado que quedó fijo en "NO" desde la limpieza anterior; ahora cuenta las puertas reales de la jerarquía.
- **Diseño libre: miniatura 3D real por pieza en el despiece**, en vez de únicamente el ícono genérico de mueble — nueva columna "Vista" en la tabla, generada con el renderizador de miniaturas nativo de SketchUp para cada pieza etiquetada manualmente.

## Cambios 4.8.0-beta.1

- **Puertas y cajones interactivos con la mano de Interactuar:** el código de Dynamic Components (`onclick`/`RotZ` con animación) ya existía en el generador de puertas antiguo (`crear_puerta_dinamica`) pero nunca estaba conectado a las puertas que arma la pestaña Configuración (jerarquía), que siempre construía piezas planas sin ningún comportamiento. Ahora toda puerta creada desde la jerarquía es un componente dinámico real: se abre/cierra con un clic usando la herramienta nativa "Interactuar" de SketchUp, respetando la bisagra elegida en "Apertura" del espacio (o abriendo hacia afuera en puertas dobles/triples). Los cajones se agrupan completos (laterales, frente, fondo, trasero y frente exterior) en un único componente con el mismo mecanismo pero deslizando en profundidad, así que el cajón y su frente salen juntos con un clic.
- **Quitados jaladores, sistema gola y puertas de vidrio:** se eliminó por completo la generación de estas piezas (`agregar_sistema_apertura`, `aplicar_material_vidrio`) y sus campos de configuración, a pedido explícito. Los ajustes de puertas/cajones que sí seguían usándose (grosor de puerta, luces, retiro de cajones, sistema de corredera, refuerzo de piso) se reubicaron dentro de "Configuración", donde antes vivían en una página completa que quedó inalcanzable tras una limpieza de una versión anterior y por lo tanto esos ajustes quedaban congelados en su valor por defecto sin ninguna forma de tocarlos.
- **Eliminado el resto de la interfaz muerta encontrada en la auditoría**: el panel duplicado de "Propiedades del espacio" (reemplazado hace tiempo por el editor de jerarquía, pero seguía ejecutándose oculto en cada actualización de vista) y sus botones que nunca podían pulsarse.
- **Huecos/retranqueos: validación en vivo y valores negativos con significado real.** Antes `validar()` en el navegador no revisaba límites de huecos —solo Ruby, y recién al construir—, así que un valor inválido se aceptaba sin aviso hasta el final. Ahora el mismo chequeo corre en vivo en el paso Casco, con un texto que muestra el fondo resultante de cada panel actualizado con cada tecla. Además, un hueco negativo ya no se rechaza: significa que el panel sobresale hacia afuera en lugar de retranquearse hacia adentro (útil para zócalos o repisas voladas), limitado a un máximo razonable para no vaciar el panel de fondo.
- **Despiece y presupuesto ya no exigen selección:** si no hay nada seleccionado, toman todo el modelo activo. Antes, una pieza de diseño libre correctamente etiquetada podía no aparecer nunca en el despiece simplemente porque el usuario olvidó seleccionarla junto con el resto antes de generar.
- **Corregidos tres defectos reales en "Editar módulo"** que podían hacer que un módulo reeditado no coincidiera con el original: (1) si la configuración jerárquica llegaba dañada o vacía, la reconstrucción caía en silencio a una caja legada casi vacía en vez de avisar del error — ahora se bloquea la construcción con un mensaje claro; (2) los módulos creados con "Convertir selección en módulo" nunca guardaban su punto de referencia de posición (`module_base_offset`), lo que podía duplicar el desplazamiento al reeditarlos — ahora se calcula y guarda siempre; (3) la transformación de una edición anterior podía quedar arrastrada a una edición distinta si la anterior se canceló sin construir — ahora se limpia explícitamente al iniciar cada edición.
- **El visor 3D respeta los mismos topes que Ruby** (20 repisas, 12 cajones por espacio) para no mostrar en vivo una cantidad que luego se recorta silenciosamente al construir.

## Cambios 4.7.3-beta.1

- **Corregido el cubo de navegación (mostraba la cara equivocada):** al portar el cubo CSS 3D de MODULAR-3D-VIEW en una versión anterior, se copiaron literalmente sus transformaciones `cube-front`/`cube-back`, pero esa referencia usa una convención de cámara opuesta a la de Modular_3D (en Modular_3D, `setView('front')` ubica la cámara en dirección `[0,0,1]`; en la referencia es al revés). Resultado: al mirar el módulo de frente, el cubo mostraba "ATRÁS" hacia el usuario y viceversa — desorientador. Se intercambiaron únicamente las transformaciones CSS de esas dos caras (`front` pasa a la posición sin rotar, `back` a la rotada 180°); las caras derecha/izquierda/arriba/abajo ya estaban correctamente adaptadas y no se tocaron. Verificado el razonamiento con la propia lógica de `setView`/`syncNavigator` del archivo antes de aplicar el cambio.

## Cambios 4.7.2-beta.1

- **Inglete horizontal (lateral con techo/base):** el inglete a 45° ahora cubre también el caso clásico de esquina de mueble donde un LATERAL se encuentra con el TECHO o la BASE, distinto del inglete vertical ya existente (costura entre dos laterales, constante en toda la altura). El nuevo corte es constante en todo el fondo de la pieza y se elige por esquina: superior/inferior × exterior/interior (`top_outer`, `top_inner`, `bottom_outer`, `bottom_inner`). Selector de esquina agrupado por tipo (vertical/horizontal) en el editor de pieza individual; geometría verificada por separado con un guion numérico (sentido de recorrido, normal y límites del polígono) antes de integrarla, igual que el inglete vertical original.
- **Cubo de navegación más chico:** el cubo CSS 3D portado en la versión anterior se redujo de tamaño (`--nav-size`/`--cube-size`) para ocupar menos espacio sobre el visor.
- **Ajuste posterior/frontal y respaldo heredan el color del casco:** ambos grupos de material arrancan con el mismo color que el casco (solo cambia su grosor, p. ej. casco 15/18 mm vs respaldo 6 mm embutido) y se actualizan en vivo si cambias el color del casco, hasta que marques "Material propio del grupo" para desvincularlos y darles un color independiente.
- **Revisado de nuevo el reporte de "el hueco funciona al revés":** no se encontró ningún defecto adicional en el código (misma conclusión que en 4.7.1-beta.1, verificada otra vez desde cero). Los campos se llaman literalmente "Hueco delantero/trasero": al aumentarlos, el hueco (separación) efectivamente aumenta y el fondo de ESE panel se reduce en la misma medida (fondo del panel = fondo total − huecos) — es el comportamiento esperado de un retranqueo, no uno invertido. Se agregó un texto explicativo junto a esos campos en el paso de Casco para dejarlo explícito, por si la medida que se estaba comparando en SketchUp era otra (por ejemplo el fondo total del módulo, que no cambia, en vez del fondo de ese panel puntual).

## Cambios 4.7.1-beta.1

- **Migración real de piezas externas:** "Convertir selección en módulo" ahora etiqueta cada pieza detectada (lateral izq./der., base, techo, respaldo, repisa, división) con los mismos atributos que una pieza paramétrica (código, dimensiones, placa, cantos), no solo el contenedor completo. Antes el módulo quedaba visualmente correcto pero invisible para Despiece/Presupuesto/Optimizador porque a las piezas individuales nunca se les asignaba `codigo`. También distingue selecciones de un solo grupo con varios sub-grupos hijos (baja un nivel y etiqueta cada hijo) y avisa si hay geometría suelta sin agrupar que no se pudo separar en piezas.
- **Cubo de navegación 3D real:** se reemplazó el cubo plano en SVG (una imagen isométrica fija que solo resaltaba un color) por un cubo CSS genuino con 6 caras que rotan de verdad (`transform-style: preserve-3d`), cada una con una grilla de 9 vistas (centro + 8 oblicuas), arrastrable con el mouse y con flechas de órbita, igual en técnica al de github.com/VLADIMIR1991-05/MODULAR-3D-VIEW pero conectado al sistema de cámara que ya tenía Modular_3D (reutiliza `setViewVector`, no duplica lógica de movimiento).
- **Investigado el reporte de "Hueco delantero no obedece":** revisé la cadena completa (ids de campo, `datosFormulario`, `build()`, `addPiece`) y no encontré un defecto de código — la asignación X/Y/Z del retranqueo frontal coincide exactamente con la de `crear_pieza` en Ruby. Sí confirmé dos cosas reales: (1) tanto el HTML (`min="0"`) como `Validation.validar` en Ruby rechazan explícitamente valores negativos ("no puede ser negativo"), así que -3 nunca fue un valor soportado por diseño; (2) 3 mm sobre un panel de ~580 mm de fondo es un cambio visualmente muy sutil en la vista isométrica por defecto. Pendiente de confirmar con una prueba con un valor positivo más grande (p. ej. 50 mm) para descartar del todo un problema real.

## Cambios 4.7.0-beta.1

- **Corrección de fondo:** el visor 3D en vivo ahora lee montaje_izq/der/superior/inferior, los 8 retranqueos por panel, lleva_lateral_*/base/techo, la orientación del ajuste posterior/frontal y las 3 variantes de respaldo (SI/INTERNO/SOBREPUESTO) igual que la construcción real; antes siempre mostraba el mismo esquema de laterales pasados sin importar la configuración elegida.
- **Inglete a 45° por pieza:** cualquier pieza admite un corte a 45° en una de sus 4 esquinas verticales (constante en toda su altura), visible en tiempo real en el visor, con columna propia en el despiece/CSV.
- **Módulo esquinero en L:** nuevo comando independiente que arma dos alas con costura mitrada a 45° entre ellas.
- **Montaje de puerta independiente** (solapada/embutida) del montaje del casco, aplicado al sistema de puertas heredado y al ajuste automático por espacio de la jerarquía.
- **IDs estables por espacio** para las piezas generadas desde la jerarquía (H_CIERRE_*, H_CJ_*, H_PUERTA_*, H_DIV_*, etc.): ya no se nombran por posición, así que reestructurar el árbol no desconecta silenciosamente sus overrides de material/sobremedida.
- **Plantillas de módulo** (bajo, alto, closet, mesa de noche, librero) que precargan el formulario desde la pestaña Medidas.
- **Orientación de módulo:** botón para intercambiar ancho/alto exteriores.
- **Render:** cielo de estudio con degradado, modo técnico (líneas ocultas) y cotas 3D en el propio modelo.
- **Optimizador de corte:** casilla "Respetar veta" por tablero de stock para no rotar piezas en materiales con veta.
- **Presupuesto:** nuevo comando que cotiza tableros por material, cantos, herrajes estimados, mano de obra y margen, exportable a PDF.
- **Biblioteca local:** guarda componentes propios como .skp reales organizados por categoría, sin depender de ningún backend en la nube.
- **Edición por lotes:** repinta varios módulos seleccionados a la vez.
- **Diseño libre:** nuevo comando para etiquetar piezas dibujadas a mano y que el despiece/presupuesto las reconozca, completando el flujo junto con "Convertir selección en módulo" ya existente.
- **Habitación básica:** muros rectos y piso a partir de una lista de tramos (largo + ángulo), sin huecos de puerta/ventana todavía.
- Se quitó el botón "Guardar en este espacio" en Configuración: esos campos ya se aplicaban en vivo con cada cambio; el botón no hacía nada adicional.
- Manifiesto migrado a schema 6 (miter_overrides_json, montaje_puerta); los módulos guardados en versiones anteriores se abren igual que antes.

Nota: esta versión no pudo probarse dentro de una sesión real de SketchUp (entorno de desarrollo sin la aplicación instalada). La sintaxis Ruby/JS/JSON de todo el proyecto se validó con herramientas de línea de comandos y la geometría nueva (inglete, muros) se verificó por separado con guiones numéricos, pero la primera apertura dentro de SketchUp debe tratarse como la prueba real.

## Cambios 4.6.0-beta.1

- Casco activable: laterales, base y techo pueden desactivarse individualmente (paso 2) para módulos abiertos o apoyados contra pared/mueble vecino, sin alterar la cavidad interior calculada.
- Ajuste frontal independiente del posterior, con orientación propia (rail horizontal de ancho completo o escuadras en las esquinas). El posterior también puede pasar a escuadras.
- Sobremedida por pieza: cualquier pieza individual (repisa, lateral, ajuste, etc.) admite un delta en mm de más o de menos sobre la medida calculada automáticamente, desde el editor de pieza en el paso 4.
- Manifiesto de módulo migrado a schema 5; los módulos guardados en versiones anteriores se abren igual que antes (todos los paneles activos, sin ajuste frontal, sin sobremedidas).
- Limpieza interna: se retiraron el constructor de ambiente 3D, la biblioteca local de módulos y otras herramientas ya inalcanzables desde el menú/toolbar (no afectan módulos existentes), y se eliminó un parser de estaciones paramétricas duplicado.

## Cambios beta.13

- Barra de navegación inferior integrada en el flujo, sin cubrir controles ni formularios.
- Un único desplazamiento para el configurador y otro independiente para MODULAR-3D VIEW.
- Puertas exteriores por espacio calculadas sobre el plano del casco y no dentro del hueco.
- Solape automático hasta el eje de laterales, repisas y divisiones físicas.
- Fuga predeterminada de 1,5 mm por hoja: junta final de 3 mm entre puertas contiguas.
- Solapes manuales independientes a izquierda, derecha, arriba y abajo.
- Contrato geométrico v4 compartido por plano 2D, visualizador, construcción y edición.

## Base heredada de beta.12

- Material general con color, archivo de imagen, URL o elemento de biblioteca.
- Escala y dirección de veta conservadas en el manifiesto del módulo.
- Texturas por grupo y por pieza con herencia y excepciones.
- Puertas exteriores globales o por espacio, con cantidad automática/manual y fugas independientes.
- Hasta ocho hojas exteriores y separación central exacta.
- El modo global conserva puertas internas y sustituye únicamente los frentes exteriores por espacio.

## Base heredada de beta.11

- Restaura silenciosamente la sesión guardada; solo vuelve a pedir credenciales si no existe token válido o el usuario pulsa **Cerrar sesión**.
- Carga determinísticamente el manifiesto completo al editar, después de inicializar jerarquía, materiales y visor.
- Conserva el espacio seleccionado y usa un contrato geométrico versionado para el 2D, el 3D y la construcción real.
- Corrige las puertas externas: se colocan delante del plano frontal y la opción automática genera una o dos según el ancho.
- Guarda cambios de contenido, repisas, cajones y puertas en el espacio en cuanto se modifican.
- Añade estrategia de canto global: mixto, todo PVC o todo canto duro.
- El modo mixto aplica canto duro a puertas/frentes y PVC al casco e interiores.
- El color del canto hereda el material de cada pieza; las excepciones individuales pueden cambiar tipo y color.
- Incluye tipo y color de canto en despiece, CSV y PDF.
- Unifica identificadores de puertas entre configurador, visor y geometría SketchUp.
- Migra manifiestos anteriores al esquema 2 sin perder módulos beta.10.

## Cambios beta.10

- Cada mueble nuevo se encapsula como un único módulo maestro seleccionable.
- El módulo conserva un manifiesto versionado con medidas, casco, jerarquía de espacios, materiales, cámara e inventario de piezas.
- **Editar módulo** abre directamente los cuatro pasos con los valores reales guardados, sin reconstruir valores aproximados ni solicitar únicamente el nombre.
- Al actualizar se conserva el UUID, la posición y la rotación del módulo seleccionado.
- Los módulos creados por beta.9 se migran al nuevo contenedor durante su primera edición.
- **Convertir selección en módulo** encapsula geometría externa y genera un inventario inicial para revisión.
- La imagen del despiece se captura con fondo blanco y sin rejilla, resaltados, espacios activos ni controles del visor.
- Cada módulo conserva su propia cámara para el despiece y para futuras ediciones.

## Cambios beta.9

- Corrige el bloqueo al seleccionar piezas del casco y evita ciclos entre el formulario y el visor.
- Sitúa repisas y divisiones al ras del frente y limita su fondo con el sistema posterior configurado.
- Sincroniza el grosor del ajuste posterior con el espesor general cuando la opción está activa.
- Añade material único para todo el módulo, excepciones por grupo y acabados individuales por pieza.
- Distingue geométricamente puertas internas y externas; las externas quedan delante del plano frontal.
- Retira las variantes de puerta de vidrio del configurador.
- Aleja el encuadre inicial para mostrar el módulo completo.

El creador paramétrico incorpora directamente el motor local de **MODULAR-3D VIEW**: iluminación física, sombras suaves, cámara ortográfica y perspectiva, navegador de vistas, árbol y propiedades de piezas, transparencia, aristas, rejilla y explosión regulable. La antigua sección de vista previa fue retirada completamente.

La V7 incorpora autenticación en línea y control de licencia en producción sin modificar la V6.

## Seguridad incorporada

- Acceso por correo y contraseña.
- Contraseña nunca almacenada por el plugin.
- Token temporal firmado por el servidor.
- Una o varias PC según la licencia.
- Validación de vencimiento y bloqueo.
- Heartbeat cada 15 minutos.
- Construcción y generación de ambientes protegidas desde Ruby.
- Cierre de sesión.
- Opción de traslado para pruebas.

## Servidor de producción

El RBZ apunta a `https://api.modular-3d.com/api/v1` y requiere conexión a
Internet. Los usuarios y activaciones se administran desde
`https://api.modular-3d.com/admin`.

Antes de entregar a clientes todavía se recomienda firmar el RBZ y pasar de
la instancia gratuita a una instancia de producción sin suspensión por inactividad.


## 4.2.0 FULL IMOS
- Instalador completo/autónomo.
- Estaciones paramétricas X/Z con proporciones, unidades, porcentajes y AUTO.
- Separaciones físicas o virtuales.
- Conserva diseñador por espacios, cajones, puertas, vidrio, gola, jaladores, iluminación, biblioteca, despiece y edición.
- Visor ampliado y ViewCube reforzado.
- Cotas 3D alejadas de la geometría para mejorar lectura.
- Convención fija: X=ancho, Y=profundidad, Z=altura.
