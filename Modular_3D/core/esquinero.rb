# frozen_string_literal: true

module LPenafiel_GeneradorMueblesExacto
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
end
