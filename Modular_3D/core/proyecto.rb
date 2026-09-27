# frozen_string_literal: true

require 'json'

module Modular3D
  # "Configuración de Proyecto" (§4 de la propuesta v5, inspirado en la
  # cascada estándar/pedido/artículo de imos): un conjunto de valores por
  # defecto guardado UNA VEZ POR MODELO (model.set_attribute, no por archivo
  # de disco -- viaja con el .skp, como cualquier otro dato del proyecto) que
  # se usa para precargar "Crear módulo" (ver commands/create_module.rb) y,
  # opcionalmente, se puede reaplicar a módulos ya existentes seleccionados
  # (ver LPenafiel_GeneradorMueblesExacto.aplicar_proyecto_a_seleccionados en
  # core/biblioteca.rb).
  #
  # Si el proyecto no tiene configuración guardada, cargar() devuelve {} (NO
  # los DEFAULTS de fábrica): un hash vacío hace que mostrar_interfaz_moderna
  # no inyecte nada (misma condición `if datos_iniciales && !datos_iniciales.
  # empty?` que ya usan Perfiles/plantillas), así que un proyecto sin
  # configuración propia se comporta exactamente igual que antes de esta
  # función existir.
  module Proyecto
    module_function

    ATRIBUTO_DICCIONARIO = 'Modular3D'
    ATRIBUTO_CLAVE = 'project_defaults'

    # Campos que tiene sentido llevar como default de PROYECTO (no de
    # PIEZA): medidas base de un módulo nuevo, huelgo/parámetro de diseño,
    # modo de canto, sistema de corredera y color/nombre de material global.
    # Deliberadamente NO incluye nada de jerarquía/espacios (eso es un
    # Principio de Espacio, ver core/principios.rb) ni nada de herrajes por
    # pieza individual.
    CAMPOS = %w[
      ancho_total alto_total prof_total espesor grosor_respaldo juego_general
      parametro_diseno_id edge_mode sistema_corredera montaje_puerta
      material_global_color material_global_nombre material_unico
    ].freeze

    # Subconjunto seguro para "Aplicar a la selección" sobre módulos YA
    # construidos: ver la nota en core/biblioteca.rb
    # (aplicar_proyecto_a_seleccionados) -- cambiar ancho_total/espesor/etc.
    # de un módulo existente exige reconstruir su geometría completa (la
    # misma lógica que ejecutarConstruccionMueble, dentro del callback del
    # diálogo principal) y no es seguro de mover sin poder probarlo en vivo
    # dentro de SketchUp. Estos campos, en cambio, solo afectan cómo se
    # pintan/exportan piezas que YA existen.
    CAMPOS_APLICABLES_A_EXISTENTES = %w[
      edge_mode sistema_corredera material_global_color material_global_nombre material_unico
    ].freeze

    def cargar(model)
      return {} unless model
      raw = model.get_attribute(ATRIBUTO_DICCIONARIO, ATRIBUTO_CLAVE)
      return {} if raw.to_s.strip.empty?

      datos = JSON.parse(raw.to_s)
      datos.is_a?(Hash) ? datos : {}
    rescue JSON::ParserError, StandardError
      {}
    end

    def guardar(model, datos)
      return { ok: false, message: 'No hay un modelo activo de SketchUp.' } unless model

      limpio = {}
      CAMPOS.each { |campo| limpio[campo] = datos[campo] unless datos[campo].nil? || datos[campo].to_s.strip.empty? }

      begin
        model.set_attribute(ATRIBUTO_DICCIONARIO, ATRIBUTO_CLAVE, JSON.generate(limpio))
      rescue StandardError => e
        return { ok: false, message: "No se pudo guardar la configuración de proyecto: #{e.message}" }
      end

      { ok: true, message: 'Configuración de proyecto guardada. Los módulos nuevos la usarán como punto de partida.', datos: limpio }
    end

    def mostrar_dialogo
      return unless Sketchup.active_model

      model = Sketchup.active_model
      actuales = cargar(model)
      defecto = Modular3D::DEFAULTS

      valor = lambda { |campo, respaldo| (actuales[campo].nil? ? respaldo : actuales[campo]).to_s }

      html = <<-HTML
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
  body { font-family: Segoe UI, Arial, sans-serif; margin: 18px; color: #111827; background: #f8fafc; }
  h2 { margin: 0 0 4px 0; }
  h3 { margin: 16px 0 6px 0; font-size: 13px; color: #1f2937; text-transform: uppercase; letter-spacing: .4px; }
  p.hint { color: #64748b; font-size: 12px; margin: 0 0 14px 0; }
  .row { display: grid; grid-template-columns: 160px 1fr; align-items: center; gap: 10px; margin-bottom: 8px; }
  input, select { border: 1px solid #cbd5e1; border-radius: 5px; padding: 6px 8px; font-size: 12px; width: 100%; box-sizing: border-box; }
  button { border: 1px solid #1d4ed8; background: #1d4ed8; color: #fff; border-radius: 6px; padding: 9px 16px; font-size: 13px; cursor: pointer; margin-right: 8px; }
  button.secondary { background: #fff; color: #1d4ed8; }
  #mensaje { display: none; margin-top: 12px; padding: 8px 10px; border-radius: 6px; font-size: 12px; background: #ecfdf5; color: #065f46; border: 1px solid #a7f3d0; }
  #mensaje.error { background: #fef2f2; color: #991b1b; border-color: #fecaca; }
  .acciones { margin-top: 14px; }
</style>
</head>
<body>
  <h2>Configuración de Proyecto</h2>
  <p class="hint">Estos valores se usan como punto de partida al crear un módulo nuevo en este archivo (no afectan a los módulos que ya existen, salvo que uses "Aplicar a la selección" más abajo).</p>

  <h3>Medidas por defecto</h3>
  <div class="row"><label>Ancho total (mm)</label><input id="p_ancho_total" type="number" value="#{html_escape(valor.call('ancho_total', defecto['ancho_total']))}"></div>
  <div class="row"><label>Alto total (mm)</label><input id="p_alto_total" type="number" value="#{html_escape(valor.call('alto_total', defecto['alto_total']))}"></div>
  <div class="row"><label>Profundidad total (mm)</label><input id="p_prof_total" type="number" value="#{html_escape(valor.call('prof_total', defecto['prof_total']))}"></div>
  <div class="row"><label>Espesor de tablero (mm)</label><input id="p_espesor" type="number" value="#{html_escape(valor.call('espesor', defecto['espesor']))}"></div>
  <div class="row"><label>Espesor de respaldo (mm)</label><input id="p_grosor_respaldo" type="number" value="#{html_escape(valor.call('grosor_respaldo', defecto['grosor_respaldo']))}"></div>

  <h3>Parámetro de diseño y herrajes</h3>
  <div class="row"><label>Parámetro de diseño</label>
    <select id="p_parametro_diseno_id">#{Modular3D::ParametrosDiseno.listar.map { |item| "<option value=\"#{html_escape(item['parametro_id'])}\"#{item['parametro_id'].to_s == valor.call('parametro_diseno_id', 'ESTANDAR') ? ' selected' : ''}>#{html_escape(item['nombre'])}</option>" }.join}</select>
  </div>
  <div class="row"><label>Modo de canto</label>
    <select id="p_edge_mode">
      <option value="MIXED"#{valor.call('edge_mode', 'MIXED') == 'MIXED' ? ' selected' : ''}>Mixto (frentes canto duro, resto PVC)</option>
      <option value="ALL_PVC"#{valor.call('edge_mode', 'MIXED') == 'ALL_PVC' ? ' selected' : ''}>Todo PVC</option>
      <option value="ALL_HARD"#{valor.call('edge_mode', 'MIXED') == 'ALL_HARD' ? ' selected' : ''}>Todo canto duro</option>
    </select>
  </div>
  <div class="row"><label>Sistema de corredera</label>
    <select id="p_sistema_corredera">#{Modular3D::Herrajes.correderas.map { |item| "<option value=\"#{html_escape(item['nombre'])}\"#{item['nombre'].to_s == valor.call('sistema_corredera', 'Telescopica estandar') ? ' selected' : ''}>#{html_escape(item['nombre'])}</option>" }.join}</select>
  </div>
  <div class="row"><label>Montaje de puerta</label>
    <select id="p_montaje_puerta">
      <option value="SOLAPADA"#{valor.call('montaje_puerta', 'SOLAPADA') == 'SOLAPADA' ? ' selected' : ''}>Solapada</option>
      <option value="EMBUTIDA"#{valor.call('montaje_puerta', 'SOLAPADA') == 'EMBUTIDA' ? ' selected' : ''}>Embutida</option>
    </select>
  </div>

  <h3>Material global por defecto</h3>
  <div class="row"><label>Usar un solo material</label>
    <select id="p_material_unico">
      <option value="NO"#{valor.call('material_unico', 'NO') == 'NO' ? ' selected' : ''}>No (uno por grupo)</option>
      <option value="SI"#{valor.call('material_unico', 'NO') == 'SI' ? ' selected' : ''}>Sí (uno para todo el módulo)</option>
    </select>
  </div>
  <div class="row"><label>Color</label><input id="p_material_global_color" type="color" value="#{html_escape(valor.call('material_global_color', '#d5a66e'))}"></div>
  <div class="row"><label>Nombre del material</label><input id="p_material_global_nombre" value="#{html_escape(valor.call('material_global_nombre', ''))}" placeholder="Ej. Blanco mate"></div>

  <div id="mensaje"></div>
  <div class="acciones">
    <button onclick="guardar()">Guardar configuración de proyecto</button>
    <button class="secondary" onclick="aplicar()">Aplicar a la selección actual</button>
  </div>
  <p class="hint">"Aplicar a la selección" solo actualiza material/canto/corredera de módulos ya construidos que tengas seleccionados -- no cambia sus medidas ni su geometría.</p>

  <script>
    function datos() {
      return {
        ancho_total: document.getElementById('p_ancho_total').value,
        alto_total: document.getElementById('p_alto_total').value,
        prof_total: document.getElementById('p_prof_total').value,
        espesor: document.getElementById('p_espesor').value,
        grosor_respaldo: document.getElementById('p_grosor_respaldo').value,
        parametro_diseno_id: document.getElementById('p_parametro_diseno_id').value,
        edge_mode: document.getElementById('p_edge_mode').value,
        sistema_corredera: document.getElementById('p_sistema_corredera').value,
        montaje_puerta: document.getElementById('p_montaje_puerta').value,
        material_unico: document.getElementById('p_material_unico').value,
        material_global_color: document.getElementById('p_material_global_color').value,
        material_global_nombre: document.getElementById('p_material_global_nombre').value
      };
    }
    function mostrarMensaje(texto, esError) {
      var el = document.getElementById('mensaje');
      el.textContent = texto; el.className = esError ? 'error' : ''; el.style.display = 'block';
    }
    function guardar() { sketchup.proyectoGuardar(datos()); }
    function aplicar() { sketchup.proyectoAplicarSeleccion(datos()); }
    window.Modular3DProyectoResult = function (resultado) { mostrarMensaje(resultado.message, !resultado.ok); };
  </script>
</body>
</html>
      HTML

      dialogo = UI::HtmlDialog.new({
        :dialog_title => "#{Modular3D::PRODUCT_NAME} | Configuración de Proyecto",
        :preferences_key => 'com.lpenafiel.modular3d.proyecto',
        :scrollable => true,
        :resizable => true,
        :width => 460,
        :height => 700,
        :style => UI::HtmlDialog::STYLE_WINDOW
      })
      dialogo.set_html(html)
      dialogo.add_action_callback('proyectoGuardar') do |_action_context, datos|
        resultado = guardar(model, datos)
        dialogo.execute_script("window.Modular3DProyectoResult(#{JSON.generate(resultado)})")
      end
      dialogo.add_action_callback('proyectoAplicarSeleccion') do |_action_context, datos|
        resultado = LPenafiel_GeneradorMueblesExacto.aplicar_proyecto_a_seleccionados(datos)
        dialogo.execute_script("window.Modular3DProyectoResult(#{JSON.generate(resultado)})")
      end
      dialogo.show
    end

    def html_escape(texto)
      texto.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;').gsub("'", '&#39;')
    end
  end
end
