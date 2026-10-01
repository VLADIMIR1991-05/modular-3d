# Modular_3D 6.4.51 · Miniatura real en el Catálogo + "Forzar salida de puerta" sincronizado en vivo

**Autor:** Lenin Vladimir Peñafiel Buestán  
**Versión:** 6.4.51  

## Cambios 6.4.51

Dos pedidos de esta ronda:

**1. "Forzar salida de puerta (mm)" ahora muestra en tiempo real, en el propio campo (como texto de fondo / placeholder, no como valor forzado), el número que "Automático" va a usar si lo dejás vacío** -- el mismo que ya se calculaba (mayor entre grosor de puerta y espesor de casco, o la sobremedida de un panel si sobresale más). Antes ese campo solo tenía un texto fijo genérico ("Automático (vacío = calculado solo)") y había que leer el aviso de más abajo para saber el número real; ahora se actualiza solo, al toque, si cambiás el grosor de puerta o el espesor del casco. Escribir un valor ahí adentro sigue forzando ESE valor exacto, igual que antes -- esto es puramente que el "automático" ya no es una sorpresa.

**2. Miniatura real en el Catálogo Global** (pedido explícito: "debe mostrarse la foto en miniatura real"). Al guardar un módulo en "5 Catálogo", ahora se sube automáticamente, como foto real, la misma vista 3D que se está viendo en ese momento en el configurador (reusando la captura que ya usa el despiece, no una renderización nueva) -- el servidor ya aceptaba esto del propio dueño del módulo, no hizo falta ningún permiso nuevo. Cada módulo de la lista que todavía no tiene foto muestra un botón "Agregar miniatura" (o "Actualizar miniatura" si ya tiene una) para sacarla de la vista actual sin tener que volver a guardar todo el módulo.

Probé el flujo completo con un navegador real (guardar → subir miniatura automática con el id real devuelto por el servidor; botón "Agregar miniatura" sobre un módulo ya guardado) -- sin errores de JavaScript.

**Pendiente, para la próxima ronda:** el árbol de categorías desplegable (elegiste esta opción junto con la miniatura) -- el servidor ya tiene toda la estructura lista (`catalog_taxonomy`, con crear/renombrar/borrar y permisos por dueño-o-admin), solo falta construir la interfaz en el plugin. Lo sigo en cuanto confirmes que esta parte (miniatura + sincronización del campo) quedó bien.

## Cambios 6.4.50

Pedido explícito del usuario: la salida automática de una puerta solapada ahora nunca es menor que el grosor del propio casco -- gana el mayor entre grosor de puerta y espesor de casco (y sigue ganando cualquier sobremedida de panel que sobresalga más, como ya era). Antes el piso era solo el grosor de la puerta; si la puerta era más angosta que el casco (ej. puerta 12mm con casco 15mm), salía más corta que el propio panel. Corregido en los 3 lugares que calculan esto (`jerarquia.rb` real, `modular3d_view.js` visor en vivo, `interfaz.js` aviso previo) para que sigan coincidiendo entre sí.

De paso, el aviso debajo de "Forzar salida de puerta" ahora **siempre** muestra el valor que va a usar "Automático" (antes solo avisaba si había una diferencia notable) -- para que se vea sin adivinar, sin necesidad de forzar nada a mano.

Verificado por ejecución: puerta 15mm + casco 15mm → 15mm; puerta 18mm + casco 15mm → 18mm (gana la puerta); puerta 12mm + casco 15mm → 15mm (nunca menos que el casco).

## Cambios 6.4.49

Implementé el pedido pendiente de permisos en el Catálogo Global ("cada usuario dueño de su creación, compartir con usuarios puntuales o con todos los que tengan licencia, y un administrador con acceso total"). Revisando el servidor (Cloudflare Worker `modular3d-platform-api`) encontré que **todo ese sistema ya estaba construido ahí** -- dueño (`created_by_user_id`), visibilidad privado/global, tabla de compartidos por usuario (`catalog_module_shares`), y administradores con acceso total (`platform_admins`). Solo faltaba conectarlo desde el plugin, así que no hizo falta ningún cambio de servidor.

**Al guardar un módulo en el Catálogo** ("5 Catálogo"): ahora elegís Visibilidad -- **Privado** (por defecto; solo vos lo ves) o **Global** (todos los usuarios con licencia activa).

**En cada módulo de la lista**: un rótulo muestra si es Privado o Global, y dos botones nuevos:
- **Compartir**: abre un panel para cambiar la visibilidad después de guardado, y (si es Privado) agregar o quitar usuarios puntuales con quienes compartirlo -- con una lista de usuarios con licencia para elegir.
- **Borrar**: lo archiva del Catálogo (con confirmación).

El servidor ya rechaza (y el plugin te avisa) cualquiera de estas dos acciones si no sos el dueño del módulo ni un administrador -- esa verificación vive enteramente ahí, el plugin no duplica nada.

Probé el flujo completo con un navegador real: guardar con cada visibilidad, abrir "Compartir", listar/agregar/quitar usuarios compartidos, y los rótulos Privado/Global en la lista -- sin errores de JavaScript.

**Nota:** un administrador de verdad (gestión de usuarios, licencias, categorías del catálogo) ya tiene su propio panel web separado en el servidor (fuera del plugin de SketchUp) -- no hizo falta construir nada de eso acá.

## Cambios 6.4.48

Confirmaste que el bug de v6.4.47 (puerta embutida en Closet/Auxiliar) era exactamente el campo "Forzar salida de puerta (mm)" con un valor cargado. Para que algo así sea mucho más difícil de pasar por alto, las dos secciones plegables relacionadas con puertas que estaban cerradas por defecto ahora empiezan abiertas:
- "Ajustes de puertas y cajones" (2 Casco) -- incluye "Grosor de puerta" y las luces/fugas entre frentes.
- "Puerta de este espacio" (3 Configuración, por espacio) -- incluye "Puerta del espacio" y "Ajuste de puerta externa".

Ningún otro comportamiento cambia -- es puramente que ahora se ven sin tener que hacer clic para desplegarlas.

**Sobre el Catálogo con permisos por usuario (dueño/compartir/administrador):** el Catálogo Global vive enteramente en el servidor (`api.modular-3d.com`, fuera de este repositorio -- `catalogo.rb` solo hace llamadas HTTP a él). Implementar dueño/compartir/admin requiere cambios en ESE servidor (modelo de datos de usuarios/roles, endpoints nuevos para visibilidad y permisos) antes de que el plugin pueda mostrarlos o usarlos. Te escribo aparte para coordinar cómo seguir con eso.

## Cambios 6.4.47

Encontré la causa real del Closet/Auxiliar con la puerta metida adentro -- reproduje tu escenario exacto (Closet 600×2120×580, Zócalo activo, Externa·una puerta, Solapada) en el visor en vivo y, con esos datos, el cálculo da el resultado correcto. La diferencia tenía que estar en algo que el visor en vivo NO está mirando pero la construcción real en SketchUp sí.

**La encontré:** en "2 Casco" hay un campo "Forzar salida de puerta (mm)" (bajo "Puertas frente a sobremedida") cuya propia etiqueta dice "escribir 0 fuerza todas las puertas a quedar a ras (sin sobresalir nada)". En `jerarquia.rb` (la construcción real) ese campo se aplica apenas no está vacío. Pero en `modular3d_view.js` (el visor en vivo) había una condición que exigía además que un desplegable "Modo" estuviera en 'MANUAL' -- un valor que ese desplegable **nunca puede tener** (sus únicas 2 opciones reales son "Automático (silencioso)" y "Automático y avisar...", ninguna es "Manual"). Esa condición imposible hacía que el visor en vivo **ignorara por completo** ese campo, mientras que la construcción real sí lo aplicaba.

Si en algún momento quedó algo cargado en "Forzar salida de puerta" para ese Closet/Auxiliar (por ejemplo un "0", quizás de una prueba anterior) -- el visor seguía mostrando la puerta bien (porque la ignoraba), pero al construir de verdad en SketchUp, la puerta nacía exactamente a ras (embutida por su propio grosor, sea cual sea), coincidiendo con lo que describiste.

**Corregido en `modular3d_view.js`:** ahora respeta ese campo con el mismo criterio que `jerarquia.rb` (alcanza con que no esté vacío, sin exigir el "modo" inexistente). De ahora en más, si queda algo cargado ahí, el visor en vivo también lo va a mostrar -- no va a volver a pasar que "se vea bien en el visor pero mal al construir" por este campo en particular.

**Por favor revisá ese Closet/Auxiliar:** andá a "2 Casco" → "Puertas frente a sobremedida" → "Forzar salida de puerta (mm)" y fijate si tiene algo cargado. Si es así, borralo (dejalo vacío) y actualizá el módulo -- la puerta debería salir protruyendo normal. Avisame si después de instalar esta versión el visor en vivo ya muestra la puerta mal ahí mismo (eso confirmaría del todo el diagnóstico, ya con el visor y la construcción real coincidiendo).

## Cambios 6.4.46

Encontré un bug real, presente desde v6.4.40: cada vez que edicionabas un módulo con "Actualizar módulo", se le sumaba OTRA VEZ el offset de posicionamiento en Y (`offset_y_modulo`, el mismo que ya tenía aplicado de la vez anterior) -- porque `@offset_edicion` ya se lee de la posición REAL actual del módulo en la escena (que ya incluye ese offset desde que se construyó o desde la última edición), y el código se lo volvía a sumar encima. Resultado: cada edición corría el módulo un poco más en Y, acumulándose edición tras edición -- lo que reportaste como "la puerta se crea bien pero jala todo el módulo hacia adelante la misma cantidad del grosor de la puerta" en un Bajo.

**Corregido en `jerarquia.rb`:** al editar un módulo existente, ya no se vuelve a sumar `offset_y_modulo`/`altura_piso_modulo` -- se usa `@offset_edicion` tal cual, exactamente como ya funcionaba antes de que existiera ese offset (v6.4.39 y anteriores). Al construir un módulo NUEVO no cambia nada, sigue aplicándose igual que siempre. Verifiqué por ejecución 2 ediciones seguidas del mismo módulo: antes del fix arrastraba +20mm por edición (acumulativo); con el fix queda estable en la misma posición sin importar cuántas veces lo edites.

**Pendiente de resolver, necesito un dato tuyo:** me confirmaste que en el Closet/Auxiliar de tu segunda captura, "Puerta del espacio" estaba en Externa y "Montaje de puerta" en Solapada (ambos correctos para una puerta que debería sobresalir hacia el frente) -- pero igual nace metida adentro del módulo. Repasé el código y no encontré todavía por qué pasaría eso específicamente en Closet/Auxiliar y no en Bajo. Para encontrar la causa exacta como la vez pasada (cuando me diste "son 15mm, el grosor de la puerta" y eso me permitió dar con el bug real): **¿cuánto mide, en mm, esa puerta metida hacia adentro respecto al canto frente del casco?** Con ese número puedo calcular qué fórmula está dando ese resultado exacto.

## Cambios 6.4.45

Encontré la causa exacta de lo que reportaste: la pieza que crea "Sincronizar continuidad" al fusionar varios módulos (Zócalo/Cornisa/Premesón) se construye con `@datos_modulo_actual` vacío a propósito -- ese comando mezcla piezas de módulos distintos en una sola pasada, así que no puede recalcular "el color configurado" de ningún módulo en particular. El efecto secundario: la pieza fusionada caía en un color/nombre genérico de respaldo (`Material = "Zocalo"/"Cornisa"/"Premeson"`, un tono anaranjado fijo) en vez de tu Blanco configurado.

**Corregido en `continuidad.rb`:** en vez de recalcular el color desde la configuración (que no está disponible ahí), la pieza fusionada ahora copia tal cual el material/color/canto real que ya tenía la pieza original que reemplaza -- la misma que ya estaba pintada de Blanco (o el color que hayas configurado) antes de fusionarse. Por defecto sale del mismo color; después la podés recolorear a mano como cualquier otra pieza, igual que ya podías hacer con las demás.

**Por favor instala esta versión y volvé a correr "Sincronizar continuidad"** (o deshacé y repetí la sincronización si ya la corriste) -- la pieza fusionada debería salir en Blanco ahora, no con un color/nombre distinto por tipo de pieza.

## Cambios 6.4.44

Ajuste puntual sobre v6.4.40/41: la altura de piso fija de los módulos Alto era 1500mm y debía ser **1486mm** (14mm más abajo). Cambiado en `jerarquia.rb`. Un Alto más alto (por ejemplo 950mm en vez del alto por defecto) sigue creciendo hacia ARRIBA desde ese mismo piso -- nunca hacia abajo -- porque la base del módulo (Z local = 0) es justo lo que se posiciona en Z=1486mm; todo lo demás (zócalo/premesón no aplican a Alto, pero cornisa y remates si están activos) sigue relativo a esa misma base, así que no se desalinea nada más.

## Cambios 6.4.43

Corrección sobre v6.4.42: había hecho el canto de Zócalo y Cornisa condicional a los remates, cuando en realidad **siempre** cantean sus 2 extremos (lado 2 y lado 4) -- con remate, sin remate, o aunque se junten con otro módulo. Solo el Premesón es la excepción condicional.

**1) Zócalo y Cornisa: cantos_c=2 fijo, siempre** (`jerarquia.rb`). Ya no dependen de `remate_inicial`/`remate_final`.

**2) Premesón: sigue siendo condicional** (sin cambios respecto a v6.4.42) -- su extremo no cantea si ese lado tiene remate. La diferencia real es que, cuando dos Premesón de módulos vecinos quedan pegados (una junta que no se ve una vez unida), esa junta tampoco debe cantear, a diferencia de Zócalo/Cornisa que sí cantean aunque se junten.

**3) `continuidad.rb` corregido para que esta regla sobreviva a "Sincronizar continuidad".** Antes, el tramo fusionado (la pieza única que reemplaza a varias piezas individuales pegadas, hasta 2420mm) llevaba SIEMPRE `1L-1C` sin importar si era Zócalo, Cornisa o Premesón -- un hardcodeo que no tenía nada que ver con esta regla. Ahora:
   - Zócalo/Cornisa fusionados: `0L-2C` siempre, igual que los individuales.
   - Premesón fusionado: `1L` + cantos cortos según si el extremo REAL del tramo (el lado izquierdo del primer módulo que lo compone, el lado derecho del último) tiene remate de ese lado -- las juntas internas entre los módulos que el tramo fusiona ya no cuentan como extremos, porque ahora son una sola pieza.

Verifiqué las 3 combinaciones (individual, fusionado con remate en un extremo, fusionado sin remates) por ejecución.

**Por favor instala esta versión y revisá el mismo despiece de antes** (el de la captura que mandaste) -- Zócalo y Cornisa deberían mostrar `0L-2C` siempre, sin importar remates; Premesón debería seguir siendo condicional como ya estaba.

## Cambios 6.4.42

Convención de 4 lados por pieza confirmada contigo: **1**=canto/borde frente (visible por defecto), **3**=atrás (opuesto, oculto), **2**=extremo derecho (o arriba en un Lateral), **4**=extremo izquierdo (o abajo en un Lateral). Con eso:

**1) Cantos (despiece) corregidos según esa convención:**
- **Zócalo y Cornisa**: ya NO llevan canto en su lado largo (el frente va laminado como cara, no como canto de borde -- eso ya estaba bien via color). Solo cantean sus dos extremos cortos (lado 2/lado 4), y solo el/los que de verdad queden expuestos: si ese lado tiene remate (Izq=inicial/Der=final) activo, el remate ya tapa el corte y no hace falta cantearlo. Con ambos remates activos: 0 cantos cortos. Con uno solo: 1. Sin ninguno: 2.
- **Premesón**: sigue con su canto de frente fijo (lado 1, como ya estaba bien), y ahora sus dos extremos (lado 2/lado 4) siguen la MISMA regla condicional que zócalo/cornisa (antes era fijo en 1, sin importar si había remates).
- **Lateral de un Alto**: además del canto de frente (lado 1, como siempre), ahora también cantea su canto de abajo (lado 4) -- al quedar colgado en alto, su cara inferior queda a la vista para quien mira hacia arriba. El lateral de un Bajo sigue igual que siempre (solo lado 1).

**2) Colores corregidos:**
- **Premesón**: revierto el cambio de v6.4.41 que lo hacía heredar el color único del módulo -- **no era lo que pediste**. Ahora su acabado se restringe a solo 2 opciones (Crudo/Blanco, nuevo selector en "Opciones avanzadas"), independiente de cualquier otro color configurado. Su **canto**, en cambio, siempre hereda el color de canto/PVC del Casco, sea cual sea el acabado (Crudo o Blanco) que elijas para su cara.
- **Zócalo, Cornisa y Remates** (incluye remate de zócalo izq/der y remate de cornisa izq/der, que ya compartían color con zócalo/cornisa): ahora heredan en vivo el color de "Frentes y puertas" mientras no marques "Material propio del grupo" para ellos -- antes quedaban en un tono genérico fijo (#d5a66e) que no seguía a nada.
- **"Usar un solo material para todo el módulo"**: activado por defecto, en Blanco -- antes arrancaba desactivado.

Todo esto también se corrigió en la vista previa en vivo del navegador (`modular3d_view.js`), que antes ni siquiera diferenciaba el color de zócalo/cornisa/premesón/remates del color del casco (bug aparte que encontré al revisar esto). Probé la fórmula de cantos condicionales por ejecución (4 combinaciones de remates) y el flujo completo de colores con un navegador real (cambiar "Frentes y puertas" y verificar que zócalo/cornisa/remates lo siguen, que se congelan al marcar "Material propio", y que el selector Crudo/Blanco del premesón cambia su color correctamente).

**Por favor instala esta versión y revisá el despiece de un Bajo con remate solo de un lado (por ejemplo, remate final activo, inicial no) -- Zócalo/Premesón deberían mostrar 1 canto corto, no 2, y el Zócalo ya no debería tener ningún canto largo.**

## Cambios 6.4.41

Tres correcciones, tal como las describiste:

**1) Despiece: ya no aparecen las piezas individuales de Zócalo/Cornisa/Premesón cuando "Sincronizar continuidad" las fusionó.** La causa real: "Sincronizar continuidad" oculta (`visible=false`) la pieza individual que un tramo fusionado ya cubre, pero el despiece recorría la escena sin fijarse en esa visibilidad -- contaba la individual oculta Y la fusionada. Ahora `recolectar_piezas_despiece` (en `despiece.rb`, usado también por Presupuesto y Biblioteca) salta cualquier pieza oculta, así que solo queda la fusionada cuando corresponde, y las individuales normales (sin continuidad sincronizada) se siguen viendo igual que siempre.

**2) El Premesón ya hereda el color configurado del módulo.** Antes quedaba siempre en material crudo a propósito (pensado para cuando encima va una cubierta/mesón real aparte). Quitamos esa excepción en `geometria.rb`: ahora, si configuras un solo color para todo el módulo, el Premesón sale con ese mismo color -- igual que ya pasaba con Zócalo, Cornisa y Remates.

