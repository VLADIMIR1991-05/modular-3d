# Modular_3D 4.7.0-beta.1 · Inglete, esquinero en L, presupuesto y sincronización del visor

**Autor:** Lenin Vladimir Peñafiel Buestán  
**Versión:** 4.7.0-beta.1  

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
