# frozen_string_literal: true

module Modular3D
  module Commands
    module Base
      module_function

      ROOT = File.expand_path('..', __dir__)
      ICONS = File.join(ROOT, 'images')

      def build(title, tooltip, icon_name, &action)
        command = UI::Command.new(title, &action)
        command.tooltip = tooltip
        command.status_bar_text = tooltip
        icon = File.join(ICONS, icon_name)
        if File.exist?(icon)
          command.small_icon = icon
          command.large_icon = icon
        end
        command
      end

      def licensed?
        estado = Modular3D::License.ensure_authorized
        return true if estado[:ok]

        UI.messagebox(estado[:message] || 'Debes iniciar sesión y validar tu licencia desde el botón Crear módulo.')
        false
      end
    end
  end
end
