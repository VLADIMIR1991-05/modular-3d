# frozen_string_literal: true

module Modular3D
  module Commands
    module CreateModule
      module_function

      def command
        Base.build('Crear módulo Modular_3D', 'Diseñar un módulo paramétrico nuevo', 'create.svg') do
          # Configuración de Proyecto (§4): precarga el formulario con los
          # valores por defecto guardados para ESTE modelo, si existen. Si el
          # proyecto no tiene configuración guardada, Proyecto.cargar devuelve
          # {} y mostrar_interfaz_moderna no inyecta nada -- mismo
          # comportamiento que antes de que Configuración de Proyecto existiera.
          datos_proyecto = Modular3D::Proyecto.cargar(Sketchup.active_model)
          LPenafiel_GeneradorMueblesExacto.mostrar_interfaz_moderna(datos_proyecto)
        end
      end
    end
  end
end
