# frozen_string_literal: true

module LPenafiel_GeneradorMueblesExacto
  # "Panel de Proyecto" (§9 de la propuesta v5): un resumen agregado por
  # módulo (piezas, puertas, bisagras estimadas, cajones, área de tablero)
  # de TODA la selección (o de todo el modelo activo si no hay selección,
  # igual que Despiece/Presupuesto vía entidades_para_despiece), sin entrar
  # al detalle pieza por pieza que ya muestra Despiece. Reutiliza
  # deliberadamente las mismas funciones (recolectar_piezas_despiece,
  # bisagras_por_altura) para que los números coincidan siempre con
  # Despiece/Presupuesto -- no se recalculan por separado.
  def self.resumen_por_modulo_proyecto
    piezas = []
    entidades_para_despiece.each { |entity| recolectar_piezas_despiece(entity, piezas) }
    return [] if piezas.empty?

    agrupado = piezas.group_by { |pieza| pieza[:modulo_uuid].to_s }
    agrupado.map do |modulo_uuid, piezas_modulo|
      puertas = piezas_modulo.count { |pieza| pieza[:codigo].to_s == 'PT' }
      bisagras = piezas_modulo.sum { |pieza| pieza[:codigo].to_s == 'PT' ? bisagras_por_altura(pieza[:alto_real_mm]) : 0 }
      cajones = (piezas_modulo.count { |pieza| pieza[:codigo].to_s == 'COS' } / 2.0).ceil
      area_m2 = piezas_modulo.sum { |pieza| (pieza[:medida_1].to_f / 1000.0) * (pieza[:medida_2].to_f / 1000.0) }
      materiales = piezas_modulo.map { |pieza| pieza[:material].to_s }.reject(&:empty?).uniq
      {
        'modulo_uuid' => modulo_uuid,
        'nombre' => piezas_modulo.first[:modulo].to_s,
        'piezas' => piezas_modulo.length,
        'puertas' => puertas,
        'bisagras' => bisagras,
        'cajones' => cajones,
        'area_m2' => area_m2.round(2),
        'materiales' => materiales.join(', ')
      }
    end.sort_by { |fila| fila['nombre'] }
  end

  def self.fila_html_panel_proyecto(fila)
    "<tr>" \
    "<td>#{html_escape(fila['nombre'])}</td>" \
    "<td class='num'>#{fila['piezas']}</td>" \
    "<td class='num'>#{fila['puertas']}</td>" \
    "<td class='num'>#{fila['bisagras']}</td>" \
    "<td class='num'>#{fila['cajones']}</td>" \
    "<td class='num'>#{'%.2f' % fila['area_m2']}</td>" \
    "<td>#{html_escape(fila['materiales'])}</td>" \
    "</tr>"
  end

  def self.mostrar_panel_proyecto
    return unless acceso_autorizado?

    filas = resumen_por_modulo_proyecto
    if filas.empty?
      UI.messagebox('No se encontraron módulos Modular_3D reconocibles en la selección (o en el modelo, si no hay nada seleccionado).')
      return
    end

    total_piezas = filas.sum { |fila| fila['piezas'] }
    total_puertas = filas.sum { |fila| fila['puertas'] }
    total_bisagras = filas.sum { |fila| fila['bisagras'] }
    total_cajones = filas.sum { |fila| fila['cajones'] }
    total_area = filas.sum { |fila| fila['area_m2'] }

    filas_html = filas.map { |fila| fila_html_panel_proyecto(fila) }.join

    html = <<-HTML
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
  body { font-family: Segoe UI, Arial, sans-serif; margin: 18px; color: #111827; background: #f8fafc; }
  h2 { margin: 0 0 4px 0; }
  p.hint { color: #64748b; font-size: 12px; margin: 0 0 14px 0; }
  table { width: 100%; border-collapse: collapse; background: #fff; margin-bottom: 10px; }
  th, td { border: 1px solid #d1d5db; padding: 7px 8px; font-size: 12px; text-align: left; }
  th { background: #e5e7eb; font-weight: 700; }
  .num { text-align: right; }
  tfoot td { font-weight: 700; background: #f1f5f9; }
</style>
</head>
<body>
  <h2>Panel de Proyecto</h2>
  <p class="hint">Resumen por módulo de #{filas.length} módulo(s) en la selección actual (o de todo el modelo activo, si no seleccionaste nada). Los mismos totales que vería Despiece/Presupuesto, agrupados por módulo.</p>
  <table>
    <thead><tr><th>Módulo</th><th>Piezas</th><th>Puertas</th><th>Bisagras est.</th><th>Cajones</th><th>Área tablero (m²)</th><th>Materiales</th></tr></thead>
    <tbody>#{filas_html}</tbody>
    <tfoot><tr><td>Total (#{filas.length} módulos)</td><td class='num'>#{total_piezas}</td><td class='num'>#{total_puertas}</td><td class='num'>#{total_bisagras}</td><td class='num'>#{total_cajones}</td><td class='num'>#{'%.2f' % total_area}</td><td></td></tr></tfoot>
  </table>
</body>
</html>
    HTML

    dialogo = UI::HtmlDialog.new({
      :dialog_title => "#{Modular3D::PRODUCT_NAME} | Panel de Proyecto",
      :preferences_key => 'com.lpenafiel.modular3d.panelproyecto',
      :scrollable => true,
      :resizable => true,
      :width => 780,
      :height => 560,
      :style => UI::HtmlDialog::STYLE_WINDOW
    })
    dialogo.set_html(html)
    dialogo.show
  end
end
