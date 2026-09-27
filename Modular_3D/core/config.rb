# frozen_string_literal: true

module Modular3D
  PRODUCT_NAME = "Modular_3D"
  VERSION = "6.2.0"
  AUTHOR = "Lenin Vladimir Peñafiel Buestan"
  PREFERENCES_KEY = "com.lpenafiel.modular3d"
  LICENSE_ENABLED = true
  LICENSE_API_URL = "https://api.modular-3d.com/api/v1"
  # Raíz del servidor de plataforma (Catálogo Global de Tipos de Módulo,
  # administración multi-producto). Mismo dominio que LICENSE_API_URL, sin el
  # prefijo "/api/v1" -- ver Modular3D::Catalogo en core/catalogo.rb.
  PLATFORM_API_URL = "https://api.modular-3d.com"
  UPDATE_MANIFEST_URL = "https://api.modular-3d.com/latest.json"
  LICENSE_HEARTBEAT_SECONDS = 900
  # 72 horas: techo local de cuánto dura la sesión verificada antes de
  # volver a llamar a /license/validate. Esto por sí solo NO evita el
  # relogin forzado si el token emitido por el servidor expira antes (ver
  # SESSION_SECONDS en el Worker de licencias) -- ver nota en license.rb.
  LICENSE_SESSION_MAX_SECONDS = 259_200

  DEFAULTS = {
    "ancho_total" => 600.0,
    "alto_total" => 760.0,
    "prof_total" => 580.0,
    "espesor" => 15.0,
    "grosor_respaldo" => 6.0,
    "juego_general" => 2.0
  }.freeze
end
