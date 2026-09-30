# frozen_string_literal: true

module LPenafiel_GeneradorMueblesExacto
  # "Sincronizar continuidad" (decisiones D2/D3 del informe de zócalo/
  # premesón/cornisa): une el zócalo, premesón y cornisa de módulos que
  # quedan pegados unos a otros, en tramos de hasta 2420mm (igual criterio
  # que un tablero de melamina estándar), en vez de que cada módulo
  # mantenga su propia pieza separada.
  #
  # Deliberadamente NO se borra ninguna pieza del módulo individual: se
  # OCULTA (visible=false) la pieza que queda cubierta por un tramo
  # continuo, y la pieza fusionada se crea aparte, en un grupo propio
  # ("M3D_CONTINUIDAD_<pieza>_<n>"). Este comando se puede correr las
  # veces que haga falta -- cada corrida primero borra los grupos de
  # continuidad anteriores y vuelve a hacer visibles todas las piezas
  # individuales, así que mover o borrar un módulo y volver a sincronizar
  # nunca deja una pieza escondida "huérfana" ni un tramo viejo colgando.
  #
  # Limitación deliberada: solo detecta módulos SIN rotación (traslación
  # pura), alineados en línea recta sobre el eje X -- el caso común de un
  # tramo de muebles contra una pared recta. Un módulo rotado (esquinero,
  # contra otra pared) queda fuera de la fusión automática sin avisar
  # error: simplemente conserva sus propias piezas tal cual las construyó.
  #
  # Las dimensiones del tramo fusionado se MIDEN de las piezas reales ya
  # construidas (no repiten constantes de jerarquia.rb): así este comando
  # sigue funcionando aunque el motor de geometría cambie esos valores
  # en el futuro.
  CONTINUIDAD_TRAMO_MAX = 2420.mm
  CONTINUIDAD_TOLERANCIA = 3.mm

  def self.continuidad_traslacion_pura?(transformacion)
    [[transformacion.xaxis.to_a, [1.0, 0.0, 0.0]], [transformacion.yaxis.to_a, [0.0, 1.0, 0.0]]].all? do |real, esperado|
      (0..2).all? { |indice| (real[indice] - esperado[indice]).abs < 0.001 }
    end
  end

  def self.continuidad_pieza_y_bounds(modulo_entity, nombre_pieza)
    contenedor = modulo_entity.respond_to?(:definition) && modulo_entity.definition ? modulo_entity.definition.entities : modulo_entity.entities
    return nil unless contenedor
    pieza = contenedor.to_a.find do |hijo|
      hijo.respond_to?(:definition) && hijo.definition &&
        hijo.definition.get_attribute('LPenafiel', 'pieza_original').to_s == nombre_pieza
    end
    return nil unless pieza
    origen = modulo_entity.transformation.origin
    local = pieza.bounds
    {
      'pieza' => pieza,
      'x_min' => local.min.x + origen.x, 'x_max' => local.max.x + origen.x,
      'y_min' => local.min.y + origen.y, 'y_max' => local.max.y + origen.y,
      'z_min' => local.min.z + origen.z, 'z_max' => local.max.z + origen.z
    }
  end

  def self.continuidad_candidatos(nombre_pieza, filtro)
    candidatos = []
    entidades_para_despiece.each do |entity|
      manifiesto = manifiesto_de_entidad(entity)
      next unless manifiesto && manifiesto['data'].is_a?(Hash)
      next unless filtro.call(manifiesto['data'])
      next unless entity.respond_to?(:transformation) && continuidad_traslacion_pura?(entity.transformation)
      info = continuidad_pieza_y_bounds(entity, nombre_pieza)
      next unless info
      # Del módulo DUEÑO de esta pieza (no de la pieza en sí): hace falta
      # para decidir, al fusionar el tramo, si el extremo real (izq del
      # primero / der del último del segmento) tiene remate -- ver canto
      # del Premesón fusionado en continuidad_procesar_familia.
      info['remate_inicial'] = (manifiesto['data']['remate_inicial'] || 'NO').to_s == 'SI'
      info['remate_final'] = (manifiesto['data']['remate_final'] || 'NO').to_s == 'SI'
      candidatos << info
    end
    candidatos
  end

  def self.continuidad_encadenar(piezas)
    grupos = Hash.new { |hash, key| hash[key] = [] }
    piezas.each do |pieza|
      llave = [pieza['z_min'].to_mm.round(1), pieza['y_min'].to_mm.round(1), pieza['y_max'].to_mm.round(1)]
      grupos[llave] << pieza
    end
    cadenas = []
    grupos.each_value do |grupo|
      ordenado = grupo.sort_by { |pieza| pieza['x_min'] }
      actual = []
      ordenado.each do |pieza|
        if actual.empty? || (pieza['x_min'] - actual.last['x_max']).abs <= CONTINUIDAD_TOLERANCIA
          actual << pieza
        else
          cadenas << actual if actual.length > 1
          actual = [pieza]
        end
      end
      cadenas << actual if actual.length > 1
    end
    cadenas
  end

  def self.continuidad_segmentar(cadena)
    segmentos = []
    actual = []
    cadena.each do |pieza|
      if actual.empty? || (pieza['x_max'] - actual.first['x_min']) <= CONTINUIDAD_TRAMO_MAX
        actual << pieza
      else
        segmentos << actual
        actual = [pieza]
      end
    end
    segmentos << actual unless actual.empty?
    segmentos
  end

  def self.continuidad_procesar_familia(model, nombre_pieza, filtro)
    tramos = 0
    cadenas = continuidad_encadenar(continuidad_candidatos(nombre_pieza, filtro))
    cadenas.each do |cadena|
      continuidad_segmentar(cadena).each do |segmento|
        next if segmento.length < 2

        primero = segmento.first
        ultimo = segmento.last
        segmento.each { |pieza| pieza['pieza'].visible = false }
        tramos += 1
        contenedor = model.entities.add_group
        contenedor.name = "M3D_CONTINUIDAD_#{nombre_pieza}_#{tramos}"
        ancho = ultimo['x_max'] - primero['x_min']
        prof = primero['y_max'] - primero['y_min']
        alto = primero['z_max'] - primero['z_min']
        # Zócalo y Cornisa cantean SIEMPRE sus 2 extremos, tengan remate o
        # no (pedido explícito del usuario); las juntas internas entre los
        # módulos que este tramo fusiona ya no existen como extremos una
        # vez fusionadas, así que no hace falta distinguirlas aparte. El
        # Premesón es la única excepción: su extremo real (izquierdo del
        # primer módulo del tramo / derecho del último) solo cantea si ese
        # módulo no tiene remate de ese lado.
        cantos_l, cantos_c = if nombre_pieza == 'PREMESON'
                               [1, (primero['remate_inicial'] ? 0 : 1) + (ultimo['remate_final'] ? 0 : 1)]
                             else
                               [0, 2]
                             end
        instancia_fusionada = self.crear_pieza(contenedor.entities, 'CONTINUIDAD', nombre_pieza, ancho, prof, alto, primero['x_min'], primero['y_min'], primero['z_min'], cantos_l, cantos_c)
        self.continuidad_copiar_material(instancia_fusionada, primero['pieza'])
      end
    end
    tramos
  end

  # crear_pieza (vía aplicar_material_configurado) no puede leer el color
  # REAL configurado acá -- @datos_modulo_actual está vacío a propósito
  # durante todo "Sincronizar continuidad" (mezcla piezas de módulos
  # distintos en una sola pasada, ver sincronizar_continuidad), así que sin
  # esto la pieza fusionada salía con un color/nombre genérico de respaldo
  # en vez del color que el usuario ya había configurado (reportado: salía
  # con Material="Zocalo"/"Cornisa"/"Premeson" en vez de "Blanco"). En vez
  # de recalcular la configuración, se copia tal cual el material/color/
  # canto que YA tenía la pieza original que este tramo reemplaza -- por
  # defecto queda del mismo color, y el usuario lo puede recolorear después
  # a mano como cualquier otra pieza.
  def self.continuidad_copiar_material(instancia_nueva, pieza_original)
    return unless instancia_nueva && pieza_original
    material = pieza_original.respond_to?(:material) ? pieza_original.material : nil
    instancia_nueva.material = material if instancia_nueva.respond_to?(:material=)
    if instancia_nueva.respond_to?(:definition) && instancia_nueva.definition
      instancia_nueva.definition.entities.grep(Sketchup::Face).each do |cara|
        cara.material = material
        cara.back_material = material
      end
    end
    return unless pieza_original.respond_to?(:definition) && pieza_original.definition
    return unless instancia_nueva.respond_to?(:definition) && instancia_nueva.definition
    %w[grupo_material material_configurado color_configurado tipo_canto color_canto color_canto_nombre].each do |clave|
      valor = pieza_original.definition.get_attribute('LPenafiel', clave)
      instancia_nueva.definition.set_attribute('LPenafiel', clave, valor) unless valor.nil?
    end
  end

  def self.sincronizar_continuidad
    return unless acceso_autorizado?

    model = Sketchup.active_model
    operacion_iniciada = false
    datos_previos = @datos_modulo_actual
    offset_previo = @offset_creacion
    tramos_creados = 0
    begin
      model.start_operation('Sincronizar continuidad', true)
      operacion_iniciada = true
      @datos_modulo_actual = {}
      @offset_creacion = nil

      model.entities.grep(Sketchup::Group).select { |grupo| grupo.name.to_s.start_with?('M3D_CONTINUIDAD_') }.each(&:erase!)

      # Antes de decidir qué se fusiona, todas las piezas individuales
      # vuelven a ser visibles -- si una sincronización anterior dejó
      # alguna oculta por un tramo que ya no existe, no se queda escondida.
      entidades_para_despiece.each do |entity|
        manifiesto = manifiesto_de_entidad(entity)
        next unless manifiesto && manifiesto['data'].is_a?(Hash)
        %w[ZOCALO PREMESON CORNISA].each do |nombre|
          info = continuidad_pieza_y_bounds(entity, nombre)
          info['pieza'].visible = true if info
        end
      end

      tramos_creados += continuidad_procesar_familia(model, 'ZOCALO', ->(datos) { %w[BAJO AUXILIAR CLOSET].include?((datos['tipo_modulo'] || '').to_s.upcase) })
      tramos_creados += continuidad_procesar_familia(model, 'PREMESON', ->(datos) { (datos['tipo_modulo'] || '').to_s.upcase == 'BAJO' })
      tramos_creados += continuidad_procesar_familia(model, 'CORNISA', ->(datos) { (datos['cornisa_activa'] || 'NO').to_s == 'SI' })

      model.commit_operation
      operacion_iniciada = false
    rescue StandardError => e
      model.abort_operation if operacion_iniciada
      UI.messagebox("No se pudo sincronizar la continuidad: #{e.message}")
      return
    ensure
      @datos_modulo_actual = datos_previos
      @offset_creacion = offset_previo
    end

    if tramos_creados.zero?
      UI.messagebox("No se encontraron módulos pegados para fusionar (o ya estaban fusionados). Solo se detectan módulos sin rotación, alineados en línea recta, con zócalo/premesón/cornisa activados.")
    else
      UI.messagebox("Continuidad sincronizada: #{tramos_creados} tramo(s) fusionado(s).")
    end
  end
end
