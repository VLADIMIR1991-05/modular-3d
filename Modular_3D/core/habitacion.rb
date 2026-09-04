# frozen_string_literal: true

module LPenafiel_GeneradorMueblesExacto
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
