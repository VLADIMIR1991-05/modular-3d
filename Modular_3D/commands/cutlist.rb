# frozen_string_literal: true

module Modular3D
  module Commands
    module Cutlist
      module_function

      def command
        Base.build('Despiece', 'Generar despiece y optimización de la selección', 'cutlist.svg') do
          next unless Base.licensed?
          LPenafiel_GeneradorMueblesExacto.generar_despiece_seleccion
        end
      end
    end
  end
end
