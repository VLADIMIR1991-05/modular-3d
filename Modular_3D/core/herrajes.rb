# frozen_string_literal: true

require 'json'

module Modular3D
  # Herrajes nivel A (§6 de la propuesta v5): mueve las fórmulas fijas de
  # bisagras/correderas a JSON editable en vez de constantes en
  # core/geometria.rb, para que ajustar un corte (como ya pasó varias veces
  # en el changelog: 900→950mm, 1600→1400mm) sea editar un archivo en vez de
  # tocar Ruby. Los valores por defecto (DEFAULT_*) son EXACTAMENTE los que
  # ya usaba bisagras_por_altura/tipo_bisagra_por_solape en core/geometria.rb
  # antes de este cambio -- si el archivo JSON no existe o es inválido, el
  # comportamiento es idéntico al de siempre.
  #
  # Deliberadamente NO se reintroducen jaladores/gola aquí (fueron retirados
  # en 4.8.0 "a pedido explícito" según el changelog): ese es el Nivel B de
  # la propuesta, que requiere confirmación explícita del usuario y no se
  # incluye en esta ronda.
  module Herrajes
    module_function

    DIRECTORIO = File.expand_path('../herrajes', __dir__)
    RUTA_BISAGRAS = File.join(DIRECTORIO, 'bisagras_default.json')
    RUTA_CORREDERAS = File.join(DIRECTORIO, 'correderas.json')

    # Umbrales tal cual estaban hardcodeados en bisagras_por_altura: 2 hasta
    # 950mm, 3 hasta 1400mm, 4 hasta 2120mm, 5 en puertas más altas.
    DEFAULT_BISAGRAS = [
      { 'hasta_mm' => 950.0, 'cantidad' => 2 },
      { 'hasta_mm' => 1400.0, 'cantidad' => 3 },
      { 'hasta_mm' => 2120.0, 'cantidad' => 4 }
    ].freeze
    CANTIDAD_MAXIMA_DEFECTO = 5

    # Distancia al canto y margen de extremos usados por defecto para la
    # posición de taladro exportable (§7 mecanizados): convención de herraje
    # europeo habitual, no un dato propio de ningún fabricante puntual --
    # editable aquí antes de exportar un despiece real a producción.
    DEFAULT_MECANIZADO = {
      'distancia_canto_mm' => 21.5,
      'margen_extremos_mm' => 100.0,
      'diametro_perforacion_mm' => 35.0
    }.freeze

    # OJO con los acentos: estos "nombre" deben coincidir tal cual (sin
    # acentos, verificado contra el texto real de las <option> de
    # ui/interfaz.html #sistema_corredera, que no tienen atributo value= --
    # el texto visible ES el valor que llega aquí en sistema_corredera_texto)
    # para que holgura_para_sistema los reconozca. Un "Telescópica estándar"
    # con acento nunca haría match contra el "Telescopica estandar" sin
    # acento que realmente manda el formulario, y silenciosamente caería en
    # el primer elemento de la lista en vez del que corresponde.
    DEFAULT_CORREDERAS = [
      { 'nombre' => 'Telescopica estandar', 'holgura_lateral_mm' => 13.0, 'referencia' => '' },
      { 'nombre' => 'Oculta', 'holgura_lateral_mm' => 21.0, 'referencia' => '' },
      { 'nombre' => 'Automatico maximo', 'holgura_lateral_mm' => 15.0, 'referencia' => '' }
    ].freeze

    def leer_json(ruta)
      return nil unless File.exist?(ruta)

      datos = JSON.parse(File.read(ruta))
      datos
    rescue JSON::ParserError, StandardError
      nil
    end

    def bisagras_config
      datos = leer_json(RUTA_BISAGRAS)
      escalones = datos.is_a?(Array) ? datos : (datos.is_a?(Hash) ? datos['escalones'] : nil)
      return DEFAULT_BISAGRAS unless escalones.is_a?(Array) && !escalones.empty?

      escalones.map { |item| { 'hasta_mm' => item['hasta_mm'].to_f, 'cantidad' => item['cantidad'].to_i } }
               .select { |item| item['hasta_mm'].positive? && item['cantidad'].positive? }
               .sort_by { |item| item['hasta_mm'] }
    rescue StandardError
      DEFAULT_BISAGRAS
    end

    def cantidad_maxima
      datos = leer_json(RUTA_BISAGRAS)
      return CANTIDAD_MAXIMA_DEFECTO unless datos.is_a?(Hash) && datos['cantidad_maxima']

      datos['cantidad_maxima'].to_i.positive? ? datos['cantidad_maxima'].to_i : CANTIDAD_MAXIMA_DEFECTO
    end

    def mecanizado_config
      datos = leer_json(RUTA_BISAGRAS)
      base = DEFAULT_MECANIZADO.dup
      base.merge!(datos['mecanizado']) if datos.is_a?(Hash) && datos['mecanizado'].is_a?(Hash)
      base
    rescue StandardError
      DEFAULT_MECANIZADO
    end

    # Reemplazo directo del bisagras_por_altura hardcodeado: misma firma,
    # misma tabla de valores por defecto, ahora leída de JSON si existe.
    def bisagras_por_altura(alto_mm)
      alto = alto_mm.to_f
      escalon = bisagras_config.find { |item| alto <= item['hasta_mm'] }
      return escalon['cantidad'] if escalon

      cantidad_maxima
    end

    def correderas
      datos = leer_json(RUTA_CORREDERAS)
      lista = datos.is_a?(Array) ? datos : (datos.is_a?(Hash) ? datos['correderas'] : nil)
      return DEFAULT_CORREDERAS unless lista.is_a?(Array) && !lista.empty?

      lista
    rescue StandardError
      DEFAULT_CORREDERAS
    end

    # Reemplazo directo del if/elsif hardcodeado en jerarquia.rb (sistema_
    # corredera.downcase.include?("oculta") -> 21mm, .include?("maximo") ->
    # 15mm, si no -> 13mm): busca por coincidencia de texto contra el
    # "nombre" de cada corredera configurada (de fábrica o del JSON editable)
    # en vez de esas dos palabras clave fijas en Ruby, para que agregar o
    # renombrar un sistema de corredera sea editar el JSON. Si el texto no
    # coincide con ninguna, cae en la primera corredera configurada (la que
    # era el "else" de siempre: Telescópica estándar, 13mm).
    def holgura_para_sistema(sistema_corredera_texto)
      texto = sistema_corredera_texto.to_s.downcase
      lista = correderas
      coincidencia = lista.find { |item| texto.include?(item['nombre'].to_s.downcase) }
      coincidencia ||= lista.find do |item|
        item['nombre'].to_s.downcase.split(/\s+/).any? { |palabra| palabra.length > 3 && texto.include?(palabra) }
      end
      coincidencia ||= lista.first
      (coincidencia ? coincidencia['holgura_lateral_mm'] : 13.0).to_f
    end

    # Posiciones estándar de taladro de bisagra a lo largo del canto vertical
    # de una puerta, para el export de mecanizados (§7): distancia al canto
    # fija (distancia_canto_mm) y reparto vertical con las bisagras extremas
    # a margen_extremos_mm de cada borde y el resto repartidas en partes
    # iguales entre esas dos. Es una convención estándar configurable, no
    # una medida certificada de ningún fabricante -- pensada para servir de
    # punto de partida a un post-procesador externo, no para operar una CNC
    # directamente sin revisión humana.
    def posiciones_taladro_bisagra(alto_mm, ancho_mm)
      cantidad = bisagras_por_altura(alto_mm)
      config = mecanizado_config
      margen = [config['margen_extremos_mm'].to_f, alto_mm.to_f / 2.0].min
      distancia_canto = config['distancia_canto_mm'].to_f

      posiciones_y = if cantidad <= 1
                       [alto_mm.to_f / 2.0]
                     else
                       paso = (alto_mm.to_f - margen * 2) / (cantidad - 1)
                       (0...cantidad).map { |indice| (margen + paso * indice).round(1) }
                     end

      posiciones_y.map do |y_mm|
        { 'x_mm' => distancia_canto, 'y_mm' => y_mm, 'diametro_mm' => config['diametro_perforacion_mm'].to_f }
      end
    end
  end
end
