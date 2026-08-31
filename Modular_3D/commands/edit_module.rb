# frozen_string_literal: true

module Modular3D
  module Commands
    module EditModule
      module_function

      def command
        Base.build('Editar módulo seleccionado', 'Editar medidas, repisas, cajones y puertas del módulo', 'edit.svg') do
          next unless Base.licensed?
          LPenafiel_GeneradorMueblesExacto.editar_modulo_desde_seleccion
        end
      end
    end
  end
end
