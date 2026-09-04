# frozen_string_literal: true

module Modular3D
  PRODUCT_NAME = "Modular_3D"
  VERSION = "4.8.13-beta.1"
  AUTHOR = "Lenin Vladimir Peñafiel Buestan"
  PREFERENCES_KEY = "com.lpenafiel.modular3d"
  LICENSE_ENABLED = true
  LICENSE_API_URL = "https://api.modular-3d.com/api/v1"
  UPDATE_MANIFEST_URL = "https://api.modular-3d.com/latest.json"
  LICENSE_HEARTBEAT_SECONDS = 900
  LICENSE_SESSION_MAX_SECONDS = 3600

  DEFAULTS = {
    "ancho_total" => 600.0,
    "alto_total" => 760.0,
    "prof_total" => 580.0,
    "espesor" => 15.0,
    "grosor_respaldo" => 6.0,
    "juego_general" => 2.0
  }.freeze
end