**3) Nuevo layout automático tipo cocina, para Bajo/Auxiliar/Closet/Alto.** Antes cada módulo nuevo se colocaba 100mm a la derecha y 20mm retranqueado del último módulo construido (cualquiera fuera su tipo), sin distinguir Bajos de Altos. Ahora:
- **Bajo, Auxiliar y Closet** forman una sola fila de piso: el primero nace en X=0, y cada uno nuevo se pega EXACTO al que quedó más a la derecha de esa fila (sin ningún espacio entre ellos).
- **Alto** forma su PROPIA fila, independiente de los Bajos: el primer Alto nace en X=0 (no continúa donde terminaron los Bajos de abajo), y cada Alto nuevo se pega al Alto anterior de esa fila.
- Los cuatro tipos van siempre con el FONDO de su casco a Y=600mm desde la pared (ya lo hacía Alto desde v6.4.40; ahora también Bajo/Auxiliar/Closet), y los Altos además a Z=1500mm de altura de piso. **Esto reemplaza** el alineado anterior que perseguía dejar la puerta/remate exactos en Y=0 según su grosor -- confirmaste que la regla de pared fija (Y=600) debía ganar. Ese alineado por grosor de puerta sigue existiendo solo para módulos Personalizado, que no forman parte de este sistema de filas.
- Nada de esto se guarda en memoria: cada módulo nuevo escanea la geometría REAL ya construida en la escena (mismo criterio que ya usa "Actualizar módulo" para saber dónde está un módulo existente), así que el orden en que construís las cosas, un deshacer/rehacer, o cerrar y volver a abrir el archivo nunca desalinean dónde cae el siguiente módulo.

Los tres cambios están solo en Ruby (`despiece.rb`, `geometria.rb`, `jerarquia.rb`) -- geometría 3D real en SketchUp. La vista previa en vivo del navegador sigue mostrando un solo módulo centrado (no tiene concepto de "varios módulos en la misma escena"), así que no aplica ahí.

**Por favor instala esta versión y probá construyendo, en orden: un Bajo, un segundo Bajo, un Alto, y un Auxiliar -- y volvé a generar el despiece de todo seleccionado.** Si el resultado en X/Y/Z de cada uno no es el que esperabas, decime las coordenadas exactas donde SÍ debería haber quedado cada uno para ajustar la regla.

## Cambios 6.4.40

Dos cambios de posicionamiento en la escena de SketchUp, tal como pediste:

**1) El módulo completo (no solo la puerta) se recorre en Y.** Antes, la puerta y el remate ya coincidían entre sí (v6.4.39), pero el conjunto podía sobresalir hacia Y negativo respecto al resto del casco. Ahora TODO el módulo (casco, interior, puertas, cajones, zócalo, cornisa, premesón, remates -- todo junto, sin perder la alineación entre sí) se recorre hacia atrás en Y por el grosor del casco, o por el grosor de la puerta si es mayor ("gana la puerta"). Resultado: el plano frontal (puerta+remate) cae exacto en Y=0 de la escena, para todos los módulos, tengan puerta o no. Verificado con números exactos: casco 15mm + puerta 18mm -> ambos terminan en Y=0; sin puerta, casco 15mm -> remate en Y=0 igual.

**2) Los módulos Alto se posicionan fijo: Z=1500mm, fondo en Y=600mm.** Pedido nuevo y separado: los módulos tipo Alto (colgantes) ahora se construyen siempre con su base a 1500mm de altura de piso, y con la cara TRASERA fija en Y=600mm (contado desde Y=0) sin importar la profundidad real del módulo -- así el lomo de un Alto queda a ras con el de los Bajos de abajo aunque sea más angosto de fondo. Verificado: Alto de 320mm de profundidad sin puertas -> fondo del casco en Y=600, base del módulo en Z=1500.

Este alineado NO afecta la coincidencia entre puerta y remate (v6.4.39): esa se resuelve en coordenadas LOCALES antes de aplicar cualquier corrimiento de escena, así que siempre van a coincidir entre sí sin importar dónde termine posicionado el conjunto completo.

Cambio hecho solo en `jerarquia.rb` (geometría 3D real en SketchUp) -- ni el plano 2D/inventario ni la vista previa en vivo manejan un concepto de "posición en la escena" (ambos trabajan en coordenadas locales del módulo), así que no aplica ahí.

## Cambios 6.4.39

v6.4.38 hizo que el remate calculara SU PROPIO saliente según el montaje de puerta (Solapada/Embutida), pero seguía siendo un cálculo aparte del de la puerta real -- y reportaste que seguían sin coincidir. Aunque en todas mis pruebas ambos cálculos daban el mismo número, para eliminar cualquier posibilidad de divergencia (redondeos, sobremedidas de panel, u otro dato tomado de un lugar distinto) se cambió el enfoque:

**El remate ya NO calcula su propio saliente.** Ahora, cuando se construye una puerta externa solapada real, se guarda el valor EXACTO que se usó para esa puerta (`protrusion_puerta_real`), y el remate reutiliza ese mismo número tal cual -- literalmente la misma variable, no una copia recalculada. Es matemáticamente imposible que terminen en planos distintos porque es el mismo valor.

Si no hay ninguna puerta externa solapada en el módulo (por ejemplo, todo Embutida, o sin puertas), el remate usa el mismo cálculo de respaldo de antes.

Esto se aplicó en `jerarquia.rb`, que es la geometría 3D REAL que se construye en SketchUp (la vista previa en vivo y el plano 2D quedan con el cálculo de v6.4.38, que ya coincide en las pruebas -- si después de esto la vista previa y lo construido en SketchUp difieren entre sí, avisame, sería una pista muy valiosa de por dónde seguir).

**Por favor instala esta versión, reconstruye el módulo con "Actualizar módulo", y volvé a medir la distancia entre la puerta y el remate.**

## Cambios 6.4.38

Encontrada la causa real de "la puerta sigue embutiéndose": tu módulo tiene **"Montaje de puerta" = Embutida** (pestaña 3, "Puertas exteriores") -- una elección de diseño completamente válida (puertas a ras en vez de sobrepuestas). El problema era que el **remate Izq/Der SIEMPRE se construía sobresaliendo** (estilo Solapada, -grosor), sin importar esa configuración. Con montaje Embutida, la puerta queda a ras (Y=0) pero el remate seguía saliendo -15mm -- una diferencia de EXACTAMENTE 1 grosor de puerta, el número exacto que mediste.

Diagnóstico verificado paso a paso: confirmé que el cálculo de posición de la puerta ya daba 0 de diferencia contra el remate en el caso Solapada (ejecutando el cálculo real, no solo leyéndolo); confirmé por el nombre de la pieza ("H_PUERTA_EXT_...") que no era un problema de puerta interna/externa; y cuando diste la medida exacta (15mm = el grosor de la puerta) encontré que faltaba sincronizar el remate con el montaje global.

Corregido: el remate ahora respeta el mismo "Montaje de puerta" que las puertas reales -- Solapada sigue sobresaliendo -grosor (como siempre), Embutida ahora también queda a ras en Y=0, igual que la puerta. Verificado con números exactos vía Playwright: en ambos modos, puerta y remate terminan en la MISMA posición (Solapada: 7.5=7.5; Embutida: -7.5=-7.5). Corregido en los tres lugares (geometría 3D real, plano 2D/inventario, vista previa en vivo).

## Cambios 6.4.37

Encontrado el bug detrás de "zócalo y cornisa se están remontando en la esquina": el "Remate de zócalo" y el "Remate de cornisa" (los caps laterales que tapan el bolsillo del retranqueo) arrancaban en la MISMA posición que el propio zócalo/cornisa -- literalmente ocupando el mismo espacio (15×15mm en esa esquina, en los tres ejes) que la pieza de zócalo/cornisa misma, en vez de empezar justo DETRÁS de ella.

Corregido: ahora el remate de zócalo/cornisa arranca justo detrás de su propia pieza (retranqueo + su grosor) y se acorta la misma medida para seguir llegando exacto hasta la pared trasera -- el zócalo/cornisa (la pieza vista, "el frente") se queda intacta, y su remate solo tapa el bolsillo que queda detrás, sin competir por el mismo espacio. Confirmado con números exactos: Closet de 580mm de fondo con remate de zócalo pasa de 510mm a 495mm de profundidad (580-70-15); remate de cornisa pasa a 545mm (580-20-15) -- ambos calzan justo hasta la pared trasera sin invadir la pieza principal.

Corregido en los tres lugares (geometría 3D real, plano 2D/inventario, vista previa en vivo) para que coincidan siempre.

**Por favor confirma si esa "doble línea"/superposición en la esquina ya desapareció.**

## Cambios 6.4.36

Encontrado el bug detrás de "la puerta/frente se ve embutida aunque no está en Embutida": en el sistema simple de cajones (los campos numéricos "Cajones por nicho" de la pestaña 3, sin usar el diseñador de espacios), el frente del cajón (`CJ_n_FRENTE`) arrancaba exactamente en el mismo plano que la propia caja del cajón (Y=0, a ras del plano del casco) -- **sin sobresalir hacia adelante** como sí lo hacen una puerta solapada o un remate (que arrancan en `-grosor`). El resultado: el frente del cajón quedaba a ras/hundido frente al remate y a cualquier puerta vecina, aunque nada esté configurado como "Embutida".

Corregido: el frente ahora se pega por delante de su propia caja (que se queda igual) y sobresale exactamente lo mismo que una puerta o un remate en su configuración por defecto -- mismo plano visual para frentes de cajón, puertas y remates.

**Si el elemento de tu captura era en realidad una puerta (no un frente de cajón)**, avísame -- esa parte usa otra lógica de posición (`puerta_interna`/`montaje_puerta`) que reviso aparte.

Sobre el segundo problema (zócalo/cornisa "remontándose" en la esquina): antes de tocar esa geometría necesito confirmar algo puntual (te pregunto en el chat) para no arriesgar otro intento a ciegas.

## Cambios 6.4.35

El "Remate inicial (izq.)"/"Remate final (der.)" usaba un alto FIJO de 2420mm ("se corta a medida en obra"), sin importar el alto real del módulo, si tenía cornisa o premesón. Eso hacía que el panel quedara más corto o más largo que el casco+cornisa/premesón real, viéndose entrelazado o cruzado con esas piezas en vez de alinearse limpio con su borde -- justo lo que mostraban tus capturas.

Ahora el alto se calcula según el tope REAL de cada módulo, tal como pediste:

- **Con cornisa activa** (Alto/Auxiliar/Closet): sube hasta el tope de la cornisa (tope del casco + altura de cornisa configurada).
- **Sin cornisa pero con premesón activo** (Bajo): sube hasta el tope del premesón (tope del casco + espesor).
- **Sin cornisa ni premesón**: sube hasta el tope del propio casco.

Corregido en los tres lugares que construyen esta pieza (geometría 3D real, vista previa en vivo, plano 2D/inventario) para que los tres coincidan siempre. Verificado con números exactos: Closet con cornisa de 300mm da 2546mm (2120 alto + 126 zócalo + 300 cornisa); Bajo con premesón da 901mm (760 alto + 126 zócalo + 15 premesón); Auxiliar sin cornisa da 2246mm (2120 alto + 126 zócalo) -- los tres coinciden exactos con la cuenta a mano.

**Por favor revisa si ahora el remate queda alineado con el borde de la cornisa/premesón/casco, sin cruzarse con ellos.**

## Cambios 6.4.34

Encontrado el bug que reportaste ("los remates de activación rápida no está activando los remates"): en 6.4.33 solo actualicé la regla de **visibilidad** de los checks Izq/Der en la interfaz (para que aparecieran en los 4 tipos), pero el código que realmente **construye la pieza** -- en la geometría 3D real (`jerarquia.rb`), en la vista previa en vivo (`modular3d_view.js`) y en el plano 2D/inventario (`plano2d_inventario.rb`) -- seguía restringido a Auxiliar/Closet únicamente. El checkbox se marcaba pero la pieza nunca se creaba en Alto/Bajo. Corregido en los tres lugares: ahora Remate Izq/Der construye la pieza en los 4 tipos, tal como ya lo mostraba la interfaz. Confirmado visualmente en Alto: los dos paneles laterales (100×2420mm) aparecen correctamente a los costados del módulo.

Sobre lo demás que comentaste:

- **"Remate de zócalo" y "Remate de cornisa"** (los selects Izquierdo/Derecho/Ambos/Ninguno de esa misma tarjeta) son piezas MÁS PEQUEÑAS y en una posición distinta a "Remate inicial/final" (esas van pegadas al plano de la puerta, hacia afuera del módulo; las de zócalo/cornisa van hacia adentro, tapando el bolsillo del retranqueo). No se entrelazan entre sí -- confirmado revisando la geometría, ocupan espacios distintos.
- **"Remate de cornisa" ya está en cascada con "Cornisa"**: solo aparece cuando Cornisa está activa, y ya usa la misma altura configurada en "Altura de cornisa" (no hay un campo de altura separado para el remate de cornisa) -- eso que proponías ya estaba así implementado.

Antes de tocar algo más, te pregunto una cosa puntual sobre el diseño (para no adivinar y tener que rehacer otra ronda).

## Cambios 6.4.33

Ajuste de qué checks rápidos aparecen según el tipo de módulo, según especificaste:

- **Alto:** Remate Izq/Der + Cornisa (sin Zócalo, sin Premesón).
- **Bajo:** Remate Izq/Der + Zócalo + Premesón (sin Cornisa).
- **Closet:** Remate Izq/Der + Zócalo + Cornisa (sin Premesón).
- **Auxiliar:** Remate Izq/Der + Zócalo + Cornisa (sin Premesón).
- **Personalizado:** ninguno (igual que antes, esta tarjeta completa no aplica a Personalizado).

Se agrega el check rápido que faltaba, **"Cornisa"**, sincronizado en ambos sentidos con el select real (pestaña Casco). Antes "Remate Izq/Der" solo aparecía en Auxiliar/Closet; ahora aparece en los cuatro tipos, tal como pediste.

También se quitó el texto "Ampliar" del botón de pantalla completa (queda solo el ícono ⛶, con el tooltip explicando qué hace) para que quepan todos los checks en una sola fila sin que se corten ni se amontonen. Probado en ventanas angostas y anchas: todo cabe en una línea.

## Cambios 6.4.32

Junto a los checks rápidos "Zócalo" y "Premesón" (arriba del visor 3D) se agregan dos nuevos: **"Izq"** y **"Der"**.

- Son un atajo directo de "Remate inicial (izq.)" y "Remate final (der.)" -- los mismos campos que ya existían en la pestaña "2 Casco" → "Zócalo, cornisa y remates".
- Solo aparecen cuando el tipo de módulo los admite (Auxiliar/Closet), igual que la fila completa en la pestaña.
- Quedan sincronizados en ambos sentidos: marcarlos/desmarcarlos aquí cambia el select de la pestaña Casco, y cambiar el select allá actualiza el check aquí -- nunca se desincronizan.

## Cambios 6.4.31

Tu captura del árbol de piezas ("MODULAR-3D VIEW") mostró algo clave: esa lista SÍ tiene una barra de scroll clásica del navegador (delgada, gris, arrastrable) y se ve y funciona perfecto en tu equipo. Esa barra nunca fue un control personalizado -- es la barra nativa del navegador, sin más.

El problema de todo este historial fue que, desde el principio, se ocultó a propósito la barra nativa en el panel de configuración (izquierda) y en el visor 3D (derecha), para reemplazarla por controles hechos a mano (barra propia, deslizador vertical, deslizador rotado, botones de flecha) -- y NINGUNO de esos reemplazos se vio nunca en tu navegador real, aunque todos probaban perfecto en las pruebas automatizadas de este lado.

Esta versión:

- **Deja de ocultar la barra nativa** en el panel de configuración y en el visor 3D.
- Le aplica el mismo estilo (delgada, gris oscuro, con acento naranja al pasar el mouse) que ya usa la lista de piezas que confirmaste que funciona -- para que se vea igual en toda la pantalla.
- **Quita por completo** los botones de flecha ▲/▼ y la barra de progreso de las versiones anteriores (6.4.26-6.4.30): ya no hacen falta.
- Se mantiene el arreglo de 6.4.30 (el alto del panel se sigue fijando en píxeles por código) -- eso fue lo que hizo que el navegador por fin supiera cuánto contenido sobra y cuándo mostrar la barra.
- Se quitan los mensajes de diagnóstico `[JS:...]` del pie de página -- ya cumplieron su función.

**Por favor probá esta versión** y confirmame si ahora ves una barra de scroll normal (como la de la lista de piezas) tanto en el panel de configuración como en el visor 3D, y que se puede arrastrar con el mouse para subir y bajar.

## Cambios 6.4.30

Tu captura de 6.4.29 dio la respuesta definitiva: `cpScrollH=1025` y `cpClientH=1025` -- **exactamente iguales**. Eso confirma la causa real: en tu navegador, el panel de configuración (`.config-pane`) no estaba recibiendo un alto fijo desde el diseño de la página (la técnica de `calc()`/porcentajes heredados a través de una cuadrícula CSS) -- simplemente crecía libre hasta el tamaño de todo su contenido (1025px), aunque la ventana solo tenía espacio real para una parte de eso. Por eso nunca aparecían flechas: el script las oculta cuando no detecta contenido de sobra, y en tu caso el panel "creía" que no le sobraba nada porque nunca se le dijo cuál era su límite real. El recorte pasaba por fuera, en silencio.

Esta versión deja de depender de esa herencia de alto por CSS (que resultó no funcionar de forma confiable en tu navegador) y en su lugar **mide y fija el alto del panel directamente en píxeles por código**, cada vez que la ventana cambia de tamaño:

- Se calcula: alto de la ventana − alto real del encabezado − márgenes = alto exacto disponible.
- Ese número se aplica directo como el alto de `.config-pane` y del panel `MODULAR-3D VIEW`, sin pasarle la decisión al navegador.
- Esto no depende de ninguna característica moderna de CSS ni de que el navegador resuelva correctamente cuadrículas/porcentajes -- es aritmética simple aplicada directo al elemento, así que debería funcionar igual en un navegador viejo o nuevo.

Se deja el mismo diagnóstico del pie de página, ahora mostrando `cpEstiloAlto=` (el alto que se le puso al panel) junto a `cpScrollH=`/`cpClientH=` -- si el arreglo funciona, `cpScrollH` debe salir MAYOR que `cpClientH` (eso es lo que hace aparecer las flechas).

**Por favor probá esta versión y contame si ahora sí aparecen y funcionan las flechas para subir/bajar**, tanto en el panel de configuración (izquierda) como en el visor 3D (derecha).

## Cambios 6.4.29

