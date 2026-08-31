# frozen_string_literal: true

module Modular3D
  module Commands
    module ConvertModule
      module_function

      def command
        Base.build('Convertir selección en módulo', 'Encapsular o migrar piezas como módulo paramétrico Modular_3D', 'convert.svg') do
          next unless Base.licensed?
          LPenafiel_GeneradorMueblesExacto.convertir_seleccion_en_modulo
        end
      end
    end
  end
end
