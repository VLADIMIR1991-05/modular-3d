# frozen_string_literal: true

require 'sketchup.rb'
Sketchup.require 'Modular_3D/core/profiles'
Sketchup.require 'Modular_3D/core/plugin'
Sketchup.require 'Modular_3D/commands/registry'

Modular3D::Commands.register unless file_loaded?(__FILE__)
file_loaded(__FILE__)
