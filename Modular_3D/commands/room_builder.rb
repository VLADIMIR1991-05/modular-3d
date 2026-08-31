# frozen_string_literal: true

module Modular3D
  module Commands
    module RoomBuilder
      module_function

      def command
        Base.build('Habitación', 'Generar muros rectos y piso a partir de una lista de tramos', 'room.svg') do
          next unless Base.licensed?
          LPenafiel_GeneradorMueblesExacto.mostrar_constructor_habitacion
        end
      end
    end
  end
end
