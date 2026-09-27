# frozen_string_literal: true

require 'json'

module Modular3D
  # "Parámetros de Diseño" (inspirado en Design Parameters de imos, ver
  # B_07_Design_Parameters_2023.pdf): agrupa los huelgos/holguras/solapes de
  # frente en un objeto con nombre propio, reutilizable entre módulos, en vez
  # de repartidos como campos sueltos con su propio default en distintos
  # puntos del código.
  #
  # ESTANDAR es el que ya usa el plugin hoy (mismos valores exactos que
  # core/config.rb DEFAULTS['juego_general'] y los defaults hardcodeados en
  # ui/hierarchical_config.js fresh()/childDefaults()) para que aplicar
  # "ESTANDAR" no cambie nada en ningún módulo existente ni nuevo. Los demás
  # viven como archivos que el propio usuario guarda desde el inspector de
  # espacio ("Guardar como Parámetro de Diseño...").
  module ParametrosDiseno
    module_function

    DIRECTORIO = File.expand_path('../parametros_diseno', __dir__)

    ESTANDAR = {
      'parametro_id' => 'ESTANDAR',
      'nombre' => 'Estándar (valores actuales del plugin)',
      'juego_general' => 2.0,
      'front_joint' => 1.5,
      'gap' => 3.0,
      'gap_center' => 3.0,
      'drawer_gap' => 1.5,
      'overlay_left' => 13.5,
      'overlay_right' => 13.5,
      'overlay_top' => 13.5,
      'overlay_bottom' => 13.5
    }.freeze

    CAMPOS = %w[juego_general front_joint gap gap_center drawer_gap overlay_left overlay_right overlay_top overlay_bottom].freeze

    def listar
      guardados = listar_guardados
      [ESTANDAR] + guardados
    end

    def listar_guardados
      return [] unless Dir.exist?(DIRECTORIO)

      Dir.glob(File.join(DIRECTORIO, '*.json')).sort.map do |ruta|
        begin
          datos = JSON.parse(File.read(ruta))
        rescue JSON::ParserError, StandardError
          next nil
        end
        next nil unless datos.is_a?(Hash) && datos['parametro_id'] && datos['parametro_id'] != 'ESTANDAR'

        # Cualquier campo ausente en el archivo guardado cae al valor
        # ESTANDAR correspondiente, nunca a nil/0 -- un parámetro de diseño
        # viejo guardado antes de agregarse un campo nuevo (p. ej. una
        # versión futura con un huelgo más) sigue siendo válido.
        ESTANDAR.merge(datos)
      end.compact
    end

    def buscar(parametro_id)
      listar.find { |item| item['parametro_id'].to_s == parametro_id.to_s }
    end

    def guardar(datos)
      nombre = datos['nombre'].to_s.strip
      return { ok: false, message: 'El parámetro de diseño necesita un nombre.' } if nombre.empty?

      id_normalizado = datos['parametro_id'].to_s.strip
      id_normalizado = nombre.upcase.gsub(/[^A-Z0-9]+/, '_').gsub(/\A_+|_+\z/, '') if id_normalizado.empty?
      return { ok: false, message: 'No se pudo derivar un identificador del nombre indicado.' } if id_normalizado.empty?
      return { ok: false, message: '"ESTANDAR" es un identificador reservado; elige otro nombre.' } if id_normalizado == 'ESTANDAR'

      registro = { 'parametro_id' => id_normalizado, 'nombre' => nombre }
      CAMPOS.each { |campo| registro[campo] = (datos[campo].nil? ? ESTANDAR[campo] : datos[campo].to_f) }

      begin
        require 'fileutils'
        FileUtils.mkdir_p(DIRECTORIO)
        File.write(File.join(DIRECTORIO, "#{id_normalizado.downcase}.json"), JSON.pretty_generate(registro))
      rescue StandardError => e
        return { ok: false, message: "No se pudo guardar: #{e.message}" }
      end

      { ok: true, message: "Parámetro de diseño \"#{nombre}\" guardado.", parametro: registro, lista: listar }
    end

    def eliminar(parametro_id)
      return { ok: false, message: 'No se puede eliminar el parámetro ESTANDAR (es el valor de fábrica del plugin).' } if parametro_id.to_s == 'ESTANDAR'

      ruta = File.join(DIRECTORIO, "#{parametro_id.to_s.downcase}.json")
      return { ok: false, message: 'Ese parámetro de diseño ya no existe.' } unless File.exist?(ruta)

      begin
        File.delete(ruta)
      rescue StandardError => e
        return { ok: false, message: "No se pudo eliminar: #{e.message}" }
      end
      { ok: true, message: 'Parámetro de diseño eliminado.', lista: listar }
    end
  end
end
