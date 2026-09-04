# frozen_string_literal: true

module LPenafiel_GeneradorMueblesExacto
  def self.version_partes(version)
    normalizada = version.to_s.strip.tr("_", "-")
    match = normalizada.match(/\A[vV]?(\d+)\.(\d+)\.(\d+)(?:[-.]([0-9A-Za-z.-]+))?\z/)
    return nil unless match

    [match[1].to_i, match[2].to_i, match[3].to_i, match[4]]
  end

  def self.version_mayor?(remota, local)
    izquierda = version_partes(remota)
    derecha = version_partes(local)
    return false unless izquierda && derecha
    base = izquierda[0, 3] <=> derecha[0, 3]
    return base.positive? unless base.zero?
    return false if izquierda[3] == derecha[3]
    return true if izquierda[3].nil? # Una versión estable supera a cualquier prerelease.
    return false if derecha[3].nil?

    izq_pre = izquierda[3].split('.')
    der_pre = derecha[3].split('.')
    [izq_pre.length, der_pre.length].max.times do |indice|
      return false unless izq_pre[indice]
      return true unless der_pre[indice]
      a = izq_pre[indice]
      b = der_pre[indice]
      comparacion = if a =~ /\A\d+\z/ && b =~ /\A\d+\z/
                      a.to_i <=> b.to_i
                    elsif a =~ /\A\d+\z/
                      -1
                    elsif b =~ /\A\d+\z/
                      1
                    else
                      a <=> b
                    end
      return comparacion.positive? unless comparacion.zero?
    end
    false
  end

  def self.buscar_actualizacion
    uri = URI.parse(Modular3D::UPDATE_MANIFEST_URL)
    raise ArgumentError, 'El manifiesto de actualización debe usar HTTPS.' unless uri.scheme == 'https'
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 8
    response = http.get(uri.request_uri, "Accept" => "application/json")
    data = JSON.parse(response.body.to_s)
    unless response.is_a?(Net::HTTPSuccess) && data["version"] && data["rbz_url"]
      return UI.messagebox("No se pudo leer la informacion de actualizacion.")
    end
    descarga = URI.parse(data['rbz_url'].to_s)
    unless descarga.scheme == 'https' && descarga.host == uri.host
      return UI.messagebox('La actualización fue rechazada porque la descarga no pertenece al servidor autorizado.')
    end
    if version_mayor?(data["version"], Modular3D::VERSION)
      mensaje = "Nueva version disponible: #{data["version"]}\n\nVersion instalada: #{Modular3D::VERSION}\n\n#{data["notes"]}\n\nDeseas abrir la descarga?"
      UI.openURL(descarga.to_s) if UI.messagebox(mensaje, MB_YESNO) == IDYES
    else
      UI.messagebox("Modular_3D ya esta actualizado.\n\nVersion instalada: #{Modular3D::VERSION}")
    end
  rescue Timeout::Error, SocketError, Errno::ECONNREFUSED
    UI.messagebox("No se pudo conectar al servidor de actualizaciones.")
  rescue StandardError => error
    UI.messagebox("No se pudo comprobar la actualizacion: #{error.message}")
  end

end
