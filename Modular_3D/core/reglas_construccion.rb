# frozen_string_literal: true

require 'json'

module Modular3D
  # "Reglas de Construcción" (inspirado en las Reglas de Construcción de
  # imos -- B_06_Construction_Rules_2023.pdf, ejercicio "Tipo_A/Tipo_B/
  # Tipo_C": una combinación completa de qué pieza va montada por encima de
  # cuál en cada esquina del casco, guardada con nombre y reutilizable en
  # cualquier módulo con un clic, en vez de tener que tocar cada
  # desplegable de "2 Casco" suelto cada vez).
  #
  # A diferencia de "Principios de Espacio" (que describen UN espacio
  # interno de la jerarquía) y "Parámetros de Diseño" (que describen
  # huelgos/holguras), una Regla de Construcción describe el CASCO GENERAL
  # del módulo: montaje interior/sobrepuesto/inglete de cada uno de los 4
  # paneles exteriores, y si base/techo son panel completo o 2 travesaños.
  #
  # ESTANDAR reproduce exactamente los defaults que ya trae el plugin
  # (montaje_izq/der = EXTERIOR, montaje_superior/inferior = INTERIOR,
  # tipo_superior = FULL) -- aplicarlo no cambia nada en un módulo que
  # nunca tocó estos campos.
  #
  # v6.0.1 -- corregido: "2 travesaños" (tipo_*/travesano_ancho_*) es
  # EXCLUSIVO de la tapa superior, a pedido explícito del usuario (la base
  # siempre debe construirse como panel completo). Antes esta Regla también
  # gestionaba tipo_inferior/travesano_ancho_inferior por simetría con la
  # tapa superior; se retiran de los campos administrados aquí -- una
  # Regla vieja guardada con esos campos simplemente los ignora ahora (ver
  # listar_de más abajo, que ya cae a ESTANDAR para cualquier campo
  # ausente/no reconocido).
  module ReglasConstruccion
    module_function

    DIRECTORIO_USUARIO = File.expand_path('../reglas_construccion', __dir__)
    DIRECTORIO_FABRICA = File.join(DIRECTORIO_USUARIO, '_de_fabrica')

    ESTANDAR = {
      'regla_id' => 'ESTANDAR',
      'nombre' => 'Estándar (valores actuales del plugin)',
      'montaje_izq' => 'EXTERIOR',
      'montaje_der' => 'EXTERIOR',
      'montaje_superior' => 'INTERIOR',
      'montaje_inferior' => 'INTERIOR',
      'tipo_superior' => 'FULL',
      'travesano_ancho_superior' => 70
    }.freeze

    CAMPOS = %w[montaje_izq montaje_der montaje_superior montaje_inferior tipo_superior travesano_ancho_superior].freeze
    CAMPOS_TEXTO = %w[montaje_izq montaje_der montaje_superior montaje_inferior tipo_superior].freeze
    CAMPOS_NUMERICOS = %w[travesano_ancho_superior].freeze

    def listar_de(directorio, origen)
      return [] unless Dir.exist?(directorio)

      Dir.glob(File.join(directorio, '*.json')).sort.map do |ruta|
        begin
          datos = JSON.parse(File.read(ruta))
        rescue JSON::ParserError, StandardError
          next nil
        end
        next nil unless datos.is_a?(Hash) && datos['regla_id'] && datos['regla_id'] != 'ESTANDAR'

        # Igual que ParametrosDiseno: un campo ausente en un archivo viejo
        # (guardado antes de que ese campo existiera) cae al valor ESTANDAR,
        # nunca a nil -- una Regla vieja sigue siendo válida.
        datos['origen'] = origen
        ESTANDAR.merge(datos)
      end.compact
    end

    def listar
      [ESTANDAR] + listar_de(DIRECTORIO_FABRICA, 'FABRICA') + listar_de(DIRECTORIO_USUARIO, 'USUARIO')
    end

    def buscar(regla_id)
      listar.find { |item| item['regla_id'].to_s == regla_id.to_s }
    end

    def guardar(datos)
      nombre = datos['nombre'].to_s.strip
      return { ok: false, message: 'La Regla de Construcción necesita un nombre.' } if nombre.empty?

      id_normalizado = datos['regla_id'].to_s.strip
      id_normalizado = nombre.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '') if id_normalizado.empty?
      return { ok: false, message: 'No se pudo derivar un identificador del nombre indicado.' } if id_normalizado.empty?
      return { ok: false, message: '"ESTANDAR" es un identificador reservado; elige otro nombre.' } if id_normalizado == 'estandar'

      registro = { 'regla_id' => id_normalizado, 'nombre' => nombre }
      CAMPOS_TEXTO.each { |campo| registro[campo] = (datos[campo].nil? || datos[campo].to_s.empty?) ? ESTANDAR[campo] : datos[campo].to_s }
      CAMPOS_NUMERICOS.each { |campo| registro[campo] = datos[campo].nil? ? ESTANDAR[campo] : datos[campo].to_f }

      begin
        require 'fileutils'
        FileUtils.mkdir_p(DIRECTORIO_USUARIO)
        File.write(File.join(DIRECTORIO_USUARIO, "#{id_normalizado}.json"), JSON.pretty_generate(registro))
      rescue StandardError => e
        return { ok: false, message: "No se pudo guardar: #{e.message}" }
      end

      { ok: true, message: "Regla de Construcción \"#{nombre}\" guardada.", regla: registro, lista: listar }
    end

    def eliminar(regla_id)
      return { ok: false, message: 'No se puede eliminar ESTANDAR (es el valor de fábrica del plugin).' } if regla_id.to_s.downcase == 'estandar'

      ruta = File.join(DIRECTORIO_USUARIO, "#{regla_id}.json")
      return { ok: false, message: 'Esa Regla no existe en tu carpeta de usuario (las de fábrica no se pueden eliminar desde aquí).' } unless File.exist?(ruta)

      begin
        File.delete(ruta)
      rescue StandardError => e
        return { ok: false, message: "No se pudo eliminar: #{e.message}" }
      end
      { ok: true, message: 'Regla de Construcción eliminada.', lista: listar }
    end
  end
end
