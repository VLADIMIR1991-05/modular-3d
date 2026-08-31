# frozen_string_literal: true

module Modular3D
  module Commands
    module CornerModule
      module_function

      def command
        Base.build('Módulo esquinero L', 'Crear un módulo esquinero en L con costura mitrada a 45°', 'corner.svg') do
          next unless Base.licensed?
          LPenafiel_GeneradorMueblesExacto.mostrar_interfaz_esquinero_l
        end
      end
    end
  end
end
