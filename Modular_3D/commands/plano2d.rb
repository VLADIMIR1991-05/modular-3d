# frozen_string_literal: true

module Modular3D
  module Commands
    module Plano2D
      module_function

      def command
        Base.build('Plano 2D (SVG)', 'Exportar elevación frontal esquemática de los módulos seleccionados', 'cutlist.svg') do
          next unless Base.licensed?
          LPenafiel_GeneradorMueblesExacto.exportar_plano_2d_seleccion
        end
      end
    end
  end
end
