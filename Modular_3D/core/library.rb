# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'securerandom'

module Modular3D
  # Biblioteca local de componentes propios: sustituto honesto de una
  # "biblioteca en la nube". Guarda componentes de SketchUp como archivos
  # .skp normales dentro de la carpeta de datos del usuario, organizados por
  # categoría/subcategoría, con un manifest.json como índice. No hay ningún
  # backend ni sincronización real: para llevarla a otro equipo, el usuario
  # copia la carpeta entera (se le indica la ruta exacta en el diálogo).
  module Library
    module_function

    def raiz
      base = ENV['APPDATA'] || Sketchup.temp_dir
      File.join(base, 'Modular_3D', 'biblioteca')
    end

    def ruta_manifest
      File.join(raiz, 'manifest.json')
    end

    def cargar_manifest
      return { 'items' => [] } unless File.exist?(ruta_manifest)

      begin
        datos = JSON.parse(File.read(ruta_manifest))
        datos.is_a?(Hash) && datos['items'].is_a?(Array) ? datos : { 'items' => [] }
      rescue JSON::ParserError, StandardError
        { 'items' => [] }
      end
    end

    def guardar_manifest(manifest)
      FileUtils.mkdir_p(raiz)
      File.write(ruta_manifest, JSON.generate(manifest))
    end

    def nombre_archivo_seguro(texto)
      texto.to_s.strip.gsub(/[^0-9A-Za-zÁÉÍÓÚÜÑáéíóúüñ _-]/, '').gsub(/\s+/, '_')
    end

    def guardar_seleccion(categoria, subcategoria, nombre)
      model = Sketchup.active_model
      seleccion = model.selection.to_a
      return { ok: false, message: 'Selecciona un grupo o componente para guardar.' } if seleccion.empty?

      entidad = seleccion.find { |item| item.respond_to?(:definition) && item.definition }
      return { ok: false, message: 'La selección debe ser un grupo o componente (no piezas sueltas).' } unless entidad

      categoria_limpia = nombre_archivo_seguro(categoria.to_s.empty? ? 'General' : categoria)
      subcategoria_limpia = nombre_archivo_seguro(subcategoria)
      nombre_limpio = nombre_archivo_seguro(nombre.to_s.empty? ? 'componente' : nombre)
      return { ok: false, message: 'El nombre no puede quedar vacío después de limpiar caracteres especiales.' } if nombre_limpio.empty?

      carpeta = subcategoria_limpia.empty? ? File.join(raiz, categoria_limpia) : File.join(raiz, categoria_limpia, subcategoria_limpia)
      FileUtils.mkdir_p(carpeta)
      id = SecureRandom.uuid
      archivo = File.join(carpeta, "#{nombre_limpio}_#{id[0, 8]}.skp")

      definicion = entidad.definition
      guardado = definicion.save_as(archivo)
      return { ok: false, message: 'SketchUp no pudo guardar el componente.' } unless guardado

      manifest = cargar_manifest
      manifest['items'] << {
        'id' => id, 'nombre' => nombre.to_s.strip.empty? ? nombre_limpio : nombre.to_s.strip,
        'categoria' => categoria.to_s.strip.empty? ? 'General' : categoria.to_s.strip,
        'subcategoria' => subcategoria.to_s.strip,
        'archivo' => archivo, 'guardado_en' => Time.now.utc.iso8601
      }
      guardar_manifest(manifest)
      { ok: true, message: "Guardado en la biblioteca (#{categoria_limpia}#{subcategoria_limpia.empty? ? '' : "/#{subcategoria_limpia}"})." }
    rescue StandardError => e
      { ok: false, message: "No se pudo guardar: #{e.message}" }
    end

    def cargar_item(id)
      manifest = cargar_manifest
      item = manifest['items'].find { |entrada| entrada['id'] == id }
      return { ok: false, message: 'No se encontró ese elemento en la biblioteca.' } unless item
      return { ok: false, message: 'El archivo .skp de este elemento ya no existe en disco.' } unless File.exist?(item['archivo'])

      model = Sketchup.active_model
      definicion = model.definitions.load(item['archivo'])
      model.start_operation('Insertar desde biblioteca Modular_3D', true)
      model.active_entities.add_instance(definicion, Geom::Transformation.new)
      model.commit_operation
      { ok: true, message: "«#{item['nombre']}» insertado en el origen del modelo." }
    rescue StandardError => e
      { ok: false, message: "No se pudo insertar: #{e.message}" }
    end

    def eliminar_item(id)
      manifest = cargar_manifest
      item = manifest['items'].find { |entrada| entrada['id'] == id }
      return { ok: false, message: 'No se encontró ese elemento.' } unless item

      File.delete(item['archivo']) if item['archivo'] && File.exist?(item['archivo'])
      manifest['items'].reject! { |entrada| entrada['id'] == id }
      guardar_manifest(manifest)
      { ok: true, message: 'Eliminado de la biblioteca.' }
    rescue StandardError => e
      { ok: false, message: "No se pudo eliminar: #{e.message}" }
    end
  end
end
