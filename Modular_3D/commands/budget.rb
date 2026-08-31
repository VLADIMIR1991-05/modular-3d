# frozen_string_literal: true

module Modular3D
  module Commands
    module Budget
      module_function

      def command
        Base.build('Presupuesto', 'Generar cotización de la selección (tableros, cantos, herrajes)', 'presupuesto.svg') do
          next unless Base.licensed?
          LPenafiel_GeneradorMueblesExacto.mostrar_presupuesto
        end
      end
    end
  end
end
