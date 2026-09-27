# frozen_string_literal: true

module Modular3D
  module Commands
    module Continuity
      module_function

      def command
        Base.build('Sincronizar continuidad', 'Une zócalo, premesón y cornisa de módulos pegados en tramos continuos de hasta 2420mm', 'update.svg') do
          next unless Base.licensed?
          LPenafiel_GeneradorMueblesExacto.sincronizar_continuidad
        end
      end
    end
  end
end
