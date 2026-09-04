# frozen_string_literal: true

module LPenafiel_GeneradorMueblesExacto
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
    # Las piezas parametricas guardan el nombre "amigable" del material que
    # el usuario tipeo (p. ej. "Blanco") en LPenafiel/material_configurado;
    # usarlo tal cual evita mostrar el nombre TECNICO interno de SketchUp
    # (M3D_Blanco_FFFFFF -- el prefijo M3D_ y el color en hex son solo para
    # que SketchUp no mezcle dos materiales iguales de color distinto entre
    # si, no estan pensados para que el usuario los vea). Las piezas sin
    # este atributo (diseño libre / importadas) siguen con la deteccion por
    # los materiales reales de sus caras.
    if entity.respond_to?(:definition) && entity.definition
      nombre_configurado = entity.definition.get_attribute("LPenafiel", "material_configurado")
      return nombre_configurado.to_s unless nombre_configurado.to_s.empty?
    end
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
    modulo = definicion.get_attribute("LPenafiel", "modulo_despiece") || definicion.get_attribute("LPenafiel", "modulo") || "SIN_MODULO"
    # modulo_uuid identifica el modulo REAL construido (a diferencia de
    # "modulo", una firma por dimensiones que puede repetirse si hay dos
    # modulos identicos): separa el despiece en secciones por modulo real y
    # no mezcla la foto 3D de uno con la de otro. Las piezas mas viejas sin
    # este atributo (construidas antes de que existiera) caen de vuelta a
    # "modulo" tal cual, que sigue siendo unico en la practica para ellas.
    modulo_uuid = definicion.get_attribute("LPenafiel", "modulo_uuid") || modulo

    # DEBUG TEMPORAL (a retirar en cuanto se confirme el fix del bug de
    # cantidad de bisagras incorrecta): compara la altura guardada en el
    # atributo dimension_1_mm (al momento de construir la puerta) contra la
    # altura medida en vivo via bounds.height (la que usa el calculo de
    # bisagras). Se ve en Window > Ruby Console. No cambia comportamiento.
    if codigo.to_s == 'PT'
      alto_bounds_mm = entity.respond_to?(:bounds) ? dimension_mm(entity.bounds.height) : nil
      puts "[Modular_3D DEBUG bisagra] pieza=#{definicion.name} dimension_1_mm(guardado)=#{definicion.get_attribute('LPenafiel', 'dimension_1_mm')} dimension_2_mm(guardado)=#{definicion.get_attribute('LPenafiel', 'dimension_2_mm')} bounds.height(vivo)=#{alto_bounds_mm} bounds.width(vivo)=#{entity.respond_to?(:bounds) ? dimension_mm(entity.bounds.width) : nil} bounds.depth(vivo)=#{entity.respond_to?(:bounds) ? dimension_mm(entity.bounds.depth) : nil}"
    end

    {
      :modulo => modulo,
      :modulo_uuid => modulo_uuid,
      :codigo => codigo.to_s,
      :nombre_legible => etiqueta_despiece_pieza(codigo.to_s),
      # Las piezas parametricas ya muestran una vista 3D del modulo completo
      # (view_snapshot); las de diseño libre no pertenecen a ningún módulo
      # real, así que se les genera una miniatura de su propia geometría.
      :miniatura => modulo.to_s == 'DISENO_LIBRE' ? miniatura_pieza(definicion) : nil,
      :medida_1 => definicion.get_attribute("LPenafiel", "dimension_1_mm").to_i,
      :medida_2 => definicion.get_attribute("LPenafiel", "dimension_2_mm").to_i,
      # Altura real (Z) de la pieza tal cual quedó dibujada, independiente del
      # orden mayor/menor de medida_1/medida_2 (esos se ordenan para el
      # listado de corte y no siempre coinciden con la altura). Se usa para
      # calcular cuántas bisagras necesita cada puerta según su altura real.
      :alto_real_mm => entity.respond_to?(:bounds) ? dimension_mm(entity.bounds.height) : 0,
      :tipo_bisagra => definicion.get_attribute("LPenafiel", "tipo_bisagra"),
      :placa => definicion.get_attribute("LPenafiel", "placa_mm").to_i,
      :canto_1 => definicion.get_attribute("LPenafiel", "cantos_largos").to_i,
      :canto_2 => definicion.get_attribute("LPenafiel", "cantos_cortos").to_i,
      :pieza_original => definicion.get_attribute("LPenafiel", "pieza_original") || definicion.name,
      :datos_modulo => definicion.get_attribute("LPenafiel", "datos_modulo"),
      :material => material_pieza(entity),
      :tipo_canto => definicion.get_attribute("LPenafiel", "tipo_canto") || "PVC",
      :color_canto => definicion.get_attribute("LPenafiel", "color_canto_nombre") || definicion.get_attribute("LPenafiel", "color_canto") || definicion.get_attribute("LPenafiel", "color_configurado"),
      :inglete => etiqueta_inglete(definicion.get_attribute("LPenafiel", "inglete_esquina"), definicion.get_attribute("LPenafiel", "inglete_medida_mm"))
    }
  end

  def self.etiqueta_tipo_canto(tipo)
    tipo.to_s.upcase == 'HARD' ? 'Canto duro' : 'PVC'
  end

  # Miniatura real (no un ícono genérico) de una pieza puntual, usando el
  # renderizador de miniaturas nativo de SketchUp. Pensada para piezas de
  # diseño libre, que no pertenecen a ningún módulo parametrico con su
  # propia vista 3D guardada.
  def self.miniatura_pieza(definicion)
    ruta = File.join(Sketchup.temp_dir, "m3d_thumb_#{rand(1_000_000_000)}.png")
    ok = definicion.save_thumbnail(ruta)
    return nil unless ok && File.exist?(ruta)
    binario = File.binread(ruta)
    "data:image/png;base64,#{[binario].pack('m0')}"
  rescue StandardError
    nil
  ensure
    File.delete(ruta) if ruta && File.exist?(ruta)
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
      csv << ['Módulo', 'Nombre', 'Cantidad', 'Medida 1', 'Canto 1', 'Medida 2', 'Canto 2', 'Placa', 'Material', 'Tipo canto', 'Color canto', 'Inglete', 'Bisagrado']
      filas.each do |fila|
        csv << %w[modulo nombre cantidad medida1 canto1 medida2 canto2 placa material tipo_canto color_canto inglete bisagrado].map { |clave| fila[clave] }
      end
    end
    # "\xEF\xBB\xBF".b es ASCII-8BIT y contenido.encode('UTF-8') es UTF-8:
    # concatenarlos directo revienta con Encoding::CompatibilityError en
    # cuanto el contenido trae un caracter no-ASCII (p. ej. "Ø" de "Ø35mm"
    # en la columna Bisagrado). Forzando ambos a ASCII-8BIT antes de sumar,
    # es una concatenacion de bytes crudos sin chequeo de compatibilidad.
    File.binwrite(path, "\xEF\xBB\xBF".b + contenido.encode('UTF-8').b)
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

  def self.fila_tr_html_despiece(fila, editable)
    clase_editable = editable ? "editable" : ""
    data_attrs = editable ? " data-campo='nombre'" : ""
    "<tr>" \
    "<td>#{fila['miniatura'] ? "<img class='pieza-miniatura' src='#{html_escape(fila['miniatura'])}' alt='Vista 3D de #{html_escape(fila['nombre'])}'>" : ''}</td>" \
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
    "<td#{editable ? " data-campo='bisagrado'" : ""}>#{html_escape(fila['bisagrado'])}</td>" \
    "</tr>"
  end

  def self.seccion_modulo_html(nombre_export, titulo, subtitulo, foto_html, filas_seccion, editable, clave_uuid = nil)
    # data-modulo lleva el nombre LEGIBLE (no un UUID interno): filasActuales()
    # en el HTML lo vuelve a leer al exportar Excel/PDF y termina en la
    # columna "Modulo" del CSV -- debe quedar entendible ahi, no una clave.
    # data-modulo-uuid guarda la clave REAL de agrupamiento (para que, al
    # exportar a PDF, dos modulos con el mismo nombre/medidas no se
    # vuelvan a mezclar en una sola tabla).
    filas_html = filas_seccion.map { |fila| fila_tr_html_despiece(fila, editable) }.join
    "<section class='modulo-page'><div class='modulo-head'>#{foto_html}<div><h3>#{html_escape(titulo)}</h3><p>#{html_escape(subtitulo)}</p></div></div>" \
    "<table data-modulo='#{html_escape(nombre_export)}' data-modulo-uuid='#{html_escape((clave_uuid || nombre_export).to_s)}'>" \
    "<thead><tr><th>Vista</th><th>Nombre</th><th>Cant.</th><th>Medida 1</th><th>Canto 1</th><th>Medida 2</th><th>Canto 2</th><th>Placa</th><th>Material</th><th>Tipo canto</th><th>Color canto</th><th>Inglete</th><th>Bisagrado</th></tr></thead>" \
    "<tbody>#{filas_html}</tbody>" \
    "</table></section>"
  end

  # Cada modulo REAL construido (identificado por modulo_uuid, no por la
  # firma de dimensiones "modulo" -- dos modulos identicos en medidas no
  # deben pisarse la foto ni mezclarse en una sola seccion) obtiene su
  # propia seccion con su propia foto 3D guardada al construirlo.
  def self.filas_html_despiece(filas, editable)
    por_modulo = filas.group_by { |fila| fila["modulo_uuid"].to_s }
    # La seccion global (si existe) siempre va al final, como resumen
    # despues de los modulos individuales, no intercalada alfabeticamente.
    claves_ordenadas = por_modulo.keys.reject { |clave| clave == '__GLOBAL_TODOS_LOS_MODULOS__' }.sort
    claves_ordenadas << '__GLOBAL_TODOS_LOS_MODULOS__' if por_modulo.key?('__GLOBAL_TODOS_LOS_MODULOS__')

    claves_ordenadas.map do |modulo_uuid|
      filas_originales = por_modulo[modulo_uuid]
      titulo = filas_originales.first["modulo"].to_s
      es_global = modulo_uuid == '__GLOBAL_TODOS_LOS_MODULOS__'
      if es_global
        foto_capturada = captura_vista_actual
        foto_html = foto_capturada ? "<img class='modulo-view' src='#{html_escape(foto_capturada)}' alt='Vista general de todos los modulos'>" : svg_modulo_despiece(titulo, filas_originales)
        next seccion_modulo_html(titulo, 'Todos los módulos (global)', 'Cutlist combinado de toda la selección, para mandar a cortar de una sola vez.', foto_html, filas_originales, editable, modulo_uuid)
      end
      vista_guardada = begin
        Sketchup.active_model.get_attribute('Modular3DViews', modulo_uuid.to_s).to_s
      rescue StandardError
        ''
      end
      # Compatibilidad con modulos guardados antes de que existiera
      # modulo_uuid: su foto habia quedado guardada con la clave vieja
      # (la firma de dimensiones).
      if vista_guardada.empty?
        vista_guardada = begin
          Sketchup.active_model.get_attribute('Modular3DViews', titulo).to_s
        rescue StandardError
          ''
        end
      end
      foto_html = vista_guardada.start_with?('data:image/') ? "<img class='modulo-view' src='#{html_escape(vista_guardada)}' alt='Vista 3D guardada de #{html_escape(titulo)}'>" : svg_modulo_despiece(titulo, filas_originales)
      seccion_modulo_html(titulo, "Modulo: #{titulo}", 'Vista 3D sincronizada al construir o actualizar este módulo. Cada módulo conserva su propia cámara.', foto_html, filas_originales, editable, modulo_uuid)
    end.join
  end

  # Foto de "Todos los modulos": la vista actual del visor 3D en el momento
  # de generar el despiece (best-effort -- si falla por lo que sea, se cae
  # de vuelta al icono generico en vez de romper el despiece entero).
  def self.captura_vista_actual
    ruta = File.join(Sketchup.temp_dir, "m3d_despiece_global_#{rand(1_000_000_000)}.png")
    vista = Sketchup.active_model.active_view
    ok = vista.write_image(:filename => ruta, :width => 640, :height => 480, :antialias => true, :compression => 0.9)
    return nil unless ok && File.exist?(ruta)
    binario = File.binread(ruta)
    "data:image/png;base64,#{[binario].pack('m0')}"
  rescue StandardError
    nil
  ensure
    File.delete(ruta) if ruta && File.exist?(ruta)
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
    .pieza-miniatura { width: 46px; height: 46px; object-fit: contain; background: #fff; border: 1px solid #e2e8f0; border-radius: 4px; display: block; }
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

  # Si no hay nada seleccionado, usa todo el modelo activo en vez de exigir
  # selección: evita el caso de piezas de diseño libre (o cualquier módulo)
  # etiquetadas correctamente pero "invisibles" para despiece/presupuesto
  # solo porque el usuario olvidó seleccionarlas antes de generar.
  def self.entidades_para_despiece
    model = Sketchup.active_model
    seleccion = model.selection
    seleccion.empty? ? model.active_entities.to_a : seleccion.to_a
  end

  def self.generar_despiece_seleccion
    seleccion = entidades_para_despiece

    if seleccion.empty?
      UI.messagebox("No hay nada en el modelo para generar el despiece.")
      return
    end

    piezas = []
    seleccion.each { |entity| recolectar_piezas_despiece(entity, piezas) }

    if piezas.empty?
      UI.messagebox("No se encontraron piezas con datos de despiece. Si es una pieza de diseño libre, etiquetala primero con 'Etiquetar pieza para despiece'.")
      return
    end

    fila_export = lambda do |pieza|
      {
        "modulo" => pieza[:modulo],
        "modulo_uuid" => pieza[:modulo_uuid],
        "miniatura" => pieza[:miniatura],
        "nombre" => pieza[:nombre_legible] || etiqueta_despiece_pieza(pieza[:codigo]),
        "cantidad" => pieza[:cantidad],
        "medida1" => pieza[:medida_1],
        "canto1" => "#{pieza[:canto_1]}L",
        "medida2" => pieza[:medida_2],
        "canto2" => "#{pieza[:canto_2]}C",
        "placa" => pieza[:placa],
        "material" => pieza[:material],
        "tipo_canto" => etiqueta_tipo_canto(pieza[:tipo_canto]),
        "color_canto" => pieza[:color_canto],
        "inglete" => pieza[:inglete],
        "bisagrado" => texto_bisagrado_pieza(pieza[:codigo], pieza[:alto_real_mm], pieza[:tipo_bisagra])
      }
    end

    # Por modulo REAL (modulo_uuid): cada modulo construido, aunque sea
    # identico en medidas a otro, obtiene su propia seccion y su propia
    # cantidad de piezas -- no se mezcla con otro modulo solo porque
    # comparten dimensiones.
    agrupado_por_modulo = {}
    piezas.each do |pieza|
      clave = [
        pieza[:modulo_uuid],
        pieza[:codigo],
        pieza[:medida_1],
        pieza[:canto_1],
        pieza[:medida_2],
        pieza[:canto_2],
        pieza[:placa],
        pieza[:material],
        pieza[:tipo_canto],
        pieza[:color_canto],
        pieza[:inglete],
        pieza[:tipo_bisagra]
      ]
      agrupado_por_modulo[clave] ||= pieza.merge(:cantidad => 0)
      agrupado_por_modulo[clave][:cantidad] += 1
    end
    filas_data = agrupado_por_modulo.values.sort_by { |pieza| [pieza[:modulo], pieza[:codigo], pieza[:medida_1], pieza[:medida_2], pieza[:material]] }.map(&fila_export)

    # Global: la MISMA pieza (mismo codigo/medidas/material/etc) se combina
    # aunque venga de modulos distintos -- pensado para un cutlist unico de
    # toda la seleccion, sin importar de que modulo salio cada una.
    agrupado_global = {}
    piezas.each do |pieza|
      clave = [
        pieza[:codigo],
        pieza[:medida_1],
        pieza[:canto_1],
        pieza[:medida_2],
        pieza[:canto_2],
        pieza[:placa],
        pieza[:material],
        pieza[:tipo_canto],
        pieza[:color_canto],
        pieza[:inglete],
        pieza[:tipo_bisagra]
      ]
      agrupado_global[clave] ||= pieza.merge(:cantidad => 0)
      agrupado_global[clave][:cantidad] += 1
    end
    filas_data_global = agrupado_global.values.sort_by { |pieza| [pieza[:codigo], pieza[:medida_1], pieza[:medida_2], pieza[:material]] }.map(&fila_export)
    # Las filas del cutlist global se marcan con una clave especial: mas
    # abajo, filas_html_despiece las reconoce y arma con eso una seccion
    # "Todos los módulos" aparte, con su propia foto de la vista actual.
    filas_data_global.each do |fila|
      fila['modulo'] = 'Todos los módulos'
      fila['modulo_uuid'] = '__GLOBAL_TODOS_LOS_MODULOS__'
    end

    hay_varios_modulos = filas_data.map { |fila| fila['modulo_uuid'] }.uniq.length > 1
    filas_html = filas_html_despiece(hay_varios_modulos ? filas_data + filas_data_global : filas_data, true)

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
    .pieza-miniatura { width: 46px; height: 46px; object-fit: contain; background: #fff; border: 1px solid #e2e8f0; border-radius: 4px; display: block; }
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
        var moduloUuid = tabla.getAttribute('data-modulo-uuid') || modulo;
        tabla.querySelectorAll('tbody tr').forEach(function(tr) {
          var fila = { modulo: modulo, modulo_uuid: moduloUuid };
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
      begin
        self.exportar_despiece_excel(filas)
      rescue StandardError => e
        UI.messagebox("No se pudo exportar a Excel: #{e.class}: #{e.message}")
      end
    end
    dialogo.add_action_callback("exportarDespiecePdf") do |_action_context, filas|
      begin
        self.exportar_despiece_pdf(filas)
      rescue StandardError => e
        UI.messagebox("No se pudo exportar a PDF: #{e.class}: #{e.message}")
      end
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
end
