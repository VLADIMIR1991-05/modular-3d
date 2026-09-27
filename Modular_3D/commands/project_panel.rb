# frozen_string_literal: true

module Modular3D
  module Commands
    module ProjectPanel
      module_function

      def command
        Base.build('Panel de Proyecto', 'Resumen por módulo de piezas, puertas, bisagras y cajones', 'presupuesto.svg') do
          next unless Base.licensed?
          LPenafiel_GeneradorMueblesExacto.mostrar_panel_proyecto
        end
      end
    end
  end
end
