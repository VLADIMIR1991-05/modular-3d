# frozen_string_literal: true

module Modular3D
  module Commands
    module CreateModule
      module_function

      def command
        Base.build('Crear módulo Modular_3D', 'Diseñar un módulo paramétrico nuevo', 'create.svg') do
          LPenafiel_GeneradorMueblesExacto.mostrar_interfaz_moderna
        end
      end
    end
  end
end
