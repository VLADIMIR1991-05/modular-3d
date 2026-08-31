# frozen_string_literal: true

Sketchup.require 'Modular_3D/commands/base'
Sketchup.require 'Modular_3D/commands/create_module'
Sketchup.require 'Modular_3D/commands/edit_module'
Sketchup.require 'Modular_3D/commands/convert_module'
Sketchup.require 'Modular_3D/commands/corner_module'
Sketchup.require 'Modular_3D/commands/cutlist'
Sketchup.require 'Modular_3D/commands/budget'
Sketchup.require 'Modular_3D/commands/library'
Sketchup.require 'Modular_3D/commands/batch_edit'
Sketchup.require 'Modular_3D/commands/updater'

module Modular3D
  module Commands
    module_function

    PRIMARY_COMMANDS = [CreateModule, EditModule, ConvertModule, CornerModule, Cutlist, Budget, LibraryCommand, BatchEdit].freeze

    def register
      toolbar = UI::Toolbar.new(Modular3D::PRODUCT_NAME)
      menu = UI.menu('Extensions').add_submenu(Modular3D::PRODUCT_NAME)

      PRIMARY_COMMANDS.each do |command_module|
        command = command_module.command
        toolbar.add_item(command)
        menu.add_item(command)
      end
      menu.add_separator
      menu.add_item(Updater.command)

      toolbar.restore
      toolbar.show if toolbar.get_last_state == TB_NEVER_SHOWN
      @toolbar = toolbar
    end
  end
end
