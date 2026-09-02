# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

unless file_loaded?(__FILE__)
  extension = SketchupExtension.new(
    'Modular_3D',
    'Modular_3D/RUBY'
  )

  extension.creator = 'Lenin Vladimir Peñafiel Buestan'
  extension.description = 'Configurador paramétrico de mobiliario, despiece y optimización de tableros para SketchUp.'
  extension.version = '4.8.6-beta.1'
  extension.copyright = '© 2026 Lenin Vladimir Peñafiel Buestan. Todos los derechos reservados.'

  Sketchup.register_extension(extension, true)
  file_loaded(__FILE__)
end
