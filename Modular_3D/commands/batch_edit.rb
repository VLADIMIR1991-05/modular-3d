# frozen_string_literal: true

module Modular3D
  module Commands
    module BatchEdit
      module_function

      def command
        Base.build('Lote', 'Repintar varios módulos Modular_3D seleccionados a la vez', 'batch.svg') do
          next unless Base.licensed?
          LPenafiel_GeneradorMueblesExacto.mostrar_edicion_lotes
        end
      end
    end
  end
end
