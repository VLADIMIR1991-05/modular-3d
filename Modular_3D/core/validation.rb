# frozen_string_literal: true

require 'json'

module Modular3D
  module Validation
    module_function

    def numero(datos, clave, predeterminado = 0.0)
      valor = datos[clave]
      valor.nil? || valor.to_s.strip.empty? ? predeterminado.to_f : Float(valor)
    rescue ArgumentError, TypeError
      predeterminado.to_f
    end

    def lista_enteros(valor)
      valor.to_s.split(/[,\s;|]+/).map(&:to_i)
    end

    def resolver_estaciones(expresion, total, separador)
      tokens = expresion.to_s.split(':').map(&:strip).reject(&:empty?)
      return nil if tokens.empty?

      util = total.to_f - ([tokens.length - 1, 0].max * separador.to_f)
      raise ArgumentError, 'Los separadores ocupan todo el espacio.' unless util.positive?

      fijo = 0.0
      flexible = 0.0
      items = tokens.map do |token|
        case token
        when /\A(\d+(?:\.\d+)?)\s*(mm|cm|m)\z/i
          valor = Regexp.last_match(1).to_f
          unidad = Regexp.last_match(2).downcase
          mm = unidad == 'mm' ? valor : (unidad == 'cm' ? valor * 10.0 : valor * 1000.0)
          fijo += mm
          [:fijo, mm]
        when /\A(\d+(?:\.\d+)?)%\z/
          mm = util * Regexp.last_match(1).to_f / 100.0
          fijo += mm
          [:fijo, mm]
        when /\AAUTO\z/i
          flexible += 1.0
          [:flexible, 1.0]
        when /\A(\d+(?:\.\d+)?)\z/
          peso = Regexp.last_match(1).to_f
          raise ArgumentError, 'Las proporciones deben ser mayores que cero.' unless peso.positive?
          flexible += peso
          [:flexible, peso]
        else
          raise ArgumentError, "Expresion no reconocida: #{token}"
        end
      end
      restante = util - fijo
      raise ArgumentError, 'Las medidas fijas exceden el espacio disponible.' if restante < -0.01
      raise ArgumentError, 'Queda espacio sin distribuir; agrega AUTO o una proporcion.' if restante > 0.01 && flexible <= 0
      items.map { |tipo, valor| tipo == :fijo ? valor : restante * valor / flexible }
    end

    def espacios(datos, errores)
      raw = datos['spaces_json'].to_s
      return [] if raw.strip.empty?

      parsed = JSON.parse(raw)
      return parsed if parsed.is_a?(Array)

      errores << 'La configuracion de espacios debe ser una lista.'
      []
    rescue JSON::ParserError
      errores << 'La configuracion de espacios esta danada.'
      []
    end

    def validar(datos)
      errores = []
      avisos = []

      ancho = numero(datos, "ancho_total")
      alto = numero(datos, "alto_total")
      profundidad = numero(datos, "prof_total")
      espesor = numero(datos, "espesor", 15)
      izquierda = numero(datos, "grosor_izq", numero(datos, "grosor_lateral_izq", espesor))
      derecha = numero(datos, "grosor_der", numero(datos, "grosor_lateral_der", espesor))
      superior = numero(datos, "grosor_superior", espesor)
      inferior = numero(datos, "grosor_inferior", espesor)
      respaldo = numero(datos, "grosor_resp", 6)
      ajuste = numero(datos, "grosor_ajuste", espesor)
      separacion_posterior = numero(datos, "separacion_ajuste_respaldo", 2)
      distancia_posterior = numero(datos, "distancia_plano_posterior", 0)
      profundidad_cajon = numero(datos, "prof_input_cj", 450)
      retiro_cajones = numero(datos, "ret_cajones")
      repisas = numero(datos, "num_repisas").to_i
      divisiones = numero(datos, "num_divisiones").to_i
      spaces = espacios(datos, errores)

      errores << "El ancho debe estar entre 150 y 3000 mm." unless ancho.between?(150, 3000)
      errores << "La altura debe estar entre 150 y 4000 mm." unless alto.between?(150, 4000)
      errores << "La profundidad debe estar entre 100 y 1500 mm." unless profundidad.between?(100, 1500)
      errores << "El espesor general debe estar entre 3 y 60 mm." unless espesor.between?(3, 60)

      {
        "lateral izquierdo" => izquierda,
        "lateral derecho" => derecha,
        "panel superior" => superior,
        "panel inferior" => inferior
      }.each do |nombre, valor|
        errores << "El grosor de #{nombre} debe estar entre 3 y 60 mm." unless valor.between?(3, 60)
      end

      errores << "Los laterales ocupan todo el ancho disponible." if izquierda + derecha >= ancho
      errores << "Los paneles superior e inferior ocupan toda la altura." if superior + inferior >= alto
      errores << "El respaldo debe estar entre 2 y 30 mm." if datos["lleva_respaldo"] == "SI" && !respaldo.between?(2, 30)
      errores << "El grosor del ajuste posterior debe estar entre 3 y 40 mm." unless ajuste.between?(3, 40)
      errores << "La separación posterior no puede ser negativa." if separacion_posterior.negative? || distancia_posterior.negative?
      if datos["lleva_respaldo"] != "NO" && respaldo < 15 && (ajuste + separacion_posterior + respaldo + distancia_posterior) >= profundidad
        errores << "El sistema posterior ocupa toda la profundidad del módulo."
      end
      errores << "La cantidad de repisas debe estar entre 0 y 30." unless repisas.between?(0, 30)
      errores << "La cantidad de divisiones debe estar entre 0 y 20." unless divisiones.between?(0, 20)

      begin
        anchos_estaciones = resolver_estaciones(
          datos['param_x_expr'], ancho - izquierda - derecha,
          datos['param_x_type'].to_s.upcase == 'VIRTUAL' ? 0 : espesor
        )
        altos_estaciones = resolver_estaciones(
          datos['param_z_expr'], alto - superior - inferior,
          datos['param_z_type'].to_s.upcase == 'VIRTUAL' ? 0 : espesor
        )
      rescue ArgumentError => error
        errores << error.message
        anchos_estaciones = nil
        altos_estaciones = nil
      end
      ancho_celda = anchos_estaciones ? anchos_estaciones.min : (ancho - izquierda - derecha - (divisiones * espesor)) / (divisiones + 1.0)
      alto_celda = altos_estaciones ? altos_estaciones.min : (alto - superior - inferior - (repisas * espesor)) / (repisas + 1.0)
      errores << 'Las divisiones dejan columnas sin ancho util.' if ancho_celda <= 30
      errores << 'Las repisas dejan espacios sin altura util.' if alto_celda <= 30
      avisos << 'Columnas menores de 180 mm suelen ser incomodas para herrajes.' if ancho_celda.between?(31, 179)
      avisos << 'Niveles menores de 120 mm limitan cajones y accesorios.' if alto_celda.between?(31, 119)

      ocupadas = {}
      spaces.each do |space|
        next unless space.is_a?(Hash)

        columna = space['column'].to_i
        nicho = space['niche'].to_i
        ancho_espacio = anchos_estaciones && anchos_estaciones[columna] ? anchos_estaciones[columna] : ancho_celda
        alto_espacio = altos_estaciones && altos_estaciones[nicho] ? altos_estaciones[nicho] : alto_celda
        clave = "#{nicho}:#{columna}"
        errores << "El diseno 2D tiene dos configuraciones para la misma celda #{nicho + 1}/#{columna + 1}." if ocupadas[clave]
        ocupadas[clave] = true

        errores << "El espacio usa una columna inexistente (#{columna + 1})." unless columna.between?(0, divisiones)
        errores << "El espacio usa un nivel inexistente (#{nicho + 1})." unless nicho.between?(0, repisas)

        contenido = space['content'].to_s.upcase
        if contenido == 'CAJONERA'
          cajones = space['drawers'].to_i
          errores << 'Cada cajonera debe tener entre 1 y 12 cajones.' unless cajones.between?(1, 12)
          errores << 'Los cajones no caben en la altura del espacio.' if cajones.positive? && (alto_espacio / cajones) < 45
          errores << 'La columna es demasiado angosta para una cajonera con correderas.' if ancho_espacio < 170
        elsif contenido.start_with?('PUERTA')
          errores << 'Una puerta doble necesita al menos 500 mm de ancho por celda.' if contenido.include?('DOBLE') && ancho_espacio < 500
          avisos << 'Puertas muy altas pueden requerir bisagra adicional.' if alto_espacio > 1200
        elsif contenido == 'REPISAS'
          repisas_celda = space['shelves'].to_i
          errores << 'Cada celda con repisas debe tener entre 1 y 12 repisas internas.' unless repisas_celda.between?(1, 12)
          errores << 'Las repisas internas no caben en la altura de la celda.' if repisas_celda.positive? && (alto_espacio / (repisas_celda + 1)) < 45
        elsif !contenido.empty? && contenido != 'VACIO'
          errores << "Contenido de celda no reconocido: #{contenido}."
        end
      end

      # Sobremedida delantera/trasera: delta directo sobre el fondo de ese
      # panel (positivo = mas grande hacia ese lado -sobresale-, negativo =
      # mas chico -se retranquea-). Un positivo muy grande se limita a un
      # maximo razonable; la suma frontal+trasera de cada panel se valida en
      # conjunto para que un par de negativos no deje el panel sin fondo
      # aunque cada campo por separado luzca razonable.
      maximo_sobremedida = [profundidad * 0.4, 200.0].min
      %w[superior inferior izq der].each do |panel|
        frontal_clave = "sobremedida_frontal_#{panel}"
        trasero_clave = "sobremedida_trasera_#{panel}"
        frontal = numero(datos, frontal_clave)
        trasero = numero(datos, trasero_clave)
        [[frontal_clave, frontal], [trasero_clave, trasero]].each do |clave, valor|
          errores << "#{clave.tr('_', ' ')} no puede sobresalir mas de #{maximo_sobremedida.round} mm." if valor > maximo_sobremedida
        end
        errores << "La sobremedida del panel #{panel} lo deja sin profundidad util." if (frontal + trasero) <= (30 - profundidad)
      end

      cajones_totales = if spaces.empty?
                          lista_enteros(datos["cajones_por_nicho"]).sum
                        else
                          spaces.sum { |space| space.is_a?(Hash) && space['content'].to_s.upcase == 'CAJONERA' ? space['drawers'].to_i : 0 }
                        end
      if cajones_totales.positive?
        errores << "La profundidad del cajon debe ser positiva." unless profundidad_cajon.positive?
        errores << "La profundidad del cajon no cabe en el cuerpo." if profundidad_cajon + retiro_cajones > profundidad - 20
        avisos << 'Mas de 8 cajones en un modulo puede complicar fabricacion e instalacion.' if cajones_totales > 8
      end

      ancho_interior = ancho - izquierda - derecha
      alto_interior = alto - superior - inferior
      avisos << "El ancho interior es menor de 250 mm." if ancho_interior < 250
      avisos << "El alto interior es menor de 250 mm." if alto_interior < 250
      avisos << "Mas de 8 repisas puede producir nichos muy pequenos." if repisas > 8
      avisos << "Revisa la direccion de veta antes de optimizar el corte." if alto > 2100

      casco_activo = %w[lleva_lateral_izq lleva_lateral_der lleva_base lleva_techo].map { |campo| datos[campo].to_s }
      avisos << "El casco no lleva ningun panel exterior activo; revisa que sea intencional." if casco_activo.all? { |valor| valor == 'NO' }

      esquinas_validas = %w[front_left front_right back_left back_right bottom_inner bottom_outer top_outer top_inner]
      begin
        miter_raw = datos['miter_overrides_json']
        miter_overrides = miter_raw.is_a?(Hash) ? miter_raw : JSON.parse(miter_raw.to_s)
        if miter_overrides.is_a?(Hash)
          miter_overrides.each do |nombre_pieza, config|
            next unless config.is_a?(Hash)
            esquina = config['corner'].to_s
            tamano = config['size'].to_f
            next if esquina.empty? && tamano.zero?
            errores << "Inglete de '#{nombre_pieza}': esquina no reconocida (#{esquina})." unless esquinas_validas.include?(esquina)
            errores << "Inglete de '#{nombre_pieza}': la medida debe ser mayor que 0 mm." unless tamano.positive?
            avisos << "Inglete de '#{nombre_pieza}' mayor a 200 mm: revisa que la pieza sea lo bastante grande." if tamano > 200
          end
        end
      rescue JSON::ParserError
        errores << 'La configuracion de ingletes esta danada.'
      end

      montaje_puerta = datos['montaje_puerta'].to_s
      errores << "Montaje de puerta no reconocido (#{montaje_puerta})." unless montaje_puerta.empty? || %w[SOLAPADA EMBUTIDA].include?(montaje_puerta.upcase)

      hierarchy_json = datos['hierarchy_json'].to_s.strip
      unless hierarchy_json.empty? || hierarchy_json == '{}'
        begin
          hierarchy_geometry = JSON.parse(datos['hierarchy_geometry_json'].to_s)
          valido = hierarchy_geometry.is_a?(Hash) && hierarchy_geometry['nodes'].is_a?(Array) && !hierarchy_geometry['nodes'].empty?
        rescue JSON::ParserError
          valido = false
        end
        errores << 'No se pudo leer la configuracion de espacios (jerarquia). No se va a construir una caja vacia: cierra y vuelve a abrir el editor del modulo antes de reintentar.' unless valido
      end

      { errores: errores, avisos: avisos }
    end
  end
end
