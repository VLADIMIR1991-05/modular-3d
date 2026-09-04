require 'sketchup'

require 'json'
require 'csv'
require 'net/http'
require 'uri'
require 'tmpdir'
require 'base64'
require 'securerandom'
require 'time'

Sketchup.require 'Modular_3D/core/config'
Sketchup.require 'Modular_3D/core/validation'
Sketchup.require 'Modular_3D/core/license'

# plugin.rb quedó como el núcleo (licencia/manifiesto) del módulo
# LPenafiel_GeneradorMueblesExacto; el resto de responsabilidades se separó
# en estos archivos, que reabren el mismo módulo (ver el reporte de
# arquitectura: antes esto era un solo archivo de más de 3700 líneas).
Sketchup.require 'Modular_3D/core/geometria'
Sketchup.require 'Modular_3D/core/actualizaciones'
Sketchup.require 'Modular_3D/core/componentes_dinamicos'
Sketchup.require 'Modular_3D/core/jerarquia'
Sketchup.require 'Modular_3D/core/despiece'
Sketchup.require 'Modular_3D/core/presupuesto'
Sketchup.require 'Modular_3D/core/biblioteca'
Sketchup.require 'Modular_3D/core/esquinero'
Sketchup.require 'Modular_3D/core/habitacion'

# Modular_3D
# Autor: Lenin Vladimir Peñafiel
# Versión: 4.8.23
module LPenafiel_GeneradorMueblesExacto

  # Una licencia real debe validarse con un servicio firmado. El nombre de
  # usuario de Windows no es un mecanismo de seguridad.
  def self.acceso_autorizado?
    true
  end

  @nombre_modulo_guardado = "BAJO"
  @ultimo_modulo_piezas = []
  @offset_creacion = nil
  @piezas_modulo_actual = nil
  @datos_modulo_actual = nil
  @seleccion_edicion = nil
  @offset_edicion = nil
  @modulo_uuid_actual = nil
  @contenedor_edicion = nil
  @transformacion_edicion = nil

  MANIFEST_VERSION = 6

  def self.migrar_manifiesto(manifiesto)
    return manifiesto unless manifiesto.is_a?(Hash)
    data = manifiesto['data'].is_a?(Hash) ? manifiesto['data'] : {}
    data['coordinate_system'] ||= 'X_WIDTH_Y_DEPTH_Z_HEIGHT_FRONT_NEGATIVE_Y'
    data['edge_mode'] ||= 'MIXED'
    data['edge_inherit_color'] ||= 'SI'
    data['selected_space_id'] ||= 'root'
    data['material_overrides_json'] ||= '{}'
    data['material_textures_json'] ||= '{}'
    data['material_texture_meta_json'] ||= '{}'
    data['dimension_overrides_json'] ||= '{}'
    # Schema 6: inglete por pieza y montaje de puerta independiente del casco.
    data['miter_overrides_json'] ||= '{}'
    data['montaje_puerta'] ||= 'SOLAPADA'
    data['external_front_scope'] ||= 'BY_SPACE'
    data['global_front_count_mode'] ||= 'AUTO'
    data['global_front_count'] ||= 2
    data['global_front_auto_width'] ||= 600
    %w[left right top bottom].each { |lado| data["global_front_gap_#{lado}"] ||= 1.5 }
    data['global_front_gap_center'] ||= 3
    # Casco activable (schema 5): módulos anteriores conservan los 4 paneles.
    %w[lleva_lateral_izq lleva_lateral_der lleva_base lleva_techo].each { |campo| data[campo] ||= 'SI' }
    data['ajuste_frontal_activo'] ||= 'NO'
    data['ajuste_frontal_orientacion'] ||= 'HORIZONTAL'
    data['ajuste_posterior_orientacion'] ||= 'HORIZONTAL'
    manifiesto['data'] = data
    manifiesto['migrated_from_schema'] = manifiesto['schema'].to_i if manifiesto['schema'].to_i < MANIFEST_VERSION
    manifiesto['schema'] = MANIFEST_VERSION
    manifiesto
  end

  def self.manifiesto_de_entidad(entity)
    return nil unless entity
    candidatos = [entity]
    candidatos << entity.definition if entity.respond_to?(:definition) && entity.definition
    candidatos.each do |objeto|
      raw = objeto.get_attribute('Modular3D', 'manifest') if objeto.respond_to?(:get_attribute)
      next if raw.to_s.strip.empty?
      begin
        data = raw.is_a?(Hash) ? raw : JSON.parse(raw.to_s)
        return migrar_manifiesto(data) if data.is_a?(Hash)
      rescue JSON::ParserError
        next
      end
    end
    nil
  end

  def self.crear_manifiesto(datos, modulo_nombre, uuid = nil, source = 'PARAMETRICO')
    limpio = datos.reject { |clave, _valor| clave.to_s.start_with?('__') || clave.to_s == 'view_snapshot' }
    {
      'schema' => MANIFEST_VERSION,
      'uuid' => uuid.to_s.empty? ? SecureRandom.uuid : uuid,
      'plugin_version' => Modular3D::VERSION,
      'source' => source,
      'name' => modulo_nombre,
      'updated_at' => Time.now.utc.iso8601,
      'coordinate_system' => 'X_WIDTH_Y_DEPTH_Z_HEIGHT_FRONT_NEGATIVE_Y',
      'data' => limpio
    }
  end

  def self.encapsular_modulo(entities, piezas, manifiesto)
    validas = piezas.to_a.select { |pieza| pieza && pieza.respond_to?(:valid?) && pieza.valid? }
    return nil if validas.empty?
    contenedor = entities.add_group(validas)
    nombre = "M3D_MODULO_#{manifiesto['name']}"
    contenedor.name = nombre if contenedor.respond_to?(:name=)
    raw = JSON.generate(manifiesto)
    [contenedor, (contenedor.definition if contenedor.respond_to?(:definition))].compact.each do |objeto|
      objeto.set_attribute('Modular3D', 'type', 'MODULE')
      objeto.set_attribute('Modular3D', 'uuid', manifiesto['uuid'])
      objeto.set_attribute('Modular3D', 'manifest', raw)
    end
    contenedor.definition.name = nombre if contenedor.respond_to?(:definition) && contenedor.definition
    contenedor
  end

  def self.inventario_geometrico(entity_or_list)
    encontrados = []
    visitar = lambda do |entity|
      if entity.respond_to?(:definition) && entity.definition
        original = entity.definition.get_attribute('LPenafiel', 'pieza_original')
        if original
          dims = [entity.bounds.width, entity.bounds.depth, entity.bounds.height].map { |v| v.to_mm.round(2) }.sort
          encontrados << {'name'=>original.to_s, 'dims'=>dims}
        else
          entity.definition.entities.each { |child| visitar.call(child) }
        end
      elsif entity.respond_to?(:entities)
        entity.entities.each { |child| visitar.call(child) }
      end
    end
    Array(entity_or_list).each { |entity| visitar.call(entity) }
    encontrados.sort_by { |item| [item['name'], item['dims']] }
  end
end
