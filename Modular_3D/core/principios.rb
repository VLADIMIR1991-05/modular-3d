# frozen_string_literal: true

require 'json'
require 'time'

module Modular3D
  # "Principios de Espacio" (inspirado en el Principio de Construcción + el
  # patrón _INSERT.xml/PART de imos, ver B_02/B_03/XML documentation_V6): un
  # nodo de la jerarquía (content/front/drawers/shelves/enclosure/
  # sobremedida/gap/etc., SIN su id ni su box, que son propios de cada
  # instancia) se guarda una sola vez y se reaplica a cualquier espacio de
  # cualquier módulo. Igual que imos separa la carpeta de fábrica de la del
  # usuario, "_de_fabrica" son los que vienen empaquetados con el plugin (no
  # editables/borrables desde la UI) y la carpeta de nivel superior es la del
  # usuario.
  module Principios
    module_function

    DIRECTORIO_USUARIO = File.expand_path('../principios', __dir__)
    DIRECTORIO_FABRICA = File.join(DIRECTORIO_USUARIO, '_de_fabrica')

    # Campos del nodo de jerarquía que tiene sentido guardar/reaplicar como
    # Principio -- deliberadamente NO incluye "id" ni "box" (propios de cada
    # instancia dentro de un árbol ya construido) ni "children" (un Principio
    # describe UN espacio, no una subestructura completa; anidar Principios
    # queda fuera de esta primera ronda para no arriesgar ciclos o árboles
    # incoherentes sin poder probarlo en vivo dentro de SketchUp).
    CAMPOS_NODO = %w[
      content front frontCount frontFit frontJoint overlayLeft overlayRight overlayTop overlayBottom
      drawers shelves gap gapCenter drawerGap drawerHeight drawerFrontStyle tiradera hinge
      enclosure sobremedida
    ].freeze

    def listar_de(directorio, origen)
      return [] unless Dir.exist?(directorio)

      Dir.glob(File.join(directorio, '*.json')).sort.map do |ruta|
        begin
          datos = JSON.parse(File.read(ruta))
        rescue JSON::ParserError, StandardError
          next nil
        end
        next nil unless datos.is_a?(Hash) && datos['principio_id'] && datos['nodo'].is_a?(Hash)

        datos['origen'] = origen
        datos
      end.compact
    end

    def listar
      listar_de(DIRECTORIO_FABRICA, 'FABRICA') + listar_de(DIRECTORIO_USUARIO, 'USUARIO')
    end

    def guardar(nodo, nombre, principio_id_existente = nil)
      return { ok: false, message: 'Selecciona primero un espacio en el árbol.' } unless nodo.is_a?(Hash)

      nombre_limpio = nombre.to_s.strip
      return { ok: false, message: 'El Principio necesita un nombre.' } if nombre_limpio.empty?

      id_normalizado = principio_id_existente.to_s.strip
      id_normalizado = nombre_limpio.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '') if id_normalizado.empty?
      return { ok: false, message: 'No se pudo derivar un identificador del nombre indicado.' } if id_normalizado.empty?

      nodo_limpio = {}
      CAMPOS_NODO.each { |campo| nodo_limpio[campo] = nodo[campo] unless nodo[campo].nil? }

      registro = {
        'principio_id' => id_normalizado,
        'nombre' => nombre_limpio,
        'creado' => Time.now.utc.iso8601,
        'nodo' => nodo_limpio
      }

      begin
        require 'fileutils'
        FileUtils.mkdir_p(DIRECTORIO_USUARIO)
        File.write(File.join(DIRECTORIO_USUARIO, "#{id_normalizado}.json"), JSON.pretty_generate(registro))
      rescue StandardError => e
        return { ok: false, message: "No se pudo guardar: #{e.message}" }
      end

      { ok: true, message: "Principio \"#{nombre_limpio}\" guardado. Reaplicarlo actualiza este archivo.", principio: registro, lista: listar }
    end

    def eliminar(principio_id)
      ruta = File.join(DIRECTORIO_USUARIO, "#{principio_id}.json")
      return { ok: false, message: 'Ese Principio no existe en tu carpeta de usuario (los de fábrica no se pueden eliminar desde aquí).' } unless File.exist?(ruta)

      begin
        File.delete(ruta)
      rescue StandardError => e
        return { ok: false, message: "No se pudo eliminar: #{e.message}" }
      end
      { ok: true, message: 'Principio eliminado.', lista: listar }
    end
  end
end
