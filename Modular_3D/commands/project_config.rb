# frozen_string_literal: true

module Modular3D
  module Commands
    module ProjectConfig
      module_function

      def command
        Base.build('Configuración de Proyecto', 'Valores por defecto para los módulos nuevos de este archivo', 'library.svg') do
          next unless Base.licensed?
          Modular3D::Proyecto.mostrar_dialogo
        end
      end
    end
  end
end
