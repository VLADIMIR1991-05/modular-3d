# frozen_string_literal: true

module LPenafiel_GeneradorMueblesExacto
  def self.crear_puerta_dinamica(entities, modulo_nombre, indice, ancho, espesor, alto, x_bisagra, y_frente, z_inferior, lado_bisagra, alineacion = {})
    definicion = Sketchup.active_model.definitions.add("#{modulo_nombre}_PT_#{indice}")
    x_cierre = lado_bisagra == :derecha ? -ancho : ancho

    face = definicion.entities.add_face([0, 0, 0], [x_cierre, 0, 0], [x_cierre, espesor, 0], [0, espesor, 0])
    face.reverse! if face.normal.z < 0
    face.pushpull(alto)

    instancia = entities.add_instance(definicion, Geom::Transformation.new([x_bisagra, y_frente, z_inferior]))
    self.alinear_bounds(instancia, alineacion) unless alineacion.empty?
    dimensiones = dimensiones_tablero(ancho, espesor, alto)
    nombre_definicion = nombre_pieza("PT", dimensiones, 2, 2)
    giro = lado_bisagra == :derecha ? 90 : -90
    formula_click = "ANIMATE(\"RotZ\",0,#{giro})"

    instancia.name = nombre_definicion
    definicion.name = nombre_definicion
    definicion.description = "2L-2C"
    definicion.set_attribute("LPenafiel", "modulo", modulo_nombre)
    definicion.set_attribute("LPenafiel", "modulo_despiece", @modulo_despiece_actual || modulo_nombre)
    definicion.set_attribute("LPenafiel", "pieza_original", "PUERTA_#{indice}")
    definicion.set_attribute("LPenafiel", "codigo", "PT")
    definicion.set_attribute("LPenafiel", "dimension_1_mm", dimensiones[0])
    definicion.set_attribute("LPenafiel", "dimension_2_mm", dimensiones[1])
    definicion.set_attribute("LPenafiel", "placa_mm", dimension_mm(espesor))
    definicion.set_attribute("LPenafiel", "cantos_largos", 2)
    definicion.set_attribute("LPenafiel", "cantos_cortos", 2)
    definicion.set_attribute("LPenafiel", "bisagra", lado_bisagra.to_s)
    definicion.set_attribute("LPenafiel", "datos_modulo", JSON.generate(@datos_modulo_actual)) if @datos_modulo_actual
    definicion.set_attribute("dynamic_attributes", "_name", nombre_definicion)
    definicion.set_attribute("dynamic_attributes", "onclick", formula_click)
    definicion.set_attribute("dynamic_attributes", "_onclick_formula", formula_click)
    definicion.set_attribute("dynamic_attributes", "rotz", 0)
    definicion.set_attribute("dynamic_attributes", "_rotz_label", "Apertura")
    definicion.set_attribute("dynamic_attributes", "_rotz_units", "DEGREES")

    instancia.set_attribute("LPenafiel", "nombre", nombre_definicion)
    instancia.set_attribute("dynamic_attributes", "_name", nombre_definicion)
    instancia.set_attribute("dynamic_attributes", "onclick", formula_click)
    instancia.set_attribute("dynamic_attributes", "_onclick_formula", formula_click)
    instancia.set_attribute("dynamic_attributes", "rotz", 0)
    instancia.set_attribute("dynamic_attributes", "_rotz_label", "Apertura")
    instancia.set_attribute("dynamic_attributes", "_rotz_units", "DEGREES")
    self.aplicar_material_configurado(instancia, "PUERTA_#{indice}")
    @piezas_modulo_actual << instancia if @piezas_modulo_actual
    instancia
  end

  # Puerta interactiva con la mano de Interactuar (Dynamic Components): usa
  # exactamente el mismo esquema de atributos que crear_puerta_dinamica de
  # arriba (onclick/rotz sin guion bajo, metadatos _label/_units/_formula con
  # guion bajo, formula ANIMATE), que ya existía en el codigo pero nunca
  # estaba conectada a las puertas que arma la jerarquia (siempre pasaban por
  # crear_pieza, sin ningun atributo de Dynamic Components). Se llama DESPUES
  # de crear_pieza. Si la bisagra es derecha, el origen local de la pieza
  # (que crear_pieza siempre deja en el borde izquierdo) se traslada al borde
  # derecho para que el giro ocurra sobre el lado correcto: se mueve la
  # geometria interna -ancho en X y se compensa la transformacion de la
  # instancia sumando +ancho, dejando la posicion final en el mundo
  # identica a la que ya tenia (comprobado: para una traslacion pura, sumar
  # o restar el mismo vector en cualquier orden da el mismo resultado, por
  # eso no importa el orden de composicion de transformaciones aqui).
  def self.agregar_interactividad_puerta(instancia, lado_bisagra)
    return unless instancia && instancia.respond_to?(:definition) && instancia.definition
    definicion = instancia.definition
    # El pivote correcto (borde izquierdo o derecho segun la bisagra) ya lo
    # deja construido crear_pieza con espejado_x=true para :derecha -- aqui
    # solo se agregan los atributos de Dynamic Components, sin tocar
    # geometria ni transformaciones.
    giro = lado_bisagra == :derecha ? 90 : -90
    # Solo dos valores (cerrado/abierto): con un punto intermedio de mas
    # (0, mitad, giro, 0) cada clic solo avanza UN paso de la lista en vez de
    # alternar cerrado<->abierto (mismo problema ya corregido en el cajon).
    formula_click = "ANIMATE(\"RotZ\",0,#{giro})"
    [definicion, instancia].each do |destino|
      destino.set_attribute("dynamic_attributes", "_name", definicion.name)
      destino.set_attribute("dynamic_attributes", "onclick", formula_click)
      destino.set_attribute("dynamic_attributes", "_onclick_formula", formula_click)
      destino.set_attribute("dynamic_attributes", "rotz", 0)
      destino.set_attribute("dynamic_attributes", "_rotz_label", "Apertura")
      destino.set_attribute("dynamic_attributes", "_rotz_units", "DEGREES")
    end
  end

  # Cajon interactivo: desliza el cajon completo (laterales, frente, fondo,
  # trasero y frente exterior si lo tiene) usando el mismo esquema de
  # Dynamic Components que las puertas, pero con la posicion Y en vez de la
  # rotacion Z. instancia debe ser el grupo/componente que contiene TODAS
  # las piezas del cajon ya anidadas (ver el bucle de cajones mas abajo),
  # para que un solo atributo de posicion mueva el cajon y su frente juntos.
  def self.agregar_interactividad_cajon(instancia, fondo_caja)
    return unless instancia && instancia.respond_to?(:definition) && instancia.definition
    definicion = instancia.definition
    salida = -[fondo_caja * 0.7, 500.mm].min.to_mm.round
    # Solo dos valores (cerrado/abierto): con un punto intermedio de mas
    # (0, mitad, salida, 0) cada clic solo avanza UN paso de la lista en vez
    # de alternar cerrado<->abierto -- por eso el cajon salia un poco con el
    # primer clic y mas lejos todavia con el segundo, en vez de abrirse del
    # todo y volver a cerrarse.
    # ANIMATE interpreta un numero suelto segun la unidad activa del modelo
    # (tipicamente cm), no en mm: pasar "321" literal lo toma como 321cm en
    # vez de 321mm, y el cajon sale disparado mucho mas lejos de lo debido.
    # Se pasa en cm con punto decimal (las comas ya separan los parametros
    # de ANIMATE) para que sea inequivoco sin importar la unidad del modelo.
    salida_cm = (salida / 10.0).round(1)
    formula_click = "ANIMATE(\"Y\",0,#{salida_cm})"
    [definicion, instancia].each do |destino|
      destino.set_attribute("dynamic_attributes", "_name", definicion.name)
      destino.set_attribute("dynamic_attributes", "onclick", formula_click)
      destino.set_attribute("dynamic_attributes", "_onclick_formula", formula_click)
      destino.set_attribute("dynamic_attributes", "y", 0)
      destino.set_attribute("dynamic_attributes", "_y_label", "Apertura")
      destino.set_attribute("dynamic_attributes", "_y_units", "LEN")
    end
  end

  # montaje_puerta: SOLAPADA (por defecto, hoy la única que existía) es la
  # puerta que cubre el frente del casco desde afuera -ancho > hueco, huelgo
  # exterior = 1 fuga y huelgo entre hojas = 2 fugas-. EMBUTIDA es la puerta
  # que queda dentro del hueco -ancho < hueco, huelgo uniforme = 1 fuga en
  # todos lados, sin sobresalir del plano frontal-. Es independiente del
  # montaje interior/exterior del casco (que es sobre laterales/base/techo).
  def self.crear_puertas_en_caja(entities, modulo_nombre, caja_total, grosor_puerta, lado_unico = :izquierda, z_min_puerta = nil, z_max_puerta = nil, cantidad_forzada = nil, fuga_personalizada = nil, montaje_puerta = 'SOLAPADA')
    fuga = fuga_personalizada || 1.5.mm
    ancho_total = caja_total.width
    z_min = z_min_puerta || caja_total.min.z
    z_max = z_max_puerta || caja_total.max.z
    alto_total = z_max - z_min
    cantidad_puertas = cantidad_forzada || (ancho_total.to_mm > 619 ? 2 : 1)
    espesor_puerta = grosor_puerta
    embutida = montaje_puerta.to_s.upcase == 'EMBUTIDA'
    ancho_puerta = embutida ? (ancho_total - (fuga * (cantidad_puertas + 1))) / cantidad_puertas : (ancho_total / cantidad_puertas) - (fuga * 2)
    alto_puerta = alto_total - (fuga * 2)

    return 0 if ancho_puerta <= 0 || alto_puerta <= 0

    x_inicio = caja_total.min.x
    x_fin = caja_total.max.x
    y_frente = embutida ? caja_total.min.y : caja_total.min.y - espesor_puerta
    z_inferior = z_min + fuga

    if cantidad_puertas == 1
      x_bisagra = lado_unico == :derecha ? x_fin - fuga : x_inicio + fuga
      alineacion = lado_unico == :derecha ? { :max_x => x_fin - fuga, :min_y => y_frente, :min_z => z_inferior } : { :min_x => x_inicio + fuga, :min_y => y_frente, :min_z => z_inferior }
      self.crear_puerta_dinamica(entities, modulo_nombre, 1, ancho_puerta, espesor_puerta, alto_puerta, x_bisagra, y_frente, z_inferior, lado_unico, alineacion)
    else
      self.crear_puerta_dinamica(entities, modulo_nombre, 1, ancho_puerta, espesor_puerta, alto_puerta, x_inicio + fuga, y_frente, z_inferior, :izquierda, { :min_x => x_inicio + fuga, :min_y => y_frente, :min_z => z_inferior })
      self.crear_puerta_dinamica(entities, modulo_nombre, 2, ancho_puerta, espesor_puerta, alto_puerta, x_fin - fuga, y_frente, z_inferior, :derecha, { :max_x => x_fin - fuga, :min_y => y_frente, :min_z => z_inferior })
    end

    cantidad_puertas
  end

end
