# frozen_string_literal: true

module Modular3D
  PRODUCT_NAME = "Modular_3D"
  VERSION = "6.4.22"
  AUTHOR = "Lenin Vladimir Peñafiel Buestan"
  PREFERENCES_KEY = "com.lpenafiel.modular3d"
  LICENSE_ENABLED = true
  LICENSE_API_URL = "https://api.modular-3d.com/api/v1"
  # Raíz del servidor de plataforma (Catálogo Global de Tipos de Módulo,
  # administración multi-producto). Mismo dominio que LICENSE_API_URL, sin el
  # prefijo "/api/v1" -- ver Modular3D::Catalogo en core/catalogo.rb.
  PLATFORM_API_URL = "https://api.modular-3d.com"
  UPDATE_MANIFEST_URL = "https://api.modular-3d.com/latest.json"
  # Cada cuanto el dialogo abierto pide un chequeo liviano al servidor SOLO
  # para refrescar el estado mostrado (días restantes, bloqueo, etc.) --
  # ver el setInterval en interfaz.js. Siempre hace un request real, sin
  # importar LICENSE_SESSION_MAX_SECONDS de abajo.
  LICENSE_HEARTBEAT_SECONDS = 900
  # 24 horas: techo local de cuánto dura la sesión verificada (login/
  # heartbeat exitoso) antes de que otras llamadas que dependen de
  # authorized_cached? (como el chequeo previo a construir un módulo)
  # vuelvan a llamar de verdad al servidor en vez de confiar en la cache.
  # Esto por sí solo NO evita el relogin forzado si el token emitido por el
  # servidor expira antes (ver SESSION_SECONDS en el Worker de licencias) --
  # ver nota en license.rb.
  LICENSE_SESSION_MAX_SECONDS = 86_400

  DEFAULTS = {
    "ancho_total" => 600.0,
    "alto_total" => 760.0,
    "prof_total" => 580.0,
    "espesor" => 15.0,
    "grosor_respaldo" => 6.0,
    "juego_general" => 2.0
  }.freeze
end
