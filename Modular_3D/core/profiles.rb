# frozen_string_literal: true

require 'json'

module Modular3D
  # Plantillas de módulo: JSON propios (no relacionados con ningún producto
  # de terceros) empaquetados en Modular_3D/profiles/*.json. Cada uno es un
  # subconjunto de los mismos campos que ya usa datosFormulario() en
  # interfaz.html, pensado como punto de partida editable, no como un tipo
  # de módulo especial ni un motor de geometría distinto.
  module Profiles
    module_function

    DIRECTORIO = File.expand_path('../profiles', __dir__)

    def listar
      return [] unless Dir.exist?(DIRECTORIO)

      Dir.glob(File.join(DIRECTORIO, '*.json')).sort.filter_map do |ruta|
        begin
          datos = JSON.parse(File.read(ruta))
        rescue JSON::ParserError, StandardError
          next nil
        end
        next nil unless datos.is_a?(Hash) && datos['id'] && datos['fields'].is_a?(Hash)

        datos
      end
    end
  end
end
