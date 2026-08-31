# frozen_string_literal: true

module Modular3D
  module Commands
    module Updater
      module_function

      def command
        Base.build('Buscar actualización', 'Buscar la última versión firmada de Modular_3D', 'update.svg') do
          LPenafiel_GeneradorMueblesExacto.buscar_actualizacion
        end
      end
    end
  end
end
