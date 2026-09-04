# frozen_string_literal: true

module LPenafiel_GeneradorMueblesExacto
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
    piezas = []
    entidades_para_despiece.each { |entity| recolectar_piezas_despiece(entity, piezas) }
    return nil if piezas.empty?

    por_material = Hash.new { |hash, clave| hash[clave] = { :area_m2 => 0.0, :canto_pvc_m => 0.0, :canto_duro_m => 0.0 } }
    puertas = 0
    bisagras_total = 0
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
      # Solo puertas reales (codigo "PT") llevan bisagra: un frente de cajón
      # exterior no es una puerta aunque salga a su misma altura y solape.
      if pieza[:codigo].to_s == 'PT'
        puertas += 1
        bisagras_total += bisagras_por_altura(pieza[:alto_real_mm])
      end
      piezas_cos += 1 if pieza[:codigo].to_s == 'COS'
    end

    { :por_material => por_material, :puertas => puertas, :bisagras_total => bisagras_total, :cajones => (piezas_cos / 2.0).ceil, :total_piezas => piezas.length }
  end

  def self.mostrar_presupuesto
    return unless acceso_autorizado?
    datos_costo = datos_costo_seleccion
    unless datos_costo
      UI.messagebox('No se encontraron piezas con datos de despiece en el modelo para presupuestar.')
      return
    end

    filas_material = datos_costo[:por_material].map do |material, valores|
      "<tr data-material='#{html_escape(material)}'>" \
      "<td>#{html_escape(material)}</td>" \
      "<td class='num'>#{'%.2f' % valores[:area_m2]}</td>" \
      "<td>" \
      "<input class='precio-m2' type='number' step='0.01' value='0' data-area='#{valores[:area_m2]}'>" \
      "<div class='modo-tablero'>" \
      "<label class='switch-tablero'><input type='checkbox' class='usar-tablero'> Por costo total del tablero</label>" \
      "<div class='campos-tablero' hidden>" \
      "<input class='tablero-ancho' type='number' value='1830' step='1' title='Ancho del tablero (mm)'> x " \
      "<input class='tablero-largo' type='number' value='2440' step='1' title='Largo del tablero (mm)'> mm · Costo total " \
      "<input class='tablero-costo' type='number' value='0' step='0.01' title='Costo total del tablero completo'>" \
      "</div></div>" \
      "</td>" \
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
  p.hint { color: #64748b; font-size: 11.5px; margin: -4px 0 8px 0; }
  .modo-tablero { margin-top: 5px; }
  .switch-tablero { display: flex; align-items: center; gap: 5px; font-size: 11px; color: #475569; width: max-content; }
  .switch-tablero input { width: auto; }
  .campos-tablero { margin-top: 4px; display: flex; align-items: center; gap: 4px; font-size: 11px; color: #475569; flex-wrap: wrap; }
  .campos-tablero input { width: 58px; }
  input:disabled { background: #f1f5f9; color: #64748b; }
  .titulo-editable { font-size: 15px; font-weight: 600; border: none; background: transparent; padding: 4px 0; margin: 0 0 6px 0; width: 100%; color: #1f2937; }
  .titulo-editable:focus { outline: 1px dashed #94a3b8; }
  .titulo-editable::placeholder { color: #94a3b8; font-weight: 400; }
</style>
</head>
<body>
  <h2>Presupuesto</h2>
  <input class="titulo-editable" id="presupuesto_titulo" type="text" placeholder="Nombre del proyecto o cliente (opcional, ej. Presupuesto Familia Pérez)">
  <p>#{datos_costo[:total_piezas]} piezas · #{datos_costo[:puertas]} puerta(s) · #{datos_costo[:bisagras_total]} bisagra(s) estimadas · #{datos_costo[:cajones]} cajón(es) estimados</p>
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
  <p class="hint">Bisagras calculadas automáticamente según la altura real de cada puerta (2 hasta 950mm, 3 hasta 1400mm, 4 hasta 2120mm, 5 en puertas más altas). Los frentes de cajón no suman bisagras, solo las puertas.</p>
  <table>
    <thead><tr><th>Concepto</th><th>Cantidad</th><th>Precio unitario</th><th>Subtotal</th></tr></thead>
    <tbody>
      <tr><td>Bisagras (según altura de cada puerta)</td><td class="num" id="cant_bisagras">#{datos_costo[:bisagras_total]}</td><td><input id="precio_bisagra" type="number" step="0.01" value="0"></td><td class="num" id="subtotal_bisagras">0.00</td></tr>
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
    // Las celdas de cantidad/metros (metros_pvc, cant_bisagras, etc.) son <td>
    // de solo texto, no <input>: no tienen .value, así que necesitan su
    // propia lectura por .textContent (antes se leían con numero() y siempre
    // daban NaN -> 0, por eso Cantos y Herrajes nunca mostraban subtotal).
    function numeroTexto(id) { var el = document.getElementById(id); return el ? (parseFloat(el.textContent) || 0) : 0; }
    function texto(id, valor) { var el = document.getElementById(id); if (el) el.textContent = valor.toFixed(2); }
    function recalcular() {
      var totalMateriales = 0;
      document.querySelectorAll('#tabla_material tbody tr').forEach(function (fila) {
        var area = parseFloat(fila.querySelector('.precio-m2').dataset.area) || 0;
        var precioInput = fila.querySelector('.precio-m2');
        var usarTablero = fila.querySelector('.usar-tablero');
        var campos = fila.querySelector('.campos-tablero');
        var precio;
        if (usarTablero && usarTablero.checked) {
          if (campos) campos.hidden = false;
          var anchoT = parseFloat(fila.querySelector('.tablero-ancho').value) || 0;
          var largoT = parseFloat(fila.querySelector('.tablero-largo').value) || 0;
          var costoT = parseFloat(fila.querySelector('.tablero-costo').value) || 0;
          var areaTablero = (anchoT * largoT) / 1000000;
          precio = areaTablero > 0 ? (costoT / areaTablero) : 0;
          precioInput.value = precio.toFixed(2);
          precioInput.disabled = true;
        } else {
          if (campos) campos.hidden = true;
          precioInput.disabled = false;
          precio = parseFloat(precioInput.value) || 0;
        }
        var subtotal = area * precio;
        fila.querySelector('.subtotal-material').textContent = subtotal.toFixed(2);
        totalMateriales += subtotal;
      });
      var subtotalPvc = numeroTexto('metros_pvc') * numero('precio_pvc'); texto('subtotal_pvc', subtotalPvc);
      var subtotalDuro = numeroTexto('metros_duro') * numero('precio_duro'); texto('subtotal_duro', subtotalDuro);
      totalMateriales += subtotalPvc + subtotalDuro;
      var subtotalBisagras = numeroTexto('cant_bisagras') * numero('precio_bisagra'); texto('subtotal_bisagras', subtotalBisagras);
      var subtotalCorrederas = numeroTexto('cant_correderas') * numero('precio_corredera'); texto('subtotal_correderas', subtotalCorrederas);
      var subtotalJaladores = numeroTexto('cant_jaladores') * numero('precio_jalador'); texto('subtotal_jaladores', subtotalJaladores);
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
    function congelarValoresParaExportar() {
      // outerHTML serializa el atributo value="" original de cada <input>,
      // no lo que el usuario escribió (eso vive solo en la propiedad .value
      // en memoria): por eso el PDF salía siempre con todo en 0.00 aunque en
      // pantalla ya calculaba bien. Se copia .value/checked a los atributos
      // justo antes de capturar el HTML para que el PDF conserve lo tecleado.
      document.querySelectorAll('input').forEach(function (el) {
        if (el.type === 'checkbox') {
          if (el.checked) el.setAttribute('checked', 'checked'); else el.removeAttribute('checked');
        } else {
          el.setAttribute('value', el.value);
        }
      });
    }
    function exportarPdf() {
      recalcular();
      congelarValoresParaExportar();
      document.querySelectorAll('.acciones').forEach(function (el) { el.style.display = 'none'; });
      sketchup.exportarPresupuestoPdf(document.documentElement.outerHTML);
      document.querySelectorAll('.acciones').forEach(function (el) { el.style.display = 'flex'; });
    }
    document.addEventListener('input', recalcular);
    document.addEventListener('change', recalcular);
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
      begin
        self.imprimir_html_como_pdf(html_actual, 'presupuesto.pdf', 'Presupuesto')
      rescue StandardError => e
        UI.messagebox("No se pudo exportar a PDF: #{e.class}: #{e.message}")
      end
    end
    dialogo.show
  end

  # --- BIBLIOTECA LOCAL ---
end