6.4.28 dio la respuesta que hacía falta: el código `[JS:...]` cambió entre dos aperturas (`VWISAQ` → `0UHSC5`) -- confirmado que `interfaz.js`/`interfaz.css` sí se actualizan frescos, caché descartado del todo. El problema es un bug real de comportamiento en tu navegador específico, no una copia vieja de archivos.

La sospecha ahora: la medición dinámica del alto del encabezado (`--header-h`, agregada en 6.4.27) podría no estar funcionando en tu navegador, dejando el panel calculado más alto de lo real -- lo que lo recortaría por fuera sin que el scroll interno detecte nada raro (ningún desborde "hacia adentro" que activar).

Se amplía la misma marca del pie de página (ya confirmada que llega) con los números exactos:

- `headerOffsetH=` el alto real medido del encabezado.
- `--header-h=` el valor que la variable de CSS quedó usando (deberían ser iguales).
- `cpScrollH=` / `cpClientH=` el alto de contenido vs. el alto visible del panel de configuración (si son iguales, ahí no hay overflow detectado -- si `cpScrollH` es mayor, sí debería haber flechas).
- `winH=` el alto de la ventana.

**Por favor mandame una captura del pie de página con estos números.** Con eso puedo confirmar exactamente en qué paso se rompe el cálculo, en vez de seguir probando a ciegas.

## Cambios 6.4.28
## Cambios 6.4.28

6.4.27 corrigió (con buena evidencia) la causa real del alto del panel, y aun así seguiste sin ver las flechas. Eso, sumado a que en TODA esta sesión ninguna solución relacionada con `interfaz.js`/`interfaz.css` se ha visto nunca -- mientras que los cambios que viven en `interfaz.html` (checks de Zócalo/Premesón, botón "Crear módulo", etc.) sí aparecen siempre -- apunta otra vez a que esos dos archivos específicos podrían estar sirviéndose desde una copia vieja, pese al intento de 6.4.24.

Esta versión **no cambia nada de la barra de scroll** -- es sólo una prueba, así de simple:

- En el pie de página (abajo del "WhatsApp"), junto al número de versión, ahora aparece **`[JS:XXXXXX]`** con un código al azar, generado de nuevo cada vez que `interfaz.js` se interpreta desde cero.
- **Por favor, hacé esto:**
  1. Abrí el plugin y anotá (o mandame captura de) el código que aparece, por ejemplo `[JS:9KDH4U]`.
  2. Cerrá el diálogo del plugin por completo.
  3. Volvé a abrirlo.
  4. Fijate si el código cambió o es el mismo de antes.

- **Si el código CAMBIA cada vez**: interfaz.js sí se está recargando de disco -- el problema de la barra es otra cosa, y seguimos investigando desde ahí (por ejemplo, revisando si aparece algún error si conseguimos abrir las herramientas de desarrollador del navegador embebido).
- **Si el código se queda IGUAL siempre** (aunque cierres y abras varias veces, aunque instales una versión nueva): eso confirma que `interfaz.js` (y probablemente `interfaz.css`) se están sirviendo desde una copia vieja guardada en disco o en memoria, no la que acabás de instalar -- en ese caso el problema no es nada que pueda arreglar con más cambios de código; hay que resolver primero por qué esos archivos no se actualizan (por ejemplo, revisando si hay un antivirus bloqueando la sobreescritura, o si el proceso de instalación del `.rbz` está fallando silenciosamente para esos dos archivos en particular).

## Cambios 6.4.27
## Cambios 6.4.27

Insististe en que "antes funcionaba perfectamente bien" y pediste revisar desde la versión 4 -- tenías razón en insistir. Encontré la diferencia real comparando el código contra el archivo original que diste al empezar (antes de que yo tocara nada, v4.6.0-beta.1).

**La versión original calculaba la altura así:** `main { height: calc(100vh - 54px); }` y `.config-pane { height: calc(100vh - 74px); }` -- números fijos, y funcionaba porque en esa versión el encabezado SIEMPRE medía lo mismo (sin la píldora de sesión con barra de días que se agregó después).

**Lo que yo cambié después (6.4.8/6.4.10), sin darme cuenta de la consecuencia:** cuando la píldora de sesión (6.4.6) hizo que el encabezado pudiera medir 1 o 2 filas según el estado, esos números fijos se desincronizaron (el visor 3D quedaba cortado). En vez de volver a la técnica original con un número que se ajustara solo, cambié a `grid-template-rows:minmax(0,1fr)` -- una técnica de CSS Grid más moderna, que se ve perfecta en un Chromium actual, pero que depende de una interacción entre Flexbox y Grid (cómo un contenedor flexible le pasa una altura "definida" a las filas de su propio grid) que en navegadores de la época de tu SketchUp 2020 (Chrome 64, 2018) no estaba completamente resuelta -- justo cuando ambas especificaciones todavía estaban madurando de forma independiente.

**Corregido:** se vuelve exactamente a la técnica de la versión original (`height: calc(100vh - Npx)`, sin ningún truco de Grid para el alto), pero el número ya no es fijo: `interfaz.js` mide el alto real del encabezado con JavaScript (`header.offsetHeight`) y lo guarda en una variable de CSS (`--header-h`) que se recalcula sola al cargar, al cambiar el tamaño de ventana, y cada medio segundo como respaldo -- así nunca se desincroniza sin importar cuántas filas tenga el encabezado, evitando el bug de 6.4.6 sin necesitar la técnica de Grid que sospecho que no funciona en tu navegador real.

Verificado con una prueba real: el alto de `main` coincide exactamente con "ventana menos encabezado" (900 - 66 = 834px), el desbordamiento se detecta correctamente, y los botones ▲/▼ mueven el contenido con normalidad.

## Cambios 6.4.26
## Cambios 6.4.26

El diagnóstico de 6.4.25 identificó la causa exacta: tu SketchUp es **Pro 2020**, con **Chrome 64** embebido (de 2018) -- un motor lo bastante viejo como para que ningún tipo de `<input type="range">` posicionado o girado con CSS (tres intentos distintos: divs, `writing-mode`, `transform:rotate`) llegara a pintarse ni a moverse, aunque el layout SIEMPRE reservaba bien el espacio.

- **Se reemplaza el control por botones ▲ Subir / ▼ Bajar**, elementos HTML básicos (el mismo tipo que "Transparencia", "Aristas" y el resto de los botones que ya funcionan en esa pantalla) -- sin `position:absolute`, sin `transform`, sin medidas por JavaScript. Aguantar presionado el botón repite el desplazamiento cada 220ms.
- **Barra de progreso** entre los dos botones: un simple `<div>` con degradado naranja que crece según cuánto se scrolleó -- es sólo visual (no se arrastra), así que tampoco depende de ninguna API de slider que pueda fallar.
- Esto es **universal por construcción**: botones y divs con `background`/`transition` son CSS de toda la vida, soportado igual en Chrome 64 (2018, SketchUp 2020) que en cualquier Chrome moderno (SketchUp 2021 a 2027) -- no hace falta detectar versión ni tener una ruta de código distinta por navegador.
- Se retira el diagnóstico temporal de 6.4.25 (ya cumplió su función: identificar el navegador real) y el `padding-right` extra que habían dejado los intentos anteriores de slider.
- Verificado con Playwright: el clic mueve el scroll correctamente (arriba/abajo, con límites), la barra de progreso refleja el avance real, cada panel sigue siendo independiente del otro, y no hay errores de JavaScript.

## Cambios 6.4.25
## Cambios 6.4.25

Confirmaste que 6.4.24 sí se instaló bien (el título mostraba v6.4.24) y el problema de la barra sigue exactamente igual -- eso descarta la teoría de caché. Cuatro implementaciones de scroll distintas, cada una probada y verificada de verdad en este lado, y ninguna aparece del lado del usuario: en vez de seguir probando ideas de CSS a ciegas, esta versión agrega un **diagnóstico temporal** para ver, con datos reales de tu navegador, qué es lo que realmente está pasando.

- Aparece una **franja amarilla debajo del encabezado** con información técnica: qué navegador/motor es exactamente (`navigator.userAgent`), si soporta `ResizeObserver`, si soporta `transform` y `accent-color`, y el estado real de los elementos de la barra (si existen en la página, su tamaño, si están escondidos).
- **No hace falta que pruebes nada de scroll esta vez** -- solo abrí el plugin y mandame una captura de pantalla donde se vea esa franja amarilla completa (puede que el texto sea largo y se corte en varias líneas, está bien, mandá la franja completa).
- Con esa información voy a poder saber exactamente qué versión de navegador es y qué es lo que realmente soporta, en vez de seguir adivinando -- esta franja se quita en cuanto se resuelva el problema de la barra.

## Cambios 6.4.24
## Cambios 6.4.24

Después de 4 implementaciones distintas de la barra de scroll (6.4.14, 6.4.20, 6.4.22, 6.4.23) -- cada una verificada funcionando en pruebas automatizadas reales, ninguna visible ni funcional para el usuario, ni siquiera el ESPACIO reservado cambiando de comportamiento entre versiones -- este patrón deja de parecer un problema de CSS y empieza a parecer un problema de que el navegador embebido nunca está cargando el `interfaz.css`/`interfaz.js` nuevo.

**El razonamiento:** `interfaz.html` se carga con `dialogo.set_file(...)`, y el pie de página (que vive en ese mismo archivo) SÍ muestra el número de versión correcto cada vez -- eso confirma que `interfaz.html` se recarga fresco en cada apertura. Pero `interfaz.css`/`interfaz.js` se referencian como archivos SEPARADOS con `?v=X.X.X` para "romper" el caché entre versiones. Si el motor de ese navegador embebido cachea archivos locales (`file://`) sin respetar bien el query string -- un comportamiento real y documentado en algunos motores basados en Chromium Embebido (CEF) más antiguos o restringidos -- entonces `interfaz.html` se actualiza solo, pero el CSS/JS que hace todo lo demás (incluida cada versión de la barra de scroll) se sigue sirviendo desde una copia vieja, por más que el número en la URL cambie de versión en versión.

**Corrección:** en vez de abrir `interfaz.html` directamente, ahora se genera una copia temporal (`.interfaz_runtime.html`, en la misma carpeta `ui/` para que las rutas relativas sigan funcionando igual) donde el `?v=X.X.X` se reemplaza por un valor ÚNICO cada vez que se abre el diálogo (no solo distinto por versión) -- así ninguna entrada de caché anterior puede coincidir jamás, sin importar qué tan mal ese motor decida invalidar caché por query string.

**Si después de instalar esto SIGUE sin verse la barra**, eso apuntaría a una causa distinta que ya no puedo diagnosticar solo con código: probablemente que la instalación del `.rbz` no está reemplazando `interfaz.css`/`interfaz.js` en el disco (por ejemplo, si SketchUp seguía abierto con el diálogo abierto durante la instalación y Windows bloqueó esos archivos). En ese caso, por favor:
1. Cerrá SketchUp por completo (no solo el diálogo del plugin).
2. Buscá la carpeta `Modular_3D` dentro de la carpeta de Plugins de SketchUp y borrala a mano.
3. Volvé a abrir SketchUp e instalá este `.rbz` de nuevo.

## Cambios 6.4.23
## Cambios 6.4.23

Confirmaste el diagnóstico más preciso hasta ahora: "ya se logra ver que hay un espacio para la barra de desplazamiento pero no se lo ve ni funcionar". Eso es oro -- dice exactamente dónde estaba el problema.

- **Causa encontrada**: el espacio SÍ se reservaba (la barra empujaba el contenido correctamente), pero el `<input type="range">` con `writing-mode:vertical-lr` + `-webkit-appearance:slider-vertical` de 6.4.22 no se pintaba. Esas dos propiedades sirven para darle orientación VERTICAL a un slider nativo, pero no son universales -- el navegador embebido de SketchUp reserva el layout (por eso el hueco aparecía) pero no sabe dibujar esa variante concreta del control.
- **Corregido de raíz, sin depender de NINGUNA API "vertical"**: ahora es un `<input type="range">` HORIZONTAL común y corriente -- el mismo tipo exacto que "Explosión"/"Velocidad de giro", que sabemos que se ve y arrastra ahí -- al que sólo se le aplica un `transform:rotate(-90deg)`. Es un simple giro visual con CSS estándar (soportado desde WebKit muy antiguo): el navegador sigue creyendo que dibuja un slider horizontal normal, sólo que rotado.
- El tamaño y la posición del control (para que el giro quede perfectamente centrado en el hueco vertical) se calculan con JavaScript a partir del alto real del panel, no con CSS fijo.
- También se dejó de depender de `accent-color` (otra propiedad relativamente reciente) para el color del thumb/track: ahora se fuerza el estilo vía `::-webkit-slider-thumb`/`::-moz-range-thumb`, soportado desde mucho antes, así el control se ve claramente incluso si ese navegador tampoco soporta `accent-color`.
- Verificado con una prueba real: el thumb aparece como una manija clara y visible en la parte superior de la barra (capturado con screenshot), y arrastrarlo de arriba a abajo mueve el panel correctamente en el sentido esperado (arriba = contenido arriba, abajo = contenido abajo), sin errores de JavaScript.

## Cambios 6.4.22
## Cambios 6.4.22

Pediste arreglar también el árbol de piezas y las medidas (letra más chica), y dijiste que lo de arrastrar la barra para ver lo de abajo TODAVÍA no se arreglaba -- con la sugerencia de revisar versiones anteriores donde sí funcionaba y tomar de ahí lo necesario, sin tocar nada más.

