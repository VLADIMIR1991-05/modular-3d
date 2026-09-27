# frozen_string_literal: true

require 'json'
require 'time'

module LPenafiel_GeneradorMueblesExacto
  # Export "plano 2D" (§8 de la propuesta v5 -- complementa la unificación
  # del visor 2D/3D de la Tarea 1, que ya vive en pantalla; esto es la
  # versión archivo/imprimible). Se reconstruye a partir de la MISMA
  # geometría jerárquica (hierarchy_geometry_json) y del inventario de piezas
  # reales calculado por core/plano2d_inventario.rb (v6 §Fase D-1) -- la
  # misma fuente que usa ejecutarConstruccionMueble para fabricar las piezas,
  # así que la disposición coincide siempre con el módulo construido.
  #
  # v6.0.1 -- rediseño pedido por el usuario tras revisar la v6.0.0 (que
  # apilaba 6 vistas a tamaño natural en milímetros, sin caber en ninguna
  # hoja real): ahora cada módulo se entrega como una PLANIMETRÍA
  # PROFESIONAL, una hoja A4 o A3 (elegida automáticamente, la más chica que
  # entre a la escala más grande posible -- 1:1, 1:2, 1:5, 1:10... hasta
  # 1:1000 si hace falta) por módulo, con 4 vistas acotadas (elevación
  # frontal, elevación lateral, planta y corte vertical) y un cajetín con
  # nombre, dimensiones, escala, formato y fecha -- tal como se ve en un
  # plano de taller real. La vista explosionada se elimina por completo (a
  # pedido explícito: "olvida la explosion"); la isométrica también se saca
  # de la hoja impresa para que las 4 vistas de fabricación entren cómodas
  # en una sola hoja por módulo (sigue disponible en el visor 3D en vivo del
  # plugin, que es donde realmente aporta valor).
  #
  # Limitación conocida y deliberada (igual que antes de v6): solo funciona
  # para módulos construidos con el árbol de espacios de "3 Configuración"
  # (los que guardan hierarchy_geometry_json). El interior mecánico de cada
  # cajón y los herrajes no se dibujan (ver el comentario de alcance en
  # core/plano2d_inventario.rb) -- esto se avisa al usuario, no se inventa
  # una reconstrucción aproximada de lo que no se calcula.
  def self.modulos_con_jerarquia_para_plano(seleccion)
    modulos = []
    seleccion.each do |entity|
      manifiesto = manifiesto_de_entidad(entity)
      next unless manifiesto && manifiesto['data'].is_a?(Hash)

      raw = manifiesto['data']['hierarchy_geometry_json']
      next if raw.to_s.strip.empty?

      geometria = begin
        JSON.parse(raw.to_s)
      rescue JSON::ParserError
        nil
      end
      next unless geometria.is_a?(Hash) && geometria['nodes'].is_a?(Array)

      inventario = VistaPrevia2D.calcular_inventario_piezas(manifiesto['data'], geometria)
      modulos << { 'nombre' => manifiesto['name'].to_s, 'uuid' => manifiesto['uuid'].to_s, 'data' => manifiesto['data'], 'geometria' => geometria, 'piezas' => inventario['piezas'], 'envolvente' => inventario['envolvente'] }
    end
    modulos
  end

  # --- Estilo por grupo de pieza (mismo criterio de color en las 4 vistas) ---
  CLASES_SVG_POR_GRUPO = {
    'CASCO' => 'm3d-plano-casco',
    'TRAVESANO' => 'm3d-plano-travesano',
    'NODO_PANEL' => 'm3d-plano-nodo',
    'RESPALDO' => 'm3d-plano-respaldo',
    'AJUSTE' => 'm3d-plano-ajuste',
    'PUERTA' => 'm3d-plano-puerta-pieza',
    'FRENTE_CAJON' => 'm3d-plano-cajones',
    'REPISA' => 'm3d-plano-repisas',
    'DIVISOR' => 'm3d-plano-divisor'
  }.freeze

  def self.clase_svg_pieza(pieza)
    CLASES_SVG_POR_GRUPO[pieza['grupo']] || 'm3d-plano-vacio'
  end

  # --- Ajuste de texto por ancho disponible (mm de hoja) ---
  # Sin esto, las notas explicativas de cada vista (largas a propósito, para
  # no dejar de avisar qué corte/proyección es) se salían del borde de la
  # hoja o se montaban encima del cajetín -- ahora se reparten en varias
  # líneas cortas que sí entran en el ancho real disponible.
  def self.envolver_texto(texto, max_chars)
    return [] if texto.to_s.strip.empty?
    limite = [max_chars.to_i, 8].max
    lineas = []
    actual = ''
    texto.to_s.split(' ').each do |palabra|
      candidato = actual.empty? ? palabra : "#{actual} #{palabra}"
      if candidato.length > limite && !actual.empty?
        lineas << actual
        actual = palabra
      else
        actual = candidato
      end
    end
    lineas << actual unless actual.empty?
    lineas
  end

  # Estimación gruesa (no hay medición real de glifos disponible en Ruby
  # puro): a la familia tipográfica usada, un carácter promedio mide
  # aproximadamente 0.56x el tamaño de fuente.
  def self.max_chars_para_ancho(ancho_mm, font_size_mm)
    [(ancho_mm.to_f / (font_size_mm.to_f * 0.56)).floor, 10].max
  end

  # --- Formatos de hoja reales (mm) y escalas de dibujo estándar ---
  FORMATOS_HOJA = [
    { 'id' => 'A4', 'ancho_mm' => 210.0, 'alto_mm' => 297.0 },
    { 'id' => 'A3', 'ancho_mm' => 297.0, 'alto_mm' => 420.0 }
  ].freeze
  ORDEN_FORMATO = { 'A4' => 0, 'A3' => 1 }.freeze

  # Denominadores de escala "de catálogo" (1:1 ... 1:1000): se prueban de
  # menor a mayor para encontrar la escala MÁS GRANDE (más clara de leer)
  # que realmente entre en alguna combinación hoja+orientación.
  DENOMINADORES_ESCALA = [1, 2, 5, 10, 15, 20, 25, 50, 75, 100, 150, 200, 250, 500, 1000].freeze

  MARGEN_HOJA_MM = 12.0
  ALTO_CAJETIN_MM = 30.0
  GAP_VISTAS_MM = 16.0
  ALTO_SUBTITULO_VISTA_MM = 5.5
  # Espacio reservado bajo la fila de planta/corte para sus notas explicativas
  # (envueltas en hasta ~3 líneas cortas -- ver envolver_texto más abajo).
  ALTO_NOTA_MM = 9.5

  # Espacio reservado (en mm de hoja, ya a escala) alrededor de cada vista
  # para sus líneas de cota -- izquierda para la cota vertical, abajo para
  # la cota horizontal.
  PLANO_PAD_IZQ = 8.0
  PLANO_PAD_DER = 3.0
  PLANO_PAD_ARRIBA = 3.0
  PLANO_PAD_ABAJO = 10.0

  # --- Cotas (líneas de dimensión con flechas y texto) -- coordenadas ya en mm de hoja ---
  def self.svg_cota_horizontal(x1, x2, y_linea, texto)
    "<g class='m3d-cota'>" \
    "<line x1='#{x1.round(2)}' y1='#{y_linea.round(2)}' x2='#{x2.round(2)}' y2='#{y_linea.round(2)}' class='m3d-cota-linea'></line>" \
    "<line x1='#{x1.round(2)}' y1='#{(y_linea - 1.6).round(2)}' x2='#{x1.round(2)}' y2='#{(y_linea + 1.6).round(2)}' class='m3d-cota-linea'></line>" \
    "<line x1='#{x2.round(2)}' y1='#{(y_linea - 1.6).round(2)}' x2='#{x2.round(2)}' y2='#{(y_linea + 1.6).round(2)}' class='m3d-cota-linea'></line>" \
    "<text x='#{((x1 + x2) / 2).round(2)}' y='#{(y_linea - 1.2).round(2)}' text-anchor='middle' class='m3d-cota-texto'>#{texto}</text>" \
    '</g>'
  end

  def self.svg_cota_vertical(y1, y2, x_linea, texto)
    "<g class='m3d-cota'>" \
    "<line x1='#{x_linea.round(2)}' y1='#{y1.round(2)}' x2='#{x_linea.round(2)}' y2='#{y2.round(2)}' class='m3d-cota-linea'></line>" \
    "<line x1='#{(x_linea - 1.6).round(2)}' y1='#{y1.round(2)}' x2='#{(x_linea + 1.6).round(2)}' y2='#{y1.round(2)}' class='m3d-cota-linea'></line>" \
    "<line x1='#{(x_linea - 1.6).round(2)}' y1='#{y2.round(2)}' x2='#{(x_linea + 1.6).round(2)}' y2='#{y2.round(2)}' class='m3d-cota-linea'></line>" \
    "<text x='#{(x_linea - 2.2).round(2)}' y='#{((y1 + y2) / 2).round(2)}' text-anchor='end' dominant-baseline='middle' class='m3d-cota-texto'>#{texto}</text>" \
    '</g>'
  end

  # --- Vista 1: elevación frontal (plano X-Z, mirando desde -Y) ---
  # `escala` reduce los milímetros REALES del módulo a milímetros DE HOJA
  # (p.ej. escala 0.1 = "1:10"); el texto de las cotas siempre muestra el
  # milímetro real, nunca el ya escalado.
  def self.svg_vista_frontal(modulo, escala)
    env = modulo['envolvente']
    ancho = env['ancho_total']; alto = env['alto_total']
    return nil if ancho <= 0 || alto <= 0

    e = escala
    piezas_ordenadas = modulo['piezas'].sort_by { |p| -p['y'] } # atrás primero, frente (y chico/negativo) al final = encima
    partes = piezas_ordenadas.map do |pieza|
      w = pieza['w']; h = pieza['h']
      next nil if w <= 0 || h <= 0
      x = pieza['x']; y_svg = alto - pieza['z'] - h
      "<rect x='#{(x * e).round(2)}' y='#{(y_svg * e).round(2)}' width='#{(w * e).round(2)}' height='#{(h * e).round(2)}' class='#{clase_svg_pieza(pieza)}'></rect>"
    end.compact

    ancho_e = ancho * e; alto_e = alto * e
    cota_ancho = svg_cota_horizontal(0, ancho_e, alto_e + 6.5, "#{ancho.round} mm")
    cota_alto = svg_cota_vertical(0, alto_e, -5.0, "#{alto.round} mm")

    { 'ancho' => ancho_e + PLANO_PAD_IZQ + PLANO_PAD_DER, 'alto' => alto_e + PLANO_PAD_ARRIBA + PLANO_PAD_ABAJO,
      'offset_x' => PLANO_PAD_IZQ, 'offset_y' => PLANO_PAD_ARRIBA,
      'svg' => "<rect x='0' y='0' width='#{ancho_e.round(2)}' height='#{alto_e.round(2)}' class='m3d-plano-marco'></rect>#{partes.join}#{cota_ancho}#{cota_alto}" }
  end

  # --- Vista 2: elevación lateral (plano Y-Z, mirando desde +X) ---
  def self.svg_vista_lateral(modulo, escala)
    env = modulo['envolvente']
    alto = env['alto_total']; prof = env['prof_total']
    piezas = modulo['piezas']
    return nil if alto <= 0 || prof <= 0

    e = escala
    y_min = ([0.0] + piezas.map { |p| p['y'] }).min
    y_max = ([prof] + piezas.map { |p| p['y'] + p['d'] }).max
    ancho_vista = y_max - y_min

    piezas_ordenadas = piezas.sort_by { |p| p['x'] } # lateral izquierdo (x chico) mas lejos, derecho (x grande, mas cerca del observador en +X) encima
    partes = piezas_ordenadas.map do |pieza|
      d = pieza['d']; h = pieza['h']
      next nil if d <= 0 || h <= 0
      x_svg = pieza['y'] - y_min
      y_svg = alto - pieza['z'] - h
      "<rect x='#{(x_svg * e).round(2)}' y='#{(y_svg * e).round(2)}' width='#{(d * e).round(2)}' height='#{(h * e).round(2)}' class='#{clase_svg_pieza(pieza)}'></rect>"
    end.compact

    ancho_vista_e = ancho_vista * e; alto_e = alto * e
    cota_prof = svg_cota_horizontal(0, ancho_vista_e, alto_e + 6.5, "#{prof.round} mm (frente a la izquierda)")
    cota_alto = svg_cota_vertical(0, alto_e, -5.0, "#{alto.round} mm")

    { 'ancho' => ancho_vista_e + PLANO_PAD_IZQ + PLANO_PAD_DER, 'alto' => alto_e + PLANO_PAD_ARRIBA + PLANO_PAD_ABAJO,
      'offset_x' => PLANO_PAD_IZQ, 'offset_y' => PLANO_PAD_ARRIBA,
      'svg' => "<rect x='0' y='0' width='#{ancho_vista_e.round(2)}' height='#{alto_e.round(2)}' class='m3d-plano-marco'></rect>#{partes.join}#{cota_prof}#{cota_alto}" }
  end

  # --- Vista 3: planta (corte horizontal a media altura del interior, plano X-Y) ---
  def self.svg_vista_planta(modulo, escala)
    env = modulo['envolvente']
    ancho = env['ancho_total']; alto = env['alto_total']; prof = env['prof_total']
    piezas = modulo['piezas']
    return nil if ancho <= 0 || prof <= 0

    e = escala
    z_corte = alto / 2.0
    y_min = ([0.0] + piezas.map { |p| p['y'] }).min
    y_max = ([prof] + piezas.map { |p| p['y'] + p['d'] }).max
    alto_vista = y_max - y_min

    piezas_en_corte = piezas.select { |p| p['z'] <= z_corte && (p['z'] + p['h']) >= z_corte }
    partes = piezas_en_corte.map do |pieza|
      w = pieza['w']; d = pieza['d']
      next nil if w <= 0 || d <= 0
      x = pieza['x']; y_svg = pieza['y'] - y_min
      "<rect x='#{(x * e).round(2)}' y='#{(y_svg * e).round(2)}' width='#{(w * e).round(2)}' height='#{(d * e).round(2)}' class='#{clase_svg_pieza(pieza)}'></rect>"
    end.compact

    ancho_e = ancho * e; alto_vista_e = alto_vista * e
    linea_frente = "<line x1='0' y1='#{(-y_min * e).round(2)}' x2='#{ancho_e.round(2)}' y2='#{(-y_min * e).round(2)}' class='m3d-plano-frente-linea'></line>"
    cota_ancho = svg_cota_horizontal(0, ancho_e, alto_vista_e + 6.5, "#{ancho.round} mm")
    cota_prof = svg_cota_vertical(0, alto_vista_e, -5.0, "#{prof.round} mm")

    { 'ancho' => ancho_e + PLANO_PAD_IZQ + PLANO_PAD_DER, 'alto' => alto_vista_e + PLANO_PAD_ARRIBA + PLANO_PAD_ABAJO,
      'offset_x' => PLANO_PAD_IZQ, 'offset_y' => PLANO_PAD_ARRIBA,
      'svg' => "<rect x='0' y='0' width='#{ancho_e.round(2)}' height='#{alto_vista_e.round(2)}' class='m3d-plano-marco-punteado'></rect>#{linea_frente}#{partes.join}#{cota_ancho}#{cota_prof}",
      'nota' => "Corte horizontal a media altura del interior (Z=#{z_corte.round}mm) -- muestra solo lo que esa altura realmente atraviesa, no la proyección completa desde arriba." }
  end

  # --- Vista 4: corte vertical (plano Y-Z a la mitad del ancho, con achurado del material cortado) ---
  def self.svg_corte_vertical(modulo, escala)
    env = modulo['envolvente']
    ancho = env['ancho_total']; alto = env['alto_total']; prof = env['prof_total']
    piezas = modulo['piezas']
    return nil if alto <= 0 || prof <= 0

    e = escala
    x_corte = ancho / 2.0
    y_min = ([0.0] + piezas.map { |p| p['y'] }).min
    y_max = ([prof] + piezas.map { |p| p['y'] + p['d'] }).max
    ancho_vista = y_max - y_min

    piezas_cortadas = piezas.select { |p| p['x'] <= x_corte && (p['x'] + p['w']) >= x_corte }
    partes = piezas_cortadas.map do |pieza|
      d = pieza['d']; h = pieza['h']
      next nil if d <= 0 || h <= 0
      x_svg = pieza['y'] - y_min
      y_svg = alto - pieza['z'] - h
      "<rect x='#{(x_svg * e).round(2)}' y='#{(y_svg * e).round(2)}' width='#{(d * e).round(2)}' height='#{(h * e).round(2)}' class='m3d-plano-corte-pieza'></rect>"
    end.compact

    ancho_vista_e = ancho_vista * e; alto_e = alto * e
    cota_prof = svg_cota_horizontal(0, ancho_vista_e, alto_e + 6.5, "#{prof.round} mm (frente a la izquierda)")
    cota_alto = svg_cota_vertical(0, alto_e, -5.0, "#{alto.round} mm")

    { 'ancho' => ancho_vista_e + PLANO_PAD_IZQ + PLANO_PAD_DER, 'alto' => alto_e + PLANO_PAD_ARRIBA + PLANO_PAD_ABAJO,
      'offset_x' => PLANO_PAD_IZQ, 'offset_y' => PLANO_PAD_ARRIBA,
      'svg' => "<rect x='0' y='0' width='#{ancho_vista_e.round(2)}' height='#{alto_e.round(2)}' class='m3d-plano-marco-punteado'></rect>#{partes.join}#{cota_prof}#{cota_alto}",
      'nota' => "Corte vertical en X=#{x_corte.round}mm (mitad del ancho) -- solo se dibuja el material que ese plano realmente atraviesa (achurado), no lo que queda detrás sin cortar." }
  end

  # --- Elección automática de hoja (A4/A3, vertical/horizontal) y escala ---
  # Prueba cada escala de catálogo de mayor a menor (1:1, 1:2, 1:5...) y, en
  # la primera que logre que las 4 vistas + cajetín entren en AL MENOS una
  # combinación hoja+orientación, se queda con esa escala -- entre las
  # combinaciones que entran a esa misma escala, prefiere A4 sobre A3 y
  # vertical sobre horizontal. Si ni la escala más chica (1:1000) alcanza
  # (módulo absurdamente grande) usa igual esa combinación como mejor
  # esfuerzo, en vez de fallar la exportación.
  def self.elegir_layout(modulo)
    mejor = nil
    DENOMINADORES_ESCALA.each do |den|
      escala = 1.0 / den
      vf = svg_vista_frontal(modulo, escala)
      vl = svg_vista_lateral(modulo, escala)
      vp = svg_vista_planta(modulo, escala)
      vc = svg_corte_vertical(modulo, escala)
      next unless vf && vl && vp && vc

      ancho_col_izq = [vf['ancho'], vp['ancho']].max
      ancho_col_der = [vl['ancho'], vc['ancho']].max
      alto_fila_sup = [vf['alto'], vl['alto']].max + ALTO_SUBTITULO_VISTA_MM
      alto_fila_inf = [vp['alto'], vc['alto']].max + ALTO_SUBTITULO_VISTA_MM
      ancho_layout = ancho_col_izq + GAP_VISTAS_MM + ancho_col_der
      alto_layout = alto_fila_sup + GAP_VISTAS_MM + alto_fila_inf + ALTO_NOTA_MM

      candidatos_den = []
      FORMATOS_HOJA.each do |formato|
        %i[vertical horizontal].each do |orientacion|
          ancho_hoja, alto_hoja = orientacion == :vertical ? [formato['ancho_mm'], formato['alto_mm']] : [formato['alto_mm'], formato['ancho_mm']]
          ancho_disp = ancho_hoja - (MARGEN_HOJA_MM * 2)
          alto_disp = alto_hoja - (MARGEN_HOJA_MM * 2) - ALTO_CAJETIN_MM
          next if ancho_layout > ancho_disp || alto_layout > alto_disp

          candidatos_den << {
            'den' => den, 'escala' => escala, 'formato' => formato['id'], 'orientacion' => orientacion,
            'ancho_hoja' => ancho_hoja, 'alto_hoja' => alto_hoja,
            'vf' => vf, 'vl' => vl, 'vp' => vp, 'vc' => vc
          }
        end
      end
      unless candidatos_den.empty?
        mejor = candidatos_den.min_by { |c| [ORDEN_FORMATO[c['formato']] || 9, c['orientacion'] == :vertical ? 0 : 1] }
        break
      end
    end

    return mejor if mejor

    # Mejor esfuerzo: ni la escala más chica de catálogo entra en A3 -- se
    # usa igual (A3 horizontal a 1:1000) para no dejar la exportación sin
    # resultado; el usuario lo notará porque el dibujo sale muy ajustado.
    den = DENOMINADORES_ESCALA.max
    escala = 1.0 / den
    vf = svg_vista_frontal(modulo, escala)
    vl = svg_vista_lateral(modulo, escala)
    vp = svg_vista_planta(modulo, escala)
    vc = svg_corte_vertical(modulo, escala)
    return nil unless vf && vl && vp && vc

    formato = FORMATOS_HOJA.last
    { 'den' => den, 'escala' => escala, 'formato' => formato['id'], 'orientacion' => :horizontal,
      'ancho_hoja' => formato['alto_mm'], 'alto_hoja' => formato['ancho_mm'],
      'vf' => vf, 'vl' => vl, 'vp' => vp, 'vc' => vc }
  end

  # --- Cajetín (título/rótulo) -- tamaño y texto fijos en mm de hoja, ajenos a la escala del dibujo ---
  def self.svg_cajetin(modulo, info, indice, total)
    ancho_hoja = info['ancho_hoja']; alto_hoja = info['alto_hoja']
    x0 = MARGEN_HOJA_MM
    y0 = alto_hoja - MARGEN_HOJA_MM - ALTO_CAJETIN_MM
    ancho_caja = ancho_hoja - (MARGEN_HOJA_MM * 2)
    ancho_col_datos = 58.0
    x_col_datos = x0 + ancho_caja - ancho_col_datos

    env = modulo['envolvente']
    nombre = html_escape(modulo['nombre'].to_s.empty? ? 'Módulo sin nombre' : modulo['nombre'])
    dimensiones = "#{env['ancho_total'].round} x #{env['alto_total'].round} x #{env['prof_total'].round} mm (An x Al x Prof)"
    orientacion_txt = info['orientacion'] == :vertical ? 'vertical' : 'horizontal'
    fecha = Time.now.strftime('%Y-%m-%d')

    filas_datos = [
      ['ESCALA', "1:#{info['den']}"],
      ['FORMATO', "#{info['formato']} #{orientacion_txt}"],
      ['HOJA', "#{indice} de #{total}"],
      ['FECHA', fecha]
    ]
    alto_fila = ALTO_CAJETIN_MM / filas_datos.length.to_f
    filas_svg = filas_datos.each_with_index.map do |par, i|
      etiqueta = par[0]; valor = par[1]
      y_fila = y0 + (i * alto_fila)
      "<line x1='#{x_col_datos.round(2)}' y1='#{y_fila.round(2)}' x2='#{(x0 + ancho_caja).round(2)}' y2='#{y_fila.round(2)}' class='m3d-cajetin-linea'></line>" \
      "<text x='#{(x_col_datos + 2.2).round(2)}' y='#{(y_fila + alto_fila - 2.0).round(2)}' class='m3d-cajetin-etiqueta'>#{html_escape(etiqueta)}</text>" \
      "<text x='#{(x0 + ancho_caja - 2.2).round(2)}' y='#{(y_fila + alto_fila - 2.0).round(2)}' text-anchor='end' class='m3d-cajetin-valor'>#{html_escape(valor)}</text>"
    end.join

    ancho_col_izquierda = ancho_caja - ancho_col_datos - 3.5
    nota_cajetin = 'Modular_3D -- plano generado automáticamente a partir de la jerarquía guardada. No es un plano de fabricación certificado por un tercero; revisar cotas y encuentros antes de producción.'
    max_chars_nota = max_chars_para_ancho(ancho_col_izquierda, 1.9)
    lineas_nota = envolver_texto(nota_cajetin, max_chars_nota).first(3)
    y_nota_inicio = y0 + ALTO_CAJETIN_MM - 3.2 - ((lineas_nota.length - 1) * 2.4)
    nota_svg = lineas_nota.each_with_index.map do |linea, li|
      "<text x='#{(x0 + 3.5).round(2)}' y='#{(y_nota_inicio + (li * 2.4)).round(2)}' class='m3d-cajetin-nota'>#{html_escape(linea)}</text>"
    end.join

    "<rect x='#{x0.round(2)}' y='#{y0.round(2)}' width='#{ancho_caja.round(2)}' height='#{ALTO_CAJETIN_MM.round(2)}' class='m3d-cajetin-marco'></rect>" \
    "<line x1='#{x_col_datos.round(2)}' y1='#{y0.round(2)}' x2='#{x_col_datos.round(2)}' y2='#{(y0 + ALTO_CAJETIN_MM).round(2)}' class='m3d-cajetin-linea'></line>" \
    "<text x='#{(x0 + 3.5).round(2)}' y='#{(y0 + 10.5).round(2)}' class='m3d-cajetin-titulo'>#{nombre}</text>" \
    "<text x='#{(x0 + 3.5).round(2)}' y='#{(y0 + 17.5).round(2)}' class='m3d-cajetin-sub'>#{dimensiones}</text>" \
    "#{nota_svg}" \
    "#{filas_svg}"
  end

  # --- Ensambla la hoja completa (una por módulo): 4 vistas en grilla 2x2 + cajetín ---
  def self.pagina_para_modulo(modulo, indice, total)
    info = elegir_layout(modulo)
    return nil unless info

    vf = info['vf']; vl = info['vl']; vp = info['vp']; vc = info['vc']
    ancho_col_izq = [vf['ancho'], vp['ancho']].max
    alto_fila_sup = [vf['alto'], vl['alto']].max

    x_izq = MARGEN_HOJA_MM
    x_der = MARGEN_HOJA_MM + ancho_col_izq + GAP_VISTAS_MM
    y_sup = MARGEN_HOJA_MM + ALTO_SUBTITULO_VISTA_MM
    y_inf = y_sup + alto_fila_sup + GAP_VISTAS_MM + ALTO_SUBTITULO_VISTA_MM

    vistas = [
      { 'titulo' => 'ELEVACIÓN FRONTAL', 'x' => x_izq, 'y' => y_sup, 'vista' => vf },
      { 'titulo' => 'ELEVACIÓN LATERAL (desde la derecha)', 'x' => x_der, 'y' => y_sup, 'vista' => vl },
      { 'titulo' => 'PLANTA (corte horizontal, media altura)', 'x' => x_izq, 'y' => y_inf, 'vista' => vp },
      { 'titulo' => 'CORTE VERTICAL (mitad del ancho)', 'x' => x_der, 'y' => y_inf, 'vista' => vc }
    ]

    grupos = vistas.map do |v|
      vista = v['vista']
      nota_svg = ''
      if vista['nota']
        max_chars = max_chars_para_ancho(vista['ancho'], 2.1)
        lineas_nota = envolver_texto(vista['nota'], max_chars)
        nota_svg = lineas_nota.each_with_index.map do |linea, li|
          "<text x='#{v['x'].round(2)}' y='#{(v['y'] + vista['alto'] + 3.4 + (li * 2.6)).round(2)}' class='m3d-plano-nota'>#{html_escape(linea)}</text>"
        end.join
      end
      "<text x='#{v['x'].round(2)}' y='#{(v['y'] - 1.6).round(2)}' class='m3d-plano-subtitulo'>#{html_escape(v['titulo'])}</text>" \
      "<g transform='translate(#{(v['x'] + vista['offset_x']).round(2)},#{(v['y'] + vista['offset_y']).round(2)})'>#{vista['svg']}</g>" \
      "#{nota_svg}"
    end.join

    ancho_hoja = info['ancho_hoja']; alto_hoja = info['alto_hoja']
    cajetin = svg_cajetin(modulo, info, indice, total)

    contenido = "<rect x='0' y='0' width='#{ancho_hoja.round(2)}' height='#{alto_hoja.round(2)}' class='m3d-hoja-fondo'></rect>" \
      "<rect x='1' y='1' width='#{(ancho_hoja - 2).round(2)}' height='#{(alto_hoja - 2).round(2)}' class='m3d-hoja-borde'></rect>" \
      "#{grupos}#{cajetin}"

    { 'ancho_hoja' => ancho_hoja, 'alto_hoja' => alto_hoja, 'den' => info['den'], 'formato' => info['formato'],
      'orientacion' => info['orientacion'], 'svg' => contenido }
  end

  ESTILO_HOJA = <<-CSS.freeze
