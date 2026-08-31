# frozen_string_literal: true

module Modular3D
  module Commands
    module TagPiece
      module_function

      def command
        Base.build('Etiquetar pieza', 'Diseño libre: asignar nombre y cantos a una pieza dibujada a mano', 'tag.svg') do
          next unless Base.licensed?
          LPenafiel_GeneradorMueblesExacto.etiquetar_pieza_seleccionada
        end
      end
    end
  end
end
