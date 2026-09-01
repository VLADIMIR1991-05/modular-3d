require 'sketchup'

require 'json'
require 'csv'
require 'net/http'
require 'uri'
require 'tmpdir'
require 'base64'
require 'securerandom'
require 'time'

Sketchup.require 'Modular_3D/core/config'
Sketchup.require 'Modular_3D/core/validation'
Sketchup.require 'Modular_3D/core/license'

# Modular_3D
# Autor: Lenin Vladimir Peñafiel
# Versión: 4.7.3-beta.1
module LPenafiel_GeneradorMueblesExacto

  # Una licencia real debe validarse con un servicio firmado. El nombre de
  # usuario de Windows no es un mecanismo de seguridad.
  def self.acceso_autorizado?
    true
  end

  @nombre_modulo_guardado = "BAJO"
  @ultimo_modulo_piezas = []
  @offset_creacion = nil
  @piezas_modulo_actual = nil
  @datos_modulo_actual = nil
  @seleccion_edicion = nil
  @offset_edicion = nil
  @modulo_uuid_actual = nil
  @contenedor_edicion = nil
  @transformacion_edicion = nil

  MANIFEST_VERSION = 6

  def self.migrar_manifiesto(manifiesto)
    return manifiesto unless manifiesto.is_a?(Hash)
    data = manifiesto['data'].is_a?(Hash) ? manifiesto['data'] : {}
    data['coordinate_system'] ||= 'X_WIDTH_Y_DEPTH_Z_HEIGHT_FRONT_NEGATIVE_Y'
    data['edge_mode'] ||= 'MIXED'
    data['edge_inherit_color'] ||= 'SI'
    data['selected_space_id'] ||= 'root'
    data['material_overrides_json'] ||= '{}'
    data['material_textures_json'] ||= '{}'
    data['material_texture_meta_json'] ||= '{}'
    data['dimension_overrides_json'] ||= '{}'
    # Schema 6: inglete por pieza y montaje de puerta independiente del casco.
    data['miter_overrides_json'] ||= '{}'
    data['montaje_puerta'] ||= 'SOLAPADA'
    data['external_front_scope'] ||= 'BY_SPACE'
    data['global_front_count_mode'] ||= 'AUTO'
    data['global_front_count'] ||= 2
    data['global_front_auto_width'] ||= 600
    %w[left right top bottom].each { |lado| data["global_front_gap_#{lado}"] ||= 1.5 }
    data['global_front_gap_center'] ||= 3
    # Casco activable (schema 5): módulos anteriores conservan los 4 paneles.
    %w[lleva_lateral_izq lleva_lateral_der lleva_base lleva_techo].each { |campo| data[campo] ||= 'SI' }
    data['ajuste_frontal_activo'] ||= 'NO'
    data['ajuste_frontal_orientacion'] ||= 'HORIZONTAL'
    data['ajuste_posterior_orientacion'] ||= 'HORIZONTAL'
    manifiesto['data'] = data
    manifiesto['migrated_from_schema'] = manifiesto['schema'].to_i if manifiesto['schema'].to_i < MANIFEST_VERSION
    manifiesto['schema'] = MANIFEST_VERSION
    manifiesto
  end

  def self.manifiesto_de_entidad(entity)
    return nil unless entity
    candidatos = [entity]
    candidatos << entity.definition if entity.respond_to?(:definition) && entity.definition
    candidatos.each do |objeto|
      raw = objeto.get_attribute('Modular3D', 'manifest') if objeto.respond_to?(:get_attribute)
      next if raw.to_s.strip.empty?
      begin
        data = raw.is_a?(Hash) ? raw : JSON.parse(raw.to_s)
        return migrar_manifiesto(data) if data.is_a?(Hash)
      rescue JSON::ParserError
        next
      end
    end
    nil
  end

  def self.crear_manifiesto(datos, modulo_nombre, uuid = nil, source = 'PARAMETRICO')
    limpio = datos.reject { |clave, _valor| clave.to_s.start_with?('__') || clave.to_s == 'view_snapshot' }
    {
      'schema' => MANIFEST_VERSION,
      'uuid' => uuid.to_s.empty? ? SecureRandom.uuid : uuid,
      'plugin_version' => Modular3D::VERSION,
      'source' => source,
      'name' => modulo_nombre,
      'updated_at' => Time.now.utc.iso8601,
      'coordinate_system' => 'X_WIDTH_Y_DEPTH_Z_HEIGHT_FRONT_NEGATIVE_Y',
      'data' => limpio
    }
  end

  def self.encapsular_modulo(entities, piezas, manifiesto)
    validas = piezas.to_a.select { |pieza| pieza && pieza.respond_to?(:valid?) && pieza.valid? }
    return nil if validas.empty?
    contenedor = entities.add_group(validas)
    nombre = "M3D_MODULO_#{manifiesto['name']}"
    contenedor.name = nombre if contenedor.respond_to?(:name=)
    raw = JSON.generate(manifiesto)
    [contenedor, (contenedor.definition if contenedor.respond_to?(:definition))].compact.each do |objeto|
      objeto.set_attribute('Modular3D', 'type', 'MODULE')
      objeto.set_attribute('Modular3D', 'uuid', manifiesto['uuid'])
      objeto.set_attribute('Modular3D', 'manifest', raw)
    end
    contenedor.definition.name = nombre if contenedor.respond_to?(:definition) && contenedor.definition
    contenedor
  end

  def self.inventario_geometrico(entity_or_list)
    encontrados = []
    visitar = lambda do |entity|
      if entity.respond_to?(:definition) && entity.definition
        original = entity.definition.get_attribute('LPenafiel', 'pieza_original')
        if original
          dims = [entity.bounds.width, entity.bounds.depth, entity.bounds.height].map { |v| v.to_mm.round(2) }.sort
          encontrados << {'name'=>original.to_s, 'dims'=>dims}
        else
          entity.definition.entities.each { |child| visitar.call(child) }
        end
      elsif entity.respond_to?(:entities)
        entity.entities.each { |child| visitar.call(child) }
      end
    end
    Array(entity_or_list).each { |entity| visitar.call(entity) }
    encontrados.sort_by { |item| [item['name'], item['dims']] }
  end


  # Solver paramétrico: proporciones, mm/cm/m, %, AUTO.
  # Misma implementación que Modular3D::Validation.resolver_estaciones (evita duplicar el parser).
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
    "CJ_FRENTE" => "FCC",
    "CJ_POSTERIOR" => "POS",
    "CJ_FONDO" => "FON",
    "PUERTA" => "PT"
  }

  def self.codigo_pieza(nombre)
    nombre_base = nombre.to_s.upcase.sub(/^CJ_\d+_/, "CJ_")
    codigo = CODIGOS_PIEZAS.find { |clave, _valor| nombre_base.start_with?(clave) }
    codigo ? codigo[1] : nombre_base
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

  def self.version_partes(version)
    normalizada = version.to_s.strip.tr("_", "-")
    match = normalizada.match(/\A[vV]?(\d+)\.(\d+)\.(\d+)(?:[-.]([0-9A-Za-z.-]+))?\z/)
    return nil unless match

    [match[1].to_i, match[2].to_i, match[3].to_i, match[4]]
  end

  def self.version_mayor?(remota, local)
    izquierda = version_partes(remota)
    derecha = version_partes(local)
    return false unless izquierda && derecha
    base = izquierda[0, 3] <=> derecha[0, 3]
    return base.positive? unless base.zero?
    return false if izquierda[3] == derecha[3]
    return true if izquierda[3].nil? # Una versión estable supera a cualquier prerelease.
    return false if derecha[3].nil?

    izq_pre = izquierda[3].split('.')
    der_pre = derecha[3].split('.')
    [izq_pre.length, der_pre.length].max.times do |indice|
      return false unless izq_pre[indice]
      return true unless der_pre[indice]
      a = izq_pre[indice]
      b = der_pre[indice]
      comparacion = if a =~ /\A\d+\z/ && b =~ /\A\d+\z/
                      a.to_i <=> b.to_i
                    elsif a =~ /\A\d+\z/
                      -1
                    elsif b =~ /\A\d+\z/
                      1
                    else
                      a <=> b
                    end
      return comparacion.positive? unless comparacion.zero?
    end
    false
  end

  def self.buscar_actualizacion
    uri = URI.parse(Modular3D::UPDATE_MANIFEST_URL)
    raise ArgumentError, 'El manifiesto de actualización debe usar HTTPS.' unless uri.scheme == 'https'
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 8
    response = http.get(uri.request_uri, "Accept" => "application/json")
    data = JSON.parse(response.body.to_s)
    unless response.is_a?(Net::HTTPSuccess) && data["version"] && data["rbz_url"]
      return UI.messagebox("No se pudo leer la informacion de actualizacion.")
    end
    descarga = URI.parse(data['rbz_url'].to_s)
    unless descarga.scheme == 'https' && descarga.host == uri.host
      return UI.messagebox('La actualización fue rechazada porque la descarga no pertenece al servidor autorizado.')
    end
    if version_mayor?(data["version"], Modular3D::VERSION)
      mensaje = "Nueva version disponible: #{data["version"]}\n\nVersion instalada: #{Modular3D::VERSION}\n\n#{data["notes"]}\n\nDeseas abrir la descarga?"
      UI.openURL(descarga.to_s) if UI.messagebox(mensaje, MB_YESNO) == IDYES
    else
      UI.messagebox("Modular_3D ya esta actualizado.\n\nVersion instalada: #{Modular3D::VERSION}")
    end
  rescue Timeout::Error, SocketError, Errno::ECONNREFUSED
    UI.messagebox("No se pudo conectar al servidor de actualizaciones.")
  rescue StandardError => error
    UI.messagebox("No se pudo comprobar la actualizacion: #{error.message}")
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

  def self.archivo_textura(textura, material_nombre)
    return nil if textura.to_s.empty?
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

  def self.crear_pieza(entities, modulo_nombre, nombre, ancho, prof, alto, x, y, z, cantos_l, cantos_c)
    delta_ancho, delta_prof, delta_alto = sobremedida_pieza(nombre)
    ancho = [ancho + delta_ancho, 1.mm].max
    prof = [prof + delta_prof, 1.mm].max
    alto = [alto + delta_alto, 1.mm].max
    esquina_inglete, medida_inglete, eje_inglete = inglete_pieza(nombre)
    grupo = entities.add_group
    if eje_inglete == :horizontal
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

  # --- INTERFAZ DEL GENERADOR ---
  def self.mostrar_interfaz_moderna(datos_iniciales = nil)
    return unless acceso_autorizado?
    model = Sketchup.active_model
    
    dialogo = UI::HtmlDialog.new({
      :dialog_title => "#{Modular3D::PRODUCT_NAME} v#{Modular3D::VERSION} | Configurador",
      :preferences_key => Modular3D::PREFERENCES_KEY,
      :scrollable => true,
      :resizable => true,
      :width => 1080,
      :height => 780,
      :style => UI::HtmlDialog::STYLE_WINDOW
    })

    ruta_html = File.expand_path('../ui/interfaz.html', __dir__)
    
    if File.exist?(ruta_html)
      dialogo.set_file(ruta_html)
    else
      UI.messagebox("Error crítico: no se encontró el archivo 'interfaz.html'.")
      return
    end

    enviar_estado_licencia = lambda do |estado|
      dialogo.execute_script("window.Modular3DLicense && window.Modular3DLicense.receive(#{JSON.generate(estado)});")
    end

    dialogo.add_action_callback("licenciaEstado") do |_action_context|
      enviar_estado_licencia.call(Modular3D::License.status)
    end

    dialogo.add_action_callback("licenciaLogin") do |_action_context, email, password, force_transfer|
      enviar_estado_licencia.call(Modular3D::License.login(email, password, force_transfer == true))
    end

    dialogo.add_action_callback("licenciaHeartbeat") do |_action_context|
      enviar_estado_licencia.call(Modular3D::License.heartbeat)
    end

    dialogo.add_action_callback("licenciaLogout") do |_action_context|
      Modular3D::License.logout
      enviar_estado_licencia.call(ok: false, code: "LOGIN_REQUIRED", message: "Sesión cerrada.")
    end

    dialogo.add_action_callback("ejecutarConstruccionMueble") do |_action_context, datos|
      estado_licencia = Modular3D::License.ensure_authorized
      unless estado_licencia[:ok]
        enviar_estado_licencia.call(estado_licencia)
        next
      end

      validacion = Modular3D::Validation.validar(datos)
      unless validacion[:errores].empty?
        UI.messagebox("No se puede construir:\n\n- #{validacion[:errores].join("\n- ")}")
        next
      end

      unless validacion[:avisos].empty?
        respuesta = UI.messagebox(
          "Avisos de Modular_3D:\n\n- #{validacion[:avisos].join("\n- ")}\n\n¿Deseas continuar?",
          MB_YESNO
        )
        next unless respuesta == IDYES
      end

      dialogo.close
      
      modulo_nombre = if datos['__edit_mode'].to_s == "SI"
                        nombre_edicion = datos['modulo_nombre'].to_s.strip.upcase.gsub(" ", "_")
                        nombre_edicion.empty? ? "MODULO" : nombre_edicion
                      else
                        nombre_modulo_unico(datos['modulo_nombre'])
                      end
      @nombre_modulo_guardado = modulo_nombre
      
      ancho_total     = datos['ancho_total'].mm
      alto_total      = datos['alto_total'].mm
      prof_total      = datos['prof_total'].mm
      espesor         = datos['espesor'].mm
      grosor_lat_izq  = (datos['grosor_izq'] || datos['espesor']).to_f.mm
      grosor_lat_der  = (datos['grosor_der'] || datos['espesor']).to_f.mm
      grosor_superior = (datos['grosor_superior'] || datos['espesor']).to_f.mm
      grosor_inferior = (datos['grosor_inferior'] || datos['espesor']).to_f.mm
      montaje_superior = (datos['montaje_superior'] || "INTERIOR").to_s
      montaje_inferior = (datos['montaje_inferior'] || "INTERIOR").to_s
      montaje_izq = (datos['montaje_izq'] || "EXTERIOR").to_s
      montaje_der = (datos['montaje_der'] || "EXTERIOR").to_s
      retranqueo_frontal_superior = (datos['retranqueo_frontal_superior'] || 0).to_f.mm
      retranqueo_trasero_superior = (datos['retranqueo_trasero_superior'] || 0).to_f.mm
      retranqueo_frontal_inferior = (datos['retranqueo_frontal_inferior'] || 0).to_f.mm
      retranqueo_trasero_inferior = (datos['retranqueo_trasero_inferior'] || 0).to_f.mm
      retranqueo_frontal_izq = (datos['retranqueo_frontal_izq'] || 0).to_f.mm
      retranqueo_trasero_izq = (datos['retranqueo_trasero_izq'] || 0).to_f.mm
      retranqueo_frontal_der = (datos['retranqueo_frontal_der'] || 0).to_f.mm
      retranqueo_trasero_der = (datos['retranqueo_trasero_der'] || 0).to_f.mm
      num_repisas     = datos['num_repisas'].to_i
      num_divisiones  = datos['num_divisiones'].to_i
      param_x_expr = datos['param_x_expr'].to_s.strip
      param_z_expr = datos['param_z_expr'].to_s.strip
      param_x_virtual = datos['param_x_type'].to_s.upcase == 'VIRTUAL'
      param_z_virtual = datos['param_z_type'].to_s.upcase == 'VIRTUAL'
      param_x_sizes_mm = param_x_expr.empty? ? nil : resolver_estaciones(param_x_expr, (ancho_total - grosor_lat_izq - grosor_lat_der).to_mm, param_x_virtual ? 0 : espesor.to_mm)
      param_z_sizes_mm = param_z_expr.empty? ? nil : resolver_estaciones(param_z_expr, (alto_total - grosor_superior - grosor_inferior).to_mm, param_z_virtual ? 0 : espesor.to_mm)
      num_divisiones = [param_x_sizes_mm.length - 1, 0].max if param_x_sizes_mm
      num_repisas = [param_z_sizes_mm.length - 1, 0].max if param_z_sizes_mm
      lleva_respaldo  = datos['lleva_respaldo']
      lleva_maletera  = datos['lleva_maletera']
      grosor_resp     = (datos['grosor_resp'] || 6).to_f.mm
      cantidad_ajustes_raw = (datos['cantidad_ajustes'] || "AUTO").to_s.upcase
      alto_ajuste = (datos['alto_ajuste'] || 60).to_f.mm
      grosor_ajuste = (datos['grosor_ajuste'] || datos['espesor'] || 15).to_f.mm
      separacion_ajuste_respaldo = (datos['separacion_ajuste_respaldo'] || 2).to_f.mm
      distancia_plano_posterior = (datos['distancia_plano_posterior'] || 0).to_f.mm
      cajones_raw     = (datos['cajones_por_nicho'] || datos['num_cajones']).to_s
      cajones_por_nicho = cajones_raw.split(/[,\s;|]+/).map { |valor| valor.to_i }
      cajones_por_nicho = [0] if cajones_por_nicho.empty?
      tipos_cajon_raw = (datos['tipos_cajon_por_nicho'] || "").to_s
      tipos_cajon_por_nicho = tipos_cajon_raw.split(/[,\s;|]+/)
      begin
        spaces_config = JSON.parse(datos['spaces_json'].to_s)
        spaces_config = [] unless spaces_config.is_a?(Array)
      rescue JSON::ParserError
        spaces_config = []
      end
      spaces_config = spaces_config.select do |space|
        space.is_a?(Hash) && space['niche'].to_i >= 0 && space['column'].to_i >= 0
      end
      spaces_config_limpio = {}
      contenidos_validos = %w[VACIO REPISAS CAJONERA PUERTA_UNICA PUERTA_DOBLE PUERTA_VIDRIO PUERTA_DOBLE_VIDRIO]
      spaces_config.each do |space|
        contenido = space['content'].to_s.upcase
        contenido = 'VACIO' unless contenidos_validos.include?(contenido)
        niche = [[space['niche'].to_i, 0].max, num_repisas].min
        column = [[space['column'].to_i, 0].max, num_divisiones].min
        limpio = space.merge(
          'niche' => niche,
          'column' => column,
          'content' => contenido,
          'drawers' => [[space['drawers'].to_i, 0].max, 12].min,
          'shelves' => [[space['shelves'].to_i, 0].max, 12].min,
          'front_type' => space['front_type'].to_s.upcase == 'FRENTES' ? 'FRENTES' : 'INTERNO'
        )
        spaces_config_limpio["#{niche}:#{column}"] = limpio
      end
      spaces_config = spaces_config_limpio.values
      begin
        hierarchy_geometry = JSON.parse(datos['hierarchy_geometry_json'].to_s)
        hierarchy_geometry = nil unless hierarchy_geometry.is_a?(Hash) && hierarchy_geometry['nodes'].is_a?(Array)
      rescue JSON::ParserError
        hierarchy_geometry = nil
      end
      # La jerarquía es la única fuente geométrica. Evita fabricar nuevamente
      # las repisas/divisiones del configurador legado (incluida la repisa media).
      if hierarchy_geometry
        alcance_frentes = (datos['external_front_scope'] || 'BY_SPACE').to_s.upcase
        num_repisas = 0
        num_divisiones = 0
        param_x_sizes_mm = nil
        param_z_sizes_mm = nil
        spaces_config = []
      end
      modo_frentes = (datos['modo_frentes'] || "POR_NICHO").to_s.upcase
      if modo_frentes == "TODOS"
        tipos_cajon_por_nicho = cajones_por_nicho.map { |cantidad| cantidad.to_i > 0 ? "FRENTES" : "INTERNO" }
      elsif modo_frentes == "NINGUNO"
        tipos_cajon_por_nicho = cajones_por_nicho.map { |_cantidad| "INTERNO" }
      end
      num_cajones = if spaces_config.empty?
                       cajones_por_nicho.inject(0) { |suma, valor| suma + valor }
                     else
                       spaces_config.inject(0) do |suma, space|
                         suma + (space['content'].to_s == 'CAJONERA' ? space['drawers'].to_i : 0)
                       end
                     end
      prof_input_cj   = datos['prof_input_cj'].mm
      descuento_madeval = datos['madeval'] == "SI" ? 1.mm : 0.mm
      @modulo_despiece_actual = nombre_modulo_despiece(modulo_nombre, ancho_total, alto_total, prof_total, num_cajones, datos['crear_puerta'])
      
      actualizar_existente = datos['__edit_mode'].to_s == "SI" && @seleccion_edicion && @offset_edicion
      @offset_creacion = actualizar_existente ? @offset_edicion : offset_siguiente_modulo
      @datos_modulo_actual = datos.reject { |clave, _valor| clave.to_s.start_with?("__") || clave.to_s == 'view_snapshot' }
      @modulo_uuid_actual = datos['__manifest_uuid'].to_s unless datos['__manifest_uuid'].to_s.empty?
      @modulo_uuid_actual = @datos_modulo_actual['module_uuid'].to_s if @modulo_uuid_actual.to_s.empty? && !@datos_modulo_actual['module_uuid'].to_s.empty?
      @modulo_uuid_actual = SecureRandom.uuid if @modulo_uuid_actual.to_s.empty?
      @datos_modulo_actual['module_uuid'] = @modulo_uuid_actual
      @datos_modulo_actual['module_base_offset'] = [
        @offset_creacion.x.to_mm, @offset_creacion.y.to_mm, @offset_creacion.z.to_mm
      ]
      @piezas_modulo_actual = []

      operacion_iniciada = false
      begin
      model.start_operation("Generar Mueble", true)
      operacion_iniciada = true
      entities = model.active_entities
      if actualizar_existente
        @seleccion_edicion.each { |entity| entity.erase! if entity && entity.respond_to?(:valid?) && entity.valid? }
        @seleccion_edicion = nil
      end
      ancho_interno = ancho_total - grosor_lat_izq - grosor_lat_der
      ancho_util_mueble = ancho_interno - descuento_madeval
      alto_interno  = alto_total - grosor_superior - grosor_inferior
      zonas_frentes_cajon = []
      
      lat_l = 1
      lat_c = prof_total > 340.mm ? 0 : 1
      if ancho_util_mueble >= prof_total
        hz_l = 1; hz_c = 0
      else
        hz_l = 0; hz_c = 1
      end
      
      # Casco activable: cada panel exterior puede omitirse (p. ej. módulo contra
      # pared o abierto) sin alterar la cavidad interior ni la posición del resto
      # de piezas, que siguen usando el mismo grosor como referencia de encaje.
      existe_lat_izq = (datos['lleva_lateral_izq'] || 'SI').to_s != 'NO'
      existe_lat_der = (datos['lleva_lateral_der'] || 'SI').to_s != 'NO'
      existe_base    = (datos['lleva_base'] || 'SI').to_s != 'NO'
      existe_techo   = (datos['lleva_techo'] || 'SI').to_s != 'NO'

      prof_lat_izq = prof_total - retranqueo_frontal_izq - retranqueo_trasero_izq
      prof_lat_der = prof_total - retranqueo_frontal_der - retranqueo_trasero_der
      alto_lat_izq = montaje_izq == "INTERIOR" ? alto_interno : alto_total
      alto_lat_der = montaje_der == "INTERIOR" ? alto_interno : alto_total
      z_lat_izq = montaje_izq == "INTERIOR" ? grosor_inferior : 0.mm
      z_lat_der = montaje_der == "INTERIOR" ? grosor_inferior : 0.mm
      self.crear_pieza(entities, modulo_nombre, "LAT_IZQ", grosor_lat_izq, prof_lat_izq, alto_lat_izq, 0, retranqueo_frontal_izq, z_lat_izq, lat_l, lat_c) if existe_lat_izq
      x_lat_der = ancho_total - grosor_lat_der
      self.crear_pieza(entities, modulo_nombre, "LAT_DER", grosor_lat_der, prof_lat_der, alto_lat_der, x_lat_der, retranqueo_frontal_der, z_lat_der, lat_l, lat_c) if existe_lat_der

      ancho_base = montaje_inferior == "EXTERIOR" ? ancho_total : ancho_util_mueble
      x_base = montaje_inferior == "EXTERIOR" ? 0.mm : grosor_lat_izq
      prof_base = prof_total - retranqueo_frontal_inferior - retranqueo_trasero_inferior
      self.crear_pieza(entities, modulo_nombre, "BASE", ancho_base, prof_base, grosor_inferior, x_base, retranqueo_frontal_inferior, 0, hz_l, hz_c) if existe_base

      ancho_techo = montaje_superior == "EXTERIOR" ? ancho_total : ancho_util_mueble
      x_techo = montaje_superior == "EXTERIOR" ? 0.mm : grosor_lat_izq
      prof_techo = prof_total - retranqueo_frontal_superior - retranqueo_trasero_superior
      z_techo = alto_total - grosor_superior
      self.crear_pieza(entities, modulo_nombre, "TECHO", ancho_techo, prof_techo, grosor_superior, x_techo, retranqueo_frontal_superior, z_techo, hz_l, hz_c) if existe_techo

      respaldo_estructural = grosor_resp >= 15.mm
      cantidad_ajustes = 0
      if lleva_respaldo != "NO" && !respaldo_estructural
        cantidad_ajustes = cantidad_ajustes_raw == "AUTO" ? (alto_total > 760.mm ? 2 : 1) : cantidad_ajustes_raw.to_i
        cantidad_ajustes = [[cantidad_ajustes, 0].max, 4].min
      end
      # Secuencia posterior única (desde atrás hacia el frente):
      # distancia posterior -> ajuste -> separación -> respaldo -> espacio útil.
      y_ajuste = prof_total - distancia_plano_posterior - grosor_ajuste
      z_superior_ajuste = alto_total - grosor_superior - alto_ajuste

      # Un ajuste "vertical" no es un rail corrido de lateral a lateral, sino un
      # par de escuadras (una por esquina) que corren en profundidad, apoyadas
      # bajo el techo. Reutiliza grosor_ajuste/alto_ajuste como su sección y su
      # alcance hacia el frente, para no añadir campos nuevos al formulario.
      crear_escuadras_ajuste = lambda do |prefijo, y_inicio|
        self.crear_pieza(entities, modulo_nombre, "#{prefijo}_ESCUADRA_IZQ", grosor_ajuste, alto_ajuste, grosor_ajuste, grosor_lat_izq, y_inicio, z_superior_ajuste, 0, 0)
        self.crear_pieza(entities, modulo_nombre, "#{prefijo}_ESCUADRA_DER", grosor_ajuste, alto_ajuste, grosor_ajuste, ancho_total - grosor_lat_der - grosor_ajuste, y_inicio, z_superior_ajuste, 0, 0)
      end

      if cantidad_ajustes > 0
        orientacion_posterior = (datos['ajuste_posterior_orientacion'] || 'HORIZONTAL').to_s.upcase
        if orientacion_posterior == 'VERTICAL'
          crear_escuadras_ajuste.call("AJUSTE_POSTERIOR", y_ajuste)
        else
          self.crear_pieza(entities, modulo_nombre, "AJUSTE_SUPERIOR", ancho_util_mueble, grosor_ajuste, alto_ajuste, grosor_lat_izq, y_ajuste, z_superior_ajuste, 1, 0)
        end
        if cantidad_ajustes > 1
          (2..cantidad_ajustes).each do |idx|
            espacio_posterior = alto_total - grosor_superior - grosor_inferior - alto_ajuste
            fraccion = idx == 2 ? 0.5 : (cantidad_ajustes - idx + 1).to_f / cantidad_ajustes
            z_ajuste = grosor_inferior + (espacio_posterior * fraccion) - (alto_ajuste / 2)
            z_min_ajuste = grosor_inferior
            z_max_ajuste = z_superior_ajuste - alto_ajuste
            z_ajuste = z_min_ajuste if z_ajuste < z_min_ajuste
            z_ajuste = z_max_ajuste if z_ajuste > z_max_ajuste
            self.crear_pieza(entities, modulo_nombre, "AJUSTE_POSTERIOR_#{idx - 1}", ancho_util_mueble, grosor_ajuste, alto_ajuste, grosor_lat_izq, y_ajuste, z_ajuste, 1, 0)
          end
        end
      end

      # Ajuste frontal: independiente del posterior, apoyado en el plano frontal
      # (y=0) para dar escuadra al frente. Desactivado por defecto para no
      # alterar módulos ya guardados.
      if (datos['ajuste_frontal_activo'] || 'NO').to_s == 'SI'
        orientacion_frontal = (datos['ajuste_frontal_orientacion'] || 'HORIZONTAL').to_s.upcase
        if orientacion_frontal == 'VERTICAL'
          crear_escuadras_ajuste.call("AJUSTE_FRONTAL", 0.mm)
        else
          self.crear_pieza(entities, modulo_nombre, "AJUSTE_FRONTAL", ancho_util_mueble, grosor_ajuste, alto_ajuste, grosor_lat_izq, 0.mm, z_superior_ajuste, 1, 0)
        end
      end
      
      if lleva_respaldo == "SI"
        profundidad_ranura = (datos['profundidad_ranura'] || 5).to_f.mm
        ancho_respaldo = ancho_interno + (profundidad_ranura * 2)
        alto_respaldo  = alto_interno + (profundidad_ranura * 2)
        espacio_libre_atras = respaldo_estructural ? (distancia_plano_posterior + grosor_resp) : (distancia_plano_posterior + grosor_ajuste + separacion_ajuste_respaldo + grosor_resp)
        y_respaldo = prof_total - espacio_libre_atras
        x_respaldo = grosor_lat_izq - profundidad_ranura
        z_respaldo = grosor_inferior - profundidad_ranura
        self.crear_pieza(entities, modulo_nombre, "RESPALDO", ancho_respaldo, grosor_resp, alto_respaldo, x_respaldo, y_respaldo, z_respaldo, 0, 0)
      elsif lleva_respaldo == "INTERNO"
        ancho_respaldo = ancho_interno
        alto_respaldo = alto_interno
        y_respaldo = if respaldo_estructural
                       prof_total - distancia_plano_posterior - grosor_resp
                     else
                       y_ajuste - separacion_ajuste_respaldo - grosor_resp
                     end
        x_respaldo = grosor_lat_izq
        z_respaldo = grosor_inferior
        self.crear_pieza(entities, modulo_nombre, "RESPALDO_INTERNO", ancho_respaldo, grosor_resp, alto_respaldo, x_respaldo, y_respaldo, z_respaldo, 0, 0)
      elsif lleva_respaldo == "SOBREPUESTO"
        holgura = 1.5.mm
        ancho_respaldo = ancho_total - (holgura * 2)
        alto_respaldo = alto_total - (holgura * 2)
        y_respaldo = prof_total - distancia_plano_posterior - grosor_resp
        x_respaldo = holgura
        z_respaldo = holgura
        self.crear_pieza(entities, modulo_nombre, "RESPALDO_SOBREPUESTO", ancho_respaldo, grosor_resp, alto_respaldo, x_respaldo, y_respaldo, z_respaldo, 0, 0)
      end
      
      retranqueo_interior = (datos['retranqueo_interior'] || 38).to_f.mm
      prof_division_descontada = prof_total - retranqueo_interior
  
      if num_divisiones > 0 && !param_x_virtual
        if param_x_sizes_mm
          cursor_x = grosor_lat_izq
          param_x_sizes_mm[0...-1].each_with_index do |size_mm, index|
            cursor_x += size_mm.mm
            self.crear_pieza(entities, modulo_nombre, "DIV_VERT_#{index + 1}", espesor, prof_division_descontada, alto_interno, cursor_x, 0.mm, grosor_inferior, 1, 1)
            cursor_x += espesor
          end
        else
          espacio_neto_divisiones = ancho_interno - (num_divisiones * espesor)
          distancia_entre_divisiones = espacio_neto_divisiones / (num_divisiones + 1)
          (1..num_divisiones).each do |k|
            x_division = grosor_lat_izq + (k * distancia_entre_divisiones) + ((k - 1) * espesor)
            self.crear_pieza(entities, modulo_nombre, "DIV_VERT_#{k}", espesor, prof_division_descontada, alto_interno, x_division, 0.mm, grosor_inferior, 1, 1)
          end
        end
      end

      posiciones_repisas = []
      z_limite_repisas = z_techo
      prof_repisa_descontada = prof_total - retranqueo_interior
      if ancho_util_mueble >= prof_repisa_descontada
        rep_l = 1; rep_c = 0
      else
        rep_l = 0; rep_c = 1
      end

      if lleva_maletera == "SI"
        altura_interna_maletera = 300.mm
        z_maletera = z_techo - espesor - altura_interna_maletera
        if z_maletera > grosor_inferior
          mal_l = ancho_util_mueble >= prof_repisa_descontada ? 1 : 0
          mal_c = ancho_util_mueble >= prof_repisa_descontada ? 0 : 1
          self.crear_pieza(entities, modulo_nombre, "REPISA_MALETERA", ancho_util_mueble, prof_repisa_descontada, espesor, grosor_lat_izq, 0, z_maletera, mal_l, mal_c)
          z_limite_repisas = z_maletera - espesor
        end
      end
      
      if num_repisas > 0 && !param_z_virtual
        if param_z_sizes_mm
          cursor_z = grosor_inferior
          param_z_sizes_mm[0...-1].each_with_index do |size_mm, index|
            cursor_z += size_mm.mm
            self.crear_pieza(entities, modulo_nombre, "REPISA_#{index + 1}", ancho_util_mueble, prof_repisa_descontada, espesor, grosor_lat_izq, 0, cursor_z, rep_l, rep_c)
            posiciones_repisas << cursor_z
            cursor_z += espesor
          end
        else
          alto_util_repisas = z_limite_repisas - grosor_inferior
          espacio_neto_huecos = alto_util_repisas - (num_repisas * espesor)
          distancia_entre_repisas = espacio_neto_huecos / (num_repisas + 1)
          (1..num_repisas).each do |i|
            z_repisa = grosor_inferior + (i * distancia_entre_repisas) + ((i - 1) * espesor)
            self.crear_pieza(entities, modulo_nombre, "REPISA_#{i}", ancho_util_mueble, prof_repisa_descontada, espesor, grosor_lat_izq, 0, z_repisa, rep_l, rep_c)
            posiciones_repisas << z_repisa
          end
        end
      elsif param_z_sizes_mm
        # En división virtual conservamos límites lógicos sin fabricar repisas.
        cursor_z = grosor_inferior
        param_z_sizes_mm[0...-1].each do |size_mm|
          cursor_z += size_mm.mm
          posiciones_repisas << cursor_z
        end
      end

      # Motor jerárquico: usa las mismas cajas exactas calculadas por el plano 2D y MODULAR-3D VIEW.
      if hierarchy_geometry
        separadores_por_padre = Hash.new(0)
        (hierarchy_geometry['separators'] || []).each do |separator|
          next unless separator.is_a?(Hash)
          axis = separator['axis'].to_s.upcase
          ancho = separator['w'].to_f.mm
          fondo = separator['d'].to_f.mm
          alto = separator['h'].to_f.mm
          next if ancho <= 0 || fondo <= 0 || alto <= 0
          padre_id = id_pieza_jerarquia(separator['parent'], 'ROOT')
          separadores_por_padre[padre_id] += 1
          sufijo = "#{padre_id}_#{separadores_por_padre[padre_id]}"
          codigo = axis == 'X' ? "H_DIV_X_#{sufijo}" : (axis == 'Z' ? "H_REP_Z_#{sufijo}" : "H_DIV_Y_#{sufijo}")
          self.crear_pieza(entities, modulo_nombre, codigo, ancho, fondo, alto,
            separator['x'].to_f.mm, separator['y'].to_f.mm, separator['z'].to_f.mm, 1, 1)
        end

        hierarchy_geometry['nodes'].each_with_index do |node, node_index|
          next unless node.is_a?(Hash) && node['box'].is_a?(Hash) && node['enclosure'].is_a?(Hash)
          box = node['box']; enc = node['enclosure']; x = box['x'].to_f.mm; y = box['y'].to_f.mm; z = box['z'].to_f.mm
          w = box['w'].to_f.mm; d = box['d'].to_f.mm; h = box['h'].to_f.mm
          nid = id_pieza_jerarquia(node['id'], "IDX#{node_index + 1}")
          self.crear_pieza(entities, modulo_nombre, "H_CIERRE_IZQ_#{nid}", espesor, d, h, x, y, z, 1, 1) if enc['left']
          self.crear_pieza(entities, modulo_nombre, "H_CIERRE_DER_#{nid}", espesor, d, h, x + w - espesor, y, z, 1, 1) if enc['right']
          self.crear_pieza(entities, modulo_nombre, "H_BASE_#{nid}", w, d, espesor, x, y, z, 1, 0) if enc['bottom']
          self.crear_pieza(entities, modulo_nombre, "H_TECHO_#{nid}", w, d, espesor, x, y, z + h - espesor, 1, 0) if enc['top']
          self.crear_pieza(entities, modulo_nombre, "H_RESP_#{nid}", w, grosor_resp, h, x, y + d - grosor_resp, z, 0, 0) if enc['back']
        end

        leaf_nodes = hierarchy_geometry['nodes'].select { |node| node.is_a?(Hash) && (!node['children'].is_a?(Array) || node['children'].empty?) }
        leaf_nodes.each_with_index do |node, node_index|
          box = node['box'] || {}
          x_min = box['x'].to_f.mm; y_min = box['y'].to_f.mm; z_min = box['z'].to_f.mm
          ancho_nodo = box['w'].to_f.mm; fondo_nodo = box['d'].to_f.mm; alto_nodo = box['h'].to_f.mm
          next if ancho_nodo <= 0 || fondo_nodo <= 0 || alto_nodo <= 0
          nid = id_pieza_jerarquia(node['id'], "IDX#{node_index + 1}")
          contenido = node['content'].to_s.upcase
          if contenido == 'REPISAS'
            cantidad = [[node['shelves'].to_i, 1].max, 20].min
            distancia = (alto_nodo - (cantidad * espesor)) / (cantidad + 1)
            (1..cantidad).each do |ri|
              z_rep = z_min + (ri * distancia) + ((ri - 1) * espesor)
              self.crear_pieza(entities, modulo_nombre, "H_REP_LOCAL_#{nid}_#{ri}", ancho_nodo, fondo_nodo, espesor, x_min, y_min, z_rep, 1, 0)
            end
          end
          if contenido.start_with?('CAJONES')
            cantidad = [[node['drawers'].to_i, 1].max, 12].min
            fuga_h = [(node['gap'] || 3).to_f, 1.0].max.mm
            holgura = 13.mm
            ancho_caja = ancho_nodo - (holgura * 2)
            altura_caja = (alto_nodo - ((cantidad + 1) * fuga_h)) / cantidad
            fondo_caja = [prof_input_cj, fondo_nodo - 10.mm].min
            if ancho_caja > (espesor * 2) && altura_caja > 25.mm && fondo_caja > (espesor * 2)
              (1..cantidad).each do |ci|
                base_x = x_min + holgura
                base_z = z_min + fuga_h + ((ci - 1) * (altura_caja + fuga_h))
                prefix = "H_CJ_#{nid}_#{ci}"
                self.crear_pieza(entities, modulo_nombre, "#{prefix}_LAT_IZQ", espesor, fondo_caja, altura_caja, base_x, y_min, base_z, 1, 0)
                self.crear_pieza(entities, modulo_nombre, "#{prefix}_LAT_DER", espesor, fondo_caja, altura_caja, base_x + ancho_caja - espesor, y_min, base_z, 1, 0)
                self.crear_pieza(entities, modulo_nombre, "#{prefix}_FRENTE", ancho_caja - (espesor * 2), espesor, altura_caja, base_x + espesor, y_min, base_z, 1, 0)
                self.crear_pieza(entities, modulo_nombre, "#{prefix}_POST", ancho_caja - (espesor * 2), espesor, altura_caja, base_x + espesor, y_min + fondo_caja - espesor, base_z, 1, 0)
                self.crear_pieza(entities, modulo_nombre, "#{prefix}_FONDO", ancho_caja - (espesor * 2), fondo_caja - (espesor * 2), espesor, base_x + espesor, y_min + espesor, base_z, 0, 0)
                if contenido == 'CAJONES_FRENTES' && alcance_frentes != 'GLOBAL'
                  self.crear_pieza(entities, modulo_nombre, "#{prefix}_FRENTE_EXT", ancho_nodo - (fuga_h * 2), espesor, altura_caja, x_min + fuga_h, -espesor, base_z, 2, 2)
                end
              end
            end
          end
        end

        # Los frentes se procesan en todos los nodos, incluidos padres que abarcan varios hijos.
        hierarchy_geometry['nodes'].each_with_index do |node, node_index|
          next unless node.is_a?(Hash)
          frente = node['front'].to_s.upcase
          frente = 'PUERTA_UNICA' if node['content'].to_s.upcase == 'CAJONES_PUERTA' && frente == 'NINGUNO'
          next if frente.empty? || frente == 'NINGUNO'
          puerta_interna = frente.include?('INTERNA')
          next if !puerta_interna && alcance_frentes != 'BY_SPACE'
          box = node['box'] || {}; fuga_h = [(node['gap'] || 3).to_f, 0.5].max.mm
          x_min = box['x'].to_f.mm; z_min = box['z'].to_f.mm; ancho_nodo = box['w'].to_f.mm; alto_nodo = box['h'].to_f.mm
          # Los valores antiguos de vidrio se abren como puertas sólidas para conservar proyectos.
          frente = frente.gsub('_VIDRIO', '').gsub('VIDRIO', 'UNICA')
          cantidad_solicitada = node['frontCount'].to_s.upcase
          cantidad = if cantidad_solicitada != '' && cantidad_solicitada != 'AUTO'
                       [[cantidad_solicitada.to_i, 1].max, 8].min
                     else
                       [[(ancho_nodo.to_mm / 600.0).ceil, 1].max, 8].min
                     end
          unless puerta_interna
            frente_box = node['front_box'].is_a?(Hash) ? node['front_box'] : nil
            if frente_box
              x_min = frente_box['x'].to_f.mm
              z_min = frente_box['z'].to_f.mm
              ancho_nodo = frente_box['w'].to_f.mm
              alto_nodo = frente_box['h'].to_f.mm
            elsif node['id'].to_s == 'root'
              x_min = 1.5.mm
              z_min = 1.5.mm
              ancho_nodo = ancho_total - 3.mm
              alto_nodo = alto_total - 3.mm
            end
            cantidad = [[(ancho_nodo.to_mm / 600.0).ceil, 1].max, 8].min if cantidad_solicitada == '' || cantidad_solicitada == 'AUTO'
          end
          grosor_puerta = [(datos['puerta_grosor'] || espesor.to_mm).to_f, 3.0].max.mm
          fuga_central = [(node['gapCenter'] || node['gap'] || 3).to_f, 0.5].max.mm
          margen_lateral = puerta_interna ? fuga_h : 0.mm
          ancho_puerta = (ancho_nodo - (margen_lateral * 2) - (fuga_central * (cantidad - 1))) / cantidad
          alto_puerta = alto_nodo - (margen_lateral * 2)
          next if ancho_puerta <= 0 || alto_puerta <= 0
          nid_puerta = id_pieza_jerarquia(node['id'], "IDX#{node_index + 1}")
          externa_embutida = !puerta_interna && (datos['montaje_puerta'] || 'SOLAPADA').to_s.upcase == 'EMBUTIDA'
          (1..cantidad).each do |pi|
            nombre_puerta = "H_PUERTA_#{puerta_interna ? 'INT' : 'EXT'}_#{nid_puerta}_#{pi}"
            # Externa solapada: ocupa el plano exterior, desde -grosor hasta el
            # frente Y=0. Externa embutida: queda a ras (Y=0), dentro del hueco
            # que ya calculó facadeBox con margen uniforme. Interna: nace
            # dentro del hueco del espacio seleccionado.
            y_puerta = puerta_interna ? box['y'].to_f.mm + 2.mm : (externa_embutida ? 0.mm : -grosor_puerta)
            self.crear_pieza(entities, modulo_nombre, nombre_puerta, ancho_puerta, grosor_puerta, alto_puerta,
              x_min + margen_lateral + ((pi - 1) * (ancho_puerta + fuga_central)), y_puerta, z_min + margen_lateral, 2, 2)
          end
        end

        # Frente exterior global: una fachada independiente que cubre todo el módulo.
        if alcance_frentes == 'GLOBAL'
          modo = (datos['global_front_count_mode'] || 'AUTO').to_s.upcase
          maximo = [[(datos['global_front_auto_width'] || 600).to_f, 100.0].max, ancho_total.to_mm].min
          cantidad = modo == 'MANUAL' ? (datos['global_front_count'] || 1).to_i : (ancho_total.to_mm / maximo).ceil
          cantidad = [[cantidad, 1].max, 8].min
          fuga_izq = [(datos['global_front_gap_left'] || 3).to_f, 0.0].max.mm
          fuga_der = [(datos['global_front_gap_right'] || 3).to_f, 0.0].max.mm
          fuga_sup = [(datos['global_front_gap_top'] || 3).to_f, 0.0].max.mm
          fuga_inf = [(datos['global_front_gap_bottom'] || 3).to_f, 0.0].max.mm
          fuga_central = [(datos['global_front_gap_center'] || 3).to_f, 0.0].max.mm
          grosor_puerta = [(datos['puerta_grosor'] || espesor.to_mm).to_f, 3.0].max.mm
          ancho_puerta = (ancho_total - fuga_izq - fuga_der - fuga_central * (cantidad - 1)) / cantidad
          alto_puerta = alto_total - fuga_sup - fuga_inf
          if ancho_puerta > 0 && alto_puerta > 0
            (1..cantidad).each do |pi|
              pieza = self.crear_pieza(entities, modulo_nombre, "G_PUERTA_EXT_#{pi}", ancho_puerta, grosor_puerta, alto_puerta,
                fuga_izq + ((pi - 1) * (ancho_puerta + fuga_central)), -grosor_puerta, fuga_inf, 2, 2)
              regla_apertura = (datos['global_front_hinge'] || 'ALTERNADA').to_s.upcase
              apertura = if regla_apertura == 'IZQUIERDA' || regla_apertura == 'DERECHA'
                           regla_apertura
                         else
                           pi <= (cantidad / 2.0).ceil ? 'IZQUIERDA' : 'DERECHA'
                         end
              pieza.set_attribute('LPenafiel', 'apertura', apertura) if pieza
            end
          end
        end
      end

      caja_modulo_estructura = bounds_de_piezas(@piezas_modulo_actual)

      if num_cajones > 0
        fuga = [(datos['luz_frentes'] || datos['juego_general'] || 3).to_f, 1.5].max.mm
        sistema_corredera = (datos['sistema_corredera'] || "Telescopica estandar").to_s
        holgura_lateral = if sistema_corredera.downcase.include?("oculta")
                            21.mm
                          elsif sistema_corredera.downcase.include?("maximo")
                            15.mm
                          else
                            13.mm
                          end
        retiro_cajones = (datos['ret_cajones'] || 0).to_f.mm
        ancho_disponible_cajon = num_divisiones > 0 ? ((ancho_util_mueble - (num_divisiones * espesor)) / (num_divisiones + 1)) : ancho_util_mueble
        ancho_caja_cajon = ancho_disponible_cajon - (holgura_lateral * 2)
        prof_caja_cajon = prof_input_cj

        nichos = []
        z_inicio_nicho_actual = grosor_inferior
        posiciones_repisas.each do |z_repisa|
          nichos << [z_inicio_nicho_actual, z_repisa]
          z_inicio_nicho_actual = z_repisa
        end
        nichos << [z_inicio_nicho_actual, z_limite_repisas]
        contador_cajon = 0

        nichos.each_with_index do |limites_nicho, indice_nicho|
          drawer_specs = if spaces_config.empty?
                           [{ 'column' => 0, 'drawers' => cajones_por_nicho[indice_nicho].to_i,
                              'front_type' => (tipos_cajon_por_nicho[indice_nicho] || 'INTERNO') }]
                         else
                           spaces_config.select do |space|
                             space['niche'].to_i == indice_nicho && space['content'].to_s == 'CAJONERA'
                           end
                         end
          drawer_specs.each do |drawer_space|
          cajones_en_nicho = drawer_space['drawers'].to_i
          next if cajones_en_nicho <= 0
          columna_cajon = [[drawer_space['column'].to_i, 0].max, num_divisiones].min

          z_inicio_nicho = limites_nicho[0]
          z_fin_nicho = limites_nicho[1]
          tipo_cajon_nicho = (drawer_space['front_type'] || "INTERNO").to_s.upcase
          altura_hueco_disponible = z_fin_nicho - z_inicio_nicho
          margen_caja = 30.mm
          total_espacio_fugas = (2 * margen_caja) + ((cajones_en_nicho - 1) * fuga)
          altura_caja_cajon = (altura_hueco_disponible - total_espacio_fugas) / cajones_en_nicho
          next if altura_caja_cajon <= 0

          (1..cajones_en_nicho).each do |j|
            contador_cajon += 1
            z_inicio_cajon = z_inicio_nicho + margen_caja + ((j - 1) * (altura_caja_cajon + fuga))
            ancho_lat_cajon = espesor; prof_lat_cajon = prof_caja_cajon; alto_lat_cajon = altura_caja_cajon
            ancho_frente_cajon = ancho_caja_cajon - (espesor * 2); prof_frente_cajon = espesor; alto_frente_cajon = altura_caja_cajon
            ancho_fondo_cajon = ancho_frente_cajon; prof_fondo_cajon = prof_caja_cajon - (espesor * 2); alto_fondo_cajon = espesor

            x_inicio_columna = grosor_lat_izq + (columna_cajon * (ancho_disponible_cajon + espesor))
            x_cj_lat_izq = x_inicio_columna + holgura_lateral
            self.crear_pieza(entities, modulo_nombre, "CJ_#{contador_cajon}_LAT_IZQ", ancho_lat_cajon, prof_lat_cajon, alto_lat_cajon, x_cj_lat_izq, retiro_cajones, z_inicio_cajon, 1, 0)
            x_cj_lat_der = x_cj_lat_izq + ancho_caja_cajon - espesor
            self.crear_pieza(entities, modulo_nombre, "CJ_#{contador_cajon}_LAT_DER", ancho_lat_cajon, prof_lat_cajon, alto_lat_cajon, x_cj_lat_der, retiro_cajones, z_inicio_cajon, 1, 0)
            x_cj_frente = x_cj_lat_izq + espesor
            self.crear_pieza(entities, modulo_nombre, "CJ_#{contador_cajon}_FRENTE", ancho_frente_cajon, prof_frente_cajon, alto_frente_cajon, x_cj_frente, retiro_cajones, z_inicio_cajon, 1, 0)
            y_cj_post = retiro_cajones + prof_caja_cajon - espesor
            self.crear_pieza(entities, modulo_nombre, "CJ_#{contador_cajon}_POSTERIOR", ancho_frente_cajon, prof_frente_cajon, alto_frente_cajon, x_cj_frente, y_cj_post, z_inicio_cajon, 1, 0)
            y_cj_fondo = retiro_cajones + espesor; z_cj_fondo = z_inicio_cajon
            self.crear_pieza(entities, modulo_nombre, "CJ_#{contador_cajon}_FONDO", ancho_fondo_cajon, prof_fondo_cajon, alto_fondo_cajon, x_cj_frente, y_cj_fondo, z_cj_fondo, 0, 0)
            if datos['reforzar_piso'].to_s == "SI"
              self.crear_pieza(entities, modulo_nombre, "CJ_#{contador_cajon}_REFUERZO_FONDO", ancho_fondo_cajon, prof_fondo_cajon, alto_fondo_cajon, x_cj_frente, y_cj_fondo, z_cj_fondo + espesor, 0, 0)
            end
          end

          if tipo_cajon_nicho == "FRENTES"
            fuga_frente = [(datos['luz_perimetral'] || datos['luz_frentes'] || 1.5).to_f, 0.5].max.mm
            x_inicio_columna = grosor_lat_izq + (columna_cajon * (ancho_disponible_cajon + espesor))
            x_frente_exterior = x_inicio_columna + fuga_frente
            ancho_frente_exterior = ancho_disponible_cajon - (fuga_frente * 2)
            y_frente_exterior = -espesor
            z_frente_inferior = if indice_nicho == 0
                                  0.mm
                                else
                                  posiciones_repisas[indice_nicho - 1] - (espesor / 2.0)
                                end
            z_frente_superior = if posiciones_repisas[indice_nicho]
                                  posiciones_repisas[indice_nicho] + (espesor / 2.0)
                                else
                                  z_limite_repisas
                                end
            alto_total_frentes = z_frente_superior - z_frente_inferior
            next if ancho_frente_exterior <= 0 || alto_total_frentes <= 0

            alto_segmento_frente = alto_total_frentes / cajones_en_nicho
            (1..cajones_en_nicho).each do |f|
              z_segmento_inferior = z_frente_inferior + ((f - 1) * alto_segmento_frente)
              z_frente = z_segmento_inferior + fuga_frente
              alto_frente = alto_segmento_frente - (fuga_frente * 2)
              next if alto_frente <= 0

              frente = self.crear_pieza(entities, modulo_nombre, "CJ_FRENTE_EXTERIOR_#{indice_nicho + 1}_#{f}", ancho_frente_exterior, espesor, alto_frente, x_frente_exterior, y_frente_exterior, z_frente, 2, 2)
              offset = @offset_creacion || Geom::Vector3d.new(0, 0, 0)
              self.alinear_bounds(frente,
                :min_x => offset.x + x_frente_exterior,
                :min_y => offset.y + y_frente_exterior,
                :min_z => offset.z + z_segmento_inferior + fuga_frente
              )
            end
            offset_zona = @offset_creacion ? @offset_creacion.z : 0
            zonas_frentes_cajon << [z_frente_inferior + offset_zona, z_frente_superior + offset_zona]
          end
          end
        end
      end
      
      unless spaces_config.empty?
        ancho_celda = (ancho_util_mueble - (num_divisiones * espesor)) / (num_divisiones + 1)
        limites_nichos = []
        inicio_nicho = grosor_inferior
        posiciones_repisas.each do |z_repisa|
          limites_nichos << [inicio_nicho, z_repisa]
          inicio_nicho = z_repisa
        end
        limites_nichos << [inicio_nicho, z_limite_repisas]
        grosor_puerta_celda = (datos['puerta_grosor'] || 15).to_f.mm
        lado_puerta_celda = datos['puerta_bisagra'] == "Derecha" ? :derecha : :izquierda
        offset_celda = @offset_creacion || Geom::Vector3d.new(0, 0, 0)
        spaces_config.each do |space|
          contenido = space['content'].to_s.upcase
          next unless contenido == 'REPISAS'

          cantidad_repisas_celda = [[space['shelves'].to_i, 0].max, 12].min
          next if cantidad_repisas_celda <= 0

          nicho = space['niche'].to_i
          columna = space['column'].to_i
          next unless limites_nichos[nicho] && columna.between?(0, num_divisiones)

          x_min = grosor_lat_izq + (columna * (ancho_celda + espesor))
          z_min, z_max = limites_nichos[nicho]
          altura_celda = z_max - z_min
          next if altura_celda <= ((cantidad_repisas_celda + 1) * espesor)

          distancia_local = (altura_celda - (cantidad_repisas_celda * espesor)) / (cantidad_repisas_celda + 1)
          (1..cantidad_repisas_celda).each do |indice_repisa|
            z_repisa_celda = z_min + (indice_repisa * distancia_local) + ((indice_repisa - 1) * espesor)
            self.crear_pieza(
              entities, modulo_nombre, "REPISA_CELDA_#{nicho + 1}_#{columna + 1}_#{indice_repisa}",
              ancho_celda, prof_repisa_descontada, espesor,
              x_min, 0.mm, z_repisa_celda,
              rep_l, rep_c
            )
          end
        end
        spaces_config.each do |space|
          contenido = space['content'].to_s.upcase
          next unless contenido.start_with?('PUERTA')
          nicho = space['niche'].to_i
          columna = space['column'].to_i
          next unless limites_nichos[nicho] && columna.between?(0, num_divisiones)

          x_min = grosor_lat_izq + (columna * (ancho_celda + espesor))
          z_min, z_max = limites_nichos[nicho]
          caja_celda = Geom::BoundingBox.new
          caja_celda.add(
            Geom::Point3d.new(offset_celda.x + x_min, offset_celda.y, offset_celda.z + z_min),
            Geom::Point3d.new(offset_celda.x + x_min + ancho_celda, offset_celda.y + prof_total, offset_celda.z + z_max)
          )
          cantidad = contenido.include?('DOBLE') ? 2 : 1
          fuga_celda = [(space['gap'] || datos['luz_perimetral'] || 1.5).to_f, 0.5].max.mm
          inicio_puertas = @piezas_modulo_actual.length
          self.crear_puertas_en_caja(entities, modulo_nombre, caja_celda, grosor_puerta_celda, lado_puerta_celda, nil, nil, cantidad, fuga_celda, (datos['montaje_puerta'] || 'SOLAPADA'))
          puertas_celda = @piezas_modulo_actual[inicio_puertas..-1] || []
          puertas_celda.each { |puerta| self.aplicar_material_vidrio(puerta) } if contenido.include?('VIDRIO')
          datos_celda = datos.merge('sistema_apertura' => (space['opening'] || datos['sistema_apertura']))
          self.agregar_sistema_apertura(entities, modulo_nombre, caja_celda, puertas_celda, datos_celda)
        end
      end

      if !hierarchy_geometry && spaces_config.empty? && datos['crear_puerta'] == "SI"
        lado_puerta = datos['puerta_bisagra'] == "Derecha" ? :derecha : :izquierda
        grosor_puerta = (datos['puerta_grosor'] || 15).to_f.mm
        tipo_puerta = (datos['tipo_puerta'] || "AUTO").to_s.upcase
        cantidad_puertas = if tipo_puerta == "UNICA" || tipo_puerta == "VIDRIO"
                             1
                           elsif tipo_puerta == "DOBLE" || tipo_puerta == "DOBLE_VIDRIO"
                             2
                           else
                             nil
                           end
        z_min_puerta = zonas_frentes_cajon.empty? ? nil : zonas_frentes_cajon.map { |zona| zona[1] }.max
        unless caja_modulo_estructura.empty?
          inicio_puertas = @piezas_modulo_actual.length
          montaje_puerta_modulo = (datos['montaje_puerta'] || 'SOLAPADA').to_s.upcase
          fuga_puertas = montaje_puerta_modulo == 'EMBUTIDA' ? (datos['luz_perimetral'] || datos['juego_general'] || 3).to_f.mm : (datos['luz_solape'] || 1.5).to_f.mm
          luz_superior = (datos['luz_sup_frente'] || 0).to_f.mm
          z_max_puerta = caja_modulo_estructura.max.z - luz_superior
          self.crear_puertas_en_caja(entities, modulo_nombre, caja_modulo_estructura, grosor_puerta, lado_puerta, z_min_puerta, z_max_puerta, cantidad_puertas, fuga_puertas, montaje_puerta_modulo)
          puertas_creadas = @piezas_modulo_actual[inicio_puertas..-1] || []
          if tipo_puerta.include?("VIDRIO")
            puertas_creadas.each { |puerta| self.aplicar_material_vidrio(puerta) }
          end
          self.agregar_sistema_apertura(entities, modulo_nombre, caja_modulo_estructura, puertas_creadas, datos)
        end
      end

      source = datos['__manifest_source'].to_s.empty? ? (datos['__legacy_migration'].to_s == 'SI' ? 'MIGRATED' : 'PARAMETRICO') : datos['__manifest_source'].to_s
      manifiesto = crear_manifiesto(@datos_modulo_actual, modulo_nombre, @modulo_uuid_actual, source)
      manifiesto['piece_inventory'] = inventario_geometrico(@piezas_modulo_actual)
      contenedor = encapsular_modulo(entities, @piezas_modulo_actual, manifiesto)
      contenedor.transformation = @transformacion_edicion if contenedor && actualizar_existente && @transformacion_edicion
      @ultimo_modulo_piezas = contenedor ? [contenedor] : @piezas_modulo_actual
      if contenedor
        model.selection.clear
        model.selection.add(contenedor)
      end
      unless datos['view_snapshot'].to_s.empty?
        model.set_attribute('Modular3DViews', @modulo_despiece_actual.to_s, datos['view_snapshot'].to_s)
        model.set_attribute('Modular3DViewCameras', @modulo_despiece_actual.to_s, datos['view_camera_json'].to_s)
      end
      @piezas_modulo_actual = nil
      @offset_creacion = nil
      @modulo_despiece_actual = nil
      @datos_modulo_actual = nil
      @modulo_uuid_actual = nil
      @contenedor_edicion = nil
      @transformacion_edicion = nil
      @offset_edicion = nil if actualizar_existente
      model.commit_operation
      operacion_iniciada = false
      rescue => e
        model.abort_operation if operacion_iniciada
        @piezas_modulo_actual = nil
        @offset_creacion = nil
        @modulo_despiece_actual = nil
        @datos_modulo_actual = nil
        @offset_edicion = nil
        @seleccion_edicion = nil
        @transformacion_edicion = nil
        UI.messagebox("Modular_3D no pudo completar la operación:\n\n#{e.class}: #{e.message}")
      end
    end

    dialogo.show
    perfiles_json = JSON.generate(Modular3D::Profiles.listar)
    UI.start_timer(0.35, false) do
      begin
        dialogo.execute_script("window.__modular3dProfiles = #{perfiles_json}; if (window.Modular3DApplyProfileList) { window.Modular3DApplyProfileList(window.__modular3dProfiles); }") if dialogo
      rescue
        nil
      end
    end
    if datos_iniciales && !datos_iniciales.empty?
      datos_json = JSON.generate(datos_iniciales)
      script = "window.__modular3dInitial = #{datos_json}; if (window.Modular3DLoadInitial) { window.Modular3DLoadInitial(window.__modular3dInitial); }"
      UI.start_timer(0.4, false) do
        begin
          dialogo.execute_script(script) if dialogo
        rescue
          nil
        end
      end
    end
  end

  # --- EDICIÓN POR LOTES (repintado) ---
  # Alcance deliberadamente acotado: repinta piezas existentes de varios
  # módulos Modular_3D seleccionados a la vez, sin tocar dimensiones. Un
  # cambio de medidas por lote implicaría reconstruir la geometría completa
  # de cada módulo con la misma lógica de ejecutarConstruccionMueble, que
  # vive dentro del callback del diálogo principal; separarla seguiría
  # siendo posible más adelante, pero no de forma segura sin poder probarlo
  # en vivo dentro de SketchUp. El repintado, en cambio, solo reasigna
  # material a piezas que ya existen y es seguro de principio a fin.
  def self.recolectar_instancias_piezas(entity, instancias)
    if entity.respond_to?(:definition) && entity.definition && entity.definition.get_attribute('LPenafiel', 'pieza_original')
      instancias << entity
      return
    end
    if entity.respond_to?(:entities)
      entity.entities.each { |hijo| recolectar_instancias_piezas(hijo, instancias) }
    elsif entity.respond_to?(:definition) && entity.definition
      entity.definition.entities.each { |hijo| recolectar_instancias_piezas(hijo, instancias) }
    end
  end

  def self.repintar_modulos_seleccionados(color_hex, nombre_material)
    return { ok: false, message: 'Color hexadecimal inválido (usa el formato #RRGGBB).' } unless color_hex.to_s.match?(/\A#[0-9a-fA-F]{6}\z/)

    model = Sketchup.active_model
    seleccion = model.selection.to_a
    modulos_afectados = 0
    piezas_afectadas = 0
    operacion_iniciada = false
    begin
      model.start_operation('Repintar módulos Modular_3D (lote)', true)
      operacion_iniciada = true
      seleccion.each do |entity|
        manifiesto = manifiesto_de_entidad(entity)
        next unless manifiesto && manifiesto['data'].is_a?(Hash)

        datos_actualizados = manifiesto['data'].dup
        datos_actualizados['material_unico'] = 'SI'
        datos_actualizados['material_global_color'] = color_hex
        datos_actualizados['material_global_nombre'] = nombre_material.to_s.strip.empty? ? 'Color de lote' : nombre_material.to_s.strip
        @datos_modulo_actual = datos_actualizados

        instancias = []
        recolectar_instancias_piezas(entity, instancias)
        instancias.each do |instancia|
          nombre_original = instancia.definition.get_attribute('LPenafiel', 'pieza_original')
          next unless nombre_original
          self.aplicar_material_configurado(instancia, nombre_original)
          piezas_afectadas += 1
        end

        manifiesto_nuevo = manifiesto.dup
        manifiesto_nuevo['data'] = datos_actualizados
        raw = JSON.generate(manifiesto_nuevo)
        [entity, (entity.respond_to?(:definition) ? entity.definition : nil)].compact.each do |objeto|
          objeto.set_attribute('Modular3D', 'manifest', raw)
        end
        modulos_afectados += 1
      end
      model.commit_operation
      operacion_iniciada = false
    rescue StandardError => e
      model.abort_operation if operacion_iniciada
      return { ok: false, message: "No se pudo repintar: #{e.message}" }
    ensure
      @datos_modulo_actual = nil
    end

    return { ok: false, message: 'La selección no contiene módulos Modular_3D reconocibles. Selecciona uno o más grupos/componentes creados con Modular_3D.' } if modulos_afectados.zero?

    { ok: true, message: "#{modulos_afectados} módulo(s) y #{piezas_afectadas} pieza(s) repintadas." }
  end

  def self.mostrar_edicion_lotes
    return unless acceso_autorizado?

    html = <<-HTML
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
  body { font-family: Segoe UI, Arial, sans-serif; margin: 18px; color: #111827; background: #f8fafc; }
  h2 { margin: 0 0 4px 0; }
  p.hint { color: #64748b; font-size: 12px; margin: 0 0 16px 0; }
  .row { display: grid; grid-template-columns: 140px 1fr; align-items: center; gap: 10px; margin-bottom: 10px; }
  input { border: 1px solid #cbd5e1; border-radius: 5px; padding: 6px 8px; font-size: 13px; }
  button { border: 1px solid #1d4ed8; background: #1d4ed8; color: #fff; border-radius: 6px; padding: 9px 16px; font-size: 13px; cursor: pointer; }
  #mensaje { display: none; margin-top: 12px; padding: 8px 10px; border-radius: 6px; font-size: 12px; background: #ecfdf5; color: #065f46; border: 1px solid #a7f3d0; }
  #mensaje.error { background: #fef2f2; color: #991b1b; border-color: #fecaca; }
</style>
</head>
<body>
  <h2>Edición por lotes</h2>
  <p class="hint">Repinta todas las piezas de los módulos Modular_3D seleccionados con un mismo color/material. Selecciona primero dos o más módulos en el modelo (Ctrl/Shift + clic) antes de aplicar.</p>
  <div class="row"><label>Color</label><input id="lote_color" type="color" value="#d5a66e"></div>
  <div class="row"><label>Nombre del material</label><input id="lote_nombre" placeholder="Ej. Blanco mate"></div>
  <button onclick="aplicar()">Aplicar a la selección</button>
  <div id="mensaje"></div>
  <script>
    function aplicar() {
      sketchup.loteRepintar(document.getElementById('lote_color').value, document.getElementById('lote_nombre').value);
    }
    window.Modular3DBatchResult = function (resultado) {
      var el = document.getElementById('mensaje');
      el.textContent = resultado.message;
      el.className = resultado.ok ? '' : 'error';
      el.style.display = 'block';
    };
  </script>
</body>
</html>
    HTML

    dialogo = UI::HtmlDialog.new({
      :dialog_title => "#{Modular3D::PRODUCT_NAME} | Edición por lotes",
      :preferences_key => 'com.lpenafiel.modular3d.lotes',
      :scrollable => true,
      :resizable => true,
      :width => 420,
      :height => 320,
      :style => UI::HtmlDialog::STYLE_WINDOW
    })
    dialogo.set_html(html)
    dialogo.add_action_callback('loteRepintar') do |_action_context, color, nombre|
      resultado = self.repintar_modulos_seleccionados(color, nombre)
      dialogo.execute_script("window.Modular3DBatchResult(#{JSON.generate(resultado)})")
    end
    dialogo.show
  end

  def self.datos_desde_seleccion_para_editar
    model = Sketchup.active_model
    seleccion = model.selection
    return nil if seleccion.empty?

    # Los módulos nuevos conservan una única fuente de verdad en el contenedor.
    seleccion.each do |entity|
      manifiesto = manifiesto_de_entidad(entity)
      next unless manifiesto && manifiesto['data'].is_a?(Hash)
      @contenedor_edicion = entity
      @seleccion_edicion = [entity]
      base = manifiesto['data']['module_base_offset']
      @offset_edicion = if base.is_a?(Array) && base.length == 3
                          Geom::Vector3d.new(base[0].to_f.mm, base[1].to_f.mm, base[2].to_f.mm)
                        else
                          Geom::Vector3d.new(entity.bounds.min.x, entity.bounds.min.y, entity.bounds.min.z)
                        end
      @transformacion_edicion = entity.transformation
      @modulo_uuid_actual = manifiesto['uuid']
      datos = manifiesto['data'].dup
      datos['modulo_nombre'] = manifiesto['name'] unless manifiesto['name'].to_s.empty?
      datos['__edit_mode'] = 'SI'
      datos['__manifest_uuid'] = manifiesto['uuid']
      datos['__manifest_source'] = manifiesto['source']
      esperado = manifiesto['piece_inventory'] || []
      actual = inventario_geometrico(entity)
      datos['__modified_outside'] = 'SI' unless esperado.empty? || esperado == actual
      return datos
    end

    datos_guardados = nil
    seleccion.each do |entity|
      piezas_temp = []
      recolectar_piezas_despiece(entity, piezas_temp)
      pieza_con_datos = piezas_temp.find { |pieza| pieza[:datos_modulo].to_s.strip.length > 0 }
      if pieza_con_datos
        begin
          datos_guardados = JSON.parse(pieza_con_datos[:datos_modulo].to_s)
        rescue
          datos_guardados = nil
        end
        break if datos_guardados
      end
    end

    piezas = []
    seleccion.each { |entity| recolectar_piezas_despiece(entity, piezas) }
    caja = Geom::BoundingBox.new
    seleccion.each { |entity| caja.add(entity.bounds) if entity.respond_to?(:bounds) }
    return nil if caja.empty?

    @seleccion_edicion = seleccion.to_a
    @offset_edicion = Geom::Vector3d.new(caja.min.x, caja.min.y, caja.min.z)
    if datos_guardados
      @modulo_uuid_actual = datos_guardados['module_uuid'] || SecureRandom.uuid
      datos_guardados["__edit_mode"] = "SI"
      datos_guardados["__legacy_migration"] = "SI"
      datos_guardados["__manifest_uuid"] = @modulo_uuid_actual
      return datos_guardados
    end

    modulo = modulo_de_seleccion(seleccion)
    repisas = piezas.count { |pieza| pieza[:pieza_original].to_s.upcase.start_with?("REPISA") }
    divisiones = piezas.count { |pieza| pieza[:pieza_original].to_s.upcase.start_with?("DIV_VERT") }
    puertas = piezas.count { |pieza| pieza[:pieza_original].to_s.upcase.start_with?("PUERTA") }
    frentes = piezas.count { |pieza| pieza[:pieza_original].to_s.upcase.start_with?("CJ_FRENTE_EXTERIOR") }
    cajones = piezas.count { |pieza| pieza[:pieza_original].to_s.upcase.start_with?("CJ_LAT_IZQ") }
    nichos = [repisas + 1, 1].max
    cajones_por_nicho = Array.new(nichos, 0)
    cajones_por_nicho[0] = cajones
    tipos = Array.new(nichos, frentes.positive? ? "FRENTES" : "INTERNO")

    {
      "modulo_nombre" => modulo.to_s.empty? ? "MODULO" : modulo,
      "tipo_modulo" => caja.height.to_mm > 1200 ? "CLOSET" : "BAJO",
      "ancho_total" => dimension_mm(caja.width),
      "alto_total" => dimension_mm(caja.height),
      "prof_total" => dimension_mm(caja.depth),
      "num_repisas" => repisas,
      "num_divisiones" => divisiones,
      "crear_puerta" => puertas.positive? ? "SI" : "NO",
      "tipo_puerta" => puertas > 1 ? "DOBLE" : "UNICA",
      "cajones_por_nicho" => cajones_por_nicho.join(","),
      "tipos_cajon_por_nicho" => tipos.join(","),
      "modo_frentes" => frentes.positive? ? "TODOS" : "POR_NICHO",
      "__edit_mode" => "SI"
    }
  end

  def self.editar_modulo_desde_seleccion
    datos = datos_desde_seleccion_para_editar
    unless datos
      UI.messagebox("Selecciona primero un grupo, componente o piezas del modulo que deseas editar.")
      return
    end

    mostrar_interfaz_moderna(datos)
  end

  # --- DISEÑO LIBRE: ETIQUETAR PIEZA MANUAL ---
  # Paso "2. Etiquetar pieza manual" del flujo de diseño libre: en vez de un
  # tool interactivo de mouse (arriesgado de escribir a ciegas, sin poder
  # probarlo dentro de SketchUp), usa UI.inputbox -API estable y ya probada
  # de SketchUp- para asignarle a cualquier grupo/componente dibujado a mano
  # los mismos atributos LPenafiel que crear_pieza genera automáticamente,
  # de modo que el despiece, el presupuesto y el optimizador de corte lo
  # reconozcan igual que a una pieza paramétrica. El paso "1. Crear volumen
  # guía" no necesita herramienta propia: se dibuja con las herramientas
  # nativas de SketchUp (rectángulo + empujar/tirar) y se etiqueta aquí; el
  # paso "3. Empaquetar a módulo" ya existía como convertir_seleccion_en_modulo.
  def self.etiquetar_pieza_seleccionada
    model = Sketchup.active_model
    entidad = model.selection.to_a.find { |item| item.respond_to?(:definition) && item.definition }
    unless entidad
      UI.messagebox('Selecciona un único grupo o componente (una pieza dibujada a mano) para etiquetarlo.')
      return
    end

    definicion = entidad.definition
    nombre_actual = definicion.get_attribute('LPenafiel', 'pieza_original').to_s
    resultado = UI.inputbox(
      ['Nombre de la pieza:', 'Cantos en los lados largos (0-2):', 'Cantos en los lados cortos (0-2):'],
      [nombre_actual.empty? ? 'PIEZA_LIBRE' : nombre_actual, '2', '2'],
      'Etiquetar pieza para despiece'
    )
    return unless resultado

    nombre = resultado[0].to_s.strip.upcase.gsub(/\s+/, '_')
    return UI.messagebox('El nombre no puede quedar vacío.') if nombre.empty?

    cantos_l = [[resultado[1].to_i, 0].max, 2].min
    cantos_c = [[resultado[2].to_i, 0].max, 2].min
    caja = entidad.bounds
    dimensiones = dimensiones_tablero(caja.width, caja.depth, caja.height)
    placa = placa_mm(caja.width, caja.depth, caja.height)
    codigo = codigo_pieza(nombre)
    nombre_definicion = nombre_pieza(codigo, dimensiones, cantos_l, cantos_c)

    model.start_operation('Etiquetar pieza de diseño libre', true)
    definicion.name = nombre_definicion
    definicion.description = "#{cantos_l}L-#{cantos_c}C"
    definicion.set_attribute('LPenafiel', 'pieza_original', nombre)
    definicion.set_attribute('LPenafiel', 'codigo', codigo)
    definicion.set_attribute('LPenafiel', 'dimension_1_mm', dimensiones[0])
    definicion.set_attribute('LPenafiel', 'dimension_2_mm', dimensiones[1])
    definicion.set_attribute('LPenafiel', 'placa_mm', placa)
    definicion.set_attribute('LPenafiel', 'cantos_largos', cantos_l)
    definicion.set_attribute('LPenafiel', 'cantos_cortos', cantos_c)
    definicion.set_attribute('LPenafiel', 'modulo', 'DISENO_LIBRE')
    definicion.set_attribute('LPenafiel', 'modulo_despiece', 'DISENO_LIBRE')
    entidad.name = nombre_definicion if entidad.respond_to?(:name=)
    model.commit_operation
    UI.messagebox("Pieza etiquetada como #{nombre_definicion}. Ya aparecerá en Despiece y Presupuesto.")
  end

  def self.clasificar_pieza_externa(entity, caja_modulo, tolerancia)
    return 'PIEZA' unless entity.respond_to?(:bounds)
    caja = entity.bounds
    dx = caja.width.to_mm; dy = caja.depth.to_mm; dz = caja.height.to_mm
    if dz >= caja_modulo.height.to_mm * 0.65 && [dx, dy].min <= tolerancia
      return caja.center.x < caja_modulo.center.x ? 'LATERAL_IZQUIERDO' : 'LATERAL_DERECHO'
    end
    if dx >= caja_modulo.width.to_mm * 0.65 && [dy, dz].min <= tolerancia
      return caja.center.z < caja_modulo.center.z ? 'BASE' : 'TAPA'
    end
    return 'RESPALDO' if dx >= caja_modulo.width.to_mm * 0.6 && dz >= caja_modulo.height.to_mm * 0.6 && dy <= tolerancia
    return 'REPISA' if dx >= caja_modulo.width.to_mm * 0.45 && dz <= tolerancia
    return 'DIVISION' if dz >= caja_modulo.height.to_mm * 0.3 && dx <= tolerancia
    'PIEZA_SIN_CLASIFICAR'
  end

  CODIGOS_ROL_EXTERNO = {
    'LATERAL_IZQUIERDO' => 'LAT', 'LATERAL_DERECHO' => 'LAT', 'BASE' => 'BAS', 'TAPA' => 'TEC',
    'RESPALDO' => 'RES', 'REPISA' => 'REP', 'DIVISION' => 'DIV', 'PIEZA_SIN_CLASIFICAR' => 'PZA', 'PIEZA' => 'PZA'
  }.freeze

  # Encuentra las piezas "de verdad" a etiquetar dentro de una selección: si
  # el usuario seleccionó varios grupos/componentes (una pieza por tablero,
  # la práctica normal en SketchUp), cada uno es una pieza. Si seleccionó UN
  # solo grupo que por dentro contiene varios grupos/componentes hijos (todo
  # el mueble agrupado de una vez), se baja un nivel y se etiqueta cada hijo
  # en vez del contenedor entero. Geometría suelta sin agrupar (caras/aristas
  # directamente en el modelo) no se puede separar en piezas de forma
  # confiable, así que se reporta aparte para avisarle al usuario.
  def self.recolectar_piezas_para_importar(seleccion)
    piezas = []
    sin_agrupar = 0
    seleccion.each do |entity|
      if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        hijos = entity.respond_to?(:definition) && entity.definition ? entity.definition.entities : []
        subgrupos = hijos.select { |hijo| hijo.is_a?(Sketchup::Group) || hijo.is_a?(Sketchup::ComponentInstance) }
        if subgrupos.length > 1 && subgrupos.length == hijos.to_a.reject { |h| h.is_a?(Sketchup::Edge) }.length
          piezas.concat(subgrupos)
        else
          piezas << entity
        end
      elsif entity.respond_to?(:bounds)
        sin_agrupar += 1
      end
    end
    [piezas, sin_agrupar]
  end

  # Migración real de piezas dibujadas fuera del plugin: no basta con
  # encapsular la selección en un grupo con un manifiesto -eso solo describe
  # el módulo como conjunto-, cada pieza necesita los mismos atributos
  # LPenafiel que crear_pieza le pone a una pieza paramétrica (codigo,
  # dimensiones, placa, cantos) para que datos_pieza_para_despiece la
  # reconozca y aparezca en Despiece/Presupuesto/Optimizador. Sin esto, un
  # mueble importado quedaba visualmente correcto pero invisible para esas
  # herramientas.
  def self.etiquetar_piezas_importadas(seleccion, caja_modulo, tolerancia, modulo_nombre)
    contador_por_codigo = Hash.new(0)
    seleccion.each do |entity|
      next unless entity.respond_to?(:definition) && entity.definition && entity.respond_to?(:bounds)

      definicion = entity.definition
      siguiente = definicion.get_attribute('LPenafiel', 'codigo').to_s
      next unless siguiente.empty? # conserva piezas que ya vinieran etiquetadas (p. ej. de otro módulo Modular_3D)

      rol = clasificar_pieza_externa(entity, caja_modulo, tolerancia)
      codigo = CODIGOS_ROL_EXTERNO[rol] || 'PZA'
      contador_por_codigo[codigo] += 1
      nombre_pieza_original = "#{rol}_#{contador_por_codigo[codigo]}"

      caja = entity.bounds
      dimensiones = dimensiones_tablero(caja.width, caja.depth, caja.height)
      placa = placa_mm(caja.width, caja.depth, caja.height)
      cantos_l = 2
      cantos_c = 2
      nombre_definicion = nombre_pieza(codigo, dimensiones, cantos_l, cantos_c)

      definicion.name = nombre_definicion if definicion.respond_to?(:name=)
      definicion.description = "#{cantos_l}L-#{cantos_c}C · #{rol}"
      definicion.set_attribute('LPenafiel', 'modulo', modulo_nombre)
      definicion.set_attribute('LPenafiel', 'modulo_despiece', modulo_nombre)
      definicion.set_attribute('LPenafiel', 'pieza_original', nombre_pieza_original)
      definicion.set_attribute('LPenafiel', 'codigo', codigo)
      definicion.set_attribute('LPenafiel', 'dimension_1_mm', dimensiones[0])
      definicion.set_attribute('LPenafiel', 'dimension_2_mm', dimensiones[1])
      definicion.set_attribute('LPenafiel', 'placa_mm', placa)
      definicion.set_attribute('LPenafiel', 'cantos_largos', cantos_l)
      definicion.set_attribute('LPenafiel', 'cantos_cortos', cantos_c)
      entity.name = nombre_definicion if entity.respond_to?(:name=)
    end
  end

  def self.convertir_seleccion_en_modulo
    model = Sketchup.active_model
    seleccion = model.selection.to_a
    if seleccion.empty?
      UI.messagebox('Selecciona las piezas o el grupo que deseas convertir.')
      return
    end
    if seleccion.any? { |entity| manifiesto_de_entidad(entity) }
      UI.messagebox('La selección ya contiene un módulo paramétrico Modular_3D.')
      return
    end
    caja = Geom::BoundingBox.new
    seleccion.each { |entity| caja.add(entity.bounds) if entity.respond_to?(:bounds) }
    return UI.messagebox('No se pudo calcular el volumen de la selección.') if caja.empty?
    nombre = UI.inputbox(['Nombre del módulo:'], ['MODULO_IMPORTADO'], [''], 'Convertir selección en módulo Modular_3D')
    return unless nombre
    modulo_nombre = nombre[0].to_s.strip.upcase.gsub(' ', '_')
    modulo_nombre = 'MODULO_IMPORTADO' if modulo_nombre.empty?

    # Si proviene de una versión anterior se recupera el JSON completo.
    piezas = []
    seleccion.each { |entity| recolectar_piezas_despiece(entity, piezas) }
    raw_guardado = piezas.map { |pieza| pieza[:datos_modulo].to_s }.find { |raw| !raw.strip.empty? }
    datos = begin
      raw_guardado ? JSON.parse(raw_guardado) : nil
    rescue JSON::ParserError
      nil
    end
    source = datos ? 'MIGRATED' : 'IMPORTED'
    piezas_a_etiquetar, sin_agrupar = recolectar_piezas_para_importar(seleccion)
    unless datos
      menores = piezas_a_etiquetar.map do |entity|
        next unless entity.respond_to?(:bounds)
        [entity.bounds.width, entity.bounds.depth, entity.bounds.height].map(&:to_mm).select { |v| v > 0.5 }.min
      end.compact.sort
      espesor = menores.empty? ? 15.0 : menores[menores.length / 2]
      tolerancia = [espesor * 1.8, 30.0].max
      inventario = piezas_a_etiquetar.map.with_index do |entity, index|
        b = entity.bounds
        {'id' => "imported_#{index + 1}", 'role' => clasificar_pieza_externa(entity, caja, tolerancia), 'name' => (entity.respond_to?(:name) ? entity.name.to_s : ''), 'w' => b.width.to_mm.round(2), 'd' => b.depth.to_mm.round(2), 'h' => b.height.to_mm.round(2)}
      end
      raiz = {'id'=>'root','name'=>'Módulo','content'=>'VACIO','front'=>'NINGUNO','drawers'=>0,'shelves'=>0,'gap'=>3,'enclosure'=>{},'children'=>[]}
      datos = {
        'modulo_nombre'=>modulo_nombre, 'tipo_modulo'=>(caja.height.to_mm > 1200 ? 'CLOSET' : 'BAJO'),
        'ancho_total'=>caja.width.to_mm.round(2), 'alto_total'=>caja.height.to_mm.round(2), 'prof_total'=>caja.depth.to_mm.round(2),
        'espesor'=>espesor.round(2), 'grosor_izq'=>espesor.round(2), 'grosor_der'=>espesor.round(2),
        'grosor_superior'=>espesor.round(2), 'grosor_inferior'=>espesor.round(2),
        'hierarchy_json'=>JSON.generate(raiz), 'external_inventory_json'=>JSON.generate(inventario),
        'material_unico'=>'NO', 'conversion_requires_review'=>'SI'
      }
    end
    datos['modulo_nombre'] = modulo_nombre
    datos['module_uuid'] ||= SecureRandom.uuid
    manifiesto = crear_manifiesto(datos, modulo_nombre, datos['module_uuid'], source)
    model.start_operation('Convertir selección en módulo Modular_3D', true)
    begin
      etiquetar_piezas_importadas(piezas_a_etiquetar, caja, [datos['espesor'].to_f * 1.8, 30.0].max, modulo_nombre) if source == 'IMPORTED'
      contenedor = encapsular_modulo(model.active_entities, seleccion, manifiesto)
      model.selection.clear
      model.selection.add(contenedor) if contenedor
      model.commit_operation
      mensaje = if source == 'MIGRATED'
                  'Módulo anterior migrado. Selecciónalo y pulsa Editar módulo.'
                else
                  "Selección encapsulada y #{piezas_a_etiquetar.length} pieza(s) etiquetada(s) para despiece (lateral/base/techo/repisa/respaldo según su tamaño). Revisa la clasificación desde Despiece y corrígela ahí si alguna quedó mal."
                end
      mensaje += "\n\nAviso: #{sin_agrupar} elemento(s) de la selección no estaban agrupados como piezas independientes y no se pudieron etiquetar por separado; agrúpalos (clic derecho > Crear grupo) y vuelve a convertir." if sin_agrupar.positive?
      UI.messagebox(mensaje)
    rescue StandardError => error
      model.abort_operation
      UI.messagebox("No se pudo convertir la selección:\n#{error.message}")
    end
  end

  # --- ASIGNACIÓN DE ÍCONOS ---
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
    formula_click = "ANIMATE(\"RotZ\",0,#{giro / 2},#{giro},0)"

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

  def self.aplicar_material_vidrio(instancia)
    model = Sketchup.active_model
    material = model.materials["Modular_3D_Vidrio"] || model.materials.add("Modular_3D_Vidrio")
    material.color = Sketchup::Color.new(150, 210, 230)
    material.alpha = 0.35
    instancia.material = material if instancia.respond_to?(:material=)
    if instancia.respond_to?(:definition)
      instancia.definition.entities.grep(Sketchup::Face).each do |face|
        face.material = material
        face.back_material = material
      end
      instancia.definition.set_attribute("LPenafiel", "material_especial", "VIDRIO")
    end
    instancia
  end

  def self.agregar_sistema_apertura(entities, modulo_nombre, caja_total, puertas, datos)
    sistema = (datos['sistema_apertura'] || "AUTOMATICO").to_s.upcase
    return if sistema == "PUSH" || puertas.empty?

    if sistema == "GOLA"
      alto = [(datos['alto_perfil_gola'] || 47).to_f, 10].max.mm
      fondo = [(datos['prof_gola'] || 50).to_f, 10].max.mm
      offset = @offset_creacion || Geom::Vector3d.new(0, 0, 0)
      self.crear_pieza(
        entities, modulo_nombre, "PERFIL_GOLA",
        caja_total.width, fondo, alto,
        caja_total.min.x - offset.x,
        caja_total.min.y - offset.y - fondo,
        caja_total.max.z - offset.z - alto,
        0, 0
      )
      return
    end

    alto_jalador = [(datos['alto_jalador'] || 30).to_f, 10].max.mm
    puertas.each_with_index do |puerta, indice|
      next unless puerta.respond_to?(:bounds)
      caja = puerta.bounds
      ancho_jalador = [caja.width * 0.32, 120.mm].min
      x = caja.center.x - (ancho_jalador / 2.0)
      y = caja.min.y - 8.mm
      z = caja.center.z - (alto_jalador / 2.0)
      offset = @offset_creacion || Geom::Vector3d.new(0, 0, 0)
      self.crear_pieza(entities, modulo_nombre, "JALADOR_#{indice + 1}", ancho_jalador, 8.mm, alto_jalador, x - offset.x, y - offset.y, z - offset.z, 0, 0)
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

  def self.modulo_de_seleccion(seleccion)
    piezas = []
    seleccion.each { |entity| recolectar_piezas_despiece(entity, piezas) }
    modulos = piezas.map { |pieza| pieza[:modulo].to_s }.reject(&:empty?).uniq
    return modulos.first if modulos.length == 1
    @nombre_modulo_guardado || "MODULO"
  end

  def self.html_escape(texto)
    texto.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;").gsub("'", "&#39;")
  end

  def self.material_pieza(entity)
    nombres = []
    nombres << entity.material.display_name if entity.respond_to?(:material) && entity.material

    if entity.respond_to?(:definition) && entity.definition
      entity.definition.entities.each do |item|
        next unless item.respond_to?(:material)
        nombres << item.material.display_name if item.material
        nombres << item.back_material.display_name if item.respond_to?(:back_material) && item.back_material
      end
    end

    nombres.compact!
    nombres.uniq!
    return "SIN MATERIAL" if nombres.empty?
    return nombres.first if nombres.length == 1
    "VARIOS"
  end

  def self.datos_pieza_para_despiece(entity)
    return nil unless entity.respond_to?(:definition) && entity.definition
    definicion = entity.definition
    codigo = definicion.get_attribute("LPenafiel", "codigo")
    return nil unless codigo && !codigo.to_s.empty?

    {
      :modulo => definicion.get_attribute("LPenafiel", "modulo_despiece") || definicion.get_attribute("LPenafiel", "modulo") || "SIN_MODULO",
      :codigo => codigo.to_s,
      :medida_1 => definicion.get_attribute("LPenafiel", "dimension_1_mm").to_i,
      :medida_2 => definicion.get_attribute("LPenafiel", "dimension_2_mm").to_i,
      :placa => definicion.get_attribute("LPenafiel", "placa_mm").to_i,
      :canto_1 => definicion.get_attribute("LPenafiel", "cantos_largos").to_i,
      :canto_2 => definicion.get_attribute("LPenafiel", "cantos_cortos").to_i,
      :pieza_original => definicion.get_attribute("LPenafiel", "pieza_original") || definicion.name,
      :datos_modulo => definicion.get_attribute("LPenafiel", "datos_modulo"),
      :material => material_pieza(entity),
      :tipo_canto => definicion.get_attribute("LPenafiel", "tipo_canto") || "PVC",
      :color_canto => definicion.get_attribute("LPenafiel", "color_canto") || definicion.get_attribute("LPenafiel", "color_configurado"),
      :inglete => etiqueta_inglete(definicion.get_attribute("LPenafiel", "inglete_esquina"), definicion.get_attribute("LPenafiel", "inglete_medida_mm"))
    }
  end

  ETIQUETAS_ESQUINA_INGLETE = {
    'front_left' => 'Del.Izq 45°', 'front_right' => 'Del.Der 45°',
    'back_left' => 'Post.Izq 45°', 'back_right' => 'Post.Der 45°',
    'bottom_outer' => 'Inf.Ext 45° (con base)', 'bottom_inner' => 'Inf.Int 45° (con base)',
    'top_outer' => 'Sup.Ext 45° (con techo)', 'top_inner' => 'Sup.Int 45° (con techo)'
  }.freeze

  def self.etiqueta_inglete(esquina, medida_mm)
    return '' if esquina.to_s.empty? || medida_mm.to_i <= 0
    "#{ETIQUETAS_ESQUINA_INGLETE[esquina.to_s] || "#{esquina} 45°"} (#{medida_mm.to_i}mm)"
  end

  def self.recolectar_piezas_despiece(entity, piezas)
    datos = datos_pieza_para_despiece(entity)
    if datos
      piezas << datos
      return
    end

    if entity.respond_to?(:entities)
      entity.entities.each { |hijo| recolectar_piezas_despiece(hijo, piezas) }
    elsif entity.respond_to?(:definition) && entity.definition
      entity.definition.entities.each { |hijo| recolectar_piezas_despiece(hijo, piezas) }
    end
  end

  def self.exportar_despiece_excel(filas)
    path = UI.savepanel("Guardar despiece compatible con Excel", "", "despiece.csv")
    return unless path
    path += ".csv" unless File.extname(path).downcase == ".csv"

    contenido = CSV.generate(:col_sep => ';', :force_quotes => true) do |csv|
      csv << ['Módulo', 'Nombre', 'Cantidad', 'Medida 1', 'Canto 1', 'Medida 2', 'Canto 2', 'Placa', 'Material', 'Tipo canto', 'Color canto', 'Inglete']
      filas.each do |fila|
        csv << %w[modulo nombre cantidad medida1 canto1 medida2 canto2 placa material tipo_canto color_canto inglete].map { |clave| fila[clave] }
      end
    end
    File.binwrite(path, "\xEF\xBB\xBF".b + contenido.encode('UTF-8'))
    UI.messagebox("Despiece exportado como CSV compatible con Excel.")
  end

  def self.exportar_despiece_pdf(filas)
    path = UI.savepanel("Guardar despiece PDF", "", "despiece.pdf")
    return unless path
    path += ".pdf" unless File.extname(path).downcase == ".pdf"

    html_path = File.join(Dir.tmpdir, "despiece_modular3d_#{Process.pid}_#{Time.now.to_i}.html")
    File.write(html_path, html_despiece_exportable(filas, false, false))

    edge_paths = [
      File.join(ENV["ProgramFiles"].to_s, "Microsoft", "Edge", "Application", "msedge.exe"),
      File.join(ENV["ProgramFiles(x86)"].to_s, "Microsoft", "Edge", "Application", "msedge.exe")
    ]
    edge = edge_paths.find { |ruta| File.exist?(ruta) }

    if edge
      ok = system(edge, "--headless", "--disable-gpu", "--print-to-pdf=#{path}", "file:///#{html_path.gsub('\\', '/')}")
      if ok && File.exist?(path)
        File.delete(html_path) if File.exist?(html_path)
        UI.messagebox("Despiece exportado a PDF.")
        return
      end
    end

    UI.openURL("file:///#{html_path.gsub('\\', '/')}")
    UI.messagebox("No se pudo crear el PDF automaticamente. Se abrio con el mismo formato para imprimir o guardar como PDF.")
  end

  def self.filas_html_despiece(filas, editable)
    por_modulo = filas.group_by { |fila| fila["modulo"].to_s }
    clase_editable = editable ? "editable" : ""
    data_attrs = editable ? " data-campo='nombre'" : ""

    por_modulo.keys.sort.map do |modulo|
      filas_originales = por_modulo[modulo]
      filas_modulo = filas_originales.map do |fila|
        "<tr>" \
        "<td class='#{clase_editable}'#{data_attrs}>#{html_escape(fila['nombre'])}</td>" \
        "<td class='#{clase_editable} num'#{editable ? " data-campo='cantidad'" : ""}>#{html_escape(fila['cantidad'])}</td>" \
        "<td class='#{clase_editable} num'#{editable ? " data-campo='medida1'" : ""}>#{html_escape(fila['medida1'])}</td>" \
        "<td class='#{clase_editable} num'#{editable ? " data-campo='canto1'" : ""}>#{html_escape(fila['canto1'])}</td>" \
        "<td class='#{clase_editable} num'#{editable ? " data-campo='medida2'" : ""}>#{html_escape(fila['medida2'])}</td>" \
        "<td class='#{clase_editable} num'#{editable ? " data-campo='canto2'" : ""}>#{html_escape(fila['canto2'])}</td>" \
        "<td class='#{clase_editable} num'#{editable ? " data-campo='placa'" : ""}>#{html_escape(fila['placa'])}</td>" \
        "<td class='#{clase_editable}'#{editable ? " data-campo='material'" : ""}>#{html_escape(fila['material'])}</td>" \
        "<td#{editable ? " data-campo='tipo_canto'" : ""}>#{html_escape(fila['tipo_canto'])}</td>" \
        "<td#{editable ? " data-campo='color_canto'" : ""}>#{html_escape(fila['color_canto'])}</td>" \
        "<td#{editable ? " data-campo='inglete'" : ""}>#{html_escape(fila['inglete'])}</td>" \
        "</tr>"
      end.join

      vista_guardada = begin
        Sketchup.active_model.get_attribute('Modular3DViews', modulo.to_s).to_s
      rescue StandardError
        ''
      end
      vista_html = vista_guardada.start_with?('data:image/') ? "<img class='modulo-view' src='#{html_escape(vista_guardada)}' alt='Vista 3D guardada de #{html_escape(modulo)}'>" : svg_modulo_despiece(modulo, filas_originales)
      "<section class='modulo-page'><div class='modulo-head'>#{vista_html}<div><h3>Modulo: #{html_escape(modulo)}</h3><p>Vista 3D sincronizada al construir o actualizar este módulo. Cada módulo conserva su propia cámara.</p></div></div>" \
      "<table data-modulo='#{html_escape(modulo)}'>" \
      "<thead><tr><th>Nombre</th><th>Cant.</th><th>Medida 1</th><th>Canto 1</th><th>Medida 2</th><th>Canto 2</th><th>Placa</th><th>Material</th><th>Tipo canto</th><th>Color canto</th><th>Inglete</th></tr></thead>" \
      "<tbody>#{filas_modulo}</tbody>" \
      "</table></section>"
    end.join
  end

  def self.svg_modulo_despiece(modulo, filas)
    total = filas.inject(0) { |suma, fila| suma + fila["cantidad"].to_i }
    puertas = filas.any? { |fila| fila["nombre"].to_s.upcase.include?("PT") || fila["nombre"].to_s.upcase.include?("PUERTA") }
    cajones = filas.any? { |fila| fila["nombre"].to_s.upcase.include?("FC") || fila["nombre"].to_s.upcase.include?("CJ") }
    divisor = puertas ? "<line x1='70' y1='38' x2='70' y2='128'/>" : ""
    lineas_cajon = cajones ? "<line x1='28' y1='64' x2='112' y2='64'/><line x1='28' y1='91' x2='112' y2='91'/>" : "<line x1='28' y1='80' x2='112' y2='80'/>"
    "<svg class='modulo-svg' viewBox='0 0 170 150' role='img' aria-label='Modulo #{html_escape(modulo)}'>" \
    "<polygon points='26,30 112,30 142,16 56,16' fill='#ead1a8' stroke='#334155'/>" \
    "<polygon points='112,30 142,16 142,112 112,130' fill='#d8b178' stroke='#334155'/>" \
    "<rect x='26' y='30' width='86' height='100' fill='#f8fafc' stroke='#334155'/>" \
    "<g stroke='#64748b' stroke-width='2'>#{divisor}#{lineas_cajon}</g>" \
    "<text x='84' y='144' text-anchor='middle' font-size='12' font-family='Segoe UI'>#{html_escape(modulo)} · #{total} pz</text>" \
    "</svg>"
  end

  def self.html_despiece_exportable(filas, excel, auto_print = false)
    filas_html = filas_html_despiece(filas, false)
    <<-HTML
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    @page { size: A4 landscape; margin: 10mm; }
    body { font-family: Segoe UI, Arial, sans-serif; margin: 18px; color: #111827; background: #f8fafc; }
    h2 { margin: 0 0 14px 0; font-size: 18px; }
    h3 { margin: 18px 0 8px 0; font-size: 14px; color: #1f2937; }
    .modulo-page { page-break-inside: avoid; break-inside: avoid; margin-bottom: 18px; padding: 12px; border: 1px solid #cbd5e1; background: #fff; }
    .modulo-head { display: grid; grid-template-columns: 180px 1fr; gap: 14px; align-items: center; margin-bottom: 10px; }
    .modulo-head p { margin: 4px 0 0; color: #64748b; }
    .modulo-svg, .modulo-view { width: 170px; height: 150px; object-fit: contain; background: #fff; border: 1px solid #e2e8f0; }
    table { width: 100%; border-collapse: collapse; background: white; margin-bottom: 14px; }
    th, td { border: 1px solid #d1d5db; padding: 7px 8px; font-size: 12px; text-align: left; }
    th { background: #e5e7eb; font-weight: 700; }
    .num { text-align: right; }
    @media print {
      body { background: white; }
      .modulo-page { page-break-inside: avoid; break-inside: avoid; }
      h3 { page-break-after: avoid; }
      table { page-break-inside: auto; }
    }
  </style>
</head>
<body>
  <h2>Despiece de Seleccion</h2>
  #{filas_html}
  #{auto_print ? "<script>window.onload = function(){ window.print(); };</script>" : ""}
</body>
</html>
    HTML
  end

  def self.generar_despiece_seleccion
    model = Sketchup.active_model
    seleccion = model.selection

    if seleccion.empty?
      UI.messagebox("Selecciona primero las piezas o modulos para generar el despiece.")
      return
    end

    piezas = []
    seleccion.each { |entity| recolectar_piezas_despiece(entity, piezas) }

    if piezas.empty?
      UI.messagebox("No se encontraron piezas con datos de despiece en la seleccion.")
      return
    end

    agrupado = {}
    piezas.each do |pieza|
      clave = [
        pieza[:modulo],
        pieza[:codigo],
        pieza[:medida_1],
        pieza[:canto_1],
        pieza[:medida_2],
        pieza[:canto_2],
        pieza[:placa],
        pieza[:material],
        pieza[:tipo_canto],
        pieza[:color_canto],
        pieza[:inglete]
      ]
      agrupado[clave] ||= pieza.merge(:cantidad => 0)
      agrupado[clave][:cantidad] += 1
    end

    filas_data = agrupado.values.sort_by { |pieza| [pieza[:modulo], pieza[:codigo], pieza[:medida_1], pieza[:medida_2], pieza[:material]] }.map do |pieza|
      {
        "modulo" => pieza[:modulo],
        "nombre" => pieza[:codigo],
        "cantidad" => pieza[:cantidad],
        "medida1" => pieza[:medida_1],
        "canto1" => "#{pieza[:canto_1]}L",
        "medida2" => pieza[:medida_2],
        "canto2" => "#{pieza[:canto_2]}C",
        "placa" => pieza[:placa],
        "material" => pieza[:material],
        "tipo_canto" => pieza[:tipo_canto],
        "color_canto" => pieza[:color_canto],
        "inglete" => pieza[:inglete]
      }
    end
    filas_html = filas_html_despiece(filas_data, true)

    html = <<-HTML
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 18px; color: #111827; background: #f8fafc; }
    h2 { margin: 0 0 14px 0; font-size: 18px; }
    h3 { margin: 18px 0 8px 0; font-size: 14px; color: #1f2937; }
    .acciones { display: flex; align-items: center; gap: 10px; margin-bottom: 14px; }
    .modulo-page { margin-bottom: 18px; padding: 12px; border: 1px solid #cbd5e1; background: #fff; }
    .modulo-head { display: grid; grid-template-columns: 230px 1fr; gap: 14px; align-items: center; margin-bottom: 10px; }
    .modulo-head p { margin: 4px 0 0; color: #64748b; }
    .modulo-svg, .modulo-view { width: 220px; height: 170px; object-fit: contain; background: #fff; border: 1px solid #e2e8f0; }
    button { border: 1px solid #9ca3af; background: #ffffff; border-radius: 5px; padding: 7px 10px; cursor: pointer; font-size: 12px; }
    button:hover { background: #f3f4f6; }
    label { font-size: 12px; display: flex; gap: 6px; align-items: center; }
    table { width: 100%; border-collapse: collapse; background: white; margin-bottom: 14px; }
    th, td { border: 1px solid #d1d5db; padding: 7px 8px; font-size: 12px; text-align: left; }
    th { background: #e5e7eb; font-weight: 700; }
    .num { text-align: right; }
    .edicion-activa td.editable { background: #fff7ed; outline: 1px dashed #fb923c; }
    .panel-optimizacion { display: none; border: 1px solid #cbd5e1; background: #ffffff; padding: 12px; margin: 0 0 14px 0; }
    .panel-optimizacion.activo { display: block; }
    .fila-controles { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; margin-bottom: 10px; }
    input.opt-input { width: 86px; border: 1px solid #cbd5e1; border-radius: 4px; padding: 5px 6px; font-size: 12px; }
    .resultado-opt { margin-top: 10px; font-size: 12px; }
    .resultado-opt h4 { margin: 12px 0 6px 0; font-size: 13px; }
    .plano-tablero { border: 1px solid #94a3b8; background: #f8fafc; margin: 8px 0 12px 0; padding: 8px; }
    .titulo-tablero { font-weight: 700; margin-bottom: 2px; }
    .subtitulo-tablero { color: #475569; margin-bottom: 8px; }
    .svg-tablero { width: 100%; max-width: 760px; height: auto; background: #fff; border: 1px solid #cbd5e1; display: block; }
    .pieza-svg { fill: #dbeafe; stroke: #1d4ed8; stroke-width: 2; }
    .pieza-texto { font-family: Segoe UI, Arial, sans-serif; font-size: 28px; font-weight: 700; fill: #111827; }
    .pieza-medida { font-family: Segoe UI, Arial, sans-serif; font-size: 22px; fill: #1f2937; }
    .sobrante-svg { fill: rgba(241,245,249,0.8); stroke: #94a3b8; stroke-width: 1; stroke-dasharray: 10 8; }
    .resumen-tablero { margin: 8px 0; color: #334155; }
  </style>
</head>
<body>
  <h2>Despiece de Seleccion</h2>
  <div class="acciones">
    <button onclick="exportarExcel()">Descargar Excel</button>
    <button onclick="exportarPdf()">Descargar PDF</button>
    <button onclick="abrirOptimizacion()">Optimizacion de Corte</button>
    <label><input type="checkbox" id="editar" onchange="toggleEditar()"> Editar</label>
  </div>
  <div id="panel_optimizacion" class="panel-optimizacion">
    <div class="fila-controles">
      <label>Espesor sierra (mm) <input class="opt-input" type="number" id="sierra_opt" value="3" step="0.1"></label>
      <button onclick="agregarStock()">Agregar material</button>
      <button onclick="calcularOptimizacion()">Calcular</button>
    </div>
    <table id="tabla_stock">
      <thead><tr><th>Material</th><th>Placa</th><th>Largo tablero</th><th>Ancho tablero</th><th>Stock</th><th>Veta</th><th></th></tr></thead>
      <tbody></tbody>
    </table>
    <div id="resultado_optimizacion" class="resultado-opt"></div>
  </div>
  #{filas_html}
  <script>
    function toggleEditar() {
      var activo = document.getElementById('editar').checked;
      document.body.classList.toggle('edicion-activa', activo);
      document.querySelectorAll('td.editable').forEach(function(celda) {
        celda.contentEditable = activo ? 'true' : 'false';
      });
    }

    function filasActuales() {
      var filas = [];
      document.querySelectorAll('table[data-modulo]').forEach(function(tabla) {
        var modulo = tabla.getAttribute('data-modulo') || '';
        tabla.querySelectorAll('tbody tr').forEach(function(tr) {
          var fila = { modulo: modulo };
          tr.querySelectorAll('[data-campo]').forEach(function(celda) {
            fila[celda.getAttribute('data-campo')] = celda.textContent.trim();
          });
          filas.push(fila);
        });
      });
      return filas;
    }

    function exportarExcel() {
      sketchup.exportarDespieceExcel(filasActuales());
    }

    function exportarPdf() {
      sketchup.exportarDespiecePdf(filasActuales());
    }

    function numeroCelda(valor) {
      var limpio = String(valor || '').replace(',', '.').replace(/[^0-9.]/g, '');
      return parseFloat(limpio) || 0;
    }

    function htmlSeguro(valor) {
      return String(valor || '').replace(/[&<>"']/g, function(caracter) {
        return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[caracter];
      });
    }

    function claveStock(material, placa) {
      return String(material || 'SIN MATERIAL').trim().toUpperCase() + '|' + String(placa || '').trim();
    }

    function piezasParaCorte() {
      var piezas = [];
      filasActuales().forEach(function(fila) {
        var cantidad = parseInt(fila.cantidad, 10) || 0;
        var medida1 = numeroCelda(fila.medida1);
        var medida2 = numeroCelda(fila.medida2);
        if (cantidad <= 0 || medida1 <= 0 || medida2 <= 0) return;
        for (var i = 0; i < cantidad; i++) {
          piezas.push({
            nombre: fila.nombre || '',
            modulo: fila.modulo || '',
            material: fila.material || 'SIN MATERIAL',
            placa: fila.placa || '',
            w: medida1,
            h: medida2
          });
        }
      });
      return piezas;
    }

    function agregarStock(material, placa) {
      var tbody = document.querySelector('#tabla_stock tbody');
      var tr = document.createElement('tr');
      tr.innerHTML =
        '<td><input class="opt-input material-stock" style="width:150px" value="' + (material || 'SIN MATERIAL') + '"></td>' +
        '<td><input class="opt-input placa-stock" value="' + (placa || '') + '"></td>' +
        '<td><input class="opt-input largo-stock" type="number" value="2440"></td>' +
        '<td><input class="opt-input ancho-stock" type="number" value="1830"></td>' +
        '<td><input class="opt-input cantidad-stock" type="number" value="1"></td>' +
        '<td><label style="display:flex;align-items:center;gap:4px;font-size:11px;white-space:nowrap"><input type="checkbox" class="veta-stock"> Respetar veta</label></td>' +
        '<td><button onclick="this.closest(\\'tr\\').remove()">Borrar</button></td>';
      tbody.appendChild(tr);
    }

    function abrirOptimizacion() {
      var panel = document.getElementById('panel_optimizacion');
      panel.classList.toggle('activo');
      if (!panel.classList.contains('activo')) return;

      var tbody = document.querySelector('#tabla_stock tbody');
      if (tbody.children.length > 0) return;

      var usados = {};
      piezasParaCorte().forEach(function(pieza) {
        var clave = claveStock(pieza.material, pieza.placa);
        if (usados[clave]) return;
        usados[clave] = true;
        agregarStock(pieza.material, pieza.placa);
      });
    }

    function stockActual() {
      var stocks = {};
      document.querySelectorAll('#tabla_stock tbody tr').forEach(function(tr) {
        var material = tr.querySelector('.material-stock').value || 'SIN MATERIAL';
        var placa = tr.querySelector('.placa-stock').value || '';
        var largo = numeroCelda(tr.querySelector('.largo-stock').value);
        var ancho = numeroCelda(tr.querySelector('.ancho-stock').value);
        var cantidad = parseInt(tr.querySelector('.cantidad-stock').value, 10) || 0;
        var sinRotar = !!(tr.querySelector('.veta-stock') && tr.querySelector('.veta-stock').checked);
        if (largo <= 0 || ancho <= 0 || cantidad <= 0) return;
        var clave = claveStock(material, placa);
        if (!stocks[clave]) stocks[clave] = [];
        stocks[clave].push({ material: material, placa: placa, w: largo, h: ancho, cantidad: cantidad, sinRotar: sinRotar });
      });
      return stocks;
    }

    function intentarUbicar(tablero, pieza, sierra) {
      var opciones = tablero.sinRotar ? [{ w: pieza.w, h: pieza.h, rotada: false }] : [{ w: pieza.w, h: pieza.h, rotada: false }, { w: pieza.h, h: pieza.w, rotada: true }];
      var mejor = null;
      for (var r = 0; r < tablero.libres.length; r++) {
        var libre = tablero.libres[r];
        for (var o = 0; o < opciones.length; o++) {
          var op = opciones[o];
          if (op.w <= libre.w && op.h <= libre.h) {
            var desperdicio = (libre.w * libre.h) - (op.w * op.h);
            var ladoCorto = Math.min(libre.w - op.w, libre.h - op.h);
            if (!mejor || desperdicio < mejor.desperdicio ||
                (desperdicio === mejor.desperdicio && ladoCorto < mejor.ladoCorto)) {
              mejor = { indice: r, libre: libre, op: op, desperdicio: desperdicio, ladoCorto: ladoCorto };
            }
          }
        }
      }
      if (!mejor) return false;

      var hueco = mejor.libre;
      var colocada = mejor.op;
      tablero.libres.splice(mejor.indice, 1);
      tablero.piezas.push({ pieza: pieza, x: hueco.x, y: hueco.y, w: colocada.w, h: colocada.h, rotada: colocada.rotada });
      tablero.area += colocada.w * colocada.h;

      var anchoDerecha = hueco.w - colocada.w - sierra;
      var altoAbajo = hueco.h - colocada.h - sierra;
      if (anchoDerecha > 0) {
        tablero.libres.push({ x: hueco.x + colocada.w + sierra, y: hueco.y, w: anchoDerecha, h: colocada.h });
      }
      if (altoAbajo > 0) {
        tablero.libres.push({ x: hueco.x, y: hueco.y + colocada.h + sierra, w: hueco.w, h: altoAbajo });
      }
      tablero.libres.sort(function(a, b) { return (a.w * a.h) - (b.w * b.h); });
      return true;
    }

    function tomarTableroDisponible(stocks, clave) {
      var lista = stocks[clave] || [];
      for (var i = 0; i < lista.length; i++) {
        if (lista[i].cantidad > 0) {
          lista[i].cantidad -= 1;
          return lista[i];
        }
      }
      return null;
    }

    function planoTablero(tablero, idx, sierra) {
      var areaTablero = tablero.w * tablero.h;
      var areaPiezas = tablero.area;
      var areaSobra = Math.max(0, areaTablero - areaPiezas);
      var uso = areaTablero > 0 ? Math.round((areaPiezas / areaTablero) * 100) : 0;
      var sobra = areaTablero > 0 ? Math.round((areaSobra / areaTablero) * 100) : 0;
      var altoVista = Math.max(tablero.h, 1);
      var anchoVista = Math.max(tablero.w, 1);
      var svg = '<svg class="svg-tablero" viewBox="0 0 ' + anchoVista + ' ' + altoVista + '" preserveAspectRatio="xMinYMin meet">';

      svg += '<rect class="sobrante-svg" x="0" y="0" width="' + tablero.w + '" height="' + tablero.h + '"></rect>';
      tablero.piezas.forEach(function(item, itemIdx) {
        var cx = item.x + (item.w / 2);
        var cy = item.y + (item.h / 2);
        var nombre = htmlSeguro(item.pieza.nombre);
        var medida = Math.round(item.w) + 'x' + Math.round(item.h) + (item.rotada ? ' R' : '');
        svg += '<rect class="pieza-svg" x="' + item.x + '" y="' + item.y + '" width="' + item.w + '" height="' + item.h + '"></rect>';
        if (item.w >= 120 && item.h >= 90) {
          svg += '<text class="pieza-texto" x="' + cx + '" y="' + (cy - 8) + '" text-anchor="middle">' + nombre + '</text>';
          svg += '<text class="pieza-medida" x="' + cx + '" y="' + (cy + 24) + '" text-anchor="middle">' + medida + '</text>';
        } else {
          svg += '<text class="pieza-medida" x="' + (item.x + 8) + '" y="' + (item.y + 24) + '">' + (itemIdx + 1) + '</text>';
        }
      });
      svg += '</svg>';

      var indice = '<table><thead><tr><th>#</th><th>Pieza</th><th>Medida presentada</th><th>X</th><th>Y</th><th>Rotada</th></tr></thead><tbody>';
      tablero.piezas.forEach(function(item, itemIdx) {
        indice += '<tr>' +
          '<td>' + (itemIdx + 1) + '</td>' +
          '<td>' + htmlSeguro(item.pieza.nombre) + '</td>' +
          '<td>' + Math.round(item.w) + 'x' + Math.round(item.h) + '</td>' +
          '<td>' + Math.round(item.x) + '</td>' +
          '<td>' + Math.round(item.y) + '</td>' +
          '<td>' + (item.rotada ? 'SI' : 'NO') + '</td>' +
          '</tr>';
      });
      indice += '</tbody></table>';

      return '<div class="plano-tablero">' +
        '<div class="titulo-tablero">TABLERO ' + (idx + 1) + ' - ' + htmlSeguro(tablero.material) + '</div>' +
        '<div class="subtitulo-tablero">Formato ' + Math.round(tablero.w) + 'x' + Math.round(tablero.h) + ' mm | Placa ' + htmlSeguro(tablero.placa) + ' | Sierra ' + sierra + ' mm' + (tablero.sinRotar ? ' | Veta respetada (sin rotar piezas)' : '') + '</div>' +
        svg +
        '<div class="resumen-tablero">Uso: ' + uso + '% | Sobra aprox: ' + Math.round(areaSobra) + ' mm2 (' + sobra + '%) | Piezas: ' + tablero.piezas.length + '</div>' +
        '<h4>Indice de corte tablero ' + (idx + 1) + '</h4>' +
        indice +
        '</div>';
    }

    function calcularOptimizacion() {
      var sierra = numeroCelda(document.getElementById('sierra_opt').value);
      var piezas = piezasParaCorte().sort(function(a, b) {
        return Math.max(b.w, b.h) - Math.max(a.w, a.h);
      });
      var stocks = stockActual();
      var tableros = [];
      var pendientes = [];

      piezas.forEach(function(pieza) {
        var clave = claveStock(pieza.material, pieza.placa);
        var ubicada = false;

        for (var i = 0; i < tableros.length; i++) {
          if (tableros[i].clave === clave && intentarUbicar(tableros[i], pieza, sierra)) {
            ubicada = true;
            break;
          }
        }

        if (!ubicada) {
          var stock = tomarTableroDisponible(stocks, clave);
          if (stock) {
            var tablero = {
              clave: clave, material: stock.material, placa: stock.placa,
              w: stock.w, h: stock.h, area: 0, piezas: [], sinRotar: !!stock.sinRotar,
              libres: [{ x: 0, y: 0, w: stock.w, h: stock.h }]
            };
            if (intentarUbicar(tablero, pieza, sierra)) {
              tableros.push(tablero);
              ubicada = true;
            }
          }
        }

        if (!ubicada) pendientes.push(pieza);
      });

      var html = '<h4>Resultado</h4>';
      if (tableros.length === 0) {
        html += '<p>No hay tableros calculados. Revisa stock, material, placa y medidas.</p>';
      } else {
        html += '<table><thead><tr><th>Tablero</th><th>Material</th><th>Placa</th><th>Medida</th><th>Piezas</th><th>Uso</th></tr></thead><tbody>';
        tableros.forEach(function(tablero, idx) {
          var uso = tablero.w > 0 && tablero.h > 0 ? Math.round((tablero.area / (tablero.w * tablero.h)) * 100) : 0;
          var detalle = tablero.piezas.map(function(item) {
            return htmlSeguro(item.pieza.nombre) + ' ' + Math.round(item.w) + 'x' + Math.round(item.h) + (item.rotada ? ' R' : '');
          }).join('<br>');
          html += '<tr><td>TABLERO ' + (idx + 1) + '</td><td>' + htmlSeguro(tablero.material) + '</td><td>' + htmlSeguro(tablero.placa) + '</td><td>' + tablero.w + 'x' + tablero.h + '</td><td>' + detalle + '</td><td>' + uso + '%</td></tr>';
        });
        html += '</tbody></table>';
        tableros.forEach(function(tablero, idx) {
          html += planoTablero(tablero, idx, sierra);
        });
      }

      if (pendientes.length > 0) {
        html += '<h4>Sin ubicar</h4><table><thead><tr><th>Nombre</th><th>Material</th><th>Placa</th><th>Medida</th></tr></thead><tbody>';
        pendientes.forEach(function(pieza) {
          html += '<tr><td>' + htmlSeguro(pieza.nombre) + '</td><td>' + htmlSeguro(pieza.material) + '</td><td>' + htmlSeguro(pieza.placa) + '</td><td>' + pieza.w + 'x' + pieza.h + '</td></tr>';
        });
        html += '</tbody></table>';
      }

      document.getElementById('resultado_optimizacion').innerHTML = html;
    }

    toggleEditar();
  </script>
</body>
</html>
    HTML

    dialogo = UI::HtmlDialog.new({
      :dialog_title => "Modular_3D | Despiece de selección",
      :preferences_key => "com.lpenafiel.modular3d.despiece",
      :scrollable => true,
      :resizable => true,
      :width => 880,
      :height => 620,
      :style => UI::HtmlDialog::STYLE_WINDOW
    })
    dialogo.set_html(html)
    dialogo.add_action_callback("exportarDespieceExcel") do |_action_context, filas|
      self.exportar_despiece_excel(filas)
    end
    dialogo.add_action_callback("exportarDespiecePdf") do |_action_context, filas|
      self.exportar_despiece_pdf(filas)
    end
    dialogo.show
  end

  # --- MÓDULO ESQUINERO EN L ---
  # Dos alas rectangulares, cada una un casco normal construido con
  # crear_pieza (la misma función probada que usa todo el resto del plugin),
  # colocadas una junto a otra a lo largo de X para que su unión forme una
  # silueta en L sin que ningún panel se atraviese ni se solape: el ala A
  # ocupa X en [0, largo_a] con profundidad pata, y el ala B ocupa X en
  # [largo_a, largo_a + pata] con su propia profundidad (mayor), de modo que
  # su silueta combinada, vista en planta, es una L real. Las dos laterales
  # que se tocan en esa costura (LAT_A_DER y LAT_B_IZQ) llevan cada una un
  # inglete a 45° en su esquina delantera, para que el corte de ambas
  # coincida en una sola línea diagonal visible en el frente en vez de un
  # canto cuadrado contra otro.
  def self.generar_modulo_esquinero_l(datos)
    estado_licencia = Modular3D::License.ensure_authorized
    return estado_licencia unless estado_licencia[:ok]

    modulo_nombre = nombre_modulo_unico(datos['modulo_nombre'].to_s.strip.empty? ? 'ESQUINERO_L' : datos['modulo_nombre'])
    espesor = [(datos['espesor'] || 15).to_f, 3.0].max.mm
    pata = [(datos['pata'] || 580).to_f, espesor.to_mm * 4].max.mm
    largo_a = [(datos['largo_a'] || 600).to_f, espesor.to_mm * 4].max.mm
    largo_b = [(datos['largo_b'] || 600).to_f, espesor.to_mm * 4].max.mm
    alto_total = [(datos['alto_total'] || 720).to_f, 100.0].max.mm
    lleva_respaldo = datos['lleva_respaldo'].to_s != 'NO'
    grosor_resp = [(datos['grosor_resp'] || 6).to_f, 2.0].max.mm
    num_repisas_a = [[(datos['num_repisas_a'] || 1).to_i, 0].max, 10].min
    num_repisas_b = [[(datos['num_repisas_b'] || 1).to_i, 0].max, 10].min
    medida_inglete = [(datos['medida_inglete'] || (espesor.to_mm * 2)).to_f, 1.0].max.mm

    @datos_modulo_actual = datos.reject { |clave, _valor| clave.to_s.start_with?('__') }
    @modulo_uuid_actual = SecureRandom.uuid
    @datos_modulo_actual['module_uuid'] = @modulo_uuid_actual
    # La costura visible entre las dos alas lleva inglete en cada lado. Se
    # define antes de crear las piezas porque crear_pieza lee
    # miter_overrides_json de @datos_modulo_actual en el momento de la
    # llamada (mismo patrón que material_overrides_json/dimension_overrides_json).
    @datos_modulo_actual['miter_overrides_json'] = JSON.generate(
      'LAT_A_DER' => { 'corner' => 'front_right', 'size' => medida_inglete.to_mm },
      'LAT_B_IZQ' => { 'corner' => 'front_left', 'size' => medida_inglete.to_mm }
    )
    @modulo_despiece_actual = "#{modulo_nombre}_ESQUINERO_L"
    @offset_creacion = offset_siguiente_modulo
    @piezas_modulo_actual = []

    model = Sketchup.active_model
    operacion_iniciada = false
    begin
      model.start_operation('Generar módulo esquinero en L', true)
      operacion_iniciada = true
      entities = model.active_entities

      alto_interior = alto_total - (espesor * 2)

      # Ala A: corre a lo largo de X, profundidad = pata.
      self.crear_pieza(entities, modulo_nombre, 'LAT_A_IZQ', espesor, pata, alto_total, 0.mm, 0.mm, 0.mm, 1, 0)
      self.crear_pieza(entities, modulo_nombre, 'LAT_A_DER', espesor, pata, alto_total, largo_a - espesor, 0.mm, 0.mm, 1, 0)
      self.crear_pieza(entities, modulo_nombre, 'BASE_A', largo_a - (espesor * 2), pata, espesor, espesor, 0.mm, 0.mm, 1, 0)
      self.crear_pieza(entities, modulo_nombre, 'TECHO_A', largo_a - (espesor * 2), pata, espesor, espesor, 0.mm, alto_total - espesor, 1, 0)
      if lleva_respaldo
        self.crear_pieza(entities, modulo_nombre, 'RESPALDO_A', largo_a - (espesor * 2), grosor_resp, alto_interior, espesor, pata - grosor_resp, espesor, 0, 0)
      end
      if num_repisas_a > 0
        distancia_a = (alto_interior - (num_repisas_a * espesor)) / (num_repisas_a + 1)
        (1..num_repisas_a).each do |i|
          z_rep = espesor + (i * distancia_a) + ((i - 1) * espesor)
          self.crear_pieza(entities, modulo_nombre, "REPISA_A_#{i}", largo_a - (espesor * 2), pata - (lleva_respaldo ? grosor_resp + 5.mm : 0.mm), espesor, espesor, 0.mm, z_rep, 1, 0)
        end
      end

      # Ala B: corre a lo largo de Y, comienza donde termina el ala A.
      self.crear_pieza(entities, modulo_nombre, 'LAT_B_IZQ', espesor, largo_b, alto_total, largo_a, 0.mm, 0.mm, 1, 0)
      self.crear_pieza(entities, modulo_nombre, 'LAT_B_DER', espesor, largo_b, alto_total, largo_a + pata - espesor, 0.mm, 0.mm, 1, 0)
      self.crear_pieza(entities, modulo_nombre, 'BASE_B', pata - (espesor * 2), largo_b, espesor, largo_a + espesor, 0.mm, 0.mm, 1, 0)
      self.crear_pieza(entities, modulo_nombre, 'TECHO_B', pata - (espesor * 2), largo_b, espesor, largo_a + espesor, 0.mm, alto_total - espesor, 1, 0)
      if lleva_respaldo
        self.crear_pieza(entities, modulo_nombre, 'RESPALDO_B', pata - (espesor * 2), grosor_resp, alto_interior, largo_a + espesor, largo_b - grosor_resp, espesor, 0, 0)
      end
      if num_repisas_b > 0
        distancia_b = (alto_interior - (num_repisas_b * espesor)) / (num_repisas_b + 1)
        (1..num_repisas_b).each do |i|
          z_rep = espesor + (i * distancia_b) + ((i - 1) * espesor)
          self.crear_pieza(entities, modulo_nombre, "REPISA_B_#{i}", pata - (espesor * 2), largo_b - (lleva_respaldo ? grosor_resp + 5.mm : 0.mm), espesor, largo_a + espesor, 0.mm, z_rep, 1, 0)
        end
      end

      manifiesto = crear_manifiesto(@datos_modulo_actual, modulo_nombre, @modulo_uuid_actual, 'ESQUINERO_L')
      manifiesto['piece_inventory'] = inventario_geometrico(@piezas_modulo_actual)
      contenedor = encapsular_modulo(entities, @piezas_modulo_actual, manifiesto)
      @ultimo_modulo_piezas = contenedor ? [contenedor] : @piezas_modulo_actual
      if contenedor
        model.selection.clear
        model.selection.add(contenedor)
      end
      model.commit_operation
      operacion_iniciada = false
      { ok: true }
    rescue StandardError => e
      model.abort_operation if operacion_iniciada
      { ok: false, message: "No se pudo generar el esquinero: #{e.class}: #{e.message}" }
    ensure
      @piezas_modulo_actual = nil
      @offset_creacion = nil
      @modulo_despiece_actual = nil
      @datos_modulo_actual = nil
      @modulo_uuid_actual = nil
    end
  end

  def self.mostrar_interfaz_esquinero_l
    return unless acceso_autorizado?

    html = <<-HTML
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 18px; color: #111827; background: #f8fafc; }
    h2 { margin: 0 0 4px 0; font-size: 18px; }
    p.hint { color: #64748b; margin: 0 0 16px 0; font-size: 13px; }
    .row { display: grid; grid-template-columns: 220px 1fr; align-items: center; gap: 10px; margin-bottom: 10px; }
    input, select { border: 1px solid #cbd5e1; border-radius: 5px; padding: 6px 8px; font-size: 13px; }
    button { border: 1px solid #1d4ed8; background: #1d4ed8; color: white; border-radius: 6px; padding: 9px 16px; font-size: 13px; cursor: pointer; }
    button:hover { background: #1e40af; }
    .message { display: none; margin-top: 12px; padding: 8px 10px; border-radius: 6px; font-size: 12px; }
    .message.error { display: block; background: #fef2f2; color: #991b1b; border: 1px solid #fecaca; }
  </style>
</head>
<body>
  <h2>Módulo esquinero en L</h2>
  <p class="hint">Dos alas que se unen en costura recta (no en escuadra hueca): la silueta combinada es una L y la costura visible entre ambas lleva un inglete a 45° en cada lado.</p>
  <div class="row"><label>Nombre</label><input id="modulo_nombre" value="ESQUINERO_L"></div>
  <div class="row"><label>Largo ala A (mm)</label><input id="largo_a" type="number" value="600" min="200"></div>
  <div class="row"><label>Largo ala B (mm)</label><input id="largo_b" type="number" value="600" min="200"></div>
  <div class="row"><label>Profundidad de cada ala (mm)</label><input id="pata" type="number" value="580" min="200"></div>
  <div class="row"><label>Alto total (mm)</label><input id="alto_total" type="number" value="720" min="200"></div>
  <div class="row"><label>Espesor tablero (mm)</label><input id="espesor" type="number" value="15" min="3"></div>
  <div class="row"><label>Repisas ala A</label><input id="num_repisas_a" type="number" value="1" min="0" max="10"></div>
  <div class="row"><label>Repisas ala B</label><input id="num_repisas_b" type="number" value="1" min="0" max="10"></div>
  <div class="row"><label>Respaldo</label><select id="lleva_respaldo"><option value="SI">Con respaldo</option><option value="NO">Sin respaldo</option></select></div>
  <div class="row"><label>Medida del inglete de costura (mm)</label><input id="medida_inglete" type="number" value="30" min="1"></div>
  <button id="construir">Construir esquinero</button>
  <div id="mensaje" class="message error"></div>
  <script>
    document.getElementById('construir').addEventListener('click', function () {
      var datos = {};
      ['modulo_nombre','largo_a','largo_b','pata','alto_total','espesor','num_repisas_a','num_repisas_b','lleva_respaldo','medida_inglete'].forEach(function (id) {
        var el = document.getElementById(id);
        datos[id] = el.type === 'number' ? parseFloat(el.value) : el.value;
      });
      sketchup.construirEsquineroL(datos);
    });
  </script>
</body>
</html>
    HTML

    dialogo = UI::HtmlDialog.new({
      :dialog_title => "#{Modular3D::PRODUCT_NAME} | Módulo esquinero en L",
      :preferences_key => 'com.lpenafiel.modular3d.esquinero_l',
      :scrollable => true,
      :resizable => true,
      :width => 460,
      :height => 620,
      :style => UI::HtmlDialog::STYLE_WINDOW
    })
    dialogo.set_html(html)
    dialogo.add_action_callback('construirEsquineroL') do |_action_context, datos|
      resultado = self.generar_modulo_esquinero_l(datos)
      if resultado[:ok]
        dialogo.close
      else
        dialogo.execute_script("document.getElementById('mensaje').textContent = #{JSON.generate(resultado[:message] || 'No se pudo construir el módulo.')}; document.getElementById('mensaje').style.display='block';")
      end
    end
    dialogo.show
  end

  # --- PRESUPUESTO / COTIZADOR ---
  # Reutiliza exactamente la misma recolección de piezas que el despiece
  # (recolectar_piezas_despiece) para no duplicar la lógica de qué cuenta
  # como pieza fabricable; solo cambia qué se hace con esos datos: en vez de
  # listarlos, se agrupan por material para el costo de tablero, se suma la
  # longitud de canto por tipo, y se cuentan puertas/cajones para herrajes.
  def self.imprimir_html_como_pdf(html, sugerido, titulo_mensaje)
    path = UI.savepanel("Guardar #{titulo_mensaje}", "", sugerido)
    return unless path
    path += ".pdf" unless File.extname(path).downcase == ".pdf"

    html_path = File.join(Dir.tmpdir, "modular3d_#{Process.pid}_#{Time.now.to_i}.html")
    File.write(html_path, html)

    edge_paths = [
      File.join(ENV["ProgramFiles"].to_s, "Microsoft", "Edge", "Application", "msedge.exe"),
      File.join(ENV["ProgramFiles(x86)"].to_s, "Microsoft", "Edge", "Application", "msedge.exe")
    ]
    edge = edge_paths.find { |ruta| File.exist?(ruta) }

    if edge
      ok = system(edge, "--headless", "--disable-gpu", "--print-to-pdf=#{path}", "file:///#{html_path.gsub('\\', '/')}")
      if ok && File.exist?(path)
        File.delete(html_path) if File.exist?(html_path)
        UI.messagebox("#{titulo_mensaje} exportado a PDF.")
        return
      end
    end

    UI.openURL("file:///#{html_path.gsub('\\', '/')}")
    UI.messagebox("No se pudo crear el PDF automaticamente. Se abrio con el mismo formato para imprimir o guardar como PDF.")
  end

  def self.datos_costo_seleccion
    model = Sketchup.active_model
    piezas = []
    model.selection.each { |entity| recolectar_piezas_despiece(entity, piezas) }
    return nil if piezas.empty?

    por_material = Hash.new { |hash, clave| hash[clave] = { :area_m2 => 0.0, :canto_pvc_m => 0.0, :canto_duro_m => 0.0 } }
    puertas = 0
    piezas_cos = 0

    piezas.each do |pieza|
      grupo = por_material[pieza[:material].to_s]
      area_m2 = (pieza[:medida_1].to_f / 1000.0) * (pieza[:medida_2].to_f / 1000.0)
      grupo[:area_m2] += area_m2
      largo_canto_m = ((pieza[:canto_1].to_i * pieza[:medida_1].to_f) + (pieza[:canto_2].to_i * pieza[:medida_2].to_f)) / 1000.0
      if pieza[:tipo_canto].to_s.upcase == 'HARD'
        grupo[:canto_duro_m] += largo_canto_m
      else
        grupo[:canto_pvc_m] += largo_canto_m
      end
      puertas += 1 if pieza[:codigo].to_s == 'PT'
      piezas_cos += 1 if pieza[:codigo].to_s == 'COS'
    end

    { :por_material => por_material, :puertas => puertas, :cajones => (piezas_cos / 2.0).ceil, :total_piezas => piezas.length }
  end

  def self.mostrar_presupuesto
    return unless acceso_autorizado?
    datos_costo = datos_costo_seleccion
    unless datos_costo
      UI.messagebox('Selecciona primero uno o varios módulos Modular_3D para presupuestar.')
      return
    end

    filas_material = datos_costo[:por_material].map do |material, valores|
      "<tr data-material='#{html_escape(material)}'>" \
      "<td>#{html_escape(material)}</td>" \
      "<td class='num'>#{'%.2f' % valores[:area_m2]}</td>" \
      "<td><input class='precio-m2' type='number' step='0.01' value='0' data-area='#{valores[:area_m2]}'></td>" \
      "<td class='num subtotal-material'>0.00</td>" \
      "</tr>"
    end.join

    html = <<-HTML
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
  body { font-family: Segoe UI, Arial, sans-serif; margin: 20px; color: #111827; background: #f8fafc; }
  h2 { margin: 0 0 4px 0; }
  h3 { margin: 18px 0 8px 0; font-size: 14px; color: #1f2937; }
  table { width: 100%; border-collapse: collapse; background: #fff; margin-bottom: 14px; }
  th, td { border: 1px solid #d1d5db; padding: 6px 8px; font-size: 12px; text-align: left; }
  th { background: #e5e7eb; }
  .num { text-align: right; }
  input { width: 90px; border: 1px solid #cbd5e1; border-radius: 4px; padding: 4px 6px; font-size: 12px; }
  .totales { background: #fff; border: 1px solid #d1d5db; border-radius: 6px; padding: 12px 16px; max-width: 420px; margin-left: auto; }
  .totales div { display: flex; justify-content: space-between; padding: 3px 0; font-size: 13px; }
  .totales .grand { font-weight: 700; font-size: 16px; border-top: 1px solid #d1d5db; margin-top: 6px; padding-top: 8px; }
  .acciones { display: flex; gap: 10px; margin-bottom: 14px; }
  button { border: 1px solid #1d4ed8; background: #1d4ed8; color: #fff; border-radius: 6px; padding: 8px 14px; font-size: 13px; cursor: pointer; }
  button.secondary { background: #fff; color: #1d4ed8; }
</style>
</head>
<body>
  <h2>Presupuesto</h2>
  <p>#{datos_costo[:total_piezas]} piezas · #{datos_costo[:puertas]} puerta(s) · #{datos_costo[:cajones]} cajón(es) estimados</p>
  <div class="acciones">
    <button onclick="recalcular()">Recalcular</button>
    <button class="secondary" onclick="exportarPdf()">Descargar PDF</button>
  </div>

  <h3>1. Tableros por material</h3>
  <table id="tabla_material">
    <thead><tr><th>Material</th><th>Área (m²)</th><th>Precio por m²</th><th>Subtotal</th></tr></thead>
    <tbody>#{filas_material}</tbody>
  </table>

  <h3>2. Cantos</h3>
  <table>
    <thead><tr><th>Concepto</th><th>Metros</th><th>Precio por metro</th><th>Subtotal</th></tr></thead>
    <tbody>
      <tr><td>Canto PVC</td><td class="num" id="metros_pvc">#{'%.2f' % datos_costo[:por_material].values.sum { |v| v[:canto_pvc_m] }}</td><td><input id="precio_pvc" type="number" step="0.01" value="0"></td><td class="num" id="subtotal_pvc">0.00</td></tr>
      <tr><td>Canto duro</td><td class="num" id="metros_duro">#{'%.2f' % datos_costo[:por_material].values.sum { |v| v[:canto_duro_m] }}</td><td><input id="precio_duro" type="number" step="0.01" value="0"></td><td class="num" id="subtotal_duro">0.00</td></tr>
    </tbody>
  </table>

  <h3>3. Herrajes estimados</h3>
  <table>
    <thead><tr><th>Concepto</th><th>Cantidad</th><th>Precio unitario</th><th>Subtotal</th></tr></thead>
    <tbody>
      <tr><td>Bisagras (2 por puerta)</td><td class="num" id="cant_bisagras">#{datos_costo[:puertas] * 2}</td><td><input id="precio_bisagra" type="number" step="0.01" value="0"></td><td class="num" id="subtotal_bisagras">0.00</td></tr>
      <tr><td>Juegos de corredera (1 por cajón)</td><td class="num" id="cant_correderas">#{datos_costo[:cajones]}</td><td><input id="precio_corredera" type="number" step="0.01" value="0"></td><td class="num" id="subtotal_correderas">0.00</td></tr>
      <tr><td>Jaladores/tiradores (1 por puerta/cajón)</td><td class="num" id="cant_jaladores">#{datos_costo[:puertas] + datos_costo[:cajones]}</td><td><input id="precio_jalador" type="number" step="0.01" value="0"></td><td class="num" id="subtotal_jaladores">0.00</td></tr>
    </tbody>
  </table>

  <h3>4. Otros costos</h3>
  <table>
    <thead><tr><th>Concepto</th><th>Monto</th></tr></thead>
    <tbody>
      <tr><td>Mano de obra</td><td><input id="costo_mano_obra" type="number" step="0.01" value="0"></td></tr>
      <tr><td>Transporte / instalación</td><td><input id="costo_transporte" type="number" step="0.01" value="0"></td></tr>
      <tr><td>Otros extras</td><td><input id="costo_otros" type="number" step="0.01" value="0"></td></tr>
      <tr><td>Margen de ganancia (%)</td><td><input id="margen_ganancia" type="number" step="0.5" value="0"></td></tr>
    </tbody>
  </table>

  <div class="totales">
    <div><span>Subtotal materiales y cantos</span><span id="total_materiales">0.00</span></div>
    <div><span>Subtotal herrajes</span><span id="total_herrajes">0.00</span></div>
    <div><span>Mano de obra + transporte + otros</span><span id="total_otros">0.00</span></div>
    <div><span>Margen de ganancia</span><span id="total_margen">0.00</span></div>
    <div class="grand"><span>Total</span><span id="total_general">0.00</span></div>
  </div>

  <script>
    function numero(id) { var el = document.getElementById(id); return el ? (parseFloat(el.value) || 0) : 0; }
    function texto(id, valor) { var el = document.getElementById(id); if (el) el.textContent = valor.toFixed(2); }
    function recalcular() {
      var totalMateriales = 0;
      document.querySelectorAll('#tabla_material tbody tr').forEach(function (fila) {
        var area = parseFloat(fila.querySelector('.precio-m2').dataset.area) || 0;
        var precio = parseFloat(fila.querySelector('.precio-m2').value) || 0;
        var subtotal = area * precio;
        fila.querySelector('.subtotal-material').textContent = subtotal.toFixed(2);
        totalMateriales += subtotal;
      });
      var subtotalPvc = numero('metros_pvc') * numero('precio_pvc'); texto('subtotal_pvc', subtotalPvc);
      var subtotalDuro = numero('metros_duro') * numero('precio_duro'); texto('subtotal_duro', subtotalDuro);
      totalMateriales += subtotalPvc + subtotalDuro;
      var subtotalBisagras = numero('cant_bisagras') * numero('precio_bisagra'); texto('subtotal_bisagras', subtotalBisagras);
      var subtotalCorrederas = numero('cant_correderas') * numero('precio_corredera'); texto('subtotal_correderas', subtotalCorrederas);
      var subtotalJaladores = numero('cant_jaladores') * numero('precio_jalador'); texto('subtotal_jaladores', subtotalJaladores);
      var totalHerrajes = subtotalBisagras + subtotalCorrederas + subtotalJaladores;
      var totalOtros = numero('costo_mano_obra') + numero('costo_transporte') + numero('costo_otros');
      var baseMargen = totalMateriales + totalHerrajes + totalOtros;
      var margen = baseMargen * (numero('margen_ganancia') / 100);
      texto('total_materiales', totalMateriales);
      texto('total_herrajes', totalHerrajes);
      texto('total_otros', totalOtros);
      texto('total_margen', margen);
      texto('total_general', baseMargen + margen);
    }
    function exportarPdf() {
      document.querySelectorAll('.acciones').forEach(function (el) { el.style.display = 'none'; });
      sketchup.exportarPresupuestoPdf(document.documentElement.outerHTML);
      document.querySelectorAll('.acciones').forEach(function (el) { el.style.display = 'flex'; });
    }
    document.addEventListener('input', recalcular);
    recalcular();
  </script>
</body>
</html>
    HTML

    dialogo = UI::HtmlDialog.new({
      :dialog_title => "#{Modular3D::PRODUCT_NAME} | Presupuesto",
      :preferences_key => 'com.lpenafiel.modular3d.presupuesto',
      :scrollable => true,
      :resizable => true,
      :width => 760,
      :height => 700,
      :style => UI::HtmlDialog::STYLE_WINDOW
    })
    dialogo.set_html(html)
    dialogo.add_action_callback('exportarPresupuestoPdf') do |_action_context, html_actual|
      self.imprimir_html_como_pdf(html_actual, 'presupuesto.pdf', 'Presupuesto')
    end
    dialogo.show
  end

  # --- BIBLIOTECA LOCAL ---
  def self.html_lista_biblioteca
    manifest = Modular3D::Library.cargar_manifest
    return '<p class="vacio">Aún no has guardado nada. Selecciona un grupo o componente y usa el formulario de arriba.</p>' if manifest['items'].empty?

    por_categoria = manifest['items'].group_by { |item| [item['categoria'], item['subcategoria']] }
    por_categoria.keys.sort.map do |clave|
      categoria, subcategoria = clave
      titulo = subcategoria.to_s.empty? ? categoria.to_s : "#{categoria} / #{subcategoria}"
      filas = por_categoria[clave].map do |item|
        "<div class='item-biblioteca'>" \
        "<span>#{html_escape(item['nombre'])}</span>" \
        "<div class='acciones-item'>" \
        "<button onclick=\"sketchup.bibliotecaCargar('#{item['id']}')\">Insertar</button>" \
        "<button class='secondary' onclick=\"sketchup.bibliotecaEliminar('#{item['id']}')\">Eliminar</button>" \
        "</div></div>"
      end.join
      "<div class='categoria-biblioteca'><h3>#{html_escape(titulo)}</h3>#{filas}</div>"
    end.join
  end

  def self.mostrar_biblioteca
    return unless acceso_autorizado?

    html = <<-HTML
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
  body { font-family: Segoe UI, Arial, sans-serif; margin: 18px; color: #111827; background: #f8fafc; }
  h2 { margin: 0 0 4px 0; }
  h3 { margin: 14px 0 6px 0; font-size: 13px; color: #1f2937; text-transform: uppercase; letter-spacing: .4px; }
  .ruta { font-size: 11px; color: #64748b; margin-bottom: 14px; word-break: break-all; }
  .row { display: grid; grid-template-columns: 110px 1fr; align-items: center; gap: 8px; margin-bottom: 8px; }
  input { border: 1px solid #cbd5e1; border-radius: 5px; padding: 6px 8px; font-size: 12px; width: 100%; }
  button { border: 1px solid #1d4ed8; background: #1d4ed8; color: #fff; border-radius: 5px; padding: 7px 12px; font-size: 12px; cursor: pointer; }
  button.secondary { background: #fff; color: #b42318; border-color: #b42318; }
  .categoria-biblioteca { border: 1px solid #e2e8f0; border-radius: 6px; padding: 8px 10px; margin-bottom: 10px; background: #fff; }
  .item-biblioteca { display: flex; align-items: center; justify-content: space-between; padding: 4px 0; border-top: 1px solid #f1f5f9; }
  .item-biblioteca:first-of-type { border-top: none; }
  .acciones-item { display: flex; gap: 6px; }
  .vacio { color: #64748b; font-size: 12px; }
  #mensaje { display: none; margin: 10px 0; padding: 8px 10px; border-radius: 6px; font-size: 12px; background: #ecfdf5; color: #065f46; border: 1px solid #a7f3d0; }
  #mensaje.error { background: #fef2f2; color: #991b1b; border-color: #fecaca; }
</style>
</head>
<body>
  <h2>Biblioteca local</h2>
  <p class="ruta">Se guarda como archivos .skp normales en: #{html_escape(Modular3D::Library.raiz)}<br>Para llevarla a otro equipo, copia esa carpeta completa (no hay sincronización en la nube).</p>
  <div id="mensaje"></div>
  <h3>Guardar la selección actual</h3>
  <div class="row"><label>Categoría</label><input id="lib_categoria" value="General"></div>
  <div class="row"><label>Subcategoría</label><input id="lib_subcategoria" placeholder="Opcional"></div>
  <div class="row"><label>Nombre</label><input id="lib_nombre" placeholder="Ej. Tirador barra 128mm"></div>
  <button onclick="guardar()">Guardar selección</button>
  <h3>Elementos guardados</h3>
  <div id="lista">#{html_lista_biblioteca}</div>
  <script>
    function mostrarMensaje(texto, esError) {
      var el = document.getElementById('mensaje');
      el.textContent = texto; el.className = esError ? 'error' : ''; el.style.display = 'block';
    }
    function guardar() {
      sketchup.bibliotecaGuardar(
        document.getElementById('lib_categoria').value,
        document.getElementById('lib_subcategoria').value,
        document.getElementById('lib_nombre').value
      );
    }
    window.Modular3DLibraryResult = function (resultado) {
      mostrarMensaje(resultado.message, !resultado.ok);
      if (resultado.ok && resultado.lista) document.getElementById('lista').innerHTML = resultado.lista;
    };
  </script>
</body>
</html>
    HTML

    dialogo = UI::HtmlDialog.new({
      :dialog_title => "#{Modular3D::PRODUCT_NAME} | Biblioteca local",
      :preferences_key => 'com.lpenafiel.modular3d.biblioteca',
      :scrollable => true,
      :resizable => true,
      :width => 480,
      :height => 640,
      :style => UI::HtmlDialog::STYLE_WINDOW
    })
    dialogo.set_html(html)
    dialogo.add_action_callback('bibliotecaGuardar') do |_action_context, categoria, subcategoria, nombre|
      resultado = Modular3D::Library.guardar_seleccion(categoria, subcategoria, nombre)
      resultado[:lista] = html_lista_biblioteca if resultado[:ok]
      dialogo.execute_script("window.Modular3DLibraryResult(#{JSON.generate(resultado)})")
    end
    dialogo.add_action_callback('bibliotecaCargar') do |_action_context, id|
      resultado = Modular3D::Library.cargar_item(id)
      dialogo.execute_script("window.Modular3DLibraryResult(#{JSON.generate(resultado)})")
    end
    dialogo.add_action_callback('bibliotecaEliminar') do |_action_context, id|
      resultado = Modular3D::Library.eliminar_item(id)
      resultado[:lista] = html_lista_biblioteca if resultado[:ok]
      dialogo.execute_script("window.Modular3DLibraryResult(#{JSON.generate(resultado)})")
    end
    dialogo.show
  end

  # --- CONSTRUCTOR DE HABITACIÓN BÁSICO (MUROS) ---
  # Alcance deliberado: muros rectos con su propio grosor y una losa de piso,
  # para tener un contexto donde ubicar módulos. Sin huecos de puerta/ventana
  # todavía: recortar un hueco pasante en un muro exige construir sus caras a
  # mano con una cara exterior perforada (un loop interior dentro de la
  # misma cara), que es una geometría más delicada para escribir sin poder
  # abrir SketchUp y comprobarla; los segmentos de muro en cambio son solo un
  # rectángulo por cada tramo, verificable con trigonometría simple.
  def self.generar_muros(datos)
    grosor = [(datos['grosor_muro'] || 150).to_f, 20.0].max.mm
    alto = [(datos['alto_muro'] || 2400).to_f, 500.0].max.mm
    grosor_piso = [(datos['grosor_piso'] || 100).to_f, 10.0].max.mm
    lineas = datos['segmentos'].to_s.split("\n").map(&:strip).reject(&:empty?)
    return { ok: false, message: 'Agrega al menos un tramo de muro (largo,ángulo por línea).' } if lineas.empty?

    segmentos = lineas.map do |linea|
      partes = linea.split(',').map(&:strip)
      return { ok: false, message: "Línea inválida: «#{linea}». Usa el formato largo_mm,angulo_grados." } unless partes.length == 2
      largo = Float(partes[0]) rescue nil
      angulo = Float(partes[1]) rescue nil
      return { ok: false, message: "Línea inválida: «#{linea}». Usa números para largo y ángulo." } unless largo && angulo
      return { ok: false, message: "El tramo «#{linea}» debe tener un largo mayor que 0." } unless largo.positive?
      [largo.mm, angulo]
    end

    model = Sketchup.active_model
    operacion_iniciada = false
    piezas = []
    begin
      model.start_operation('Generar habitación (muros)', true)
      operacion_iniciada = true
      entities = model.active_entities
      offset = offset_siguiente_modulo
      punto_actual = Geom::Point3d.new(offset.x, offset.y, offset.z)
      caja_planta = Geom::BoundingBox.new

      segmentos.each_with_index do |(largo, angulo_grados), indice|
        angulo = angulo_grados * Math::PI / 180.0
        direccion = Geom::Vector3d.new(Math.cos(angulo), Math.sin(angulo), 0)
        normal = Geom::Vector3d.new(-Math.sin(angulo), Math.cos(angulo), 0)
        punto_siguiente = punto_actual.offset(direccion, largo)
        mitad = grosor / 2.0
        # Orden verificado numéricamente para que coincida con el sentido
        # (antihorario visto desde +Z) que usa crear_pieza, de modo que
        # pushpull(-alto) extruya hacia arriba en vez de hacia abajo.
        c0 = punto_actual.offset(normal, -mitad)
        c1 = punto_siguiente.offset(normal, -mitad)
        c2 = punto_siguiente.offset(normal, mitad)
        c3 = punto_actual.offset(normal, mitad)
        caja_planta.add(c0, c1, c2, c3)

        grupo = entities.add_group
        cara = grupo.entities.add_face(c0, c1, c2, c3)
        cara.pushpull(-alto)
        instancia = grupo.to_component rescue grupo
        nombre_muro = "MURO_#{indice + 1}"
        if instancia.respond_to?(:definition)
          instancia.definition.name = nombre_muro
          instancia.definition.set_attribute('LPenafiel', 'pieza_original', nombre_muro)
          instancia.definition.set_attribute('LPenafiel', 'modulo', 'HABITACION')
        end
        self.aplicar_material_configurado(instancia, 'CASCO') rescue nil
        piezas << instancia
      end

      unless caja_planta.empty?
        grupo_piso = entities.add_group
        cara_piso = grupo_piso.entities.add_face(
          [caja_planta.min.x, caja_planta.min.y, 0], [caja_planta.max.x, caja_planta.min.y, 0],
          [caja_planta.max.x, caja_planta.max.y, 0], [caja_planta.min.x, caja_planta.max.y, 0]
        )
        cara_piso.pushpull(-grosor_piso)
        instancia_piso = grupo_piso.to_component rescue grupo_piso
        if instancia_piso.respond_to?(:definition)
          instancia_piso.definition.name = 'PISO_HABITACION'
          instancia_piso.definition.set_attribute('LPenafiel', 'pieza_original', 'PISO_HABITACION')
          instancia_piso.definition.set_attribute('LPenafiel', 'modulo', 'HABITACION')
        end
        piezas << instancia_piso
      end

      contenedor = entities.add_group(piezas.select { |item| item && item.valid? })
      contenedor.name = 'M3D_HABITACION' if contenedor.respond_to?(:name=)
      model.selection.clear
      model.selection.add(contenedor)
      model.commit_operation
      operacion_iniciada = false
      { ok: true, message: "Habitación generada: #{segmentos.length} muro(s)." }
    rescue StandardError => e
      model.abort_operation if operacion_iniciada
      { ok: false, message: "No se pudo generar la habitación: #{e.class}: #{e.message}" }
    end
  end

  def self.mostrar_constructor_habitacion
    return unless acceso_autorizado?

    html = <<-HTML
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
  body { font-family: Segoe UI, Arial, sans-serif; margin: 18px; color: #111827; background: #f8fafc; }
  h2 { margin: 0 0 4px 0; }
  p.hint { color: #64748b; font-size: 12px; margin: 0 0 12px 0; }
  .row { display: grid; grid-template-columns: 170px 1fr; align-items: center; gap: 10px; margin-bottom: 10px; }
  input, textarea { border: 1px solid #cbd5e1; border-radius: 5px; padding: 6px 8px; font-size: 13px; font-family: Consolas, monospace; }
  textarea { width: 100%; height: 120px; }
  button { border: 1px solid #1d4ed8; background: #1d4ed8; color: #fff; border-radius: 6px; padding: 9px 16px; font-size: 13px; cursor: pointer; }
  #mensaje { display: none; margin-top: 12px; padding: 8px 10px; border-radius: 6px; font-size: 12px; }
  #mensaje.error { display: block; background: #fef2f2; color: #991b1b; border: 1px solid #fecaca; }
  #mensaje.ok { display: block; background: #ecfdf5; color: #065f46; border: 1px solid #a7f3d0; }
</style>
</head>
<body>
  <h2>Habitación (muros)</h2>
  <p class="hint">Un tramo de muro por línea: <code>largo_mm,ángulo_grados</code>. El ángulo es absoluto (0° = eje X, 90° = eje Y), no relativo al tramo anterior. Ejemplo de una habitación rectangular de 4x3 m:<br><code>4000,0<br>3000,90<br>4000,180<br>3000,270</code></p>
  <div class="row"><label>Grosor de muro (mm)</label><input id="grosor_muro" type="number" value="150" min="20"></div>
  <div class="row"><label>Alto de muro (mm)</label><input id="alto_muro" type="number" value="2400" min="500"></div>
  <div class="row"><label>Grosor de piso (mm)</label><input id="grosor_piso" type="number" value="100" min="10"></div>
  <textarea id="segmentos">4000,0
3000,90
4000,180
3000,270</textarea>
  <br><br>
  <button id="construir">Generar habitación</button>
  <div id="mensaje"></div>
  <script>
    document.getElementById('construir').addEventListener('click', function () {
      sketchup.construirHabitacion({
        grosor_muro: parseFloat(document.getElementById('grosor_muro').value) || 150,
        alto_muro: parseFloat(document.getElementById('alto_muro').value) || 2400,
        grosor_piso: parseFloat(document.getElementById('grosor_piso').value) || 100,
        segmentos: document.getElementById('segmentos').value
      });
    });
    window.Modular3DRoomResult = function (resultado) {
      var el = document.getElementById('mensaje');
      el.textContent = resultado.message;
      el.className = resultado.ok ? 'ok' : 'error';
    };
  </script>
</body>
</html>
    HTML

    dialogo = UI::HtmlDialog.new({
      :dialog_title => "#{Modular3D::PRODUCT_NAME} | Habitación (muros)",
      :preferences_key => 'com.lpenafiel.modular3d.habitacion',
      :scrollable => true,
      :resizable => true,
      :width => 480,
      :height => 560,
      :style => UI::HtmlDialog::STYLE_WINDOW
    })
    dialogo.set_html(html)
    dialogo.add_action_callback('construirHabitacion') do |_action_context, datos|
      resultado = self.generar_muros(datos)
      dialogo.execute_script("window.Modular3DRoomResult(#{JSON.generate(resultado)})")
      dialogo.close if resultado[:ok]
    end
    dialogo.show
  end

end