- **Árbol de piezas y medidas con letra más chica**: `.m3dv-tree-item` de 10px a 8px, los valores de "Propiedades técnicas" (Largo/Ancho/Espesor/etc.) de 8px a 7px y el nombre de la pieza seleccionada de 10px a 8px.
- **La barra de cada panel vuelve a ser un `<input type="range">` nativo, ahora vertical** (en 6.4.17 fue horizontal y se descartó "esas barras horizontales no me sirven de nada"; en 6.4.20 se probó una barra propia dibujada con divs con arrastre manual, que pasó todas las pruebas automatizadas pero, igual que la de 6.4.14, nunca llegó a confirmarse que arrastrara de verdad en tu navegador. Motivo técnico real: un range nativo arrastra con el manejo interno del propio navegador, sin depender de que los eventos de mouse lleguen bien a JavaScript mientras el cursor sale del control fuera del elemento -- justo el tipo de cosa que un navegador embebido puede manejar distinto a uno de escritorio. Es también el único tipo de control con evidencia real de funcionar en tu SketchUp: "Explosión"/"Velocidad de giro" son del mismo tipo. A diferencia de 6.4.17, esta vez el bug real de fondo (el corte de ancho de 6.4.18) ya está corregido, así que el arrastre sí debería mover el panel.
- Se posiciona vertical, pegado al borde derecho de cada panel, ocupando todo su alto -- mismo lugar donde iba la barra de divs. Verificado con una prueba real: la manija arriba dejó el panel scrolleado hasta arriba, la manija abajo lo dejó scrolleado hasta abajo, y mover la del configurador no afecta al visor (ni viceversa).
- Todo lo demás (tema oscuro, layout, checks de Zócalo/Premesón, botón "Crear módulo", etc.) queda exactamente igual, sin tocar.

## Cambios 6.4.21
## Cambios 6.4.21

Pediste reducir el tamaño de letra un par de puntos "para que se pueda leer" -- el botón "Ocultar/mostrar" (en Propiedades técnicas, al seleccionar una pieza) se veía cortado como "Ocultar/mos".

- **Causa:** ese botón usaba `font-size:9px` con `white-space:nowrap` dentro de una tarjeta con `overflow:hidden` -- el texto completo no cabía en una sola línea y el sobrante se recortaba de raíz, sin ni siquiera puntos suspensivos.
- **Corregido:** se bajó a `font-size:7px` y se permite que el texto pase a una segunda línea si hace falta (`white-space:normal`) en vez de cortarse. Verificado con una prueba real: el botón "Ocultar/mostrar" ahora entra completo, sin desbordar ni recortarse, incluso en la tarjeta más angosta.

## Cambios 6.4.20
## Cambios 6.4.20

En 6.4.19 el scroll interno ya funcionaba en los dos paneles por separado, pero dependía de que el navegador embebido de SketchUp pintara su propia scrollbar nativa -- y dijiste "no se ve que esta arreglado... debe tener una barra lateral deslizable para cada uno". Aquí se agrega una barra 100% propia, visible siempre que haya contenido para desplazar, una para el configurador y otra para el visor 3D -- sin depender de si el navegador decide mostrar su scrollbar nativa o no.

- **Barra de scroll propia** (franja angosta con manija arrastrable) en el borde derecho de CADA panel por separado -- una para `.config-pane`, otra para `aside.m3dv-panel`. Se arrastra con el mouse igual que una scrollbar normal.
- Se apaga la scrollbar nativa del navegador (`scrollbar-width:none` / `::-webkit-scrollbar{display:none}`) para no duplicar: ahora la única que se ve es la propia, bajo control total del plugin.
- **Se evitó a propósito el bug de 6.4.14** (el `MutationObserver` que se disparaba a sí mismo y congeló el diálogo entero): esta barra usa `ResizeObserver` sobre el panel que se scrollea, no sobre sí misma, así que nuestro propio refresco nunca puede volver a dispararse solo. Verificado con una prueba real: el hilo de JavaScript siguió respondiendo con normalidad durante y después de usar la barra.
- Verificado arrastrando cada barra por separado con eventos de mouse reales: mover la del configurador no mueve el visor, y viceversa.

## Cambios 6.4.19
## Cambios 6.4.19

Confirmaste que la barra lateral del visor sí se activaba al achicar la ventana, pero señalaste el problema de fondo: el configurador (izquierda) y el visor 3D (derecha) deben ser **dos secciones independientes, cada una con su propio scroll, en cualquier dimensión de ventana** -- no una que se apile sobre la otra compartiendo un solo scroll de página cuando la ventana se hace angosta.

- **Se quitó por completo el "modo de una sola columna"** que existía para ventanas angostas (antes activo por debajo de 991px). En 6.4.18 ese modo apilaba el configurador arriba y el visor abajo, compartiendo un único scroll de página -- exactamente lo contrario de lo que pediste.
- **Las dos columnas ahora son siempre independientes:** en vez de un ancho fijo (480px cada una, que obligaba a apilar por debajo de cierto ancho), usan un ancho flexible (`minmax(300px, ...)`) que se comprime en ventanas angostas pero nunca colapsa a una columna -- así que el configurador y el visor están siempre uno al lado del otro, cada uno con su propio scroll vertical interno, sin importar qué tan angosta esté la ventana.
- Verificado con pruebas automatizadas reales en 7 anchos distintos (400px a 1900px): en todos, ambos paneles son scrolleables por separado, y desplazar uno nunca mueve el otro ni la página. Sólo por debajo de ~630px (más angosto que cualquier uso real) aparece una barra horizontal para llegar a la segunda columna -- pero el scroll independiente de cada panel se mantiene incluso ahí.

## Cambios 6.4.18
## Cambios 6.4.18

Dijiste, con toda razón, que el deslizador de 6.4.17 "es ridículo": querías el movimiento vertical, no horizontal, y además moviéndolo horizontalmente no pasaba nada -- y pediste una auditoría a fondo de la causa real antes de corregir, no otro parche a ciegas. Esto es lo que se encontró.

**Causa raíz real (afectó a las 3 soluciones de scroll intentadas en esta sesión, no solo al deslizador):**

`.config-pane` y `aside.m3dv-panel` (el panel de configuración y el visor 3D) sólo recibían `overflow-y:auto` -- lo que los vuelve "scrolleables" de verdad -- dentro de una regla `@media (min-width:981px)`. Pero la fila `main { grid-template-columns: minmax(480px,1fr) 480px; }` (sin media query, siempre activa) necesita como mínimo 480+480px de columnas + 12px de espacio + 20px de relleno = **992px reales**, no 981px. Y el paso a una sola columna apilada (donde antes hacía falta) sólo se activaba por debajo de 720px.

Eso dejaba una **franja de ancho lógico entre ~721px y ~991px** donde ninguna de las dos reglas aplicaba: ni el scroll interno de los paneles (necesitaba ≥981px, y en la práctica ≥992px) ni el apilado de una sola columna con scroll de página completa (necesitaba <720px). En esa franja, `.config-pane` quedaba con `overflow-y` en su valor por defecto (`visible`), que hace que **mover `scrollTop` por código no tenga absolutamente ningún efecto visual** -- sin importar si lo mueve la rueda del mouse, una barra propia hecha con divs, o un `<input type="range">`. Las tres soluciones de este hilo (6.4.14, y el deslizador de 6.4.17) apuntaban exactamente a esa propiedad rota; ninguna podía haber funcionado nunca mientras la ventana real estuviera en esa franja de ancho -- lo cual es fácil que pase con el escalado de pantalla de Windows (125%/150%/200%): una ventana que se ve grande en una captura de pantalla (en píxeles físicos) puede tener un ancho lógico/CSS bastante menor, que es contra lo que la media query realmente compara.

Esto también explica por qué mis pruebas automatizadas (que corrían a 1280px o más de ancho) nunca detectaron el problema: nunca pisaban esa franja intermedia.

**Corregido:**
- El punto de corte del scroll interno sube de 981px a **992px** (el mínimo real que exigen las dos columnas).
- El punto de corte del apilado a una sola columna sube de 720px a **991px**, exactamente pegado al de arriba -- ya no queda ningún ancho intermedio sin una de las dos formas de scroll activa.
- **Se retiran los deslizadores horizontales** de 6.4.17 ("esas barras horizontales no me sirven de nada") -- con el corte de ancho corregido, la scrollbar **nativa** del navegador (ya estilizada en el mismo tono oscuro que usaban el árbol de piezas y "Velocidad de giro") vuelve a ser suficiente, sin necesitar ningún control adicional.
- El respaldo de scroll con la rueda del mouse ahora también revisa el scroll de la página completa como última opción, por si el ancho real cae en una ventana muy angosta donde todo se apila en una sola columna.
- Verificado con pruebas automatizadas reales (simulando la rueda del mouse, no solo moviendo `scrollTop` por código) en 4 anchos distintos: 850px, 991px, 992px y 1900px -- en los 4 el scroll ahora funciona, y ninguno produce desbordamiento horizontal de la página.

## Cambios 6.4.17

Pediste confirmar el scroll y luego señalaste que, aunque el congelamiento ya estaba resuelto, "lo que hasta ahora no puedes poner es el scrool o la barra para navegar" -- la scrollbar propia (hecha con divs, de 6.4.14) seguía sin aparecer/funcionar en tu SketchUp real, pese a que en las pruebas automatizadas sí se movía correctamente.

- **Se retiró por completo la scrollbar propia (divs + arrastre con mouse)** y se reemplazó por un **deslizador `<input type="range">` nativo** ("⇅ Desplazar"), uno para el panel de configuración (izquierda) y otro para MODULAR-3D VIEW (derecha). Se eligió este tipo de control porque es EL MISMO que ya usan "Explosión" y "Velocidad de giro" -- controles que en tus propias capturas de pantalla sí se ven y funcionan en tu navegador embebido de SketchUp. En vez de seguir depurando a ciegas un control que no puedo reproducir del lado del bug, se cambió a uno cuyo tipo ya está probado en tu entorno real.
- El deslizador mueve el contenido del panel (`scrollTop`) al arrastrarlo, y se actualiza solo si el panel se desplaza por otro medio (rueda del mouse, etc.). Se oculta automáticamente si el contenido ya cabe completo (no hay nada que desplazar).
- Se eliminó el código muerto de la scrollbar anterior (`inicializarScrollbarPropia` y su `MutationObserver`) en `interfaz.js`.

## Nota de fusión (este repositorio)

Este código venía desarrollándose en paralelo en dos sesiones distintas: este repositorio de git (hasta v4.9.0, con la biblioteca de texturas de 8 fabricantes ya incorporada) y un paquete aparte que avanzó por su cuenta hasta v6.2.0. Como ambos son la misma línea de desarrollo (v6.2.0 continúa exactamente donde este repo había quedado en 4.9.0), la fusión fue directa: se trajo todo el código de v6.2.0 a este repositorio, lote por lote y verificado byte a byte contra el original, y se conservó intacta la carpeta `Modular_3D/textures/` de este repo (el paquete v6.2.0 no la traía por el límite de tamaño de subida, no porque se haya quitado a propósito). Los dos bugs geométricos reales que v6.2.0 encontró y corrigió (protrusión de puerta e inglete que quedaba pegado) quedan documentados en la sección "Cambios 6.0.0"/"Cambios 6.0.1" más abajo. El backend del Catálogo Global (`api.modular-3d.com`) ya está desplegado en producción y confirmado compatible con el cliente de esta versión.

## Cambios 6.4.16

Confirmaste que 6.4.15 arregló el congelamiento (pestañas fijas, todo lo demás con scroll/zoom normal) y pediste un botón "Crear" debajo de Zócalo/Premesón para construir el módulo sin tener que bajar hasta el botón de abajo del todo.

- **Nuevo botón "✓ Crear módulo"** en la cabecera de MODULAR-3D VIEW, en su propia fila debajo de Zócalo/Premesón/Abierto/Ampliar. Hace exactamente lo mismo que "Construir módulo" (el de abajo del panel, que sigue estando ahí) -- es un acceso directo, no una acción nueva ni distinta.

## Cambios 6.4.15

**Bug crítico de 6.4.14, corregido de inmediato:** "se bugeó, se quedó así y no me deja ni escribir" -- el diálogo entero se congelaba (ni el login aceptaba texto, ni el visor 3D terminaba de dibujarse).

- **Causa real:** la scrollbar propia de 6.4.14 usaba un `MutationObserver` mirando el panel completo (`attributes:true, subtree:true`) para refrescarse solo cuando el contenido cambiaba de tamaño -- pero la propia función que la refresca (`refrescar()`) escribe `thumb.style.height`/`top`, que ES una mutación de atributo dentro de ese mismo panel observado. Resultado: cada refresco generaba la mutación que volvía a disparar el observer, que volvía a refrescar, en un ciclo infinito que colgaba el hilo de JavaScript por completo -- de ahí que nada más funcionara (ni el teclado, ni el resto del dibujado).
- **Corregido:** el observer ahora ignora las mutaciones que ocurren dentro de la barra de scroll propia (donde antes se mordía la cola a sí mismo); solo reacciona a cambios reales de contenido en el resto del panel. Verificado con una prueba automatizada real: la página ahora carga y acepta texto con normalidad, sin ningún indicio de bucle o cuelgue.
- **Disculpas por el susto** -- este bug se coló pese a la validación de sintaxis porque es un error de comportamiento en tiempo de ejecución (un bucle de eventos), no un error de sintaxis; a partir de ahora, cualquier `MutationObserver` que agregue en este proyecto va a revisar explícitamente este mismo riesgo antes de subirlo.

## Cambios 6.4.14

Dos pedidos: "que exista una check para activar o desactivar zócalo y también activar o desactivar premesón" (ubicado en la barra de MODULAR-3D VIEW, junto a "Abierto", según pediste) -- "no solo visual, si se activa sale también en el despiece y si no va se retira del despiece" -- y, en paralelo, una vuelta más al problema del scroll.

- **Checks "Zócalo" y "Premesón"** en la barra del visor 3D (junto a "Abierto"), marcados por defecto (para no cambiar el comportamiento de módulos ya guardados). Solo aparecen cuando aplican: "Zócalo" en Bajo/Auxiliar/Closet, "Premesón" solo en Bajo -- igual que ya hacía el check de Cornisa.
- **No es solo visual: afecta la construcción real Y el despiece.** Se aplicó el mismo check en los 3 motores del plugin: la construcción real en SketchUp (`jerarquia.rb`), el despiece/plano 2D (`plano2d_inventario.rb` -- de acá sale también el presupuesto, así que se actualiza solo) y el visor 3D en vivo. Desmarcar "Zócalo" quita la pieza de los tres lugares a la vez; volver a marcarlo la trae de vuelta.
- **Scrollbar propia (dibujada con divs normales, ya no con el scrollbar nativo del navegador).** Después de que la scrollbar nativa estilizada no apareciera visible en tu SketchUp real (probablemente por una configuración de Windows que ninguna hoja de estilos puede forzar), se reemplazó por un control 100% propio: una franja angosta con una manija que se arrastra con el mouse y mueve el contenido a mano, sin depender en absoluto de cómo el navegador embebido decida pintar (o no) su scrollbar. Verificado que el arrastre mueve el contenido correctamente.

## Cambios 6.4.13

Responde a que "sigo sin poder mover el scroll" persistía incluso después de dos rondas de arreglos de CSS/JS que sí funcionaban en pruebas reales de navegador, y a "esta parte de propiedades técnicas haz que encuadren dentro del recuadro".

- **Propiedades técnicas (panel derecho) ya no se sale de su recuadro.** Los valores (580 mm, 570 mm, PVC, etc.) se salían del borde de la tarjeta hacia la derecha. Causa real: `.m3dv-body` usaba columnas `1fr 1fr` sin límite mínimo -- si el contenido de una columna quería ser más ancho (por los valores sin salto de línea), la columna podía crecer más de lo debido. Corregido con `minmax(0,1fr)` en las columnas y `overflow:hidden` en la tarjeta, para que el contenido siempre quede contenido dentro del recuadro, nunca por fuera.
- **Scrollbar ancha y siempre visible, para arrastrar con el mouse.** Si la rueda del mouse no se entrega bien al contenido dentro del navegador embebido de SketchUp (posible causa de fondo, fuera del alcance de lo que HTML/CSS/JS puede arreglar si es un problema de cómo SketchUp reenvía el evento de scroll a su ventana interna), ahora hay una alternativa que no depende de la rueda para nada: una barra de scroll bien ancha (14px, se pone naranja al pasar el mouse) que se puede arrastrar con clic normal, en el panel de configuración, el visor 3D, el árbol de piezas y demás listas largas.

## Cambios 6.4.12

Dos pedidos: "pon todo el plugin en este estilo que se complemente" (el tema oscuro del panel MODULAR-3D VIEW, para cuidar mejor la vista) y seguir de cerca "sigo sin poder scrolear" en la pestaña de Configuración.

- **Tema oscuro en todo el plugin.** Antes solo el panel del visor 3D (derecha) era oscuro; el resto (pestañas, tarjetas, campos, materiales, catálogo, login) era claro/blanco, un choque visual fuerte entre ambos lados. Ahora todo el plugin reutiliza la MISMA paleta oscura que ya tenía el visor (fondos `#151a1f`/`#20272d`, texto claro `#eef2f5`, acentos naranja de marca sin cambios) -- probado visualmente pestaña por pestaña (Medidas, Configuración, Materiales, login, términos y condiciones) para confirmar que todo quede legible y con buen contraste antes de empaquetar.
- **Scroll con rueda del mouse, a prueba del navegador embebido de SketchUp.** Aunque las pruebas en Chromium confirmaron que el CSS de 6.4.11 ya dejaba todo scrolleable, el navegador embebido de SketchUp puede comportarse distinto entregando la rueda del mouse a un contenedor `overflow:auto` anidado dentro de flex/grid. Se agregó un manejo manual de la rueda (busca el contenedor scrolleable real bajo el cursor y mueve su `scrollTop` a mano) como respaldo explícito, sin depender de que el motor del navegador lo resuelva solo -- y sin interferir con el zoom del visor 3D (si OrbitControls ya manejó el evento para hacer zoom, este respaldo se queda quieto).

## Cambios 6.4.11

Responde a "sigue sin poder scrolear... no sé si el lado izquierdo o también el derecho, el visualizador" -- esta vez se probó en un navegador real (Chromium headless a distintos altos de ventana) en vez de solo leer el CSS, para confirmar el bug de verdad en vez de adivinar.

- **Panel de configuración (izquierda):** su scroll SÍ funciona correctamente (confirmado con la prueba) -- el `grid-template-rows` de 6.4.10 lo dejó bien. Si en tu pantalla no ves una barra de scroll visible es porque el contenido de esa pestaña ya entra completo en tu ventana actual (no hay nada más abajo que ver en ese caso).
- **Visor 3D (derecha) -- bug real encontrado y corregido:** en una ventana lo bastante baja, "Validar módulo"/"Construir módulo" (los botones de abajo de todo) quedaban recortados fuera de la ventana SIN NINGUNA forma de llegar a ellos -- `aside.m3dv-panel` tenía `overflow:hidden!important` a propósito (para que el visor 3D "quedara fijo" y no se moviera con el scroll del árbol de piezas), pero eso significaba que si el contenido fijo (cabecera, visor, barra de vistas, explosión/giro) más los botones de abajo no entraban juntos en el alto disponible, la parte de abajo se perdía para siempre -- en el peor caso, "Construir módulo" se volvía imposible de pulsar. Se le agregó scroll de respaldo a todo el panel: en una ventana con espacio de sobra no cambia nada (no aparece ninguna barra), pero en una ventana chica ahora siempre se puede bajar hasta el botón de construir.
- Verificado con una prueba automatizada real (no solo lectura de CSS): a 900px de alto de ventana, "Construir módulo" pasó de estar fuera de la ventana a quedar alcanzable haciendo scroll.

## Cambios 6.4.10

Corrige el fix de 6.4.8, que quedó incompleto: "solo me deja ver lo que está aquí y no puedo deslizar para ver más funciones... el lado izquierdo o también el derecho, el visualizador".

- **Causa real:** 6.4.8 le quitó a `main`/`.config-pane`/`aside.m3dv-panel` el `height:calc(100vh - Npx)` con número fijo (correcto, porque se desincronizaba con el alto real de la cabecera) pero les dejó un `height:100%` que dependía de que la fila del grid de `main` tuviera una altura definida -- y no la tenía (quedaba "auto", del tamaño del contenido). Con eso, tanto el panel de configuración (izquierda) como el visor 3D (derecha) simplemente CRECÍAN al alto completo de su contenido en vez de quedarse del alto de la ventana, y como el `body` tiene `overflow:hidden`, todo lo que sobraba se recortaba sin ninguna barra de scroll -- ni a la izquierda ni a la derecha, exactamente lo reportado.
- **Fix real:** se agregó `grid-template-rows:minmax(0,1fr)` a `main`, que le da a esa fila una altura definida y flexible (llena exactamente lo que queda debajo de la cabecera, sea cual sea su alto). Con eso, el `height:100%` de ambos paneles ya tiene de qué ser el 100%, y su scroll interno (el de la izquierda siempre, el de la derecha solo en el árbol de piezas) vuelve a funcionar.

## Cambios 6.4.9

Responde a "le acabo de cambiar los días pero en la barra no se actualiza... quiero que se actualice cada 15min, lo de la validación de la licencia sería cada 24h".

- **Bug real encontrado y corregido:** el servidor de licencias nunca manda `ttl_seconds` en su respuesta -- por eso `mark_verified` calculaba `[0, 60].max` = **60 segundos** de sesión en caché, siempre, sin importar `LICENSE_SESSION_MAX_SECONDS`. Efecto práctico: cada vez que el plugin construía un módulo (que primero llama a `ensure_authorized`) volvía a llamar al servidor de verdad porque la caché de 60 segundos ya había expirado casi siempre. Corregido: si el servidor no manda `ttl_seconds` (nunca lo manda hoy), se confía en la sesión recién validada por el techo completo, no por 60 segundos.
- **`LICENSE_SESSION_MAX_SECONDS` pasa de 72h a 24h**, tal como pediste para "la validación completa".
- **La barra de días ya se refrescaba cada 15 minutos** (`LICENSE_HEARTBEAT_SECONDS`, ya existía) -- ese heartbeat SIEMPRE hace un request real al servidor sin importar la caché de sesión, así que si un administrador extiende tu licencia mientras el configurador ya está abierto, el cambio se refleja solo, sin cerrar y volver a abrir nada, dentro de esos 15 minutos (no es instantáneo: el plugin consulta, no recibe un aviso push).

## Cambios 6.4.8

Responde a "en esta parte me parece que había más funciones hacia abajo" (MODULAR-3D VIEW) y a "donde dice módulo seguido de medidas quiero que diga Espacio Libre".

- **Regresión real de 6.4.6, ya corregida:** al reorganizar la cabecera para que la barra de días fuera a todo el ancho (debajo de correo/días/Cerrar sesión), la cabecera pasó a ocupar 2 filas y quedó más alta que antes. El alto del panel del visor 3D (`aside.m3dv-panel`) y del panel de configuración (`.config-pane`) se calculaba con un número fijo en píxeles que asumía la altura vieja de la cabecera (`calc(100vh - 74px)`) -- al quedar la cabecera más alta, ese cálculo ya no cuadraba y recortaba la parte de abajo del visor (velocidad de giro, árbol de piezas, "Validar módulo"/"Construir módulo"). Se quitaron esos números fijos: ahora el alto se calcula solo mediante flexbox/grid (`height:100%` + `flex:1 1 auto`), sin depender de cuánto mida la cabecera -- que además cambia de alto ella misma según si hay sesión iniciada o no, así que un número fijo nunca iba a ser 100% confiable.
- **"Módulo" (la etiqueta del espacio antes de subdividirlo) ahora se llama "Espacio Libre"** en el badge naranja del visor (ej. "Espacio Libre · 570 × 730 × 557 mm"), para que no se confunda con el módulo completo -- es solo el hueco interior disponible, antes de dividirlo en zonas/espacios.

## Cambios 6.4.7

Tres pedidos en un solo mensaje: módulos que "se unen" cuando se crean varios en fila, el cajón sigue saliendo mucho, y "4 Materiales... es todo un champú, le pongo un color solo al lateral y me pinta todo el módulo".

- **Cada módulo nuevo se coloca 20mm hacia atrás (Y) respecto al anterior.** Sin este retranqueo, dos módulos creados en fila quedaban con el frente exactamente en el mismo plano Y, y SketchUp fusionaba visualmente los bordes/caras compartidas entre ambos como si fueran una sola pieza continua. Con el desplazamiento de 20mm ya no coinciden esos planos.
- **El cajón interactivo ahora sale la mitad de lejos que antes.** Salía `0.7 × fondo del cajón` (tope 500mm) -- se cambió a `0.35 × fondo` (tope 250mm), exactamente la mitad en ambos casos.
- **"4 Materiales" simplificado y con el bug real corregido:**
  - **Causa real de "le pongo un color solo al lateral y me pinta todo el módulo":** no existe (ni existía) un grupo "Lateral" separado -- "Casco" siempre incluyó los 2 laterales + base + techo juntos, todo de una. No es un bug de prioridad/cascada (esa parte ya funcionaba bien), es que el nombre del grupo no avisaba su alcance real. Se renombró a **"Casco (laterales, base y techo)"** en todos los desplegables y tarjetas, y se agregó un aviso arriba de la sección: para pintar UNA sola pieza (ej. solo el lateral izquierdo) hay que usar "Editar una pieza individual" (seleccionarla en el visualizador), no el grupo.
  - **Se redujeron los grupos siempre visibles de 10 a 6** (Casco, Interior, Frentes y puertas, Cajones interiores, Respaldo, Herrajes). Los otros 4 (Ajuste, Zócalo, Cornisa, Remates) -- que casi nunca hace falta tocar porque por defecto heredan el color del Casco -- quedaron detrás de un desplegable "Opciones avanzadas", sin perder nada de funcionalidad.
  - **Bug real corregido:** los desplegables "Grupo heredado" (al editar una pieza individual) y "Grupo" (al asignar una textura) no tenían las opciones Zócalo/Cornisa/Remates -- si elegías una pieza de esos grupos para darle un acabado individual, el grupo que se guardaba no era el correcto. Ya están las 10 opciones completas en ambos.

## Cambios 6.4.6

Ajuste puntual sobre el rediseño de 6.4.5, según la captura marcada: "la x marca lo que quiero que retires y le pongas así como está en la imagen, a todo el ancho y debajo de todo".

- **Se quitó la línea/separador vertical** que quedaba entre el correo y "X días".
- **La barra de días ahora ocupa todo el ancho de la píldora de sesión** (antes era una barra corta de 92px) y queda en su propia fila, debajo de todo (correo, días y "Cerrar sesión" arriba en una fila; la barra sola, a todo lo ancho, en la fila de abajo).

## Cambios 6.4.5

Responde a "esto debe quedar fijo al deslizar" (pestañas 1-5), "organiza mejor esos espacios que no me parece nada profesional" (cabecera con el correo/días/botón amontonados) y "aun aparece los 6 dias restantes" después de instalar 6.4.4.

- **Pestañas (1 Medidas...5 Catálogo) ahora quedan fijas arriba al desplazar** el panel de configuración — antes se iban con el scroll como el resto del contenido.
- **Cabecera reorganizada.** El correo, los días restantes y "Cerrar sesión" ahora van agrupados dentro de una píldora propia con separación clara (antes iban sueltos, pegados unos a otros, con la barra de días quedando visualmente encimada al correo) — la marca queda a la izquierda y Soporte/WhatsApp/versión a la derecha, cada uno con su espacio.
- **Causa real de por qué "aun aparece los 6 dias" incluso instalando 6.4.4 — dos problemas distintos, los dos ya corregidos:**
  1. **El bug de fondo estaba en el servidor, no en el plugin.** Extender la fecha de un usuario desde el panel admin solo actualizaba el registro de la cuenta, pero el plugin instalado consulta un registro POR PRODUCTO que nunca se actualizaba — por eso el panel mostraba 2027 y el plugin seguía leyendo la fecha vieja. Ya corregido en el servidor de licencias (repo aparte) y ya se sincronizaron manualmente en la base de datos real los usuarios que habían quedado desincronizados por este bug — tu cuenta ya debería mostrar la fecha correcta la próxima vez que abras el configurador, sin que dependa de esta actualización del plugin.
  2. **`interfaz.css`/`interfaz.js` y el resto de los `.js` del plugin no tenían ninguna forma de decirle a SketchUp "esta es una versión nueva, no uses la copia vieja que ya tenías en caché"** — el navegador embebido de SketchUp puede quedarse con la versión anterior de estos archivos aunque el `.rbz` ya haya instalado los nuevos en disco. Se agregó `?v=6.4.5` a cada uno; a partir de ahora, cada número de versión nuevo fuerza a SketchUp a leer los archivos actualizados de verdad.
  - **Nota importante para que cualquier corrección de código Ruby (como la de 6.4.4) tome efecto:** hace falta **reiniciar SketchUp por completo** después de instalar un `.rbz` con cambios en archivos `.rb` — cerrar y volver a abrir solo el panel del plugin no alcanza, porque Ruby no vuelve a cargar un archivo que ya cargó en esa sesión de SketchUp.

## Cambios 6.4.4

Responde a "le quedan 6 días... yo le aumenté un año pero no se puede ver, pero en la licencia sí está la fecha límite 2027, corrige eso" y al pedido de que la barra de días sea más larga y quede debajo de las letras, dentro del cuadro naranja.

- **La fecha/días restantes ahora se actualiza al abrir el configurador, no solo cada 72 horas.** Causa real: al abrir el diálogo, el plugin pedía el estado de la licencia con `Modular3D::License.status`, que devuelve lo último guardado en caché mientras no hayan pasado `LICENSE_SESSION_MAX_SECONDS` (72h) desde el último chequeo real al servidor — si un administrador extendía la licencia desde el panel, el plugin seguía mostrando los días/fecha viejos hasta que esa caché expirara sola o se reiniciara SketchUp. Ahora ese primer chequeo, al abrir el diálogo, llama de verdad a `/license/validate` (con el token ya guardado, sin pedir contraseña), así que una extensión hecha por el administrador se ve de inmediato la próxima vez que se abre el configurador.
  - Para no desconectar a nadie por un corte de internet momentáneo: si esa llamada falla por no poder contactar al servidor y la sesión anterior todavía era válida localmente, el plugin se queda con el estado en caché (no bloquea) y reintenta en el próximo heartbeat (cada 15 minutos) o en la próxima apertura.
- **Barra de días restantes: más larga (92px, antes 56px) y ahora debajo del texto "X días"** (antes iban en la misma fila, lado a lado), sin salir del cuadro naranja de la sesión.

## Cambios 6.4.3

Responde a "la puerta... está dentro del módulo y no fuera como el frente del cajón... debe estar alineado con el frente del cajón" y al pedido de agregar una opción de riel oculta con 3mm de holgura por lado (en vez de los 13mm fijos de la telescópica).

- **Puerta y frente de cajón ahora sobresalen exactamente lo mismo.** Causa real: el frente del cajón (falso o por cajón) usaba un grosor de tablero fijo para decidir cuánto sobresalir, mientras que la puerta calculaba su salida real según la sobremedida del panel vecino que tocaba (`calcularProtrusionPuerta`) — dos fórmulas distintas que solo coincidían por casualidad. Ahora el frente del cajón usa la MISMA fórmula que usaría una puerta en ese lugar, en los 3 motores (construcción real, visor en vivo, y el mismo cálculo se corrigió en ambos estilos de frente: falso y por cajón).
- **Nueva opción "Riel oculta" en "Sistema de corredera"** (holgura de 3mm por lado, para correderas invisibles montadas por debajo del cajón, no por los costados). El valor que ya existía con ese nombre estaba mal (21mm, más que la telescópica estándar) — no tenía sentido para un sistema que se monta abajo; se corrigió a 3mm.
- El módulo con árbol de espacios ("3 Configuración") ahora también respeta el "Sistema de corredera" elegido — antes esa holgura estaba fija en 13mm sin importar la opción seleccionada, solo el flujo más simple/antiguo la aplicaba de verdad.

## Cambios 6.4.2

Corrige un efecto secundario de la corrección 6.4.1: "en el visualizador los espacios deben sincronizarse tal como son" — al elegir un espacio de la lista ("Zona A", "Zona B", etc.) en un módulo con zócalo, el recuadro naranja de resaltado en el visor 3D no coincidía con la posición real de las piezas.

- **Causa real**: el "levante" del casco (para que el zócalo quede por fuera, ver 6.4.1) se aplicó dentro de `addPiece` (lo que dibuja cada pieza), pero las cajas invisibles de selección de espacio (`addSpaceHit`, usadas para el clic y el resaltado naranja de "Zona A"/"Zona B"/etc.) tenían su propio cálculo de posición aparte, sin ese mismo desplazamiento — quedaban ancladas a la posición vieja mientras las piezas ya se habían movido.
- Revisé todo el archivo del visor buscando cualquier otro lugar que posicionara algo en 3D sin pasar por el mismo mecanismo (`addPiece`) y confirmé que este era el único caso suelto.

## Cambios 6.4.1

Corrige 2 bugs reales reportados al probar v6.4.0 en SketchUp por primera vez: "el zócalo y las cornisas están creando dentro del módulo... debería ir por fuera" y "si el módulo es de 600 de ancho no debe crear un zócalo de 570mm sino de 600mm".

- **Zócalo/cornisa ya no quedan embebidos dentro del casco.** El bug real: el zócalo se creaba en el mismo nivel (z=0) donde ya empieza la base del módulo, y la cornisa se restaba desde arriba del alto total en vez de agregarse por encima — ambas terminaban superpuestas con piezas del casco en vez de visibles por fuera. Corregido de raíz: cuando un módulo lleva zócalo, TODO el casco (laterales, base, techo, interior, ajustes, respaldo, puertas, cajones) se levanta 126mm para quedar apoyado ENCIMA del zócalo, que ahora sí ocupa el piso real. La cornisa se apoya sobre el tope real del casco ya levantado. Corregido en los 3 motores de geometría que tiene el plugin (construcción real en Ruby, visor 3D en vivo, plano 2D/despiece) para que los tres muestren exactamente lo mismo.
- **Zócalo, premesón y cornisa ahora cubren el ancho TOTAL del módulo**, no solo el hueco interior entre laterales — un módulo de 600mm de ancho ahora genera un zócalo (y cornisa, y premesón) de 600mm, tapando también el grosor de los laterales, como se esperaba desde el diseño original.
- **Validado con números reales antes de empaquetar**: para un módulo de 760mm de alto con zócalo, el casco queda de 126 a 886mm y el zócalo de 0 a 126mm — se tocan exactamente, sin superposición ni hueco.

## Cambios 6.4.0

Responde al pedido "al iniciar sesion aceptara el usuario unos terminos y condiciones... solo si acepta puede ingresar por unica vez". El servidor de licencias (`api.modular-3d.com`) ya exige esta aceptación desde el 2026-09-28 — **instalar esta versión es obligatorio para poder iniciar sesión**, una versión anterior del plugin no sabe mostrar el modal y solo se ve el mensaje de error sin forma de continuar.

- **Modal de términos y condiciones en el primer login.** Al iniciar sesión, si el servidor indica que todavía no aceptaste, aparece un modal con el texto completo, un checkbox de confirmación y los botones "Acepto y continuar"/"Cancelar" — nunca se entra sin marcar el checkbox y aceptar. Se pide una sola vez por usuario (en cualquier equipo autorizado de tu licencia); una vez aceptado, no se vuelve a preguntar.
- **"Leer términos y condiciones"** en la pantalla de login: podés leerlos completos ANTES de intentar iniciar sesión, sin necesitar red ni escribir tu contraseña primero.
- **Nuevo endpoint del lado servidor** (`/auth/accept-terms`): reenvía las mismas credenciales, registra la aceptación con fecha y versión del texto, y devuelve la sesión ya iniciada en el mismo paso — no hace falta escribir la contraseña dos veces.
- **Datos de contacto al activar un usuario nuevo.** El panel administrativo (donde se crean las licencias) ahora pide también apellido, celular y dirección — no afecta a los usuarios ya activos. Se agregó un botón "WhatsApp" junto a cada usuario para poder escribirle manualmente (con un mensaje ya sugerido) cuando su licencia está por vencer o ya venció.
- **Nota honesta de alcance:** el texto de términos y condiciones es un borrador razonable escrito para cubrir lo esencial (licencia de uso, qué datos se guardan, vigencia, responsabilidad, soporte) — no es una revisión legal profesional; conviene que lo revises vos (o un abogado) antes de depender de él para algo serio. Todo lo demás (modal, endpoint, datos de contacto, botón de WhatsApp) ya está probado en producción real, no solo en teoría.

## Cambios 6.3.0

Responde al pedido "quiero que agregues automaticamente un zocalo cuando cree un modulo bajo..." y a las 3 rondas de aclaración que siguieron (premesón, cornisa, remates, colores por tipo, sesión de 72h, ajustes por defecto). Manifiesto migrado a **schema 9** (`tipo_modulo`, `cornisa_activa`, `cornisa_altura`, `remate_inicial`, `remate_final`, `remate_zocalo_lado`, `remate_cornisa_lado`) — los módulos guardados en versiones anteriores se abren igual que siempre, con estos campos en sus valores por defecto (sin zócalo/cornisa/remates hasta que edites el módulo y elijas un `tipo_modulo`).

- **Zócalo automático en módulos Bajo/Auxiliar/Closet.** Al elegir `tipo_modulo` = BAJO, AUXILIAR o CLOSET en "1 Medidas", el módulo construye un zócalo de 126mm de alto × 15mm de grosor, retranqueado 70mm desde el frente, automáticamente. Sin opción de desactivarlo (regla que confirmaste: "el zócalo siempre debe ir").
- **Premesón automático en módulos Bajo.** Cubre la parte alta del módulo bajo (ancho × profundidad libre tras el zócalo), siempre en material crudo (sin rol de color asignable — es la placa donde se instala el mesón/cubierta real).
- **Cornisa opcional en Alto/Auxiliar/Closet, con altura editable.** A diferencia del zócalo, la cornisa se activa/desactiva por módulo (`cornisa_activa`) y su altura es un campo libre (`cornisa_altura`), retranqueada 20mm desde la altura de la puerta.
- **Remates laterales en Auxiliar/Closet.** Panel de 100mm de ancho en el costado, continuo con la puerta desde el zócalo hasta 2420mm de alto (para cortar a medida en obra). Elegibles por separado: remate inicial (izquierdo), remate final (derecho), remate de zócalo (cubre en profundidad desde los 70mm del zócalo hacia atrás) y remate de cornisa (misma lógica, a la altura de la cornisa).
- **Tope de 2420mm en zócalo/premesón/cornisa/remates**, igual que un tablero de melamina estándar — estas piezas nunca se construyen más largas que eso, incluso si el módulo lo es.
- **Nuevo comando "Sincronizar continuidad".** Cuando pegás varios módulos con zócalo/premesón/cornisa unos a otros (en línea recta, sin rotación), este comando los detecta y fusiona esas piezas en tramos continuos de hasta 2420mm — como pediste ("si creo otro bajo debera la pieza ser continua"). Nunca borra piezas de un módulo: oculta las que quedan cubiertas por el tramo fusionado y crea la pieza fusionada aparte, en un grupo propio; correlo cuantas veces quieras, cada corrida recalcula todo desde cero (mover o borrar un módulo y volver a sincronizar nunca deja una pieza oculta "huérfana"). Solo detecta módulos sin rotación alineados en línea recta sobre el eje X — un módulo esquinero o contra otra pared queda fuera de la fusión automática, sin avisar error, conservando sus propias piezas.
- **3 roles de color nuevos en "4 Materiales":** Zócalo, Cornisa y Remates (auxiliar/closet) — con su propio selector de color/nombre, igual que Casco/Interior/Puertas/etc. Por defecto los remates de auxiliar/closet heredan el color de las puertas (se puede cambiar por separado). El premesón no tiene rol de color: siempre queda en crudo.
- **Respaldo: nueva opción "Solo ajustes (sin respaldo)".** Además de Sí/No, ahora podés dejar un módulo sin panel de respaldo pero con sus ajustes (topes de nivelación) igual, sin la contradicción anterior de tener que elegir "No" y perder los ajustes también.
- **Ajustes: 70mm por defecto (antes 60mm) en todo el plugin** (formulario, construcción real, visor en vivo y plano 2D) — la cantidad de ajustes sigue siendo automática según la altura por defecto, editable como siempre.
- **Sesión de licencia: 72 horas.** `LICENSE_SESSION_MAX_SECONDS` (el techo local de cuánto dura la sesión "verificada" antes de volver a llamar al servidor) pasó de 1 a 72 horas. El otro límite real — cuánto dura el token en sí antes de forzar un nuevo login — se define en el servidor (Cloudflare Worker de licencias), fuera de este repositorio; quedó documentado en el código para quien administre ese Worker.
- **Alcance dejado fuera a propósito, documentado (no oculto): NO se implementó el rediseño completo de "materiales por lotes"** que pediste ("quitar del configurador e implementar en este boton [Repintar varios módulos]... por defecto todo se pintará en blanco... por grupos o tipos"). Esa parte exige retirar el paso "4 Materiales" de la creación de cada módulo, hacer que todo nazca en blanco, y reconstruir "Repintar varios módulos" para asignar color por tipo/grupo o por pieza sobre todo lo ya creado en el escenario — un cambio de flujo completo que puede romper el paso de materiales que YA funciona y del que dependen los módulos ya guardados. Se implementó únicamente la parte aditiva y segura: los 3 roles de color nuevos (zócalo/cornisa/remates) en el panel por módulo que ya existía, sin tocar su funcionamiento. El rediseño de "Repintar varios módulos" queda pendiente para una ronda aparte, ya con este motor de piezas probado en SketchUp primero.
- **Nota honesta de alcance:** sin entorno real de SketchUp disponible esta ronda, la validación fue `ruby -c`/`node --check` en el proyecto completo (sin errores), balance de tags en `interfaz.html`, y verificación cruzada manual de cada pieza nueva (zócalo/premesón/cornisa/remates) contra las fórmulas de posición que ya usa `jerarquia.rb` para el resto del casco, replicadas igual en `plano2d_inventario.rb` (plano 2D) y `modular3d_view.js` (visor en vivo). El motor de continuidad se revisó línea por línea contra el patrón ya usado en `despiece.rb`/`biblioteca.rb` para leer módulos existentes y guardar/restaurar el estado de construcción — pero no hay una prueba real dentro de SketchUp todavía; es la primera cosa a probar al instalar este `.rbz`.

## Cambios 6.2.0

Respuesta a tu pregunta "hay manera de crear un catalogo para que se sincronice con otros usuarios... dentro del mismo ecosistema modular-3D" y a la aclaración de qué querías guardar ("tipos de modulos... con su respectiva clasificacion, listos para modificar anchos y alturas"). Esta ronda tuvo dos partes: primero la infraestructura en la nube (servidor, base de datos, panel de administración multi-producto), y después esta — la pestaña nueva del lado del plugin para que el catálogo se use de verdad desde SketchUp. Sin cambios de manifiesto (sigue en schema 8) — no es un campo del módulo guardado, es una sincronización aparte.

- **Nueva pestaña "5 Catálogo" en el configurador.** Lista los Tipos de Módulo guardados por cualquier usuario con licencia activa, filtrables por categoría o por texto, con miniatura (cuando tiene), dimensiones, autor y contador de uso. "Insertar" precarga el formulario completo (medidas, casco, espacios y materiales) reutilizando tal cual el mismo mecanismo que ya usan "Editar módulo" y "Configuración de Proyecto" — así que ancho, alto y profundidad quedan editables antes de construir, exactamente como pediste.
- **"Guardar el módulo actual en el Catálogo"**, en la misma pestaña: con categoría (con sugerencias de las ya usadas) y nombre, guarda la configuración completa del módulo activo para que el resto del equipo con licencia lo tenga disponible al instante.
- **Reutiliza la sesión existente, sin una segunda contraseña.** El Catálogo se autentica con el mismo token que ya usa Modular3D::License para la licencia; si no iniciaste sesión, te avisa que primero hace falta entrar (mismo candado que ya bloquea el resto del plugin).
- **Nuevo módulo `core/catalogo.rb`** (`Modular3D::Catalogo`): habla por HTTPS con el servidor de plataforma (mismo dominio `api.modular-3d.com`, ruta separada de la de licencias). `core/license.rb` ahora también manda `product_code: "modular3d_plugin"` en login/validate/heartbeat — aditivo, no rompe nada si el servidor todavía no lo usa.
- **Diseño deliberado para no sumar latencia:** a diferencia de Perfiles/Principios/Parámetros de Diseño (archivos locales, se cargan solos al abrir el diálogo), el Catálogo es una llamada de red real — se carga solo la PRIMERA vez que abrís la pestaña "5 Catálogo" en esa sesión, nunca al abrir el configurador, para no demorar a quien nunca la usa.
- **Nota honesta de alcance:** sin entorno real de SketchUp ni servidor desplegado disponibles en esta sesión (el Worker de plataforma quedó listo pero pendiente de que lo despliegues vos, ver ronda anterior), la verificación fue: `ruby -c`/`node --check` en el proyecto completo (sin errores), balance de tags y de ids en `interfaz.html` (sin duplicados ni referencias colgantes), y un harness headless (Chromium) con el puente `window.sketchup` simulado con respuestas de ejemplo — confirmó que la pestaña carga categorías y resultados, que "Insertar" precarga ancho/alto correctamente y deja "1 Medidas" listo para editar, y que "Guardar" arma el payload con las medidas ya normalizadas a número. La prueba real contra el servidor en vivo, y dentro de SketchUp, sigue pendiente hasta que despliegues el Worker nuevo.

## Cambios 6.1.0

Ronda de dos partes. La primera (6.0.1) corrige 4 problemas concretos que reportaste al instalar y probar v6.0.0 por primera vez dentro de SketchUp, más la aclaración "la puerta debe respetar su última sobremedida". La segunda (6.1.0 propiamente) responde a tu pedido de mitad de ronda: "ademas debe dejarme escojer los colores subidos y debe darme una muestra del color en miniatura para saber diferenciar, organiza totalmente el paso 4 que es de materiales". Sin cambios de manifiesto en esta ronda (sigue en schema 8) — todos los módulos guardados en versiones anteriores se abren igual que siempre.

- **Causa raíz de 3 de los 4 bugs reportados: el visor 3D en vivo (JS) y la construcción real (Ruby) son dos motores de geometría paralelos, y v6.0.0 solo actualizó uno.** `core/jerarquia.rb` (Ruby, construye de verdad) y `ui/modular3d_view.js` (JS, dibuja la previsualización en vivo mientras editás) tienen que mantenerse espejados a mano — un comentario del propio archivo ya se comprometía a esto. El trabajo de v6.0.0 (protrusión de puerta, montaje por nodo) solo tocó el lado Ruby, así que SketchUp construía bien pero el visor en pantalla seguía mostrando el comportamiento viejo. Se portó a JS la lógica que faltaba en los 3 puntos reportados.
- **Puerta embutida / debe respetar la última sobremedida — corregido en el visor en vivo.** La fórmula de protrusión de puerta (que ya funcionaba bien en la construcción real desde v6.0.0) ahora también corre en el visor 3D: cambiás la sobremedida de cualquier panel vecino y la puerta se adelanta en pantalla al instante, sin tener que reconstruir en SketchUp para verlo.
- **Inglete 45° que quedaba pegado aunque eligieras Interior o Sobrepuesto — bug real, no solo falta de espejo.** El código que inyectaba automáticamente el bisel de inglete nunca lo quitaba al cambiar de opción. Se corrigió marcando cada inyección automática por separado de un ajuste manual tuyo, para poder borrarla sola sin tocar nada que hayas puesto a mano vos.
- **Montaje Interior/Sobrepuesto por espacio — corregido en el visor en vivo**, mismo motivo que la puerta: la construcción real ya lo hacía bien, el visor JS no se había actualizado.
- **"2 travesaños" ahora es exclusivo de la tapa superior**, como aclaraste — se retiró la opción de la base inferior en los 3 lugares donde vivía (formulario, Reglas de Construcción, visor en vivo).
- **Plano 2D rediseñado de punta a punta: ahora es una planimetría de taller real, no 6 vistas en milímetros crudos sin caber en ninguna hoja.** 4 vistas con cotas (elevación frontal, elevación lateral, planta, corte vertical — se sacó la explosión que pediste eliminar, y también la isométrica, que ahora vive solo en el visor 3D), escala y tamaño de hoja (A4/A3, vertical/horizontal) elegidos automáticamente para que el dibujo entre legible, cajetín con nombre/medidas/escala/fecha, y de verdad una hoja `.svg` por módulo cuando exportás varios (antes todos los módulos caían en el mismo archivo).
- **Paso "4 Materiales" reorganizado por completo, con selector de colores ya usados y miniatura de color.** Al auditar la pestaña para reorganizarla apareció una duplicación real: "Material único para todo el módulo" vivía repetido en dos pestañas distintas, sincronizado a mano — se unificó en un solo lugar. La pestaña quedó en 7 tarjetas con un propósito cada una (material único, cantos, materiales por grupo, biblioteca, pieza individual, resumen). Se agregó lo que pediste: debajo de cada selector de color aparece una fila de muestras clicables con los colores que ya usaste en el módulo (más un puñado de neutros de referencia) para reutilizarlos con un clic en vez de volver a tipear o elegir el hex; y el desplegable de materiales guardados ahora pinta cada opción con su color real para diferenciarlos de un vistazo.
- **Nota honesta de alcance:** los 4 fixes de espejo JS/Ruby se verificaron por lectura cruzada línea a línea contra la lógica ya probada de Ruby (no hay entorno real de SketchUp en esta sesión para probarlos en vivo dentro del visor — sigue siendo la prueba real pendiente). El plano 2D y la reorganización de Materiales sí se verificaron con render/captura headless (Chromium) además de lectura de código: se encontraron y corrigieron en el momento dos bugs de layout del plano (notas que se salían de la hoja) y dos de la paleta de colores (campo de nombre angosto por un choque de grid CSS, y paletas que quedaban visibles en grupos sin activar) antes de dar cada parte por terminada.

## Cambios 6.0.0

Ronda basada en tu revisión de la v5.0.0 (capturas de "Componentes del espacio" y "3 Configuración") y en el reporte `Reporte_v6_Casco_Puertas_Plano2D.md` que se entregó ANTES de tocar código, a pedido explícito tuyo ("dame un reporte completo a detalle antes de implementar"). Las 3 preguntas de ese reporte las respondiste así: Fase A con decisión editable (automático + aviso opcional), Fase B con inglete 45° también por espacio y los mismos defaults del casco general (bases/techos internos, laterales sobrepuestos), Fase D con vectores editables completos, no imágenes. Manifiesto migrado a **schema 8** (`puerta_protrusion_modo`, `puerta_protrusion_override_mm`); los módulos guardados en versiones anteriores se abren igual que siempre, sin cambiar ni un milímetro.

- **Corrección importante de diagnóstico (honestidad ante todo).** El reporte original diagnosticó el bug de "puerta embutida" como un problema de `facadeBox` en JS (ancho/alto de la puerta calculados sin sobremedida). Al implementar se descubrió que ese diagnóstico era impreciso: la sobremedida SOLO afecta profundidad (eje Y), nunca ancho/alto — el bug real es que la posición Y de la puerta (`core/jerarquia.rb`) nunca se enteraba de cuánto sobresalía un panel vecino. El arreglo real (Fase A, abajo) vive enteramente en Ruby, no en `facadeBox`. Se corrige acá para que quede documentado con precisión.
- **Fase A — Puertas que respetan la sobremedida real (motor de protrusión).** Cada puerta solapada ahora calcula, pieza por pieza, cuál de los paneles que realmente toca (lateral/base/techo — del casco o del espacio) sobresale más hacia adelante, y se adelanta hasta quedar al ras de ESE panel en vez de nacer siempre en `-grosor_puerta`. Nueva tarjeta **"Puertas frente a sobremedida"** en "2 Casco": modo *Automático* (silencioso) o *Automático y avisar* (aviso en vivo si hay una diferencia notable entre piezas, por si fue un error de tipeo), más un campo para **forzar manualmente** la salida de todas las puertas solapadas del módulo — la "decisión editable" que pediste, sin necesitar una UI de overrides por arista.
- **Fase B — Montaje interior/sobrepuesto + inglete 45° generalizado a cada espacio.** El casco general ya tenía "Construcción" (Interior/Sobrepuesto/Inglete) por panel; ahora "Componentes del espacio" (en cada nodo de "3 Configuración") tiene el mismo control para lateral izq./der./base/techo, con los defaults que pediste (bases/techos/travesaños internos, laterales sobrepuestos por defecto). Un lateral sobrepuesto o con inglete fuerza la base/techo de ESE MISMO espacio a interior (misma regla de conflicto de esquina que ya regía al casco general, replicada por nodo). El casco general también suma **"2 travesaños"** como alternativa a techo/base completos (ya existía por espacio; faltaba a nivel casco).
- **Fase C — Reglas de Construcción con nombre (inspirado en B_06 de imos).** Nueva tarjeta en "2 Casco": guarda la combinación completa de montaje de laterales/base/techo + tipo base/techo (panel o travesaños) con un nombre, para reaplicarla con un clic en cualquier otro módulo — igual que "Parámetro de Diseño", pero para el casco general en vez de los huelgos. "ESTANDAR" reproduce exactamente los valores que ya traía el plugin.
- **Fase D — Plano 2D con 6 vistas vectoriales por módulo (antes: solo una elevación esquemática).** Nuevo motor de inventario de piezas (`core/plano2d_inventario.rb`) que recalcula, en Ruby puro y sin necesitar el módulo construido en SketchUp, la posición real de cada pieza (envolvente, paneles por espacio, puertas con su protrusión, frentes de cajón, respaldo, ajustes) a partir de los mismos datos que usa la construcción real. El comando **"Plano 2D (SVG)"** ahora exporta, por cada módulo seleccionado: elevación frontal y lateral con cotas, planta (corte horizontal a media altura), corte vertical con achurado del material cortado, isométrica vectorial y vista explosionada — las 6 en un solo SVG, todo vector editable (no imágenes embebidas).
- **Alcance dejado fuera a propósito, documentado (no oculto):** el plano 2D no dibuja el interior mecánico de cada cajón (laterales/post/fondo — quedan detrás de su frente en cualquier vista externa) ni herrajes individuales (bisagras/correderas, que ya tienen su propio dominio en Despiece/Presupuesto); la isométrica y la explosión usan un algoritmo propio y más simple que el explosionado interactivo del visor 3D (no es el mismo código, adaptado).
- **Nota honesta de alcance:** igual que en v5.0.0, sin entorno real de SketchUp disponible esta ronda, la validación fue sintaxis Ruby/JS (`ruby -c`, `node --check` en el proyecto completo, todo en verde), una verificación numérica cruzada manual de `plano2d_inventario.rb` contra las fórmulas de `jerarquia.rb` con un módulo de prueba, y una revisión visual del SVG generado (renderizado con Chromium headless) para confirmar que las 6 vistas ubican cada pieza donde corresponde. La primera apertura dentro de SketchUp sigue siendo la prueba real.

## Cambios 5.0.0

Ronda grande basada en la propuesta `Propuesta_Modular3D_v5_Mejoras_imos.md` (comparación previa contra imos): 8 tareas, implementadas y entregadas juntas a pedido explícito ("completo y probar una sola" — todo de una vez, un solo ciclo de prueba al final). Manifiesto migrado a **schema 7** (`parametro_diseno_id`); los módulos guardados en versiones anteriores se abren igual que siempre.

- **Visor 2D/3D unificado (tarea 1/8).** Se eliminó el plano 2D aparte (`mountPlan`, el diagrama en HTML/CSS de "3 Configuración") junto con toda la interfaz "review" muerta que quedó de una versión anterior. El visor 3D existente ya tenía casi toda la infraestructura de un plano técnico (hit-boxes por espacio, vistas fijas, separadores como piezas reales): el botón **"Vista 2D"** ahora pone cámara ortogonal de frente, activa transparencia temporal para ver el interior a través de los frentes, y permite seleccionar cualquier espacio con un clic — un solo visor para las dos vistas, mejor organizado en vez de mantener dos representaciones aparte.
- **Motor de reglas de visibilidad orientado a datos (tarea 2/8).** Las tres cascadas de mostrar/ocultar campos que existían por separado (inspector de espacio, Casco, Materiales — cada una escrita a mano) se migraron a un solo motor compartido (`ui/reglas_visibilidad.js`, inspirado en el `LOGIC_DEFINITION` declarativo de imos): cada pestaña declara sus condiciones como datos (`{selector, cuando}`) y las ~19 reglas existentes se migraron una por una, verificadas contra el código original, sin inventar ni cambiar ningún comportamiento. Agregar una cascada nueva en cualquier pestaña futura ahora es una línea de datos, no una función nueva — el pedido de "así con todo" queda resuelto de raíz.
- **Parámetros de Diseño reutilizables (tarea 3/8, inspirado en Design Parameters de imos).** Nuevo desplegable "Parámetro de diseño" en "1 Medidas": agrupa juego general, fuga de frente, solapes de puerta/repisa y huelgo entre cajones en un conjunto con nombre propio, reutilizable entre módulos. "ESTANDAR" reproduce exactamente los valores que ya traía el plugin (no cambia nada existente); "Guardar huelgos actuales como Parámetro de diseño…" guarda uno nuevo. Solo afecta a los ESPACIOS NUEVOS que se crean después — nunca reescribe uno ya configurado.
- **Configuración de Proyecto (tarea 4/8, cascada estándar → proyecto → módulo, como en imos).** Nuevo comando "Configuración de Proyecto": guarda medidas/parámetro de diseño/canto/corredera/material por defecto para ESTE archivo. "Crear módulo" precarga el formulario con esos valores automáticamente; "Aplicar a la selección" reaplica material/canto/corredera (nunca medidas, eso exigiría reconstruir geometría) a módulos ya construidos que tengas seleccionados.
- **Principios de Espacio reutilizables (tarea 5/8, inspirado en el Principio de Construcción + patrón `_INSERT.xml`/PART de imos).** En el inspector de cada espacio: "Guardar este espacio como Principio…" / "Aplicar Principio…" — reutiliza contenido, frente, huelgos y cierres de un espacio en cualquier otro espacio de cualquier módulo (sin anidar subdivisiones, por ahora). Distingue Principios "de fábrica" (empaquetados con el plugin) de los guardados por el usuario, igual que la carpeta de Biblioteca.
- **Herrajes editables por JSON, nivel A (tarea 6/8).** Las tablas fijas de bisagras por altura y holgura de corredera (hardcodeadas en Ruby, y que ya cambiaron de valor varias veces en el changelog) pasan a `Modular_3D/herrajes/*.json` opcional — si el archivo no existe, el comportamiento es idéntico al de siempre. Deliberadamente NO se reintroducen jaladores/gola (retirados en 4.8.0 a pedido explícito); eso es Nivel B y necesita confirmación aparte.
- **Mecanizados exportables + Plano 2D + Panel de Proyecto (tareas 7-9/8).** El despiece suma una columna **"Mecanizado"** con la posición de taladro de bisagra de cada puerta (distancia al canto + reparto vertical), pensada como punto de partida para revisar a mano, no coordenadas listas para CNC sin supervisión. Nuevo comando **"Plano 2D (SVG)"**: exporta una elevación frontal esquemática de los módulos seleccionados a partir de la misma jerarquía guardada que ya usa la construcción real (no una aproximación aparte); solo disponible para módulos construidos con el árbol de espacios de "3 Configuración". Nuevo comando **"Panel de Proyecto"**: resumen agregado por módulo (piezas, puertas, bisagras, cajones, área de tablero) reutilizando los mismos cálculos que Despiece/Presupuesto.
- **Nota honesta de alcance:** sin entorno real de SketchUp disponible para esta ronda, la validación hecha es sintaxis Ruby/JS (`ruby -c`, `node --check`), balance de tags HTML y verificación cruzada manual de cada pieza migrada contra el código original. La primera apertura dentro de SketchUp debe tratarse como la prueba real — se documentó cada decisión de alcance (qué se dejó afuera y por qué) en `claude/Implementacion_Modular3D_v5_bitacora.md` para quien retome el trabajo.

## Cambios 4.9.0

Se incorporó la biblioteca completa de texturas de fabricantes (`Texturas.zip`, ~244MB, enviada en 12 partes) tal como estaba organizada, con lectura recursiva de colores incluso en subcarpetas.

- **8 marcas, 423 fotos de melamina/color reales**, agregadas en `Modular_3D/textures/<MARCA>/...` respetando la estructura original: DURAPLAC, FABLAC, FIBRAPLAC, GUARARAPES, MASISA, PELIKANO, TABLEROS HISPANOS y VESTO (esta última con sus 5 colecciones como subcarpetas: Clásico, Innovación, Sinkronía, Tendencias, Unicolores). Los 7 colores curados que ya existían (blanco liso, roble claro, wengué, etc.) se conservan igual que antes.
- **Lectura recursiva de cualquier profundidad de subcarpetas**: no se limitó a un solo nivel "marca → archivo" — funciona igual si una marca tiene colecciones intermedias (como VESTO) o no.
- **El selector de textura ahora agrupa por marca** (y colección, cuando aplica) en vez de mostrar una lista plana de 430 nombres — se ve "MASISA · Santorini" dentro de un grupo "MASISA", no una lista interminable sin organizar.
- **Cómo funciona por dentro:** las fotos no se leen en vivo desde Ruby/SketchUp en cada apertura (ahí no hay forma de calcular un color promedio real sin una librería de imágenes) — hay un script nuevo, `Modular_3D/textures/generar_manifiesto.py`, que se corre una sola vez (o cada vez que agregues/quites carpetas de marcas) y genera `manifest.json` con el nombre, la ruta, un color promedio calculado de cada foto real y la marca/colección de cada textura. Ese `manifest.json` es el único lugar que hay que tocar para sumar o sacar texturas — no hace falta tocar Ruby ni JS.
- **Aviso de tamaño:** esto agrega ~244MB de imágenes al repositorio de git de forma permanente (no se usó Git LFS ni hosting externo, para mantenerlo simple como un solo paquete instalable). Si en algún momento el repositorio se vuelve incómodo de clonar/descargar por este motivo, se puede migrar a Git LFS más adelante sin perder ninguna textura.

## Cambios 4.8.28

La v4.8.27 no gustó: la columna de configuración quedó demasiado angosta con las pestañas verticales, se sentía amontonada. Se rehizo el layout completo en base al feedback puntual.

- **El visor 3D ahora queda fijo de verdad.** Antes, si el árbol de piezas o la lista de materiales tenían mucho contenido, todo el panel derecho (incluido el visor) se desplazaba al hacer scroll, tapando el 3D. Ahora el panel del visor es una columna fija dividida en dos zonas: arriba, la cabecera + el visor 3D + la barra de vistas + explosión/giro automático **nunca se mueven ni se ocultan** (siguen mostrando el módulo actualizándose en tiempo real pase lo que pase); abajo, solo el árbol de piezas y las propiedades técnicas se desplazan en su propio espacio acotado, sin arrastrar el visor con ellos.
- **Se deshizo la columna angosta de 330px y las pestañas verticales** de la v4.8.27 — vuelven las pestañas horizontales de siempre y el configurador recupera un ancho cómodo (flexible, ~480px o más según el tamaño de la ventana) para que las etiquetas y campos no queden apretados.
- **Se restauraron las grillas de varias columnas** que se habían aplastado a una sola columna la ronda pasada para "caber" en el espacio angosto: la grilla de materiales, el editor de pieza individual y el panel de jerarquía (plano + inspector lado a lado) vuelven a repartirse en 2-3 columnas cuando hay espacio, con su propio resguardo para pantallas angostas.
- Se conserva todo lo bueno de la v4.8.27 que no tenía que ver con el ancho de columna: la activación en cascada en Casco y Materiales, y la limpieza de botones muertos/redundantes de la auditoría.

## Cambios 4.8.27

A partir de las capturas de referencia que mandaste (un configurador de cuerpos de mueble con árbol a la izquierda, visor grande al centro y panel de propiedades a la derecha) y del informe de auditoría de la ronda anterior, se rediseñó la pantalla principal en una sola versión — sin dejar nada a mitad de camino.

- **El visor 3D pasa a ser el protagonista.** Antes el configurador ocupaba la mitad ancha de la pantalla y el visor quedaba angosto a la derecha; ahora se invirtió: el configurador es una columna angosta de 330px a la izquierda (como un panel de propiedades) y el visor 3D toma todo el resto del ancho disponible, igual que en la referencia.
- **Las pestañas del configurador pasan de una fila horizontal a una lista vertical** ("1 Medidas", "2 Casco", "3 Configuración", "4 Materiales" uno debajo del otro), ya que ahora viven en una columna angosta en vez de una franja ancha.
- **Activación en cascada — lo que no aplica, no se muestra:**
  - En **Casco**: si "Sin respaldo" está elegido, se ocultan grosor y profundidad de ranura (no aportan nada sin respaldo). Si "Cantidad posterior" es "Sin ajustes", se ocultan las 5 opciones de detalle del ajuste posterior. Si "Ajuste frontal" está apagado, se oculta su fila de orientación.
  - En **Materiales**: los campos de color/textura de "Material único" ahora están escondidos hasta que marcás ese checkbox. Cada grupo (Casco, Interior, Frentes, etc.) esconde su selector de color hasta que marcás "Material propio del grupo" — antes se veía siempre aunque estuviera heredando del casco. Al editar una pieza individual, todo el bloque de color/textura/canto/sobremedida/inglete queda oculto hasta que elegís "Usar material propio" en vez de "Heredar del grupo".
  - Esto ya existía parcialmente en el configurador jerárquico (el contenido de cada espacio ya ocultaba lo que no aplicaba); ahora se extendió el mismo criterio al resto de la interfaz.
- **Limpieza de la auditoría anterior, aplicada de una vez:**
  - Se sacaron los 7 botones de vista (Isométrica, Frontal, Posterior, etc.) que llevaban años escondidos por CSS sin que nada los volviera a mostrar — el cubo de navegación ya cubre exactamente lo mismo.
  - Se sacó el checkbox "Heredar automáticamente el color de cada pieza", que no tenía ningún efecto real.
  - "Aplicar a todo el módulo" y "Restaurar materiales por grupo" se sacaron — eran alias del mismo checkbox "Material único" que ya estaba dos líneas arriba.
  - Se sacó el botón "Recalcular" del presupuesto — cada cambio ya recalcula solo.
  - Se corrigió el clic para seleccionar en 3D desde las tarjetas "Sistema posterior" (antes no hacía nada por un desajuste de clases CSS); la de "Ajustes" se dejó sin ese atajo porque un módulo puede tener varias piezas de ajuste a la vez y no hay una sola pieza "correcta" para seleccionar ahí.
- Los hallazgos de la auditoría que **no** se tocaron en esta ronda (por ser cambios de fondo a la geometría o requerir una decisión tuya primero, no algo que se limpia sin más): el parser de medidas triplicado, la geometría del casco duplicada en Ruby/JS, "Validar módulo" no cubriendo la jerarquía, "Abierto" sin destapar frentes de cajón, y el resto de los puntos B/C/D del informe — siguen ahí, documentados, esperando prioridad tuya.


## Cambios 4.8.26

Reportaste que en 4.8.25 el visualizador 3D se puso en negro y el cubo dejó de verse como un cubo (una especie de rombo aplanado). No pude reproducirlo en este entorno (no tengo SketchUp real para abrir el diálogo), así que hice lo siguiente:

- **Encontré y corregí una causa real y concreta del cubo aplanado**: al achicar el cubo en la ronda anterior (46px → 38px → 32px) dejé el `perspective` fijo en 280px sin ajustarlo. En CSS 3D, `perspective` y el tamaño del objeto tienen que guardar una proporción — si el objeto se achica y la perspectiva se queda igual, el efecto de profundidad se debilita y el cubo se ve cada vez más plano. Ajusté `perspective` a 195px para mantener la misma proporción que tenía la versión que sí se veía bien (280px con un cubo de 46px).
- **Quité el `filter: drop-shadow` de la sombra del cubo**: es un patrón conocido que en versiones de Chromium más viejas (el navegador embebido de SketchUp no siempre es el más reciente) puede romper el contexto de transformaciones 3D de los elementos hijos — exactamente el tipo de síntoma que describiste. Era puramente decorativo, así que se saca sin perder funcionalidad.
- **Agregué un reporte de errores directo en el panel**: si el visualizador se pone en negro de nuevo (por esto o por cualquier otra causa), el texto que dice "Render local" abajo del visor va a cambiar automáticamente a algo como "Error JS: mensaje (archivo:línea)" en vez de quedarse en silencio. Si vuelve a pasar, copiame exactamente ese texto — con eso puedo ir directo a la causa real en vez de seguir adivinando a ciegas.

**Sobre tus otros pedidos de este mensaje** (puertas/cajones que se abran de verdad a 90° en vez de solo ocultarse, la barra de licencia más ancha/doble grosor ocupando todo el ancho, y reorganizar el encabezado en dos filas): los dejo pendientes a propósito, porque pediste una revisión completa del plugin antes de seguir incorporando cosas — te la mando aparte en un informe.

## Cambios 4.8.25

Ronda grande: se retomó el pedido completo de mejoras (cubo, navegación 3D, tiradera, recorte de repisas, montaje sin choques, Inglete) más varios ajustes de interfaz pedidos sobre la marcha. Se valida y prueba todo junto al final, no módulo por módulo.

- **El cubo vuelve a flotar en la esquina superior derecha del visor 3D** (la versión anterior lo separó a su propia franja, pero no era lo que pedías): ahora es un cubo "flotante" sin fondo/panel detrás (como un PNG), más chico, con las mismas etiquetas cortas (FREN/POST/DER/IZQ/SUP/INF) y la perspectiva correcta (280px) de la ronda pasada.
- **Dimensiones del módulo y "espacio activo" reorganizados**: se quitaron los títulos fijos ("DIMENSIONES DEL MÓDULO", "ESPACIO ACTIVO") y se redujo el tamaño/padding de esos recuadros para que ocupen bastante menos espacio sobre el 3D y se vea menos "ruido" encima del modelo.
- **Navegación 3D libre**: el rango de zoom ya no está limitado a 20mm–20000mm (ahora 5mm–60000mm), y el zoom con la rueda del mouse ya no siempre se acerca/aleja hacia el centro del módulo — ahora el pivote de zoom se va corriendo hacia el punto de la pieza que está debajo del cursor (como en un visor 3D normal), en vez de sentirse "atado" al centro.
- **Giro automático del módulo con control de velocidad**: nuevo botón "⟳ Girar" junto a un slider de velocidad (2°/s a 90°/s) que rota la cámara alrededor del centro total del módulo de forma constante, igual que ya existía para la Explosión. Cualquier clic/arrastre en el visor o la rueda del mouse lo detiene automáticamente.
- **Checkbox "Lleva tiradera" por espacio de cajones**: en la jerarquía, cada espacio de cajones tiene ahora un check "Lleva tiradera" — por defecto marcado en "Cajones con frentes" (frente externo, visible) y desmarcado en "Cajones internos"/"Cajones internos + puerta" (quedan detrás de una puerta), editable en ambos casos. El presupuesto ahora cuenta los jaladores según ese check en vez de contar todos los cajones por igual (antes contaba tiradera hasta en cajones internos que no la necesitan).
- **Repisas internas se recortan automáticamente si el espacio tiene puerta interna**: si un espacio con repisas también tiene "Puerta interna", las repisas ahora empiezan justo donde termina el grosor de esa puerta (antes llegaban al ras del frente y chocarían contra ella). Por ahora esto cubre repisas; las divisiones/separadores compartidos entre varios espacios hermanos no se tocaron porque recortarlos correctamente solo del lado con puerta (sin afectar a los espacios vecinos que no la tienen) es un cambio más grande — avisame si lo necesitás y lo hacemos en una ronda aparte.
- **Laterales y horizontales (base/techo) ya nunca compiten por la misma esquina**: se encontró la causa real del "entrelazado": el montaje de cada lateral (izq/der) y de cada horizontal (superior/inferior) se configura por separado, y nada impedía que ambos quedaran en "Sobrepuesto exterior" a la vez en la misma esquina — ahí sí chocaban (los dos ocupando el mismo espacio). Ahora, cambiar cualquiera de los dos grupos a "Sobrepuesto exterior" (o a "Inglete", ver abajo) adapta automáticamente al otro grupo hacia "Montaje interior" para que nunca se vuelvan a superponer — en vivo en la interfaz y también como red de seguridad al construir, por si un manifiesto viejo trae una combinación conflictiva.
- **Nueva opción de montaje "Inglete 45°" en los laterales**: además de "Montaje interior"/"Sobrepuesto exterior", cada lateral (izq/der) tiene ahora "Inglete 45° (con techo)" e "Inglete 45° (con base)", que aplican automáticamente el mismo corte a 45° que ya existía como ajuste manual por pieza (de la ronda del módulo esquinero en L) — sin tener que configurarlo pieza por pieza. **Limitación honesta**: por ahora es un corte por extremo (arriba O abajo), no los dos a la vez en el mismo lateral — la geometría interna de una sola pieza solo soporta un corte de inglete por llamada. Si necesitás inglete en las dos puntas del mismo lateral al mismo tiempo, decime y lo armamos en una ronda dedicada (implica extender esa geometría interna, y prefiero no tocarla a las apuradas sin poder probarla en vivo).
- **Encabezado renombrado a "Soporte Técnico y Licencias"** (antes "Configuración jerárquica + MODULAR-3D VIEW") con un botón de WhatsApp al lado (abre chat directo al +593 98 460 4086) y la versión al final.
- **Botón "Ampliar" en el visor 3D** (donde antes decía "INTEGRADO"): agranda solo el visualizador 3D a pantalla completa dentro del diálogo (sin deformar el módulo — se reajusta cámara/render a la nueva proporción) conservando toda la navegación libre; se vuelve a presionar para regresar a la normalidad.
- **Checkbox "Abierto" junto al botón Ampliar**: vuelve las puertas invisibles en tiempo real para ver qué hay construido dentro del módulo. Nota honesta: en SketchUp real las puertas se abren de verdad con su bisagra (Dynamic Components); este visor web es una maqueta aparte que nunca tuvo esa información por pieza, así que en vez de arriesgar un giro con el pivote mal puesto (sin poder probarlo en vivo), esta versión las oculta en vez de animarlas — el resultado práctico (ver el interior) es el mismo.
- **Propiedades técnicas reorganizadas**: los valores largos (nombre de pieza, color de canto, etc.) ahora truncan con "…" en vez de desbordar o amontonarse, con un poco más de espacio entre filas; los 4 botones de acción pasan de una grilla 2×2 a una lista de una columna para que "Ocultar/mostrar" y el resto entren en una sola línea.
- **Barra de días restantes de la licencia**: junto a "Cerrar sesión" aparece una barra que arranca en azul (100%, día 1 de tu plan) y se va mezclando hacia verde → amarillo → naranja → rojo a medida que se acerca el vencimiento. Depende de que el servidor de licencias mande cuántos días quedan (o la fecha de vencimiento) en la respuesta de login — si tu servidor todavía no manda ese dato, la barra se queda oculta sola (nada se rompe) hasta que lo agregues; avisame el nombre exacto del campo que devuelve tu API si no es alguno de los que ya probé (`days_left`/`dias_restantes`/`expires_at`/`subscription_ends_at`/`vencimiento`) y lo ajusto.

## Cambios 4.8.24

- **El cubo de navegación ya no flota encima del visor 3D.** Antes era un panel `position:absolute` metido dentro del mismo contenedor del canvas 3D, por eso se superponía visualmente al modelo. Ahora vive en su propia franja separada (con línea divisoria propia), entre el visor y la barra de vistas — nunca se dibuja encima del 3D.
- **Cubo más pequeño y compacto**, como pediste: 78px de marco (antes 96px) y 38px de cubo (antes 46px).
- **Corregido el "desfase" visual del cubo**: el `perspective` se había subido a 900px en una ronda anterior como prueba y no arregló nada (tu captura lo seguía mostrando distorsionado); lo volví al valor 280px, que es el que usa MODULAR-3D-VIEW y da la profundidad isométrica correcta en vez de aplanar el cubo.
- **Revisé a fondo si el frente/atrás del cubo estaban invertidos** (una pista real que encontré comparando contra MODULAR-3D-VIEW, donde esa asignación CSS está al revés de la nuestra). Hice el álgebra completa de las 6 caras contra la fórmula que ya usa el cubo para orientarse según la cámara (`rotateX(pitch) rotateY(-yaw)`) y confirmé que nuestra versión ya es la correcta para el sistema de ejes que usa este visor — el cubo de referencia solo la tiene al revés porque su propia escena usa el eje contrario para "frente". No se tocó ese CSS: tocarlo a ciegas habría roto la orientación.
- **Etiquetas de las caras más cortas** (FREN/POST/DER/IZQ/SUP/INF en vez de FRENTE/ATRÁS/DER./IZQ./ARRIBA/ABAJO) para que entren sin amontonarse en el cubo más chico — esto es lo que probablemente causaba el texto encimado ("FREN E"/"DER") que se veía en tu captura, ya que antes las palabras completas no entraban en el recuadro central de una cara tan pequeña.
- Sigue pendiente del mismo pedido (rondas siguientes, una por una): navegación 3D libre sin límite de zoom al centro del módulo, giro automático con slider de velocidad, checkbox de tiradera en cajones internos, recorte de repisas/divisiones donde pasa una puerta interna, que laterales/base/techo nunca se solapen entre sí, y la nueva opción de montaje "Inglete".

## Cambios 4.8.23

- **Fix real del bug de cantidad de bisagras.** Causa encontrada: `Sketchup::BoundingBox#height` **no** devuelve el alto en el eje Z como parece indicar su nombre — devuelve la medida en el eje Y (`#depth` es la que da el eje Z). El cálculo de bisagras leía `bounds.height` pensando que era el alto real de la puerta, así que para una puerta de 2117mm terminaba usando 15mm (su grosor) en su lugar, dando 2 bisagras en vez de 4. La geometría de la puerta en sí siempre estuvo bien — nunca fue un problema de construcción, solo de qué medida se leía después para las bisagras. Ahora se calcula directo desde las coordenadas Z reales de la pieza (igual que ya se hacía para verificar la posición de las puertas), sin depender de esa nomenclatura confusa de la API de SketchUp.
- Se retiraron las dos instrumentaciones de depuración temporal (bisagras y geometría), ya no hacen falta.

## Cambios 4.8.22-beta.1

- **Diagnóstico de bisagras, segunda vuelta.** Con tus datos anteriores encontré algo puntual: una puerta de 2117×597mm apareció con `bounds.height` (alto medido en vivo) de solo 15mm y `bounds.depth` de 2117mm — es decir, la puerta quedó **acostada** (el alto corrido hacia la profundidad) en vez de parada, y por eso el cálculo de bisagras usa 15mm en lugar de 2117mm. Confirmaste que la columna "Inglete" del despiece está vacía para esa puerta, lo que descarta mi primera sospecha (un inglete horizontal mal aplicado). Para ir a la causa real sin seguir adivinando, se agregó un diagnóstico más profundo, dentro de `crear_pieza` (donde se arma la geometría), que muestra el ancho/profundidad/alto exactos que recibe la pieza y el eje de inglete calculado, justo antes de dibujarla.
  - **Para seguir ayudando**: con Window > Ruby Console abierta, reconstruí el mismo módulo con la puerta de 2117mm (o cualquiera que dé bisagras incorrectas) y copiame las líneas `[Modular_3D DEBUG geometria]` que aparezcan para esa puerta.

## Cambios 4.8.21-beta.1

- **Fix: los frentes de cajón ahora salen todos de la misma altura y alineados con las puertas.** Antes, el primero y el último frente de una columna salían más altos que los del medio (heredaban el hueco mecánico completo hasta la base/techo) y además quedaban 1.5mm más angostos/metidos que una puerta en el mismo lugar (se les restaba una fuga extra encima de la que ya trae el plano de fachada). Ahora todos los frentes de una misma columna reparten el alto disponible en partes iguales, con 3mm entre uno y otro, y el ancho/margen lateral sale exactamente igual al de una puerta vecina (1.5mm contra el casco o división). Aplica a "Uno por cajón", "Único" y "Falso".
- **Despiece con una sección y foto por cada módulo real, más un resumen global.** Si construías 2 o 3 módulos idénticos en medidas, el despiece los mezclaba en una sola sección y se quedaba con la foto del último (compartían la misma "firma" por dimensiones). Ahora cada módulo construido tiene su propia identidad real (independiente de sus medidas) y su propia foto guardada; si hay más de un módulo en la selección, se agrega al final una sección **"Todos los módulos (global)"** con el cutlist combinado de todo (para mandar a cortar de una sola vez) y una foto de la vista actual del visor.
- **Nombre de material más claro en el despiece.** La columna "Material" mostraba el nombre técnico interno de SketchUp (p. ej. `M3D_Blanco_FFFFFF`); ahora usa el nombre que vos escribiste (p. ej. "Blanco"), guardado aparte para este fin.
- **Diagnóstico temporal para el cálculo de bisagras**: seguís viendo cantidades que no coinciden con la altura real de la puerta (2/3/4/5 según 950/1400/2120mm). Revisé la fórmula a fondo y está bien en aislado, así que agregué una línea de depuración (ver Window > Ruby Console) que compara la altura guardada al construir contra la altura medida en vivo — con esos números puedo encontrar la causa real en vez de seguir revisando a ciegas.
- Se retiró la instrumentación de depuración de la puerta desplazada (confirmaste que ya salía bien con tus datos de consola).

## Cambios 4.8.20-beta.1

- **Migración opcional de módulos antiguos al configurador jerárquico** (tarea 7/8 de esta ronda). Al editar un módulo guardado con una versión anterior del plugin (grid de nichos/columnas vía `spaces_json`, o el formato más viejo con solo puerta+cajones sueltos, sin ninguna jerarquía todavía), aparece un aviso en la pestaña "Configuración" con un botón **"Convertir a configurador jerárquico"**.
  - Se optó por la opción segura en vez de retirar directamente el código que construye esos formatos viejos: no hay forma de probar la conversión contra un `.skp` real guardado con una versión vieja en este entorno (sin SketchUp), así que borrar ese código a ciegas tenía riesgo real de romper módulos existentes. En cambio:
    - El código Ruby que construye los formatos antiguos **no se tocó ni se retiró** — un módulo viejo sigue abriendo y reconstruyéndose exactamente igual que siempre si no usás el botón nuevo.
    - La conversión es 100% opcional y reversible: se puede deshacer con "Deshacer" (Ctrl-like, el botón de la pestaña) si el resultado no queda bien, y no se guarda nada hasta que vos decidís actualizar el módulo.
    - Se avisa explícitamente que es "una primera aproximación, no un reemplazo exacto" — cubre grids de nichos/columnas (con cajoneras, puertas simples/dobles, repisas) y el formato más viejo de puerta+cajones sueltos; no reproduce "maletera" (poco común, y ya no tiene forma de activarse desde la interfaz actual).
  - Probado con 5 casos sintéticos (grid 2×2 con contenido mixto, formato más viejo sin grid, fila única de 3 columnas, columna única con 1 espacio, aviso de maletera) verificando que el árbol resultante tiene la forma y los valores esperados.

## Cambios 4.8.19

- **Fix crítico: el plugin no abría en SketchUp 2020** (`NoMethodError: undefined method 'filter_map'`). `Array#filter_map` es Ruby 2.7+, y SketchUp 2020 trae Ruby 2.5 — se reemplazó por `map` + `compact` en `core/profiles.rb`, que es compatible con ambos. Se hizo además un barrido de todo el código buscando otros métodos de Ruby moderno (`filter_map`, parámetros numerados, pattern matching `case/in`, `Hash#except`, métodos endless, `tally`, `clamp` con rango) y no se encontró ningún otro caso.
- **Fix del bug de la puerta con bisagra derecha desplazada, encontrado con datos reales**: gracias a la instrumentación temporal de la versión anterior, un usuario mandó los números reales de una puerta bisagra derecha construida — el alto salía invertido en Z (por ejemplo, esperado 1.5..758.5mm, real -755.5..1.5mm: exactamente el mismo alto, para el lado opuesto). La causa era el `face.reverse!` que se aplicaba a la cara espejada antes de extruirla: esa cara en particular ya queda orientada de forma que `pushpull` extruye para el lado correcto sin revertirla, así que revertirla era justo lo que invertía el alto. Se quitó ese `reverse!`. **Si construís un módulo con puerta bisagra derecha, avisame si ya sale bien** para retirar la instrumentación de depuración (las líneas `[Modular_3D DEBUG puerta]` en la consola) en la próxima versión.

## Cambios 4.8.18-beta.1

- **Nueva biblioteca de texturas incluidas con el plugin** (tarea 8/8 de esta ronda — se saltó la 7/8 por ahora, ver abajo): 7 acabados genéricos (blanco liso, blanco nube, negro mate, gris antracita, roble claro, nogal oscuro, wengué) que viven dentro del propio plugin en `Modular_3D/textures/`, sin depender de Internet ni de que subas un archivo. Son imágenes genéricas/procedurales, no fotografías reales de un proveedor — un punto de partida rápido, no un catálogo de materiales reales.
  - Nuevo selector "Textura incluida" en el material general, en el editor de material por grupo, y en el editor de una pieza individual.
  - En Ruby, se agregó soporte para resolver una referencia `INCLUDED:<id>` (guardada en `material_textures_json`) al archivo real dentro de `Modular_3D/textures/`, usando el mismo mecanismo que ya existía para texturas subidas o por URL.
- **Nota sobre la tarea 7/8** (retirar el código de las generaciones antiguas de construcción): se pausó a pedido tuyo, porque no hay forma de probarla con un .skp real guardado con una versión vieja del plugin en este entorno, y borrar ese código sin poder verificarlo tiene riesgo real de romper algún módulo viejo al abrirlo. Queda pendiente en la lista de tareas para cuando quieras retomarla (por ejemplo, si me pasás un .skp viejo para probar la migración antes de borrar nada).

## Cambios 4.8.17-beta.1

- **Nuevas validaciones para cada espacio del configurador jerárquico** (tarea 6/8 de esta ronda): antes, si un espacio de la jerarquía pedía, por ejemplo, 15 cajones o una puerta doble en una celda muy angosta, el código simplemente lo recortaba en silencio (a 12 cajones, etc.) sin avisar nada — el sistema plano/antiguo sí tenía ese aviso, pero la jerarquía no. Ahora la jerarquía valida lo mismo, con el mismo mensaje: cajones fuera de 1-12, repisas internas fuera de 1-20, puerta doble en una celda de menos de 500mm de ancho, y un aviso si quedan menos de 45mm de alto por cajón.
- **Reglas de validación reorganizadas en `validation.rb`**: cada regla de la jerarquía (sobremedida, cajones, repisas, puertas) ahora es una función propia (`validar_sobremedida_nodo`, `validar_cajones_nodo`, `validar_repisas_nodo`, `validar_puertas_nodo`) en vez de un bloque de código mezclado, para que sea más fácil de mantener y de ubicar cuándo haga falta ajustar un límite.

## Cambios 4.8.16-beta.1

- **`interfaz.html` ya no tiene CSS/JS embebido** (tarea 5/8 de esta ronda): el `<style>` de 188 líneas pasó a `ui/interfaz.css` (cargado con `<link rel="stylesheet">`) y el `<script>` de 660 líneas pasó a `ui/interfaz.js` (cargado con `<script src="interfaz.js">`), igual que ya se hacía con `hierarchical_config.js`, `material_config.js` y `modular3d_view.js`. `interfaz.html` bajó de 1166 a 316 líneas. Cero cambios de comportamiento: se verificó reconstruyendo el archivo original a partir de los 3 archivos nuevos y comparando byte a byte que da idéntico.

## Cambios 4.8.15-beta.1

- **Reorganización interna de `plugin.rb`** (tarea 4/8 de esta ronda): el archivo tenía más de 3700 líneas con todo mezclado. Se dividió en 9 archivos por responsabilidad dentro de `core/`, sin cambiar ningún comportamiento (mismo código, solo reubicado):
  - `geometria.rb` — construcción de piezas, materiales, cantos, ingletes, sobremedida por pieza.
  - `actualizaciones.rb` — comparación de versiones y aviso de actualización disponible.
  - `jerarquia.rb` — el configurador jerárquico (diálogo + construcción del módulo desde `hierarchy_geometry_json`).
  - `componentes_dinamicos.rb` — puertas y cajones interactivos (Dynamic Components).
  - `despiece.rb` — generación, export a Excel/PDF del despiece.
  - `presupuesto.rb` — cotizador y su export a PDF.
  - `biblioteca.rb` — biblioteca local, edición por lotes, importar piezas externas.
  - `esquinero.rb` — módulo esquinero en L.
  - `habitacion.rb` — constructor de habitación (muros).
  - `plugin.rb` quedó solo con el núcleo (licencia/manifiesto) y los `require` de todo lo anterior.
  - Verificado que ningún método se perdió ni se duplicó (mismo listado exacto de 75 métodos antes y después) y que el contenido de código es línea por línea idéntico al original (solo cambió su ubicación de archivo); además se simuló la carga completa fuera de SketchUp para confirmar que no hay errores de referencia entre archivos.

## Cambios 4.8.14-beta.1

- **Diagnóstico temporal para el bug de la puerta izq./der. desplazada** (tarea 3/8 de esta ronda): tras 3+ rondas revisando el código sin encontrar la causa por pura lectura (la fórmula de posición es textualmente idéntica entre bisagra izquierda y derecha), se agregó una línea de depuración que se ve en **Window > Ruby Console** cada vez que se crea una puerta: compara la posición que se le pidió a la pieza (x/y/z esperados) contra los bounds reales de la puerta ya insertada en el modelo. No cambia ningún comportamiento, solo imprime información.
  - **Para ayudar a resolverlo**: abre Window > Ruby Console *antes* de construir un módulo con al menos una puerta con bisagra derecha (y otra con bisagra izquierda para comparar), construye el módulo, y copia/pega aquí las líneas que empiezan con `[Modular_3D DEBUG puerta]`. Con esos números exactos (esperado vs. real) se podrá identificar la causa real en vez de seguir revisando el código a ciegas.
  - Esta instrumentación es temporal y se retirará en cuanto el bug quede confirmado como resuelto.

## Cambios 4.8.13-beta.1

- **Sobremedida por espacio (nodo) en el configurador jerárquico**: cada espacio con lateral izq./der., base o cierre superior (techo completo) activados ahora tiene su propio panel "Sobremedida de este espacio" con 8 campos (frontal/trasera para cada uno de esos 4 paneles), igual en concepto a la sobremedida del casco general — un valor positivo hace que ese panel sobresalga hacia adelante o atrás; negativo lo retranquea. No aplica a "2 travesaños" (son listones, no un panel) ni al respaldo.
  - Mismo cálculo en Ruby (construcción real), en la vista previa 3D y en las reglas de validación (límite proporcional a la profundidad del propio espacio, igual que el casco general).
  - Tarea 2/8 de esta ronda. Sigue pendiente que la puerta de un espacio "se adapte" automáticamente cuando la sobremedida frontal de su base/techo/laterales la sobrepase — se hará junto con la tarea 3/8 (diagnóstico de la puerta desplazada), porque ambas tocan el mismo cálculo de posición Y de la puerta y conviene resolverlas juntas para no arriesgar una regresión.

## Cambios 4.8.12-beta.1

- **"Espacio entre cajones" ahora es 1.5mm por defecto** (antes 30mm), la misma fuga que ya usan las puertas — sigue siendo 100% editable por espacio si tu sistema de corredera necesita más holgura mecánica real. Primera de varias tareas de esta ronda (ver tareas en curso más abajo); las siguientes son sobremedida por nodo en la jerarquía, el bug de la puerta desplazada, y una reorganización del código en archivos por responsabilidad.

## Cambios 4.8.11-beta.1

- **Nueva opción "2 travesaños" para el cierre superior de un espacio**, alternativa al techo completo (dos tablas angostas, adelante y atrás, de 70mm por defecto). Se elige junto al check "Cierre superior" (antes "Techo").
- **Bisagras por altura ajustadas**: 2 hasta 950mm, 3 hasta 1400mm, 4 hasta 2120mm, 5 en puertas más altas (antes 950/1600/2200).
- **Eliminada la opción "Reforzar piso cajón"**: el fondo del cajón ya es 15mm por defecto (usa el mismo espesor general que el resto del módulo); la plancha extra que agregaba esta opción no aportaba nada que no se pudiera lograr subiendo el espesor general.
- **Cubo de navegación menos distorsionado**: se aumentó la perspectiva CSS del cubo (de 280 a 900) para reducir el efecto "ojo de pez" que lo hacía verse descuadrado en ángulos oblicuos.
- **Panel "Interior y frente" del configurador más compacto**: los ajustes de cajones y de puerta de cada espacio ahora están en sub-paneles plegables (colapsados por defecto, un clic para expandir) en vez de mostrar todos los campos siempre — mismo tamaño de letra, menos scroll.
- **Puerta con bisagra derecha (endurecimiento defensivo, aún sin confirmar en vivo):** la cara espejada de esa puerta ahora siempre se invierte sin condición (antes dependía de un chequeo que debía coincidir exactamente con un cálculo matemático aparte). Si la puerta derecha sigue apareciendo desplazada después de esta versión, revisar primero en "Materiales → Editar una pieza individual" si esa puerta específica tiene alguna sobremedida (ancho/alto) cargada por accidente de una edición anterior.

## Cambios 4.8.10-beta.1

- **Corregida la causa real de que el cajón se alejara demasiado al interactuar** (diagnosticado por el usuario): `ANIMATE` interpreta un número suelto según la unidad activa del modelo (típicamente cm), no en mm — pasar "321" literal lo tomaba como 321cm en vez de 321mm. Ahora el valor de salida del cajón se pasa en cm con punto decimal (las comas ya separan los parámetros de `ANIMATE`), inequívoco sin importar la unidad del modelo.

## Cambios 4.8.9-beta.1

- **Corregido el error al descargar Excel del despiece** (`Encoding::CompatibilityError: incompatible character encodings: ASCII-8BIT and UTF-8`, reproducido y verificado con un script aparte): el CSV se escribía concatenando bytes marcados como ASCII-8BIT (el BOM) con texto UTF-8, lo que revienta en cuanto el contenido trae un carácter no-ASCII — la columna "Bisagrado" agrega justamente eso ("Ø35mm"). Se soluciona forzando ambos fragmentos a ASCII-8BIT antes de unirlos (concatenación de bytes crudos, sin chequeo de compatibilidad).
- **Corregida la apertura de las puertas** (mismo problema que ya se había corregido en los cajones, pero se había pasado por alto en las puertas): la fórmula `ANIMATE("RotZ",0,giro/2,giro,0)` tenía un punto intermedio de más — con 4 valores, cada clic de Interactuar solo avanza un paso de la lista en vez de alternar cerrado/abierto. Reducida a 2 valores en las puertas (jerarquía y el generador de puertas antiguo) y en los cajones.
- **La miniatura del módulo en el despiece ahora siempre encuadra el módulo completo**, en vez de la miniatura salir recortada si el usuario había dejado la cámara del visor 3D con zoom sobre un detalle antes de construir: la captura ahora siempre usa el mismo encuadre isométrico que ajusta todo el módulo, independiente de dónde haya quedado la cámara del usuario (que no se toca).
- **Presupuesto: nuevo campo editable para el nombre del proyecto o cliente** (ej. "Presupuesto Familia Pérez"), que se conserva en el PDF exportado.
- Reportado y aún en investigación, sin cambio de código todavía: el conteo de bisagras no sube de 2 a 3 para una puerta de 1177mm de altura real en un despiece concreto — la fórmula fue verificada de nuevo y da 3 para ese valor, así que el número que llega a esa función parece no ser el real; y el panel/puerta desplazados al construir un módulo con varios niveles de jerarquía. Se necesita más información puntual del caso (detallada al usuario) para aislar la causa exacta.

## Cambios 4.8.8-beta.1

- **Corregida la apertura del cajón con Interactuar** (salía un poco y, al volver a hacer clic, se alejaba más en vez de cerrarse): la fórmula `ANIMATE` tenía un punto intermedio de más (cerrado, mitad, abierto, cerrado); con 4 valores cada clic solo avanza un paso de la lista en vez de alternar cerrado/abierto. Ahora son solo 2 valores (cerrado/abierto), alternando correctamente en cada clic.
- **Corregido el PDF de Presupuesto que salía con todos los valores en 0.00** aunque en pantalla calculaba bien: el export capturaba `outerHTML`, que serializa el `value=""` original de cada campo, no lo que el usuario tecleó (eso vive solo en memoria). Ahora, antes de exportar, se copian los valores tecleados a los atributos del HTML para que el PDF los conserve.
- **Mensajes de error visibles si falla una exportación** (Excel/PDF del despiece, PDF del presupuesto) en vez de que el botón simplemente no haga nada — ayuda a diagnosticar cualquier caso puntual que quede.
- Puesto bajo revisión (sin cambio de código todavía, pendiente de más datos): panel largo y desalineado al construir un módulo con varios niveles de jerarquía tras usar "Girar 90°", y conteo de bisagras que no sube de 2 a 3 en una puerta reportada de más de 1000mm en el despiece de un módulo editado — no reproducido en la revisión de código, se necesita más detalle para aislarlo.

## Cambios 4.8.7-beta.1

- **El frente de cajón ahora se alinea al mismo plano/ancho que tendría una puerta en ese lugar**, en vez de quedarse angosto dentro del hueco interno del propio espacio de cajones: usa el mismo cálculo de solape sobre el casco o sobre una división (`front_box`, ya probado en las puertas) para salir del hueco y cubrir los laterales igual que una puerta vecina — arriba, abajo y a los costados —, dejando siempre 1.5mm contra el borde real (casco o una puerta/frente vecino en otro espacio) y por lo tanto 3mm donde dos frentes o un frente y una puerta se encuentran. Antes el frente solo llegaba hasta el borde de su propio hueco interior, mucho más angosto que la puerta de al lado. Reflejado también en la vista previa 3D.
- **Bisagras: el corte de "recta" (2 bisagras) sube de 900mm a 950mm** de altura real de puerta, según lo confirmado.

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
