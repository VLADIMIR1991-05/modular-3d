# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module Modular3D
  # Catálogo Global de Tipos de Módulo: pedido explícito del usuario para
  # "crear tipos de modulos y tenerlos guardados con su respectiva
  # clasificacion, listos para modificar anchos y alturas" y que "todos
  # tengan acceso a ese catalogo" -- sincronizado contra el servidor de
  # plataforma en la nube (Modular3D::PLATFORM_API_URL, ver core/config.rb),
  # visible para cualquier usuario con licencia activa del producto
  # "modular3d_plugin".
  #
  # Reutiliza el MISMO token de sesión que ya administra Modular3D::License
  # (no hay una segunda cuenta ni una segunda contraseña): el servidor
  # resuelve, a partir de ese token, a qué usuario y a qué producto
  # pertenece la sesión, y aplica ahí el control de acceso (licencia activa
  # o bloqueada para ese producto puntual).
  module Catalogo
    module_function

    def categorias
      request(:get, '/api/catalog/categories')
    end

    def listar(categoria: nil, buscar: nil)
      query = {}
      query['category'] = categoria.to_s unless categoria.to_s.strip.empty?
      query['q'] = buscar.to_s unless buscar.to_s.strip.empty?
      request(:get, '/api/catalog/module-types', nil, query)
    end

    def detalle(id)
      request(:get, "/api/catalog/module-types/#{id.to_i}")
    end

    # datos: el hash completo de datosFormulario() del lado JS (medidas,
    # casco, jerarquia de espacios y materiales) -- el mismo manifiesto
    # paramétrico que ya usa "ejecutarConstruccionMueble" para fabricar el
    # módulo real, no una copia aparte.
    #
    # visibilidad: 'private' (default -- solo el dueño, más quien agregue a
    # "compartidos_actualizar" después) o 'global' (todos los usuarios con
    # licencia activa del producto). El servidor ya resuelve todo el resto
    # del control de acceso (dueño/compartido/admin) a partir de esto, el
    # mismo criterio que ya aplica "listar"/"detalle" sin que el plugin
    # tenga que filtrar nada -- ver visibilityWhere() en el Worker.
    def guardar(categoria, nombre, descripcion, datos, visibilidad = 'private')
      payload = {
        category: categoria.to_s.strip,
        name: nombre.to_s.strip,
        description: descripcion.to_s.strip,
        ancho_mm: numero(datos, 'ancho_total'),
        alto_mm: numero(datos, 'alto_total'),
        profundidad_mm: numero(datos, 'prof_total'),
        visibility: visibilidad.to_s == 'global' ? 'global' : 'private',
        data: datos
      }
      request(:post, '/api/catalog/module-types', payload)
    end

    def eliminar(id)
      request(:delete, "/api/catalog/module-types/#{id.to_i}")
    end

    # Cambia la visibilidad de un Tipo de Módulo ya guardado. El servidor
    # rechaza esto (FORBIDDEN) si quien llama no es el dueño ni un
    # administrador -- el plugin no necesita duplicar esa verificación acá.
    def cambiar_visibilidad(id, visibilidad)
      request(:put, "/api/catalog/module-types/#{id.to_i}/meta", { visibility: visibilidad.to_s == 'global' ? 'global' : 'private' })
    end

    # Usuarios con licencia activa del mismo producto a quienes se podría
    # compartir un módulo privado (excluye al propio usuario que pregunta).
    def usuarios_compartibles
      request(:get, '/api/catalog/shareable-users')
    end

    # Usuarios con quienes YA está compartido ese módulo puntual (solo
    # tiene sentido para uno privado; el servidor lo resuelve igual aunque
    # sea global, simplemente no afecta nada verlo).
    def compartidos_listar(id)
      request(:get, "/api/catalog/module-types/#{id.to_i}/shares")
    end

    # agregar/quitar: arrays de ids numéricos de usuario (license_users.id,
    # los mismos que devuelve usuarios_compartibles/compartidos_listar).
    def compartidos_actualizar(id, agregar: [], quitar: [])
      payload = { add: Array(agregar).map(&:to_i), remove: Array(quitar).map(&:to_i) }
      request(:put, "/api/catalog/module-types/#{id.to_i}/shares", payload)
    end

    # png_bytes: bytes crudos (binarios, no base64) del PNG a subir como
    # miniatura real del módulo -- el servidor (catalogThumbUpload) ya
    # permite esto al dueño del Tipo de Módulo (o a un admin), no hace
    # falta ningún permiso especial nuevo. Máx. 3MB (límite del servidor).
    def subir_miniatura(id, png_bytes)
      request(:put, "/api/catalog/module-types/#{id.to_i}/thumbnail", nil, nil, cuerpo_crudo: png_bytes, content_type: 'image/png')
    end

    def numero(datos, campo)
      return 0.0 unless datos.is_a?(Hash)

      valor = datos.key?(campo) ? datos[campo] : datos[campo.to_sym]
      valor.to_f
    end

    # cuerpo_crudo + content_type: para subir_miniatura (bytes de imagen tal
    # cual, no JSON) -- el servidor (catalogThumbUpload) lee el body con
    # request.arrayBuffer(), no con JSON.parse, así que acá no se puede
    # envolver en JSON.generate como el resto de las llamadas.
    def request(method, path, payload = nil, query = nil, cuerpo_crudo: nil, content_type: nil)
      token = Modular3D::License.saved_token
      if token.empty?
        return { ok: false, code: 'LOGIN_REQUIRED', message: 'Inicia sesión en Modular_3D para usar el Catálogo Global.' }
      end

      uri = URI.parse("#{Modular3D::PLATFORM_API_URL}#{path}")
      uri.query = URI.encode_www_form(query) if query && !query.empty?
      raise 'El Catálogo Global debe usar HTTPS.' if uri.scheme != 'https' && uri.host != '127.0.0.1' && uri.host != 'localhost'

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 6
      http.read_timeout = 15

      http_request = case method
                     when :get then Net::HTTP::Get.new(uri.request_uri)
                     when :post then Net::HTTP::Post.new(uri.request_uri)
                     when :put then Net::HTTP::Put.new(uri.request_uri)
                     when :delete then Net::HTTP::Delete.new(uri.request_uri)
                     else raise "Método no soportado: #{method}"
                     end
      http_request['Accept'] = 'application/json'
      http_request['Authorization'] = "Bearer #{token}"
      if cuerpo_crudo
        http_request['Content-Type'] = content_type || 'application/octet-stream'
        http_request.body = cuerpo_crudo
      elsif payload
        http_request['Content-Type'] = 'application/json'
        http_request.body = JSON.generate(payload)
      end

      response = http.request(http_request)
      body = response.body.to_s
      parsed = body.empty? ? {} : JSON.parse(body)
      symbolize(parsed).merge(http_status: response.code.to_i)
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED => error
      { ok: false, code: 'SERVER_UNAVAILABLE', message: 'No se pudo conectar al Catálogo Global.', detail: error.class.name }
    rescue JSON::ParserError
      { ok: false, code: 'INVALID_SERVER_RESPONSE', message: 'El servidor del Catálogo devolvió una respuesta inválida.' }
    rescue StandardError => error
      { ok: false, code: 'CATALOGO_ERROR', message: error.message }
    end

    def symbolize(hash)
      return hash unless hash.is_a?(Hash)

      hash.each_with_object({}) { |(key, value), output| output[key.to_s.to_sym] = value }
    end
  end
end
