# frozen_string_literal: true

module Modular3D
  module Commands
    module LibraryCommand
      module_function

      def command
        Base.build('Biblioteca', 'Guardar y reutilizar componentes propios (local)', 'library.svg') do
          next unless Base.licensed?
          LPenafiel_GeneradorMueblesExacto.mostrar_biblioteca
        end
      end
    end
  end
end
