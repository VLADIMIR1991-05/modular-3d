# frozen_string_literal: true

require 'digest'
require 'json'
require 'net/http'
require 'securerandom'
require 'time'
require 'uri'

module Modular3D
  module License
    module_function

    INSTALLATION_KEY = "installation_uuid"
    TOKEN_KEY = "license_token"
    EMAIL_KEY = "license_email"

    @verified_until = Time.at(0)
    @last_status = { ok: false, code: "NOT_VALIDATED" }

    def enabled?
      Modular3D::LICENSE_ENABLED == true
    end

    def installation_uuid
      value = Sketchup.read_default(Modular3D::PREFERENCES_KEY, INSTALLATION_KEY, "").to_s
      return value unless value.empty?

      value = SecureRandom.uuid
      Sketchup.write_default(Modular3D::PREFERENCES_KEY, INSTALLATION_KEY, value)
      value
    end

    def machine_id
      source = [installation_uuid, Sketchup.platform.to_s, RUBY_PLATFORM.to_s].join("|")
      Digest::SHA256.hexdigest(source)
    end

    def saved_token
      Sketchup.read_default(Modular3D::PREFERENCES_KEY, TOKEN_KEY, "").to_s
    end

    def saved_email
      Sketchup.read_default(Modular3D::PREFERENCES_KEY, EMAIL_KEY, "").to_s
    end

    def authorized_cached?
      !enabled? || (@last_status[:ok] == true && Time.now < @verified_until)
    end

    # Una contraseña solo es necesaria para crear la sesión. Todas las
    # operaciones posteriores renuevan silenciosamente el token persistido.
    def ensure_authorized
      return @last_status if authorized_cached?
      return mark_verified(ok: true, mode: "development") unless enabled?
      return { ok: false, code: "LOGIN_REQUIRED" } if saved_token.empty?

      validate
    end

    def login(email, password, force_transfer = false)
      response = request(
        "/auth/login",
        {
          email: email.to_s.strip.downcase,
          password: password.to_s,
          machine_id: machine_id,
          force_transfer: force_transfer == true,
          plugin_version: Modular3D::VERSION,
          sketchup_version: Sketchup.version.to_s,
          product_code: "modular3d_plugin"
        }
      )
      if response[:ok] && response[:token]
        Sketchup.write_default(Modular3D::PREFERENCES_KEY, TOKEN_KEY, response[:token])
        Sketchup.write_default(Modular3D::PREFERENCES_KEY, EMAIL_KEY, email.to_s.strip.downcase)
        mark_verified(response)
      end
      response
    end

    # Se llama cuando login() devolvió TERMS_REQUIRED y el usuario aceptó los
    # términos en el diálogo. Reenvía las mismas credenciales al servidor,
    # que registra la aceptación (una sola vez, para siempre) y devuelve la
    # sesión igual que login() si accept es true.
    def accept_terms(email, password, accept, force_transfer = false)
      response = request(
        "/auth/accept-terms",
        {
          email: email.to_s.strip.downcase,
          password: password.to_s,
          accept: accept == true,
          machine_id: machine_id,
          force_transfer: force_transfer == true,
          plugin_version: Modular3D::VERSION,
          sketchup_version: Sketchup.version.to_s,
          product_code: "modular3d_plugin"
        }
      )
      if response[:ok] && response[:token]
        Sketchup.write_default(Modular3D::PREFERENCES_KEY, TOKEN_KEY, response[:token])
        Sketchup.write_default(Modular3D::PREFERENCES_KEY, EMAIL_KEY, email.to_s.strip.downcase)
        mark_verified(response)
      end
      response
    end

    def validate
      return mark_verified(ok: true, mode: "development") unless enabled?
      return { ok: false, code: "LOGIN_REQUIRED" } if saved_token.empty?

      response = request(
        "/license/validate",
        {
          token: saved_token,
          machine_id: machine_id,
          plugin_version: Modular3D::VERSION,
          sketchup_version: Sketchup.version.to_s,
          product_code: "modular3d_plugin"
        }
      )
      response[:ok] ? mark_verified(response) : mark_denied(response)
    end

    def heartbeat
      return validate unless authorized_cached?
      response = request(
        "/license/heartbeat",
        { token: saved_token, machine_id: machine_id, plugin_version: Modular3D::VERSION, product_code: "modular3d_plugin" }
      )
      response[:ok] ? mark_verified(response) : mark_denied(response)
    end

    def logout
      request("/auth/logout", { token: saved_token, machine_id: machine_id }) unless saved_token.empty?
    rescue StandardError
      nil
    ensure
      Sketchup.write_default(Modular3D::PREFERENCES_KEY, TOKEN_KEY, "")
      @verified_until = Time.at(0)
      @last_status = { ok: false, code: "LOGIN_REQUIRED" }
    end

    def status
      ensure_authorized
    end

    # Se usa al abrir el diálogo del configurador: fuerza una llamada real a
    # /license/validate en vez de devolver la caché de hasta 72h
    # (LICENSE_SESSION_MAX_SECONDS). Así, si un administrador extendió la
    # licencia desde el panel, el plugin lo refleja de inmediato (fecha
    # límite, días restantes) sin esperar a que la caché expire ni reiniciar
    # SketchUp. Usa el token ya guardado, no pide contraseña.
    #
    # Si el servidor no responde (sin internet, mantenimiento, etc.) pero la
    # sesión seguía siendo válida localmente, no se desconecta al usuario:
    # se conserva el estado en caché y se reintenta en el próximo heartbeat.
    def refresh_status
      return mark_verified(ok: true, mode: "development") unless enabled?
      return { ok: false, code: "LOGIN_REQUIRED" } if saved_token.empty?

      had_valid_cache = authorized_cached?
      cached_status = @last_status
      cached_until = @verified_until

      response = validate
      return response if response[:ok]

      if response[:code] == "SERVER_UNAVAILABLE" && had_valid_cache
        @last_status = cached_status
        @verified_until = cached_until
        return cached_status
      end

      response
    end

    def request(path, payload)
      uri = URI.parse("#{Modular3D::LICENSE_API_URL}#{path}")
      raise "La API de licencias debe usar HTTPS." if uri.scheme != "https" && uri.host != "127.0.0.1" && uri.host != "localhost"

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 8
      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request.body = JSON.generate(payload)
      response = http.request(request)
      body = JSON.parse(response.body.to_s)
      symbolize(body).merge(http_status: response.code.to_i)
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED => error
      { ok: false, code: "SERVER_UNAVAILABLE", message: "No se pudo conectar al servidor de licencias.", detail: error.class.name }
    rescue JSON::ParserError
      { ok: false, code: "INVALID_SERVER_RESPONSE", message: "El servidor devolvió una respuesta inválida." }
    rescue StandardError => error
      { ok: false, code: "LICENSE_ERROR", message: error.message }
    end

    def mark_verified(response)
      # El servidor (Cloudflare Worker) nunca manda ttl_seconds -- por eso
      # [nil.to_i, 60].max daba SIEMPRE 60 segundos de cache real, sin
      # importar LICENSE_SESSION_MAX_SECONDS: cada build (que llama
      # ensure_authorized) y cada heartbeat de 15min terminaban haciendo un
      # request en vivo al servidor de todos modos. Si el servidor no manda
      # ttl_seconds, se confia en la sesion recien validada por el techo
      # completo (LICENSE_SESSION_MAX_SECONDS = 24h), no por 60 segundos.
      ttl_servidor = response[:ttl_seconds].to_i
      ttl = ttl_servidor > 0 ? [ttl_servidor, Modular3D::LICENSE_SESSION_MAX_SECONDS].min : Modular3D::LICENSE_SESSION_MAX_SECONDS
      @verified_until = Time.now + ttl
      @last_status = response.merge(ok: true, verified_until: @verified_until.utc.iso8601)
    end

    def mark_denied(response)
      @verified_until = Time.at(0)
      @last_status = response.merge(ok: false)
    end

    def symbolize(hash)
      hash.each_with_object({}) { |(key, value), output| output[key.to_s.to_sym] = value }
    end
  end
end
