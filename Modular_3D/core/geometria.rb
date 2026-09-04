# frozen_string_literal: true

module LPenafiel_GeneradorMueblesExacto
  def self.resolver_estaciones(expresion, total_mm, separador_mm = 0.0)
    Modular3D::Validation.resolver_estaciones(expresion, total_mm, separador_mm)
  end

  CODIGOS_PIEZAS = {
    "LAT_IZQ" => "LAT",
    "LAT_DER" => "LAT",
    "BASE" => "BAS",
    "TECHO" => "TEC",
    "AJUSTE" => "AJ",
    "RESPALDO" => "RES",
    "DIV_VERT" => "DIV",
    "REPISA" => "REP",
    "CJ_LAT_IZQ" => "COS",
    "CJ_LAT_DER" => "COS",
    "CJ_FRENTE_EXTERIOR" => "FC",
    "CJ_FRENTE_EXT" => "FC",
    "CJ_FRENTE" => "FCC",
    "CJ_POSTERIOR" => "POS",
    "CJ_POST" => "POS",
    "CJ_FONDO" => "FON",
    "PUERTA" => "PT",
    # Piezas generadas desde la jerarquía (prefijo H_/G_ ya retirado en
    # codigo_pieza antes de llegar aquí): mismos códigos que sus
    # equivalentes del sistema legado, para que despiece/presupuesto las
    # cuenten y agrupen igual sin importar de qué sistema vinieron.
    "CIERRE_IZQ" => "LAT",
    "CIERRE_DER" => "LAT",
    "RESP" => "RES",
    "REP_LOCAL" => "REP",
    "REP_Z" => "REP",
    "DIV_X" => "DIV",
    "DIV_Y" => "DIV",
    "TRAV_DEL" => "TRAVD",
    "TRAV_TRAS" => "TRAVT"
  }

  ETIQUETAS_CODIGO_PIEZA = {
    "LAT" => "Lateral", "BAS" => "Base", "TEC" => "Techo", "AJ" => "Ajuste posterior",
    "RES" => "Respaldo", "DIV" => "División", "REP" => "Repisa", "PT" => "Puerta",
    "COS" => "Cajón · costado", "FC" => "Cajón · frente exterior", "FCC" => "Cajón · frente interno",
    "POS" => "Cajón · trasero", "FON" => "Cajón · fondo",
    "TRAVD" => "Travesaño delantero", "TRAVT" => "Travesaño trasero"
  }.freeze

  def self.codigo_pieza(nombre)
    nombre_base = nombre.to_s.upcase.sub(/\A[HG]_/, "")
    nombre_base = nombre_base.sub(/\ACJ_.*?_(LAT_IZQ|LAT_DER|FRENTE_EXTERIOR|FRENTE_EXT|FRENTE|POSTERIOR|POST|FONDO)\z/) { "CJ_#{Regexp.last_match(1)}" }
    codigo = CODIGOS_PIEZAS.find { |clave, _valor| nombre_base.start_with?(clave) }
    codigo ? codigo[1] : nombre_base
  end

  # Etiqueta legible en español para la columna "Nombre" del despiece; el
  # codigo interno (LAT, BAS, PT...) sigue siendo el que se usa para agrupar
  # piezas iguales y para nombrar la definicion de SketchUp.
  def self.etiqueta_despiece_pieza(codigo)
    ETIQUETAS_CODIGO_PIEZA[codigo.to_s] || codigo.to_s.split('_').map(&:capitalize).join(' ')
  end

  # Regla estándar de herrajes por altura de puerta (ajustable si el
  # proveedor local usa otros cortes). Solo aplica a puertas reales (codigo
  # "PT"): un frente de cajón exterior, aunque salga a la altura de la
  # puerta y comparta su solape, no es una puerta y no lleva bisagra.
  def self.bisagras_por_altura(alto_mm)
    alto = alto_mm.to_f
    return 2 if alto <= 950.0
    return 3 if alto <= 1400.0
    return 4 if alto <= 2120.0
    5
  end

  # Texto para la columna "Bisagrado" del despiece: solo las puertas (codigo
  # "PT") llevan bisagra, con una perforación de Ø35mm por bisagra.
  def self.texto_bisagrado_pieza(codigo, alto_mm, tipo_bisagra)
    return '' unless codigo.to_s == 'PT'
    cantidad = bisagras_por_altura(alto_mm)
    etiqueta = tipo_bisagra.to_s.empty? ? 'Recta' : tipo_bisagra.to_s
    "#{cantidad} bisagras #{etiqueta} (#{cantidad} perf. Ø35mm)"
  end

  # Tipo de bisagra según el solape real de la puerta sobre el panel de su
  # lado de bisagra, siguiendo la convención estándar de herrajes europeos
  # de mueble melamínico:
  # - Recta (overlay total): la puerta solapa casi todo el grosor de un
  #   lateral propio del casco -> solape de referencia = espesor - 1.5mm.
  # - Semicodada (half overlay): dos puertas comparten una división central,
  #   cada una tapa la mitad del grosor de esa división -> referencia =
  #   espesor / 2.
  # - Codada (inset): puerta embutida o interna (dentro de un hueco), sin
  #   solape hacia afuera.
  # Se clasifica por la referencia numérica más cercana al solape real, en
  # vez de cortes fijos, para que el "más/menos 3mm" quede como tolerancia
  # natural en vez de dejar huecos sin clasificar entre los dos casos.
  def self.tipo_bisagra_por_solape(solape_mm, espesor_mm, embutida)
    return 'Codada' if embutida
    return 'Recta (revisar: sin apoyo firme)' if solape_mm < 3.0
    ref_recta = espesor_mm - 1.5
    ref_semicodada = espesor_mm / 2.0
    (solape_mm - ref_recta).abs <= (solape_mm - ref_semicodada).abs ? 'Recta' : 'Semicodada'
  end

  # ID estable para nombrar piezas generadas desde la jerarquía: usa el id del
  # nodo/espacio (persistente aunque se reordenen o inserten hermanos) en vez
  # de la posición dentro del arreglo, para que material_overrides_json y
  # dimension_overrides_json no se desincronicen al reestructurar el árbol.
  def self.id_pieza_jerarquia(valor, respaldo = nil)
    limpio = valor.to_s.strip.upcase.gsub(/[^A-Z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
    return limpio unless limpio.empty?
    respaldo.to_s.empty? ? 'N' : respaldo.to_s
  end

  def self.dimension_mm(valor)
    valor.to_mm.round
  end

  def self.dimensiones_tablero(ancho, prof, alto)
    [ancho, prof, alto].sort_by { |valor| dimension_mm(valor) }.last(2).reverse.map { |valor| dimension_mm(valor) }
  end

  def self.placa_mm(ancho, prof, alto)
    [ancho, prof, alto].map { |valor| dimension_mm(valor) }.min
  end

  def self.nombre_pieza(codigo, dimensiones, cantos_l, cantos_c)
    "#{codigo}-#{dimensiones[0]}X#{dimensiones[1]}-#{cantos_l}L-#{cantos_c}C"
  end

  def self.tipo_original_pieza(entity)
    return "" unless entity.respond_to?(:definition) && entity.definition
    original = entity.definition.get_attribute("LPenafiel", "pieza_original")
    (original || entity.definition.name).to_s.upcase
  end

  def self.bounds_de_piezas(piezas)
    caja = Geom::BoundingBox.new
    piezas.to_a.each do |pieza|
      next unless pieza && pieza.respond_to?(:valid?) && pieza.valid? && pieza.respond_to?(:bounds)
      caja.add(pieza.bounds)
    end
    caja
  end

  def self.alinear_bounds(instancia, objetivos = {})
    return instancia unless instancia && instancia.respond_to?(:valid?) && instancia.valid? && instancia.respond_to?(:bounds)

    caja = instancia.bounds
    dx = 0
    dy = 0
    dz = 0

    dx = objetivos[:min_x] - caja.min.x if objetivos.key?(:min_x)
    dx = objetivos[:max_x] - caja.max.x if objetivos.key?(:max_x)
    dy = objetivos[:min_y] - caja.min.y if objetivos.key?(:min_y)
    dy = objetivos[:max_y] - caja.max.y if objetivos.key?(:max_y)
    dz = objetivos[:min_z] - caja.min.z if objetivos.key?(:min_z)
    dz = objetivos[:max_z] - caja.max.z if objetivos.key?(:max_z)

    instancia.transform!(Geom::Transformation.translation([dx, dy, dz])) unless dx == 0 && dy == 0 && dz == 0
    instancia
  end

  def self.offset_siguiente_modulo
    caja_ultimo = bounds_de_piezas(@ultimo_modulo_piezas)
    return Geom::Vector3d.new(0, 0, 0) if caja_ultimo.empty?
    separacion = 100.mm
    Geom::Vector3d.new(caja_ultimo.max.x + separacion, caja_ultimo.min.y, caja_ultimo.min.z)
  end

  def self.nombre_modulo_unico(nombre_base)
    base = nombre_base.to_s.strip.upcase.gsub(" ", "_")
    base = "MODULO" if base.empty?
    usados = {}

    Sketchup.active_model.definitions.each do |definicion|
      modulo = definicion.get_attribute("LPenafiel", "modulo")
      usados[modulo.to_s.upcase] = true if modulo && !modulo.to_s.empty?
    end

    return base unless usados[base]

    contador = 2
    loop do
      candidato = "#{base}_#{contador}"
      return candidato unless usados[candidato]
      contador += 1
    end
  end

  def self.nombre_modulo_despiece(nombre, ancho, alto, prof, num_cajones, crear_puerta)
    partes = [
      nombre.to_s.strip.upcase.gsub(" ", "_"),
      dimension_mm(ancho).to_s,
      "H#{dimension_mm(alto)}",
      "P#{dimension_mm(prof)}"
    ]
    partes << "G#{num_cajones.to_i}" if num_cajones.to_i > 0
    partes << "S/P" if crear_puerta != "SI"
    partes.join("_")
  end

  # --- CREACIÓN DE PIEZAS ---
  def self.grupo_material_pieza(nombre)
    clave = nombre.to_s.upcase
    return 'frentes' if clave.include?('PUERTA') || clave.include?('FRENTE_EXT') || clave.include?('FRENTE_EXTERIOR')
    return 'respaldo' if clave.include?('RESP')
    return 'ajuste' if clave.include?('AJUSTE')
    return 'herrajes' if clave.include?('GOLA') || clave.include?('JALADOR') || clave.include?('TIRADOR')
    return 'cajones' if clave.start_with?('CJ_') || clave.include?('_CJ_')
    return 'interior' if clave.include?('DIV') || clave.include?('REP') || clave.start_with?('H_CIERRE') || clave.start_with?('H_BASE') || clave.start_with?('H_TECHO')
    'casco'
  end

  def self.configuracion_material_pieza(nombre)
    datos = @datos_modulo_actual || {}
    grupo = grupo_material_pieza(nombre)
    overrides = begin
      raw = datos['material_overrides_json']
      raw.is_a?(Hash) ? raw : JSON.parse(raw.to_s)
    rescue JSON::ParserError
      {}
    end
    individual = overrides[nombre.to_s] || overrides[nombre.to_s.upcase] || {}
    grupo = individual['group'].to_s unless individual['group'].to_s.empty?
    material_unico = datos['material_unico'].to_s == 'SI'
    grupo_personalizado = datos["material_#{grupo}_custom"].to_s == 'SI'
    color = individual['color'].to_s
    if color.empty?
      color = material_unico && !grupo_personalizado ? datos['material_global_color'].to_s : datos["material_#{grupo}_color"].to_s
    end
    color = '#d5a66e' unless color.match?(/\A#[0-9a-f]{6}\z/i)
    material_nombre = individual['name'].to_s
    if material_nombre.empty?
      material_nombre = material_unico && !grupo_personalizado ? datos['material_global_nombre'].to_s : datos["material_#{grupo}_nombre"].to_s
    end
    material_nombre = grupo.capitalize if material_nombre.empty?
    textures = begin
      raw = datos['material_textures_json']
      raw.is_a?(Hash) ? raw : JSON.parse(raw.to_s)
    rescue JSON::ParserError
      {}
    end
    textura = individual['texture'].to_s
    if textura.empty?
      textura = material_unico && !grupo_personalizado ? textures['global'].to_s : textures[grupo].to_s
    end
    metas = begin
      raw = datos['material_texture_meta_json']
      raw.is_a?(Hash) ? raw : JSON.parse(raw.to_s)
    rescue JSON::ParserError
      {}
    end
    meta_base = material_unico && !grupo_personalizado ? (metas['global'] || {}) : (metas[grupo] || {})
    meta = meta_base.merge('rotation' => individual['rotation']) unless individual['rotation'].to_s.empty? || individual['rotation'].to_s == 'INHERIT'
    meta ||= meta_base
    [grupo, color, material_nombre, textura, meta]
  end

  # Biblioteca de texturas incluidas con el plugin (Modular_3D/textures/):
  # imagenes genericas/procedurales, no fotografias reales, para tener
  # variedad basica sin depender de internet ni de que el usuario suba algo.
  # Referenciadas en material_textures_json como "INCLUDED:<id>".
  def self.manifiesto_texturas_incluidas
    return @manifiesto_texturas_incluidas if defined?(@manifiesto_texturas_incluidas)
    ruta = File.expand_path('../textures/manifest.json', __dir__)
    @manifiesto_texturas_incluidas = begin
      datos = JSON.parse(File.read(ruta))
      (datos['textures'] || []).each_with_object({}) { |item, memo| memo[item['id'].to_s] = item if item.is_a?(Hash) && item['id'] }
    rescue StandardError
      {}
    end
  end

  def self.archivo_textura(textura, material_nombre)
    return nil if textura.to_s.empty?
    if textura.start_with?('INCLUDED:')
      item = manifiesto_texturas_incluidas[textura.sub('INCLUDED:', '')]
      return nil unless item
      ruta = File.expand_path("../textures/#{item['file']}", __dir__)
      return File.exist?(ruta) ? ruta : nil
    end
    if textura.start_with?('data:image/') && textura.include?(';base64,')
      cabecera, contenido = textura.split(',', 2)
      extension = cabecera.include?('png') ? 'png' : 'jpg'
      ruta = File.join(Dir.tmpdir, "m3d_#{material_nombre.hash.abs}_#{contenido.hash.abs}.#{extension}")
      File.binwrite(ruta, Base64.decode64(contenido)) unless File.exist?(ruta)
      return ruta
    end
    return nil unless textura.start_with?('https://')
    uri = URI.parse(textura)
    response = Net::HTTP.start(uri.host, uri.port, :use_ssl => true, :open_timeout => 5, :read_timeout => 10) { |http| http.get(uri.request_uri) }
    return nil unless response.is_a?(Net::HTTPSuccess)
    return nil if response.body.to_s.bytesize > 8 * 1024 * 1024
    tipo = response['content-type'].to_s.downcase
    extension = tipo.include?('png') ? 'png' : 'jpg'
    ruta = File.join(Dir.tmpdir, "m3d_url_#{textura.hash.abs}.#{extension}")
    File.binwrite(ruta, response.body) unless File.exist?(ruta)
    ruta
  rescue StandardError
    nil
  end

  def self.aplicar_material_configurado(instancia, nombre)
    grupo, color, material_nombre, textura, meta_textura = configuracion_material_pieza(nombre)
    model = Sketchup.active_model
    clave = "M3D_#{material_nombre.gsub(/[^0-9A-Za-zÁÉÍÓÚÜÑáéíóúüñ _-]/, '').strip}_#{color.delete('#').upcase}"
    material = model.materials[clave] || model.materials.add(clave)
    rgb = color.delete('#').scan(/../).map { |par| par.to_i(16) }
    material.color = Sketchup::Color.new(rgb[0], rgb[1], rgb[2])
    ruta_textura = archivo_textura(textura, material_nombre)
    if ruta_textura
      material.texture = ruta_textura
      escala = [[(meta_textura['scale'] || 600).to_f, 10.0].max, 10_000.0].min
      material.texture.size = escala.mm if material.texture && material.texture.respond_to?(:size=)
    end
    instancia.material = material if instancia.respond_to?(:material=)
    if instancia.respond_to?(:definition)
      instancia.definition.entities.grep(Sketchup::Face).each do |cara|
        cara.material = material
        cara.back_material = material
      end
      instancia.definition.set_attribute('LPenafiel', 'grupo_material', grupo)
      instancia.definition.set_attribute('LPenafiel', 'material_configurado', material_nombre)
      instancia.definition.set_attribute('LPenafiel', 'color_configurado', color)
      canto_tipo, canto_color = configuracion_canto_pieza(nombre, grupo, color)
      instancia.definition.set_attribute('LPenafiel', 'tipo_canto', canto_tipo)
      instancia.definition.set_attribute('LPenafiel', 'color_canto', canto_color)
      instancia.definition.set_attribute('LPenafiel', 'color_canto_nombre', canto_color == color ? material_nombre : canto_color)
    end
    instancia
  end

  def self.configuracion_canto_pieza(nombre, grupo = nil, color_pieza = nil)
    datos = @datos_modulo_actual || {}
    grupo ||= grupo_material_pieza(nombre)
    color_pieza ||= configuracion_material_pieza(nombre)[1]
    overrides = begin
      raw = datos['material_overrides_json']
      raw.is_a?(Hash) ? raw : JSON.parse(raw.to_s)
    rescue JSON::ParserError
      {}
    end
    individual = overrides[nombre.to_s] || overrides[nombre.to_s.upcase] || {}
    tipo = individual['edge'].to_s
    if tipo.empty? || tipo == 'INHERIT'
      modo = datos['edge_mode'].to_s
      modo = 'MIXED' if modo.empty?
      tipo = modo == 'ALL_HARD' ? 'HARD' : (modo == 'ALL_PVC' ? 'PVC' : (grupo == 'frentes' ? 'HARD' : 'PVC'))
    end
    color = individual['edgeColor'].to_s
    # La herencia es el valor por defecto, pero una excepción individual siempre manda.
    color = color_pieza if color.empty? || color == 'INHERIT'
    color = color_pieza unless color.to_s.match?(/\A#[0-9a-f]{6}\z/i)
    [tipo, color]
  end

  # Inglete a 45°: corta una de las 4 esquinas verticales del footprint de la
  # pieza (constante en toda su altura/extrusión), pensado para el caso más
  # común de una unión visible entre dos piezas que se encuentran en una
  # arista vertical (por ejemplo, las dos alas de un módulo esquinero en L,
  # o un poste/columna decorativo). Usa el mismo patrón de excepciones por
  # nombre que dimension_overrides_json/material_overrides_json.
  ESQUINAS_INGLETE = %i[front_left front_right back_right back_left].freeze

  # Inglete horizontal: corta el canto superior o inferior de un lateral donde
  # se encuentra con el techo o la base (constante en toda la profundidad),
  # en vez del vertical de arriba (constante en toda la altura). "outer" es el
  # canto visible hacia afuera del mueble, "inner" el que da hacia el interior.
  ESQUINAS_INGLETE_HORIZONTAL = %i[bottom_inner bottom_outer top_outer top_inner].freeze

  def self.inglete_pieza(nombre)
    datos = @datos_modulo_actual || {}
    overrides = begin
      raw = datos['miter_overrides_json']
      raw.is_a?(Hash) ? raw : JSON.parse(raw.to_s)
    rescue JSON::ParserError
      {}
    end
    individual = overrides[nombre.to_s] || overrides[nombre.to_s.upcase] || {}
    esquina = individual['corner'].to_s.to_sym
    medida = individual['size'].to_f
    return [nil, nil, :vertical] unless medida.positive?
    return [esquina, medida.mm, :vertical] if ESQUINAS_INGLETE.include?(esquina)
    return [esquina, medida.mm, :horizontal] if ESQUINAS_INGLETE_HORIZONTAL.include?(esquina)
    [nil, nil, :vertical]
  end

  # Devuelve los puntos del footprint (ancho x prof, en el plano Z=0) listos
  # para add_face + pushpull. Si hay esquina+medida, sustituye esa esquina por
  # dos puntos sobre las aristas adyacentes, dejando un corte a 45° constante
  # en toda la altura de la pieza. El orden y sentido de recorrido se
  # preserva exactamente (front_left -> front_right -> back_right ->
  # back_left) para no alterar la normal de la cara ni el pushpull existente.
  def self.puntos_footprint_biselado(ancho, prof, esquina, medida)
    base = {
      :front_left => Geom::Point3d.new(0, 0, 0),
      :front_right => Geom::Point3d.new(ancho, 0, 0),
      :back_right => Geom::Point3d.new(ancho, prof, 0),
      :back_left => Geom::Point3d.new(0, prof, 0)
    }
    orden = %i[front_left front_right back_right back_left]
    return orden.map { |clave| base[clave] } unless esquina && medida && medida.to_f.positive?

    s = [medida.to_f, ancho * 0.48, prof * 0.48].min
    return orden.map { |clave| base[clave] } unless s.positive?

    puntos = []
    orden.each do |clave|
      if clave == esquina
        case clave
        when :front_left
          puntos << Geom::Point3d.new(0, s, 0) << Geom::Point3d.new(s, 0, 0)
        when :front_right
          puntos << Geom::Point3d.new(ancho - s, 0, 0) << Geom::Point3d.new(ancho, s, 0)
        when :back_right
          puntos << Geom::Point3d.new(ancho, prof - s, 0) << Geom::Point3d.new(ancho - s, prof, 0)
        when :back_left
          puntos << Geom::Point3d.new(s, prof, 0) << Geom::Point3d.new(0, prof - s, 0)
        end
      else
        puntos << base[clave]
      end
    end
    puntos
  end

  # Perfil (ancho x alto, en el plano Y=0) para el inglete horizontal: la
  # unión de un lateral con el techo o la base. Se extruye a lo largo de la
  # profundidad (pushpull(-prof) desde crear_pieza), de modo que el corte a
  # 45° queda constante en todo el fondo de la pieza, igual que el vertical
  # queda constante en toda su altura. Z=0 es el tope local de la pieza y
  # Z=-alto su base (coherente con la transformación de crear_pieza, que
  # coloca el punto z recibido como el borde superior de la pieza). Orden y
  # sentido de recorrido (bottom_inner -> bottom_outer -> top_outer ->
  # top_inner) verificado por separado para que la normal resultante sea
  # siempre -Y y el pushpull(-prof) extruya hacia +Y (0..prof), igual que el
  # resto de piezas.
  def self.perfil_biselado_horizontal(ancho, alto, esquina, medida)
    zb = 0 - alto
    zt = 0
    base = {
      :bottom_inner => Geom::Point3d.new(0, 0, zb),
      :bottom_outer => Geom::Point3d.new(ancho, 0, zb),
      :top_outer => Geom::Point3d.new(ancho, 0, zt),
      :top_inner => Geom::Point3d.new(0, 0, zt)
    }
    orden = %i[bottom_inner bottom_outer top_outer top_inner]
    return orden.map { |clave| base[clave] } unless esquina && medida && medida.to_f.positive?

    s = [medida.to_f, ancho * 0.48, alto * 0.48].min
    return orden.map { |clave| base[clave] } unless s.positive?

    puntos = []
    orden.each do |clave|
      if clave == esquina
        case clave
        when :bottom_inner
          puntos << Geom::Point3d.new(0, 0, zb + s) << Geom::Point3d.new(s, 0, zb)
        when :bottom_outer
          puntos << Geom::Point3d.new(ancho - s, 0, zb) << Geom::Point3d.new(ancho, 0, zb + s)
        when :top_outer
          puntos << Geom::Point3d.new(ancho, 0, zt - s) << Geom::Point3d.new(ancho - s, 0, zt)
        when :top_inner
          puntos << Geom::Point3d.new(s, 0, zt) << Geom::Point3d.new(0, 0, zt - s)
        end
      else
        puntos << base[clave]
      end
    end
    puntos
  end

  # Sobremedida por pieza: un delta en mm (positivo o negativo) que ajusta el
  # tamaño calculado automáticamente para una pieza puntual sin tocar el resto
  # del cálculo paramétrico. Usa el mismo patrón de excepciones por nombre que
  # material_overrides_json.
  def self.sobremedida_pieza(nombre)
    datos = @datos_modulo_actual || {}
    overrides = begin
      raw = datos['dimension_overrides_json']
      raw.is_a?(Hash) ? raw : JSON.parse(raw.to_s)
    rescue JSON::ParserError
      {}
    end
    individual = overrides[nombre.to_s] || overrides[nombre.to_s.upcase] || {}
    %w[delta_ancho delta_prof delta_alto].map { |clave| individual[clave].to_f.mm }
  end

  # espejado_x: para puertas con bisagra derecha, el origen local (0,0,0)
  # debe coincidir con el borde DERECHO de la pieza (no el izquierdo, que es
  # donde lo deja el footprint normal) para que el pivote de giro de Dynamic
  # Components caiga sobre la bisagra real. En vez de construir la pieza
  # normal y mover la geometria despues (metodo fragil, causaba una puerta
  # rota/con algo "invisible" mas grande al abrir), se construye el
  # footprint espejado desde el inicio -x en vez de +x.
  #
  # BUG REAL (encontrado con datos de consola de un usuario, no solo
  # teoria): con face.reverse! + pushpull(-alto), la puerta con bisagra
  # derecha salia con los bounds en Z invertidos -- por ejemplo z esperado
  # 1.5..758.5mm y bounds reales -755.5..1.5mm, exactamente el mismo alto
  # pero para el lado opuesto. La suposicion anterior (que la cara espejada
  # SIEMPRE sale con normal -Z y hay que corregirla con reverse! antes de
  # extruir igual que el resto de las piezas) no se cumple en la practica:
  # SketchUp arma esta cara concreta con la orientacion que YA hace que
  # pushpull(-alto) extruya para el lado correcto sin tocarla. Por eso el
  # fix es simplemente no revertir la cara -- no hace falta, y revertirla
  # es lo que invertia el alto. Cuando espejado_x es true, x debe ser la
  # posicion mundial del borde DERECHO de la pieza (no el izquierdo).
  def self.crear_pieza(entities, modulo_nombre, nombre, ancho, prof, alto, x, y, z, cantos_l, cantos_c, espejado_x = false)
    delta_ancho, delta_prof, delta_alto = sobremedida_pieza(nombre)
    ancho = [ancho + delta_ancho, 1.mm].max
    prof = [prof + delta_prof, 1.mm].max
    alto = [alto + delta_alto, 1.mm].max
    esquina_inglete, medida_inglete, eje_inglete = inglete_pieza(nombre)
    # DEBUG TEMPORAL (a retirar en cuanto se confirme el fix del bug de
    # cantidad de bisagras incorrecta): muestra exactamente que ancho/prof/
    # alto y que eje de inglete recibe crear_pieza para una puerta, justo
    # antes de armar la geometria. Se ve en Window > Ruby Console.
    if nombre.to_s.upcase.include?('PUERTA')
      puts "[Modular_3D DEBUG geometria] nombre=#{nombre} espejado_x=#{espejado_x} ancho=#{ancho.to_mm.round(1)}mm prof=#{prof.to_mm.round(1)}mm alto=#{alto.to_mm.round(1)}mm eje_inglete=#{eje_inglete.inspect} esquina_inglete=#{esquina_inglete.inspect} medida_inglete=#{medida_inglete.inspect} delta_ancho=#{delta_ancho.to_mm.round(1)} delta_prof=#{delta_prof.to_mm.round(1)} delta_alto=#{delta_alto.to_mm.round(1)}"
    end
    grupo = entities.add_group
    if espejado_x
      puntos = [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(-ancho, 0, 0), Geom::Point3d.new(-ancho, prof, 0), Geom::Point3d.new(0, prof, 0)]
      face = grupo.entities.add_face(puntos)
      face.pushpull(-alto)
    elsif eje_inglete == :horizontal
      puntos = perfil_biselado_horizontal(ancho, alto, esquina_inglete, medida_inglete)
      face = grupo.entities.add_face(puntos)
      face.pushpull(-prof)
    else
      puntos = puntos_footprint_biselado(ancho, prof, esquina_inglete, medida_inglete)
      face = grupo.entities.add_face(puntos)
      face.pushpull(-alto)
    end

    instancia = grupo.to_component rescue grupo
    codigo = codigo_pieza(nombre)
    dimensiones = dimensiones_tablero(ancho, prof, alto)
    placa = placa_mm(ancho, prof, alto)
    cantos = "#{cantos_l}L-#{cantos_c}C"
    nombre_definicion = nombre_pieza(codigo, dimensiones, cantos_l, cantos_c)

    if instancia.respond_to?(:definition)
      instancia.name = nombre_definicion if instancia.respond_to?(:name=)
      instancia.definition.name = nombre_definicion
      instancia.definition.description = cantos
      instancia.definition.set_attribute("LPenafiel", "modulo", modulo_nombre)
      instancia.definition.set_attribute("LPenafiel", "modulo_despiece", @modulo_despiece_actual || modulo_nombre)
      # UUID real de ESTE modulo construido (a diferencia de modulo_despiece,
      # que es una firma por dimensiones pensada para agrupar cantidades de
      # modulos identicos en el despiece global): permite separar el despiece
      # en secciones por modulo real aunque dos modulos compartan medidas
      # exactas, y guardar/recuperar la foto 3D de cada uno sin que una
      # pise la otra.
      instancia.definition.set_attribute("LPenafiel", "modulo_uuid", @modulo_uuid_actual || @modulo_despiece_actual || modulo_nombre)
      instancia.definition.set_attribute("LPenafiel", "pieza_original", nombre)
      instancia.definition.set_attribute("LPenafiel", "codigo", codigo)
      instancia.definition.set_attribute("LPenafiel", "dimension_1_mm", dimensiones[0])
      instancia.definition.set_attribute("LPenafiel", "dimension_2_mm", dimensiones[1])
      instancia.definition.set_attribute("LPenafiel", "placa_mm", placa)
      instancia.definition.set_attribute("LPenafiel", "cantos_largos", cantos_l)
      instancia.definition.set_attribute("LPenafiel", "cantos_cortos", cantos_c)
      instancia.definition.set_attribute("LPenafiel", "inglete_esquina", esquina_inglete.to_s)
      instancia.definition.set_attribute("LPenafiel", "inglete_medida_mm", medida_inglete ? dimension_mm(medida_inglete) : 0)
      instancia.definition.set_attribute("LPenafiel", "datos_modulo", JSON.generate(@datos_modulo_actual)) if @datos_modulo_actual
      instancia.set_attribute("LPenafiel", "nombre", nombre_definicion) if instancia.respond_to?(:set_attribute)
    end
    
    punto = Geom::Point3d.new(x, y, z)
    punto = punto + @offset_creacion if @offset_creacion
    transformacion = Geom::Transformation.new(punto)
    instancia.transformation = transformacion
    self.aplicar_material_configurado(instancia, nombre)
    @piezas_modulo_actual << instancia if @piezas_modulo_actual
    return instancia
  end

end
