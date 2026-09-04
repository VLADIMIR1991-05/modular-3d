# frozen_string_literal: true

module LPenafiel_GeneradorMueblesExacto
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
    @transformacion_edicion = nil
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
    datos['module_base_offset'] ||= [caja.min.x.to_mm, caja.min.y.to_mm, caja.min.z.to_mm]
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
end