.m3d-hoja-fondo { fill: #ffffff; }
.m3d-hoja-borde { fill: none; stroke: #94a3b8; stroke-width: 0.3; }
.m3d-plano-marco { fill: #ffffff; stroke: #111827; stroke-width: 0.4; }
.m3d-plano-marco-punteado { fill: #ffffff; stroke: #94a3b8; stroke-width: 0.3; stroke-dasharray: 2.2 1.6; }
.m3d-plano-vacio { fill: none; stroke: #334155; stroke-width: 0.25; }
.m3d-plano-casco { fill: #f8fafc; stroke: #111827; stroke-width: 0.3; }
.m3d-plano-travesano { fill: #e2e8f0; stroke: #334155; stroke-width: 0.25; }
.m3d-plano-nodo { fill: #eef2ff; stroke: #334155; stroke-width: 0.25; }
.m3d-plano-respaldo { fill: #f1f5f9; stroke: #64748b; stroke-width: 0.22; stroke-dasharray: 1.4 1; }
.m3d-plano-ajuste { fill: #fef9c3; stroke: #92400e; stroke-width: 0.22; }
.m3d-plano-puerta-pieza { fill: #dbeafe; stroke: #1d4ed8; stroke-width: 0.28; }
.m3d-plano-cajones { fill: #fff7ed; stroke: #9a3412; stroke-width: 0.28; }
.m3d-plano-repisas { fill: #ecfdf5; stroke: #047857; stroke-width: 0.25; }
.m3d-plano-divisor { fill: #f5f5f4; stroke: #57534e; stroke-width: 0.25; }
.m3d-plano-corte-pieza { fill: #cbd5e1; stroke: #111827; stroke-width: 0.35; }
.m3d-plano-frente-linea { stroke: #ef4444; stroke-width: 0.18; stroke-dasharray: 1 1; }
.m3d-plano-subtitulo { font-size: 3.6px; fill: #1f2937; font-weight: 600; }
.m3d-plano-nota { font-size: 2.1px; fill: #64748b; font-style: italic; }
.m3d-cota-linea { stroke: #475569; stroke-width: 0.15; }
.m3d-cota-texto { font-size: 2.6px; fill: #334155; }
.m3d-cajetin-marco { fill: #ffffff; stroke: #111827; stroke-width: 0.5; }
.m3d-cajetin-linea { stroke: #111827; stroke-width: 0.25; }
.m3d-cajetin-titulo { font-size: 5.2px; fill: #111827; font-weight: 700; }
.m3d-cajetin-sub { font-size: 3.0px; fill: #1f2937; }
.m3d-cajetin-nota { font-size: 1.9px; fill: #64748b; font-style: italic; }
.m3d-cajetin-etiqueta { font-size: 2.2px; fill: #64748b; }
.m3d-cajetin-valor { font-size: 2.9px; fill: #111827; font-weight: 600; }
  CSS

  def self.svg_documento_pagina(pagina)
    <<-SVG
<svg xmlns="http://www.w3.org/2000/svg" width="#{pagina['ancho_hoja'].round(2)}mm" height="#{pagina['alto_hoja'].round(2)}mm" viewBox="0 0 #{pagina['ancho_hoja'].round(2)} #{pagina['alto_hoja'].round(2)}" font-family="Segoe UI, Arial, sans-serif">
<style>
#{ESTILO_HOJA}</style>
#{pagina['svg']}
</svg>
    SVG
  end

  def self.nombre_archivo_modulo(modulo)
    base = modulo['nombre'].to_s.strip
    base = 'modulo' if base.empty?
    limpio = base.gsub(/[^A-Za-z0-9_\- ]+/, '').strip.gsub(/\s+/, '_')
    limpio.empty? ? 'modulo' : limpio
  end

  def self.exportar_plano_2d_seleccion
    seleccion = entidades_para_despiece
    modulos = modulos_con_jerarquia_para_plano(seleccion)
    if modulos.empty?
      UI.messagebox("No hay módulos con jerarquía guardada en la selección. El plano 2D solo está disponible para módulos construidos con el árbol de espacios de la pestaña \"3 Configuración\" (los que ya usan el visor 2D/3D unificado); selecciona uno o más módulos así construidos e inténtalo de nuevo.")
      return
    end

    paginas = []
    modulos.each_with_index do |modulo, i|
      pagina = pagina_para_modulo(modulo, i + 1, modulos.length)
      paginas << { 'modulo' => modulo, 'pagina' => pagina } if pagina
    end

    if paginas.empty?
      UI.messagebox("Ningún módulo de la selección tiene dimensiones válidas para generar un plano (ancho/alto/profundidad en cero).")
      return
    end

    if paginas.length == 1
      modulo = paginas.first['modulo']; pagina = paginas.first['pagina']
      path = UI.savepanel("Guardar plano 2D (SVG)", "", "plano_#{nombre_archivo_modulo(modulo)}.svg")
      return unless path

      path += ".svg" unless File.extname(path).downcase == ".svg"
      File.write(path, svg_documento_pagina(pagina), :encoding => 'UTF-8')
      UI.messagebox("Plano 2D exportado como SVG: 1 hoja #{pagina['formato']} #{pagina['orientacion'] == :vertical ? 'vertical' : 'horizontal'} a escala 1:#{pagina['den']}, con las 4 vistas acotadas (frontal, lateral, planta y corte) y su cajetín. Vector editable a partir de la jerarquía guardada -- no es un plano de fabricación certificado por un tercero, revísalo antes de enviarlo a producción.")
      return
    end

    # Más de un módulo: "una hoja por módulo" solo es literal si cada
    # módulo termina en su PROPIO archivo (cada uno con su propio tamaño de
    # hoja y escala, que pueden diferir entre módulos) -- se pide una
    # carpeta en vez de un único archivo.
    directorio = begin
      UI.select_directory(title: "Elegir carpeta para los planos 2D (una hoja por módulo)")
    rescue ArgumentError, StandardError
      begin
        UI.select_directory
      rescue StandardError
        nil
      end
    end
    unless directorio
      UI.messagebox("Exportación cancelada: no se eligió ninguna carpeta.")
      return
    end

    nombres_usados = {}
    escritos = []
    paginas.each do |item|
      modulo = item['modulo']; pagina = item['pagina']
      base = nombre_archivo_modulo(modulo)
      nombres_usados[base] = (nombres_usados[base] || 0) + 1
      sufijo = nombres_usados[base] > 1 ? "_#{nombres_usados[base]}" : ''
      ruta = File.join(directorio, "plano_#{base}#{sufijo}.svg")
      File.write(ruta, svg_documento_pagina(pagina), :encoding => 'UTF-8')
      escritos << "#{File.basename(ruta)} (#{pagina['formato']} #{pagina['orientacion'] == :vertical ? 'vert.' : 'horiz.'}, 1:#{pagina['den']})"
    end

    UI.messagebox("#{escritos.length} plano(s) 2D exportado(s) a la carpeta elegida, uno por módulo:\n#{escritos.join("\n")}\n\nCada archivo es una hoja A4 o A3 independiente con sus 4 vistas acotadas y su cajetín -- no son planos de fabricación certificados por un tercero, revísalos antes de enviarlos a producción.")
  end
end
