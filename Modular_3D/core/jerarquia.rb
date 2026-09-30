# frozen_string_literal: true

module LPenafiel_GeneradorMueblesExacto
  # Varias versiones seguidas (6.4.20 a 6.4.23) implementaron formas distintas
  # de barra de scroll, cada una verificada funcionando en pruebas
  # automatizadas reales, y ninguna llegó a aparecer ni funcionar del lado
  # del usuario -- ni siquiera el espacio vacío que sí quedaba reservado
  # cambiaba de comportamiento entre versiones. Eso, más que cualquier CSS
  # puntual, es la firma clásica de un navegador embebido sirviendo
  # interfaz.css/interfaz.js DESDE CACHÉ pese al "?v=X.X.X" en la URL --
  # el propio interfaz.html sí se recarga fresco en cada versión (el pie de
  # página muestra el número correcto cada vez), pero sus archivos
  # referenciados por separado pueden quedar servidos desde una copia vieja
  # si ese motor no invalida caché de archivos locales (file://) por query
  # string de forma confiable. Esta función reescribe esos "?v=X.X.X" con un
  # valor ÚNICO en cada apertura del diálogo (no solo distinto por versión),
  # así que ninguna entrada de caché previa puede coincidir jamás, sea cual
  # sea el criterio real que use ese caché para decidir si algo sigue
  # vigente. Se guarda como un archivo temporal DENTRO de la misma carpeta
  # ui/ (no en otro lado) para que las rutas relativas a interfaz.css/js seguir
  # resolviendo exactamente igual que si fuera el interfaz.html original.
  def self.ruta_interfaz_sin_cache
    ruta_original = File.expand_path('../ui/interfaz.html', __dir__)
    return ruta_original unless File.exist?(ruta_original)

    contenido = File.read(ruta_original, encoding: 'UTF-8')
    buster = "#{Time.now.to_i}#{format('%03d', Time.now.usec / 1000)}"
    contenido = contenido.gsub(/\?v=[\d.]+/, "?v=#{buster}")

    ruta_temp = File.join(File.dirname(ruta_original), '.interfaz_runtime.html')
    File.write(ruta_temp, contenido, encoding: 'UTF-8')
    ruta_temp
  rescue StandardError
    # Si algo falla al reescribir (permisos de solo lectura, disco lleno,
    # etc.), mejor mostrar el diálogo con el archivo original que no
    # mostrar nada.
    ruta_original
  end

  def self.mostrar_interfaz_moderna(datos_iniciales = nil)
    return unless acceso_autorizado?
    model = Sketchup.active_model

    dialogo = UI::HtmlDialog.new({
      :dialog_title => "#{Modular3D::PRODUCT_NAME} v#{Modular3D::VERSION} | Configurador",
      :preferences_key => Modular3D::PREFERENCES_KEY,
      :scrollable => true,
      :resizable => true,
      :width => 1080,
      :height => 780,
      :style => UI::HtmlDialog::STYLE_WINDOW
    })

    ruta_html_original = File.expand_path('../ui/interfaz.html', __dir__)

    if File.exist?(ruta_html_original)
      dialogo.set_file(ruta_interfaz_sin_cache)
    else
      UI.messagebox("Error crítico: no se encontró el archivo 'interfaz.html'.")
      return
    end

    enviar_estado_licencia = lambda do |estado|
      dialogo.execute_script("window.Modular3DLicense && window.Modular3DLicense.receive(#{JSON.generate(estado)});")
    end

    dialogo.add_action_callback("licenciaEstado") do |_action_context|
      enviar_estado_licencia.call(Modular3D::License.refresh_status)
    end

    dialogo.add_action_callback("licenciaLogin") do |_action_context, email, password, force_transfer|
      enviar_estado_licencia.call(Modular3D::License.login(email, password, force_transfer == true))
    end

    dialogo.add_action_callback("licenciaAceptarTerminos") do |_action_context, email, password, accept, force_transfer|
      enviar_estado_licencia.call(Modular3D::License.accept_terms(email, password, accept == true, force_transfer == true))
    end

    dialogo.add_action_callback("licenciaHeartbeat") do |_action_context|
      enviar_estado_licencia.call(Modular3D::License.heartbeat)
    end

    dialogo.add_action_callback("licenciaLogout") do |_action_context|
      Modular3D::License.logout
      enviar_estado_licencia.call(ok: false, code: "LOGIN_REQUIRED", message: "Sesión cerrada.")
    end

    # --- Parámetros de Diseño (§3) ---
    dialogo.add_action_callback("parametroDisenoGuardar") do |_action_context, datos|
      resultado = Modular3D::ParametrosDiseno.guardar(datos)
      dialogo.execute_script("if (window.Modular3DParametroDisenoResult) { window.Modular3DParametroDisenoResult(#{JSON.generate(resultado)}); }")
    end
    dialogo.add_action_callback("parametroDisenoEliminar") do |_action_context, parametro_id|
      resultado = Modular3D::ParametrosDiseno.eliminar(parametro_id)
      dialogo.execute_script("if (window.Modular3DParametroDisenoResult) { window.Modular3DParametroDisenoResult(#{JSON.generate(resultado)}); }")
    end

    # --- Reglas de Construcción (v6 §Fase C, inspirado en B_06) ---
    dialogo.add_action_callback("reglaConstruccionGuardar") do |_action_context, datos|
      resultado = Modular3D::ReglasConstruccion.guardar(datos)
      dialogo.execute_script("if (window.Modular3DReglaConstruccionResult) { window.Modular3DReglaConstruccionResult(#{JSON.generate(resultado)}); }")
    end
    dialogo.add_action_callback("reglaConstruccionEliminar") do |_action_context, regla_id|
      resultado = Modular3D::ReglasConstruccion.eliminar(regla_id)
      dialogo.execute_script("if (window.Modular3DReglaConstruccionResult) { window.Modular3DReglaConstruccionResult(#{JSON.generate(resultado)}); }")
    end

    # --- Principios de Espacio (§2) ---
    dialogo.add_action_callback("principioGuardar") do |_action_context, nodo, nombre, principio_id_existente|
      resultado = Modular3D::Principios.guardar(nodo, nombre, principio_id_existente)
      dialogo.execute_script("if (window.Modular3DPrincipioResult) { window.Modular3DPrincipioResult(#{JSON.generate(resultado)}); }")
    end
    dialogo.add_action_callback("principioEliminar") do |_action_context, principio_id|
      resultado = Modular3D::Principios.eliminar(principio_id)
      dialogo.execute_script("if (window.Modular3DPrincipioResult) { window.Modular3DPrincipioResult(#{JSON.generate(resultado)}); }")
    end

    # --- Catálogo Global de Tipos de Módulo (ecosistema Modular-3D) ---
    # Llamadas de red reales (Modular3D::Catalogo, ver core/catalogo.rb)
    # disparadas bajo demanda desde la pestaña "5 Catálogo" -- nunca al abrir
    # el diálogo, para no sumarle latencia de red a la apertura del
    # configurador (a diferencia de Perfiles/Principios/Reglas, que son
    # lectura de archivos locales instantánea).
    dialogo.add_action_callback("catalogoCategorias") do |_action_context|
      resultado = Modular3D::Catalogo.categorias
      dialogo.execute_script("if (window.Modular3DCatalogoCategoriasResult) { window.Modular3DCatalogoCategoriasResult(#{JSON.generate(resultado)}); }")
    end
    dialogo.add_action_callback("catalogoListar") do |_action_context, categoria, buscar|
      resultado = Modular3D::Catalogo.listar(categoria: categoria, buscar: buscar)
      dialogo.execute_script("if (window.Modular3DCatalogoListaResult) { window.Modular3DCatalogoListaResult(#{JSON.generate(resultado)}); }")
    end
    dialogo.add_action_callback("catalogoDetalle") do |_action_context, catalogo_id|
      resultado = Modular3D::Catalogo.detalle(catalogo_id)
      dialogo.execute_script("if (window.Modular3DCatalogoDetalleResult) { window.Modular3DCatalogoDetalleResult(#{JSON.generate(resultado)}); }")
    end
    dialogo.add_action_callback("catalogoGuardar") do |_action_context, categoria, nombre, descripcion, datos|
      resultado = Modular3D::Catalogo.guardar(categoria, nombre, descripcion, datos)
      dialogo.execute_script("if (window.Modular3DCatalogoGuardarResult) { window.Modular3DCatalogoGuardarResult(#{JSON.generate(resultado)}); }")
    end

    dialogo.add_action_callback("ejecutarConstruccionMueble") do |_action_context, datos|
      estado_licencia = Modular3D::License.ensure_authorized
      unless estado_licencia[:ok]
        enviar_estado_licencia.call(estado_licencia)
        next
      end

      validacion = Modular3D::Validation.validar(datos)
      unless validacion[:errores].empty?
        UI.messagebox("No se puede construir:\n\n- #{validacion[:errores].join("\n- ")}")
        next
      end

      unless validacion[:avisos].empty?
        respuesta = UI.messagebox(
          "Avisos de Modular_3D:\n\n- #{validacion[:avisos].join("\n- ")}\n\n¿Deseas continuar?",
          MB_YESNO
        )
        next unless respuesta == IDYES
      end

      dialogo.close
      
      modulo_nombre = if datos['__edit_mode'].to_s == "SI"
                        nombre_edicion = datos['modulo_nombre'].to_s.strip.upcase.gsub(" ", "_")
                        nombre_edicion.empty? ? "MODULO" : nombre_edicion
                      else
                        nombre_modulo_unico(datos['modulo_nombre'])
                      end
      @nombre_modulo_guardado = modulo_nombre
      
      ancho_total     = datos['ancho_total'].mm
      alto_total      = datos['alto_total'].mm
      prof_total      = datos['prof_total'].mm
      espesor         = datos['espesor'].mm
      grosor_lat_izq  = (datos['grosor_izq'] || datos['espesor']).to_f.mm
      grosor_lat_der  = (datos['grosor_der'] || datos['espesor']).to_f.mm
      grosor_superior = (datos['grosor_superior'] || datos['espesor']).to_f.mm
      grosor_inferior = (datos['grosor_inferior'] || datos['espesor']).to_f.mm
      montaje_superior = (datos['montaje_superior'] || "INTERIOR").to_s
      montaje_inferior = (datos['montaje_inferior'] || "INTERIOR").to_s
      montaje_izq = (datos['montaje_izq'] || "EXTERIOR").to_s
      montaje_der = (datos['montaje_der'] || "EXTERIOR").to_s
      # Red de seguridad server-side (la UI ya evita esto en vivo): un
      # lateral y un horizontal nunca pueden llegar los dos "de punta a
      # punta" a la misma esquina (EXTERIOR/sobrepuesto, o cualquiera de los
      # INGLETE_*, que tambien llegan al alto total) -- si los dos abrazaran
      # la misma esquina por fuera, ocuparian el mismo espacio o competirian
      # por el mismo corte a 45°. Si llega una combinacion asi (manifiesto
      # viejo, plantilla, etc.), gana el lateral (es el default historico de
      # este plugin) y el horizontal en conflicto se fuerza a montaje
      # interior.
      if montaje_izq != "INTERIOR" || montaje_der != "INTERIOR"
        montaje_superior = "INTERIOR" if montaje_superior == "EXTERIOR"
        montaje_inferior = "INTERIOR" if montaje_inferior == "EXTERIOR"
      end
      # Sobremedida delantera/trasera: delta directo sobre el fondo de ESE
      # panel (positivo = panel mas grande hacia ese lado, negativo = mas
      # chico), igual convencion de signo que la sobremedida por pieza en
      # Materiales. La posicion (retranqueo_frontal_X, usado abajo como
      # coordenada Y de arranque del panel) es el negativo de la sobremedida
      # delantera: crecer hacia el frente desplaza el arranque del panel
      # hacia Y negativo (sobresale), achicarlo lo desplaza hacia Y positivo
      # (se mete hacia adentro).
      sobremedida_frontal_superior = (datos['sobremedida_frontal_superior'] || 0).to_f.mm
      sobremedida_trasera_superior = (datos['sobremedida_trasera_superior'] || 0).to_f.mm
      sobremedida_frontal_inferior = (datos['sobremedida_frontal_inferior'] || 0).to_f.mm
      sobremedida_trasera_inferior = (datos['sobremedida_trasera_inferior'] || 0).to_f.mm
      sobremedida_frontal_izq = (datos['sobremedida_frontal_izq'] || 0).to_f.mm
      sobremedida_trasera_izq = (datos['sobremedida_trasera_izq'] || 0).to_f.mm
      sobremedida_frontal_der = (datos['sobremedida_frontal_der'] || 0).to_f.mm
      sobremedida_trasera_der = (datos['sobremedida_trasera_der'] || 0).to_f.mm
      retranqueo_frontal_superior = 0.mm - sobremedida_frontal_superior
      retranqueo_trasero_superior = 0.mm - sobremedida_trasera_superior
      retranqueo_frontal_inferior = 0.mm - sobremedida_frontal_inferior
      retranqueo_trasero_inferior = 0.mm - sobremedida_trasera_inferior
      retranqueo_frontal_izq = 0.mm - sobremedida_frontal_izq
      retranqueo_trasero_izq = 0.mm - sobremedida_trasera_izq
      retranqueo_frontal_der = 0.mm - sobremedida_frontal_der
      retranqueo_trasero_der = 0.mm - sobremedida_trasera_der
      # v6 §Fase A: la puerta externa solapada nacía siempre en
      # Y = -grosor_puerta, sin enterarse de que un lateral/base/techo vecino
      # podía sobresalir mas hacia adelante por su propia sobremedida frontal
      # -- si esa sobremedida era mayor que el grosor de puerta, la puerta
      # quedaba "embutida" detras del panel que ahora sobresalia mas. Ver
      # calcular_protrusion_puerta mas abajo (linea ~326) y su uso en el bucle
      # de puertas. "puerta_protrusion_override_mm" es la "decision editable"
      # pedida: si tiene un valor, gana sobre cualquier calculo automatico.
      puerta_protrusion_modo = (datos['puerta_protrusion_modo'] || 'AUTOMATICO').to_s.upcase
      puerta_protrusion_override_raw = datos['puerta_protrusion_override_mm'].to_s.strip
      puerta_protrusion_override = puerta_protrusion_override_raw.empty? ? nil : [puerta_protrusion_override_raw.to_f, 0.0].max.mm
      num_repisas     = datos['num_repisas'].to_i
      num_divisiones  = datos['num_divisiones'].to_i
      param_x_expr = datos['param_x_expr'].to_s.strip
      param_z_expr = datos['param_z_expr'].to_s.strip
      param_x_virtual = datos['param_x_type'].to_s.upcase == 'VIRTUAL'
      param_z_virtual = datos['param_z_type'].to_s.upcase == 'VIRTUAL'
      param_x_sizes_mm = param_x_expr.empty? ? nil : resolver_estaciones(param_x_expr, (ancho_total - grosor_lat_izq - grosor_lat_der).to_mm, param_x_virtual ? 0 : espesor.to_mm)
      param_z_sizes_mm = param_z_expr.empty? ? nil : resolver_estaciones(param_z_expr, (alto_total - grosor_superior - grosor_inferior).to_mm, param_z_virtual ? 0 : espesor.to_mm)
      num_divisiones = [param_x_sizes_mm.length - 1, 0].max if param_x_sizes_mm
      num_repisas = [param_z_sizes_mm.length - 1, 0].max if param_z_sizes_mm
      lleva_respaldo  = datos['lleva_respaldo']
      lleva_maletera  = datos['lleva_maletera']
      grosor_resp     = (datos['grosor_resp'] || 6).to_f.mm
      cantidad_ajustes_raw = (datos['cantidad_ajustes'] || "AUTO").to_s.upcase
      alto_ajuste = (datos['alto_ajuste'] || 70).to_f.mm
      grosor_ajuste = (datos['grosor_ajuste'] || datos['espesor'] || 15).to_f.mm
      separacion_ajuste_respaldo = (datos['separacion_ajuste_respaldo'] || 2).to_f.mm
      distancia_plano_posterior = (datos['distancia_plano_posterior'] || 0).to_f.mm
      cajones_raw     = (datos['cajones_por_nicho'] || datos['num_cajones']).to_s
      cajones_por_nicho = cajones_raw.split(/[,\s;|]+/).map { |valor| valor.to_i }
      cajones_por_nicho = [0] if cajones_por_nicho.empty?
      tipos_cajon_raw = (datos['tipos_cajon_por_nicho'] || "").to_s
      tipos_cajon_por_nicho = tipos_cajon_raw.split(/[,\s;|]+/)
      begin
        spaces_config = JSON.parse(datos['spaces_json'].to_s)
        spaces_config = [] unless spaces_config.is_a?(Array)
      rescue JSON::ParserError
        spaces_config = []
      end
      spaces_config = spaces_config.select do |space|
        space.is_a?(Hash) && space['niche'].to_i >= 0 && space['column'].to_i >= 0
      end
      spaces_config_limpio = {}
      contenidos_validos = %w[VACIO REPISAS CAJONERA PUERTA_UNICA PUERTA_DOBLE PUERTA_VIDRIO PUERTA_DOBLE_VIDRIO]
      spaces_config.each do |space|
        contenido = space['content'].to_s.upcase
        contenido = 'VACIO' unless contenidos_validos.include?(contenido)
        niche = [[space['niche'].to_i, 0].max, num_repisas].min
        column = [[space['column'].to_i, 0].max, num_divisiones].min
        limpio = space.merge(
          'niche' => niche,
          'column' => column,
          'content' => contenido,
          'drawers' => [[space['drawers'].to_i, 0].max, 12].min,
          'shelves' => [[space['shelves'].to_i, 0].max, 12].min,
          'front_type' => space['front_type'].to_s.upcase == 'FRENTES' ? 'FRENTES' : 'INTERNO'
        )
        spaces_config_limpio["#{niche}:#{column}"] = limpio
      end
      spaces_config = spaces_config_limpio.values
      begin
        hierarchy_geometry = JSON.parse(datos['hierarchy_geometry_json'].to_s)
        hierarchy_geometry = nil unless hierarchy_geometry.is_a?(Hash) && hierarchy_geometry['nodes'].is_a?(Array)
      rescue JSON::ParserError
        hierarchy_geometry = nil
      end
      # Capturado más abajo, dentro del bucle que construye las puertas
      # reales (hierarchy_geometry['nodes']): el remate reutiliza este mismo
      # valor exacto en vez de recalcular el suyo por separado, para que sea
      # matemáticamente imposible que queden en planos distintos.
      protrusion_puerta_real = nil
      # La jerarquía es la única fuente geométrica. Evita fabricar nuevamente
      # las repisas/divisiones del configurador legado (incluida la repisa media).
      if hierarchy_geometry
        alcance_frentes = (datos['external_front_scope'] || 'BY_SPACE').to_s.upcase
        num_repisas = 0
        num_divisiones = 0
        param_x_sizes_mm = nil
        param_z_sizes_mm = nil
        spaces_config = []
      end
      modo_frentes = (datos['modo_frentes'] || "POR_NICHO").to_s.upcase
      if modo_frentes == "TODOS"
        tipos_cajon_por_nicho = cajones_por_nicho.map { |cantidad| cantidad.to_i > 0 ? "FRENTES" : "INTERNO" }
      elsif modo_frentes == "NINGUNO"
        tipos_cajon_por_nicho = cajones_por_nicho.map { |_cantidad| "INTERNO" }
      end
      num_cajones = if spaces_config.empty?
                       cajones_por_nicho.inject(0) { |suma, valor| suma + valor }
                     else
                       spaces_config.inject(0) do |suma, space|
                         suma + (space['content'].to_s == 'CAJONERA' ? space['drawers'].to_i : 0)
                       end
                     end
      prof_input_cj   = datos['prof_input_cj'].mm
      descuento_madeval = datos['madeval'] == "SI" ? 1.mm : 0.mm
      # crear_puerta es un campo legado (siempre "NO" desde que se quito la
      # pagina vieja de puertas); el indicador real de si el modulo lleva
      # puertas hay que sacarlo de la jerarquia (cualquier nodo con frente
      # distinto de NINGUNO) o de spaces_config, para no mostrar "S/P" en
      # despiece cuando el modulo si tiene puertas.
      tiene_puertas_jerarquia = if hierarchy_geometry
                                  hierarchy_geometry['nodes'].any? { |nodo| nodo.is_a?(Hash) && !%w[NINGUNO].include?(nodo['front'].to_s.upcase) && !nodo['front'].to_s.empty? }
                                else
                                  spaces_config.any? { |space| space['content'].to_s.upcase.start_with?('PUERTA') } || datos['crear_puerta'] == 'SI'
                                end
      @modulo_despiece_actual = nombre_modulo_despiece(modulo_nombre, ancho_total, alto_total, prof_total, num_cajones, tiene_puertas_jerarquia ? 'SI' : 'NO')
      
      actualizar_existente = datos['__edit_mode'].to_s == "SI" && @seleccion_edicion && @offset_edicion
      @offset_creacion = actualizar_existente ? @offset_edicion : offset_siguiente_modulo((datos['tipo_modulo'] || 'PERSONALIZADO').to_s.upcase)
      @datos_modulo_actual = datos.reject { |clave, _valor| clave.to_s.start_with?("__") || clave.to_s == 'view_snapshot' }
      @modulo_uuid_actual = datos['__manifest_uuid'].to_s unless datos['__manifest_uuid'].to_s.empty?
      @modulo_uuid_actual = @datos_modulo_actual['module_uuid'].to_s if @modulo_uuid_actual.to_s.empty? && !@datos_modulo_actual['module_uuid'].to_s.empty?
      @modulo_uuid_actual = SecureRandom.uuid if @modulo_uuid_actual.to_s.empty?
      @datos_modulo_actual['module_uuid'] = @modulo_uuid_actual
      # Montaje "Inglete" (arriba o abajo, no los dos a la vez todavia -- un
      # lateral solo puede tener un corte a 45° por llamada a crear_pieza) en
      # LAT_IZQ/LAT_DER: aplica automaticamente el mismo corte que ya existia
      # como ajuste manual por pieza (miter_overrides_json), sin pisar un
      # override que el usuario ya haya puesto a mano para esa pieza puntual.
      #
      # v6.0.1 -- bug real encontrado y corregido: la version anterior de
      # este bloque (y su gemelo por nodo, mas abajo) SOLO agregaba un
      # override cuando el montaje ERA Inglete, pero nunca lo sacaba cuando
      # el usuario volvia a elegir Interior/Sobrepuesto -- ese override
      # "automatico" viejo se quedaba pegado para siempre en el manifiesto y
      # seguia biselando esa pieza a 45°, aunque el desplegable ya dijera
      # otra cosa. Cada entrada automatica ahora se marca con 'auto' => true
      # para poder distinguirla de un ajuste manual real (Materiales > pieza
      # individual, que nunca pone esa marca) y borrarla cuando corresponda,
      # sin tocar nunca un ajuste manual del usuario.
      miter_overrides_auto = begin
        raw_miter = @datos_modulo_actual['miter_overrides_json']
        parseado = raw_miter.is_a?(Hash) ? raw_miter : JSON.parse(raw_miter.to_s)
        parseado.is_a?(Hash) ? parseado : {}
      rescue JSON::ParserError
        {}
      end
      gestionar_inglete_auto = lambda do |overrides_hash, nombre_pieza, montaje_pieza|
        existente = overrides_hash[nombre_pieza]
        fue_automatico = existente.is_a?(Hash) && existente['auto'] == true
        esquina_auto = case montaje_pieza
                        when 'INGLETE_SUPERIOR' then 'top_outer'
                        when 'INGLETE_INFERIOR' then 'bottom_outer'
                        end
        if esquina_auto
          overrides_hash[nombre_pieza] = { 'corner' => esquina_auto, 'size' => espesor.to_mm, 'auto' => true } unless existente.is_a?(Hash) && !fue_automatico
        elsif fue_automatico
          overrides_hash.delete(nombre_pieza)
        end
      end
      { 'LAT_IZQ' => montaje_izq, 'LAT_DER' => montaje_der }.each do |nombre_lateral, montaje_lateral|
        gestionar_inglete_auto.call(miter_overrides_auto, nombre_lateral, montaje_lateral)
      end
      @datos_modulo_actual['miter_overrides_json'] = JSON.generate(miter_overrides_auto)
      @datos_modulo_actual['module_base_offset'] = [
        @offset_creacion.x.to_mm, @offset_creacion.y.to_mm, @offset_creacion.z.to_mm
      ]
      @piezas_modulo_actual = []

      operacion_iniciada = false
      begin
      model.start_operation("Generar Mueble", true)
      operacion_iniciada = true
      entities = model.active_entities
      if actualizar_existente
        @seleccion_edicion.each { |entity| entity.erase! if entity && entity.respond_to?(:valid?) && entity.valid? }
        @seleccion_edicion = nil
      end
      ancho_interno = ancho_total - grosor_lat_izq - grosor_lat_der
      ancho_util_mueble = ancho_interno - descuento_madeval
      alto_interno  = alto_total - grosor_superior - grosor_inferior
      zonas_frentes_cajon = []

      # Zócalo: si el módulo lo lleva (Bajo/Auxiliar/Closet), TODO el casco
      # que se construye de aquí en adelante (laterales, base, techo,
      # interior, ajustes, respaldo, puertas, cajones) se levanta
      # zocalo_alto para quedar apoyado ENCIMA del zócalo -- que ocupa el
      # piso real (z=0..zocalo_alto) y así nunca se superpone con la base
      # del casco, que antes también nacía en z=0. offset_creacion_base
      # guarda el offset ORIGINAL (antes de este levante) para restaurarlo
      # justo antes de construir zócalo/premesón/cornisa/remates, al final
      # del método -- esas piezas van relativas al piso/tope real, no al
      # casco ya levantado.
      zocalo_alto = 126.mm
      tipo_modulo = (datos['tipo_modulo'] || 'PERSONALIZADO').to_s.upcase
      # zocalo_activo/premeson_activo son checks manuales (visor 3D, junto a
      # "Abierto"): por defecto SI para no romper modulos guardados antes de
      # que existiera este check (ausente = comportamiento historico, que
      # siempre llevaba zocalo/premeson en estos tipos de modulo).
      lleva_zocalo = %w[BAJO AUXILIAR CLOSET].include?(tipo_modulo) && datos['zocalo_activo'].to_s != 'NO'
      alto_carcasa_offset = lleva_zocalo ? zocalo_alto : 0.mm
      # Los módulos del sistema de cocina (Bajo/Auxiliar/Closet/Alto) van
      # siempre con su fondo (cara trasera) a una profundidad fija de
      # Y=600mm desde la pared, sea cual sea su propia profundidad o si
      # llevan puerta -- así todos los módulos del mismo tipo quedan
      # alineados contra la misma pared y los Altos quedan a ras con los
      # Bajos de abajo. Los Altos además van a una altura de piso fija
      # (Z=1500mm). Pedido explícito del usuario: esta regla REEMPLAZA (no
      # convive con) el alineado anterior que perseguía dejar la
      # puerta/remate exactos en Y=0 según su grosor -- ese alineado por
      # grosor sigue vigente solo para módulos fuera de este sistema
      # (Personalizado), que no tienen posición de pared fija.
      tipos_layout_cocina = CAPA_PISO_COCINA + ['ALTO']
      if tipos_layout_cocina.include?(tipo_modulo)
        fondo_fijo_modulo = 600.mm
        offset_y_modulo = fondo_fijo_modulo - prof_total
        altura_piso_modulo = tipo_modulo == 'ALTO' ? 1500.mm : 0.mm
      else
        hay_puerta_externa_solapada = false
        if hierarchy_geometry && (datos['montaje_puerta'] || 'SOLAPADA').to_s.upcase != 'EMBUTIDA'
          hierarchy_geometry['nodes'].each do |nodo_chequeo|
            next unless nodo_chequeo.is_a?(Hash)
            frente_chequeo = nodo_chequeo['front'].to_s.upcase
            frente_chequeo = 'PUERTA_UNICA' if nodo_chequeo['content'].to_s.upcase == 'CAJONES_PUERTA' && frente_chequeo == 'NINGUNO'
            next if frente_chequeo.empty? || frente_chequeo == 'NINGUNO' || frente_chequeo.include?('INTERNA')
            hay_puerta_externa_solapada = true
            break
          end
        end
        grosor_puerta_offset = [(datos['puerta_grosor'] || espesor.to_mm).to_f, 3.0].max.mm
        offset_y_modulo = hay_puerta_externa_solapada ? [espesor, grosor_puerta_offset].max : espesor
        altura_piso_modulo = 0.mm
      end
      offset_creacion_base = (@offset_creacion || Geom::Vector3d.new(0, 0, 0)) + Geom::Vector3d.new(0, offset_y_modulo, altura_piso_modulo)
      @offset_creacion = offset_creacion_base + Geom::Vector3d.new(0, 0, alto_carcasa_offset)

      lat_l = 1
      lat_c = prof_total > 340.mm ? 0 : 1
      if ancho_util_mueble >= prof_total
        hz_l = 1; hz_c = 0
      else
        hz_l = 0; hz_c = 1
      end
      
      # Casco activable: cada panel exterior puede omitirse (p. ej. módulo contra
      # pared o abierto) sin alterar la cavidad interior ni la posición del resto
      # de piezas, que siguen usando el mismo grosor como referencia de encaje.
      existe_lat_izq = (datos['lleva_lateral_izq'] || 'SI').to_s != 'NO'
      existe_lat_der = (datos['lleva_lateral_der'] || 'SI').to_s != 'NO'
      existe_base    = (datos['lleva_base'] || 'SI').to_s != 'NO'
      existe_techo   = (datos['lleva_techo'] || 'SI').to_s != 'NO'

      prof_lat_izq = prof_total - retranqueo_frontal_izq - retranqueo_trasero_izq
      prof_lat_der = prof_total - retranqueo_frontal_der - retranqueo_trasero_der
      alto_lat_izq = montaje_izq == "INTERIOR" ? alto_interno : alto_total
      alto_lat_der = montaje_der == "INTERIOR" ? alto_interno : alto_total
      z_lat_izq = montaje_izq == "INTERIOR" ? grosor_inferior : 0.mm
      z_lat_der = montaje_der == "INTERIOR" ? grosor_inferior : 0.mm
      self.crear_pieza(entities, modulo_nombre, "LAT_IZQ", grosor_lat_izq, prof_lat_izq, alto_lat_izq, 0, retranqueo_frontal_izq, z_lat_izq, lat_l, lat_c) if existe_lat_izq
      x_lat_der = ancho_total - grosor_lat_der
      self.crear_pieza(entities, modulo_nombre, "LAT_DER", grosor_lat_der, prof_lat_der, alto_lat_der, x_lat_der, retranqueo_frontal_der, z_lat_der, lat_l, lat_c) if existe_lat_der

      # v6 §Fase B: "2 travesaños" tambien como alternativa al panel
      # completo en BASE/TECHO del casco general, simetrico con lo que ya
      # existia por espacio (h_top_mode). No aplica sobremedida a los
      # travesaños (son listones angostos, no un panel) -- mismo criterio
      # que ya usa la version por nodo mas abajo.
      base_modo_general = (datos['tipo_inferior'] || 'FULL').to_s.upcase
      techo_modo_general = (datos['tipo_superior'] || 'FULL').to_s.upcase

      ancho_base = montaje_inferior == "EXTERIOR" ? ancho_total : ancho_util_mueble
      x_base = montaje_inferior == "EXTERIOR" ? 0.mm : grosor_lat_izq
      prof_base = prof_total - retranqueo_frontal_inferior - retranqueo_trasero_inferior
      if existe_base
        if base_modo_general == 'TRAVESANOS'
          ancho_trav_base = [(datos['travesano_ancho_inferior'] || 70).to_f, 20.0].max.mm
          self.crear_pieza(entities, modulo_nombre, "BASE_TRAV_DEL", ancho_base, ancho_trav_base, grosor_inferior, x_base, 0.mm, 0, hz_l, hz_c)
          self.crear_pieza(entities, modulo_nombre, "BASE_TRAV_TRAS", ancho_base, ancho_trav_base, grosor_inferior, x_base, prof_total - ancho_trav_base, 0, hz_l, hz_c)
        else
          self.crear_pieza(entities, modulo_nombre, "BASE", ancho_base, prof_base, grosor_inferior, x_base, retranqueo_frontal_inferior, 0, hz_l, hz_c)
        end
      end

      ancho_techo = montaje_superior == "EXTERIOR" ? ancho_total : ancho_util_mueble
      x_techo = montaje_superior == "EXTERIOR" ? 0.mm : grosor_lat_izq
      prof_techo = prof_total - retranqueo_frontal_superior - retranqueo_trasero_superior
      z_techo = alto_total - grosor_superior
      if existe_techo
        if techo_modo_general == 'TRAVESANOS'
          ancho_trav_techo = [(datos['travesano_ancho_superior'] || 70).to_f, 20.0].max.mm
          self.crear_pieza(entities, modulo_nombre, "TECHO_TRAV_DEL", ancho_techo, ancho_trav_techo, grosor_superior, x_techo, 0.mm, z_techo, hz_l, hz_c)
          self.crear_pieza(entities, modulo_nombre, "TECHO_TRAV_TRAS", ancho_techo, ancho_trav_techo, grosor_superior, x_techo, prof_total - ancho_trav_techo, z_techo, hz_l, hz_c)
        else
          self.crear_pieza(entities, modulo_nombre, "TECHO", ancho_techo, prof_techo, grosor_superior, x_techo, retranqueo_frontal_superior, z_techo, hz_l, hz_c)
        end
      end

      # v6 §Fase A -- ver comentario junto a "puerta_protrusion_override" mas
      # arriba. Por puerta: la protrusion efectiva es la mayor entre el
      # grosor de puerta (piso de siempre) y la sobremedida frontal de cada
      # panel -- global de casco o propio del espacio -- que esa puerta
      # realmente toca (se detecta por coincidencia de coordenadas, mismo
      # criterio de "eps" que ya usa facadeBox en JS). Si hay un override
      # manual, ese gana siempre y no hace falta calcular nada.
      calcular_protrusion_puerta = lambda do |cav_x_min, cav_x_max, cav_z_min, cav_z_max, enc_nodo, sob_nodo, grosor_puerta_local|
        next puerta_protrusion_override if puerta_protrusion_override
        eps = 0.5.mm
        candidatos = [grosor_puerta_local]
        candidatos << sobremedida_frontal_izq if existe_lat_izq && (cav_x_min - grosor_lat_izq).abs <= eps
        candidatos << sobremedida_frontal_der if existe_lat_der && (cav_x_max - (ancho_total - grosor_lat_der)).abs <= eps
        candidatos << sobremedida_frontal_inferior if existe_base && base_modo_general != 'TRAVESANOS' && (cav_z_min - grosor_inferior).abs <= eps
        candidatos << sobremedida_frontal_superior if existe_techo && techo_modo_general != 'TRAVESANOS' && (cav_z_max - (alto_total - grosor_superior)).abs <= eps
        if enc_nodo.is_a?(Hash)
          sob_nodo = {} unless sob_nodo.is_a?(Hash)
          candidatos << (sob_nodo['frontalIzq'] || 0).to_f.mm if enc_nodo['left']
          candidatos << (sob_nodo['frontalDer'] || 0).to_f.mm if enc_nodo['right']
          candidatos << (sob_nodo['frontalInferior'] || 0).to_f.mm if enc_nodo['bottom']
          candidatos << (sob_nodo['frontalSuperior'] || 0).to_f.mm if enc_nodo['top'] && enc_nodo['topMode'].to_s.upcase != 'TRAVESANOS'
        end
        candidatos.max
      end

      # Zócalo/premesón/cornisa/remates: ver bloque al final del método,
      # justo antes de armar el manifiesto. Se construyen ahí (no aquí)
      # porque deben quedar relativos al piso/tope REAL del módulo, después
      # de restaurar @offset_creacion al valor original sin el levante del
      # casco (ver comentario junto a "alto_carcasa_offset" más arriba).

      respaldo_estructural = grosor_resp >= 15.mm
      cantidad_ajustes = 0
      # "SOLO_AJUSTES": sin panel de respaldo pero con ajustes igual -- se
      # ignora respaldo_estructural en ese modo porque no hay panel cuyo
      # grosor evaluar.
      if lleva_respaldo == "SOLO_AJUSTES" || (lleva_respaldo != "NO" && !respaldo_estructural)
        cantidad_ajustes = cantidad_ajustes_raw == "AUTO" ? (alto_total > 760.mm ? 2 : 1) : cantidad_ajustes_raw.to_i
        cantidad_ajustes = [[cantidad_ajustes, 0].max, 4].min
      end
      # Secuencia posterior única (desde atrás hacia el frente):
      # distancia posterior -> ajuste -> separación -> respaldo -> espacio útil.
      y_ajuste = prof_total - distancia_plano_posterior - grosor_ajuste
      z_superior_ajuste = alto_total - grosor_superior - alto_ajuste

      # Un ajuste "vertical" no es un rail corrido de lateral a lateral, sino un
      # par de escuadras (una por esquina) que corren en profundidad, apoyadas
      # bajo el techo. Reutiliza grosor_ajuste/alto_ajuste como su sección y su
      # alcance hacia el frente, para no añadir campos nuevos al formulario.
      crear_escuadras_ajuste = lambda do |prefijo, y_inicio|
        self.crear_pieza(entities, modulo_nombre, "#{prefijo}_ESCUADRA_IZQ", grosor_ajuste, alto_ajuste, grosor_ajuste, grosor_lat_izq, y_inicio, z_superior_ajuste, 0, 0)
        self.crear_pieza(entities, modulo_nombre, "#{prefijo}_ESCUADRA_DER", grosor_ajuste, alto_ajuste, grosor_ajuste, ancho_total - grosor_lat_der - grosor_ajuste, y_inicio, z_superior_ajuste, 0, 0)
      end

      if cantidad_ajustes > 0
        orientacion_posterior = (datos['ajuste_posterior_orientacion'] || 'HORIZONTAL').to_s.upcase
        if orientacion_posterior == 'VERTICAL'
          crear_escuadras_ajuste.call("AJUSTE_POSTERIOR", y_ajuste)
        else
          self.crear_pieza(entities, modulo_nombre, "AJUSTE_SUPERIOR", ancho_util_mueble, grosor_ajuste, alto_ajuste, grosor_lat_izq, y_ajuste, z_superior_ajuste, 1, 0)
        end
        if cantidad_ajustes > 1
          (2..cantidad_ajustes).each do |idx|
            espacio_posterior = alto_total - grosor_superior - grosor_inferior - alto_ajuste
            fraccion = idx == 2 ? 0.5 : (cantidad_ajustes - idx + 1).to_f / cantidad_ajustes
            z_ajuste = grosor_inferior + (espacio_posterior * fraccion) - (alto_ajuste / 2)
            z_min_ajuste = grosor_inferior
            z_max_ajuste = z_superior_ajuste - alto_ajuste
            z_ajuste = z_min_ajuste if z_ajuste < z_min_ajuste
            z_ajuste = z_max_ajuste if z_ajuste > z_max_ajuste
            self.crear_pieza(entities, modulo_nombre, "AJUSTE_POSTERIOR_#{idx - 1}", ancho_util_mueble, grosor_ajuste, alto_ajuste, grosor_lat_izq, y_ajuste, z_ajuste, 1, 0)
          end
        end
      end

      # Ajuste frontal: independiente del posterior, apoyado en el plano frontal
      # (y=0) para dar escuadra al frente. Desactivado por defecto para no
      # alterar módulos ya guardados.
      if (datos['ajuste_frontal_activo'] || 'NO').to_s == 'SI'
        orientacion_frontal = (datos['ajuste_frontal_orientacion'] || 'HORIZONTAL').to_s.upcase
        if orientacion_frontal == 'VERTICAL'
          crear_escuadras_ajuste.call("AJUSTE_FRONTAL", 0.mm)
        else
          self.crear_pieza(entities, modulo_nombre, "AJUSTE_FRONTAL", ancho_util_mueble, grosor_ajuste, alto_ajuste, grosor_lat_izq, 0.mm, z_superior_ajuste, 1, 0)
        end
      end
      
      if lleva_respaldo == "SI"
        profundidad_ranura = (datos['profundidad_ranura'] || 5).to_f.mm
        ancho_respaldo = ancho_interno + (profundidad_ranura * 2)
        alto_respaldo  = alto_interno + (profundidad_ranura * 2)
        espacio_libre_atras = respaldo_estructural ? (distancia_plano_posterior + grosor_resp) : (distancia_plano_posterior + grosor_ajuste + separacion_ajuste_respaldo + grosor_resp)
        y_respaldo = prof_total - espacio_libre_atras
        x_respaldo = grosor_lat_izq - profundidad_ranura
        z_respaldo = grosor_inferior - profundidad_ranura
        self.crear_pieza(entities, modulo_nombre, "RESPALDO", ancho_respaldo, grosor_resp, alto_respaldo, x_respaldo, y_respaldo, z_respaldo, 0, 0)
      elsif lleva_respaldo == "INTERNO"
        ancho_respaldo = ancho_interno
        alto_respaldo = alto_interno
        y_respaldo = if respaldo_estructural
                       prof_total - distancia_plano_posterior - grosor_resp
                     else
                       y_ajuste - separacion_ajuste_respaldo - grosor_resp
                     end
        x_respaldo = grosor_lat_izq
        z_respaldo = grosor_inferior
        self.crear_pieza(entities, modulo_nombre, "RESPALDO_INTERNO", ancho_respaldo, grosor_resp, alto_respaldo, x_respaldo, y_respaldo, z_respaldo, 0, 0)
      elsif lleva_respaldo == "SOBREPUESTO"
        holgura = 1.5.mm
        ancho_respaldo = ancho_total - (holgura * 2)
        alto_respaldo = alto_total - (holgura * 2)
        y_respaldo = prof_total - distancia_plano_posterior - grosor_resp
        x_respaldo = holgura
        z_respaldo = holgura
        self.crear_pieza(entities, modulo_nombre, "RESPALDO_SOBREPUESTO", ancho_respaldo, grosor_resp, alto_respaldo, x_respaldo, y_respaldo, z_respaldo, 0, 0)
      end
      
      retranqueo_interior = (datos['retranqueo_interior'] || 38).to_f.mm
      prof_division_descontada = prof_total - retranqueo_interior
  
      if num_divisiones > 0 && !param_x_virtual
        if param_x_sizes_mm
          cursor_x = grosor_lat_izq
          param_x_sizes_mm[0...-1].each_with_index do |size_mm, index|
            cursor_x += size_mm.mm
            self.crear_pieza(entities, modulo_nombre, "DIV_VERT_#{index + 1}", espesor, prof_division_descontada, alto_interno, cursor_x, 0.mm, grosor_inferior, 1, 1)
            cursor_x += espesor
          end
        else
          espacio_neto_divisiones = ancho_interno - (num_divisiones * espesor)
          distancia_entre_divisiones = espacio_neto_divisiones / (num_divisiones + 1)
          (1..num_divisiones).each do |k|
            x_division = grosor_lat_izq + (k * distancia_entre_divisiones) + ((k - 1) * espesor)
            self.crear_pieza(entities, modulo_nombre, "DIV_VERT_#{k}", espesor, prof_division_descontada, alto_interno, x_division, 0.mm, grosor_inferior, 1, 1)
          end
        end
      end

      posiciones_repisas = []
      z_limite_repisas = z_techo
      prof_repisa_descontada = prof_total - retranqueo_interior
      if ancho_util_mueble >= prof_repisa_descontada
        rep_l = 1; rep_c = 0
      else
        rep_l = 0; rep_c = 1
      end

      if lleva_maletera == "SI"
        altura_interna_maletera = 300.mm
        z_maletera = z_techo - espesor - altura_interna_maletera
        if z_maletera > grosor_inferior
          mal_l = ancho_util_mueble >= prof_repisa_descontada ? 1 : 0
          mal_c = ancho_util_mueble >= prof_repisa_descontada ? 0 : 1
          self.crear_pieza(entities, modulo_nombre, "REPISA_MALETERA", ancho_util_mueble, prof_repisa_descontada, espesor, grosor_lat_izq, 0, z_maletera, mal_l, mal_c)
          z_limite_repisas = z_maletera - espesor
        end
      end
      
      if num_repisas > 0 && !param_z_virtual
        if param_z_sizes_mm
          cursor_z = grosor_inferior
          param_z_sizes_mm[0...-1].each_with_index do |size_mm, index|
            cursor_z += size_mm.mm
            self.crear_pieza(entities, modulo_nombre, "REPISA_#{index + 1}", ancho_util_mueble, prof_repisa_descontada, espesor, grosor_lat_izq, 0, cursor_z, rep_l, rep_c)
            posiciones_repisas << cursor_z
            cursor_z += espesor
          end
        else
          alto_util_repisas = z_limite_repisas - grosor_inferior
          espacio_neto_huecos = alto_util_repisas - (num_repisas * espesor)
          distancia_entre_repisas = espacio_neto_huecos / (num_repisas + 1)
          (1..num_repisas).each do |i|
            z_repisa = grosor_inferior + (i * distancia_entre_repisas) + ((i - 1) * espesor)
            self.crear_pieza(entities, modulo_nombre, "REPISA_#{i}", ancho_util_mueble, prof_repisa_descontada, espesor, grosor_lat_izq, 0, z_repisa, rep_l, rep_c)
            posiciones_repisas << z_repisa
          end
        end
      elsif param_z_sizes_mm
        # En división virtual conservamos límites lógicos sin fabricar repisas.
        cursor_z = grosor_inferior
        param_z_sizes_mm[0...-1].each do |size_mm|
          cursor_z += size_mm.mm
          posiciones_repisas << cursor_z
        end
      end

      # Motor jerárquico: usa las mismas cajas exactas calculadas por el plano 2D y MODULAR-3D VIEW.
      if hierarchy_geometry
        separadores_por_padre = Hash.new(0)
        (hierarchy_geometry['separators'] || []).each do |separator|
          next unless separator.is_a?(Hash)
          axis = separator['axis'].to_s.upcase
          ancho = separator['w'].to_f.mm
          fondo = separator['d'].to_f.mm
          alto = separator['h'].to_f.mm
          next if ancho <= 0 || fondo <= 0 || alto <= 0
          padre_id = id_pieza_jerarquia(separator['parent'], 'ROOT')
          separadores_por_padre[padre_id] += 1
          sufijo = "#{padre_id}_#{separadores_por_padre[padre_id]}"
          codigo = axis == 'X' ? "H_DIV_X_#{sufijo}" : (axis == 'Z' ? "H_REP_Z_#{sufijo}" : "H_DIV_Y_#{sufijo}")
          self.crear_pieza(entities, modulo_nombre, codigo, ancho, fondo, alto,
            separator['x'].to_f.mm, separator['y'].to_f.mm, separator['z'].to_f.mm, 1, 1)
        end

        # v6 §Fase B: montaje interior/sobrepuesto (+ inglete 45°) por panel
        # de espacio, generalizando el mismo control que el casco general ya
        # tenia (montaje_izq/der/superior/inferior, lineas ~110-135) a cada
        # nodo de la jerarquia. Los overrides de inglete se inyectan aqui,
        # por nodo, en @datos_modulo_actual['miter_overrides_json'] --
        # inglete_pieza() (core/geometria.rb) lo relee en cada crear_pieza,
        # asi que alcanza con actualizarlo antes de construir la pieza que
        # corresponda.
        miter_overrides_nodo = begin
          raw_miter_nodo = @datos_modulo_actual['miter_overrides_json']
          parseado_nodo = raw_miter_nodo.is_a?(Hash) ? raw_miter_nodo : JSON.parse(raw_miter_nodo.to_s)
          parseado_nodo.is_a?(Hash) ? parseado_nodo : {}
        rescue JSON::ParserError
          {}
        end
        hierarchy_geometry['nodes'].each_with_index do |node, node_index|
          next unless node.is_a?(Hash) && node['box'].is_a?(Hash) && node['enclosure'].is_a?(Hash)
          box = node['box']; enc = node['enclosure']; x = box['x'].to_f.mm; y = box['y'].to_f.mm; z = box['z'].to_f.mm
          w = box['w'].to_f.mm; d = box['d'].to_f.mm; h = box['h'].to_f.mm
          nid = id_pieza_jerarquia(node['id'], "IDX#{node_index + 1}")
          # Sobremedida por nodo: mismo mecanismo que la sobremedida del
          # casco general (retranqueo = 0.mm - sobremedida), pero aplicado
          # panel por panel dentro de este espacio de la jerarquia. Un valor
          # positivo hace que ese panel sobresalga hacia adelante/atras;
          # negativo lo retranquea. Solo afecta cierres laterales, base y
          # techo (modo completo) -- travesanos y respaldo quedan fuera.
          sob = node['sobremedida'].is_a?(Hash) ? node['sobremedida'] : {}
          ret_frontal_de = lambda { |clave| 0.mm - (sob["frontal#{clave}"] || 0).to_f.mm }
          ret_trasera_de = lambda { |clave| 0.mm - (sob["trasera#{clave}"] || 0).to_f.mm }
          mount_izq_nodo = (enc['leftMount'] || 'EXTERIOR').to_s.upcase
          mount_der_nodo = (enc['rightMount'] || 'EXTERIOR').to_s.upcase
          mount_inf_nodo = (enc['bottomMount'] || 'INTERIOR').to_s.upcase
          mount_sup_nodo = (enc['topMount'] || 'INTERIOR').to_s.upcase
          # Misma regla de conflicto de esquina que el casco general: un
          # lateral que llega de punta a punta (EXTERIOR o INGLETE_*) no
          # puede competir por la misma esquina con un horizontal que
          # tambien llegue de punta a punta -- gana el lateral.
          if mount_izq_nodo != 'INTERIOR' || mount_der_nodo != 'INTERIOR'
            mount_inf_nodo = 'INTERIOR' if mount_inf_nodo == 'EXTERIOR'
            mount_sup_nodo = 'INTERIOR' if mount_sup_nodo == 'EXTERIOR'
          end
          if enc['left']
            rf = ret_frontal_de.call('Izq'); rt = ret_trasera_de.call('Izq')
            nombre_izq_nodo = "H_CIERRE_IZQ_#{nid}"
            gestionar_inglete_auto.call(miter_overrides_nodo, nombre_izq_nodo, mount_izq_nodo)
            @datos_modulo_actual['miter_overrides_json'] = JSON.generate(miter_overrides_nodo)
            alto_izq_nodo = mount_izq_nodo == 'INTERIOR' ? (h - (enc['bottom'] ? espesor : 0.mm) - (enc['top'] ? espesor : 0.mm)) : h
            z_izq_nodo = mount_izq_nodo == 'INTERIOR' && enc['bottom'] ? z + espesor : z
            self.crear_pieza(entities, modulo_nombre, nombre_izq_nodo, espesor, d - rf - rt, alto_izq_nodo, x, y + rf, z_izq_nodo, 1, 1)
          end
          if enc['right']
            rf = ret_frontal_de.call('Der'); rt = ret_trasera_de.call('Der')
            nombre_der_nodo = "H_CIERRE_DER_#{nid}"
            gestionar_inglete_auto.call(miter_overrides_nodo, nombre_der_nodo, mount_der_nodo)
            @datos_modulo_actual['miter_overrides_json'] = JSON.generate(miter_overrides_nodo)
            alto_der_nodo = mount_der_nodo == 'INTERIOR' ? (h - (enc['bottom'] ? espesor : 0.mm) - (enc['top'] ? espesor : 0.mm)) : h
            z_der_nodo = mount_der_nodo == 'INTERIOR' && enc['bottom'] ? z + espesor : z
            self.crear_pieza(entities, modulo_nombre, nombre_der_nodo, espesor, d - rf - rt, alto_der_nodo, x + w - espesor, y + rf, z_der_nodo, 1, 1)
          end
          if enc['bottom']
            rf = ret_frontal_de.call('Inferior'); rt = ret_trasera_de.call('Inferior')
            ancho_base_nodo = mount_inf_nodo == 'INTERIOR' ? (w - (enc['left'] ? espesor : 0.mm) - (enc['right'] ? espesor : 0.mm)) : w
            x_base_nodo = mount_inf_nodo == 'INTERIOR' && enc['left'] ? x + espesor : x
            self.crear_pieza(entities, modulo_nombre, "H_BASE_#{nid}", ancho_base_nodo, d - rf - rt, espesor, x_base_nodo, y + rf, z, 1, 0)
          end
          if enc['top']
            ancho_top_nodo = mount_sup_nodo == 'INTERIOR' ? (w - (enc['left'] ? espesor : 0.mm) - (enc['right'] ? espesor : 0.mm)) : w
            x_top_nodo = mount_sup_nodo == 'INTERIOR' && enc['left'] ? x + espesor : x
            if enc['topMode'].to_s.upcase == 'TRAVESANOS'
              # Cierre superior alternativo: 2 travesaños (adelante y atras) en
              # vez de un techo completo -- ahorra material cuando no hace
              # falta un panel entero encima (p. ej. debajo de una encimera).
              # No aplica sobremedida: son listones angostos, no un panel.
              # Si respeta el montaje interior/sobrepuesto en su ancho (igual
              # que la base/techo completo).
              ancho_trav = [(enc['topTravesano'] || 70).to_f, 20.0].max.mm
              self.crear_pieza(entities, modulo_nombre, "H_TRAV_DEL_#{nid}", ancho_top_nodo, ancho_trav, espesor, x_top_nodo, y, z + h - espesor, 1, 0)
              self.crear_pieza(entities, modulo_nombre, "H_TRAV_TRAS_#{nid}", ancho_top_nodo, ancho_trav, espesor, x_top_nodo, y + d - ancho_trav, z + h - espesor, 1, 0)
            else
              rf = ret_frontal_de.call('Superior'); rt = ret_trasera_de.call('Superior')
              self.crear_pieza(entities, modulo_nombre, "H_TECHO_#{nid}", ancho_top_nodo, d - rf - rt, espesor, x_top_nodo, y + rf, z + h - espesor, 1, 0)
            end
          end
          self.crear_pieza(entities, modulo_nombre, "H_RESP_#{nid}", w, grosor_resp, h, x, y + d - grosor_resp, z, 0, 0) if enc['back']
        end

        leaf_nodes = hierarchy_geometry['nodes'].select { |node| node.is_a?(Hash) && (!node['children'].is_a?(Array) || node['children'].empty?) }
        leaf_nodes.each_with_index do |node, node_index|
          box = node['box'] || {}
          x_min = box['x'].to_f.mm; y_min = box['y'].to_f.mm; z_min = box['z'].to_f.mm
          ancho_nodo = box['w'].to_f.mm; fondo_nodo = box['d'].to_f.mm; alto_nodo = box['h'].to_f.mm
          next if ancho_nodo <= 0 || fondo_nodo <= 0 || alto_nodo <= 0
          nid = id_pieza_jerarquia(node['id'], "IDX#{node_index + 1}")
          contenido = node['content'].to_s.upcase
          # Si este mismo espacio tiene puerta interna, esta ocupa su propio
          # grosor pegada al frente (ver mas abajo, y_puerta = box.y + 2mm):
          # una repisa que llegara al ras del frente (y_min) chocaria contra
          # ese panel. Se recorta la repisa por ese mismo grosor, dejandola
          # empezar justo donde termina la puerta -- nunca se entrelazan.
          tiene_puerta_interna_local = node['front'].to_s.upcase.include?('INTERNA')
          grosor_puerta_local = tiene_puerta_interna_local ? [(datos['puerta_grosor'] || espesor.to_mm).to_f, 3.0].max.mm : 0.mm
          if contenido == 'REPISAS'
            cantidad = [[node['shelves'].to_i, 1].max, 20].min
            distancia = (alto_nodo - (cantidad * espesor)) / (cantidad + 1)
            fondo_repisa = fondo_nodo - grosor_puerta_local
            y_repisa = y_min + grosor_puerta_local
            if fondo_repisa > 0.mm
              (1..cantidad).each do |ri|
                z_rep = z_min + (ri * distancia) + ((ri - 1) * espesor)
                self.crear_pieza(entities, modulo_nombre, "H_REP_LOCAL_#{nid}_#{ri}", ancho_nodo, fondo_repisa, espesor, x_min, y_repisa, z_rep, 1, 0)
              end
            end
          end
          if contenido.start_with?('CAJONES')
            # Frente de este espacio de cajones: independiente de "Puerta del
            # espacio" (esa sigue siendo la puerta con bisagra de verdad).
            # - POR_CAJON (por defecto): un frente por cada cajon, como hasta
            #   ahora.
            # - UNICO_INFERIOR: un solo frente que cubre TODA la pila de
            #   cajones, atornillado siempre al cajon mas bajo -- los demas
            #   cajones de esa columna se abren igual de independientes con
            #   la mano de Interactuar, pero sin frente propio (quedan ocultos
            #   detras del frente unico mientras estan cerrados).
            # - FALSO: un panel fijo (sin Dynamic Component) que cubre todo el
            #   espacio; no se crea ningun cajon real detras.
            sin_puerta_propia = node['front'].to_s.empty? || node['front'].to_s.upcase == 'NINGUNO'
            frente_cajon_activo = contenido == 'CAJONES_FRENTES' && alcance_frentes != 'GLOBAL' && sin_puerta_propia
            # Tiradera (jalador) por espacio de cajones: por defecto SI solo en
            # "Cajones con frentes" (frente externo, visible) y NO en
            # "Cajones internos"/"Cajones internos + puerta" (quedan detras de
            # una puerta, no hace falta agarradera). Editable con el checkbox
            # "Lleva tiradera" de la jerarquia -- una vez que node['tiradera']
            # llega explicito (true/false) desde ahi, gana sobre el default.
            lleva_tiradera = node['tiradera'].nil? ? (contenido == 'CAJONES_FRENTES') : !!node['tiradera']
            estilo_frente = frente_cajon_activo ? (node['drawerFrontStyle'] || 'POR_CAJON').to_s.upcase : 'POR_CAJON'
            # Fuga ENTRE frentes (y entre el frente y una puerta vecina de otro
            # nodo): valor completo, igual que fuga_central entre puertas -- NO
            # se reparte a la mitad aca porque el reparto ya lo hace front_box
            # (frontJoint) contra el borde del casco/division, y contra un
            # nodo vecino cada uno pone su propio frontJoint (1.5mm) y entre
            # los dos suman los 3mm esperados sin que este codigo lo duplique.
            fuga_frente_ext = [(node['gap'] || 3).to_f, 0.5].max.mm
            # El frente de cajon se alinea al mismo plano/ancho que tendria una
            # puerta ahi (front_box, calculado en JS con el mismo solape sobre
            # el casco/division que usan las puertas), y se usa TAL CUAL --
            # sin restarle una fuga extra -- para que salga exactamente del
            # mismo ancho y con el mismo margen de 1.5mm que tendria una
            # puerta en ese lugar (front_box ya trae ese margen incluido via
            # frontJoint; una puerta tampoco le resta nada mas encima).
            frente_box_cajon = node['front_box'].is_a?(Hash) ? node['front_box'] : nil
            frente_x_min = frente_box_cajon ? frente_box_cajon['x'].to_f.mm : x_min
            frente_ancho = frente_box_cajon ? frente_box_cajon['w'].to_f.mm : ancho_nodo
            frente_z_min = frente_box_cajon ? frente_box_cajon['z'].to_f.mm : z_min
            frente_alto = frente_box_cajon ? frente_box_cajon['h'].to_f.mm : alto_nodo
            # Todos los frentes visibles de esta columna (1 en FALSO/UNICO_
            # INFERIOR, "cantidad" en POR_CAJON) se reparten con la MISMA
            # altura entre si, llenando frente_alto de punta a punta con
            # fuga_frente_ext (3mm por defecto) entre cada uno -- en vez de
            # heredar la altura mecanica del cajon (altura_caja), que no
            # coincide con el alto visible de fachada y hacia que el primero
            # y el ultimo salieran mas altos que los del medio.
            cantidad_frentes_visibles = estilo_frente == 'UNICO_INFERIOR' ? 1 : [[node['drawers'].to_i, 1].max, 12].min
            altura_frente_uniforme = if cantidad_frentes_visibles.positive?
                                       (frente_alto - (fuga_frente_ext * [cantidad_frentes_visibles - 1, 0].max)) / cantidad_frentes_visibles
                                     else
                                       0.mm
                                     end

            # El frente de cajon (falso o por cajon) sobresale exactamente
            # igual que sobresaldria una puerta en ese mismo lugar -- misma
            # formula (calcular_protrusion_puerta, la sobremedida del panel
            # vecino que realmente toca), en vez de un grosor de tablero fijo
            # aparte. Antes divergian: la puerta podia sobresalir mas (o
            # menos) que el frente de cajon segun la sobremedida configurada,
            # y quedaban visiblemente desalineados entre si.
            grosor_puerta_frente = [(datos['puerta_grosor'] || espesor.to_mm).to_f, 3.0].max.mm
            protrusion_frente = calcular_protrusion_puerta.call(x_min, x_min + ancho_nodo, z_min, z_min + alto_nodo, node['enclosure'], node['sobremedida'], grosor_puerta_frente)

            if frente_cajon_activo && estilo_frente == 'FALSO'
              if frente_ancho > 0.mm && frente_alto > 0.mm
                pieza_frente_falso = self.crear_pieza(entities, modulo_nombre, "H_CJ_#{nid}_FRENTE_FALSO", frente_ancho, espesor, frente_alto,
                  frente_x_min, -protrusion_frente, frente_z_min, 2, 2)
                pieza_frente_falso.definition.set_attribute('LPenafiel', 'lleva_tiradera', lleva_tiradera ? 'SI' : 'NO') if pieza_frente_falso.respond_to?(:definition)
              end
            else
            cantidad = [[node['drawers'].to_i, 1].max, 12].min
            # Espacio mecanico entre cajones: 1.5mm por defecto (misma fuga
            # que usan las puertas), aplicado entre cajon y cajon y entre el
            # primero/ultimo y la base/techo/repisa que los encierra. Editable
            # por espacio con "Espacio entre cajones" -- si el sistema de
            # corredera necesita mas holgura mecanica real, se sube ahi.
            fuga_h = [(node['drawerGap'] || 1.5).to_f, 0.5].max.mm
            # Antes fijo en 13mm (solo telescopica) -- ahora usa el mismo
            # "Sistema de corredera" configurable que ya tenia el camino
            # viejo de cajones (spaces_config), para poder elegir Oculta
            # (3mm) o Automatico maximo aca tambien.
            holgura = Modular3D::Herrajes.holgura_para_sistema((datos['sistema_corredera'] || 'Telescopica estandar').to_s).mm
            ancho_caja = ancho_nodo - (holgura * 2)
            # Altura de cajon: automatica (reparte el alto disponible en
            # partes iguales) salvo que se pida una altura manual y esta
            # quepa junto con las fugas; si no entra, se ignora en silencio
            # y se usa la automatica en su lugar (nunca se solapan cajones).
            altura_manual = (node['drawerHeight'] || 0).to_f.mm
            altura_auto = (alto_nodo - ((cantidad + 1) * fuga_h)) / cantidad
            cabe_manual = altura_manual.positive? && ((altura_manual * cantidad) + (fuga_h * (cantidad + 1))) <= alto_nodo
            altura_caja = cabe_manual ? altura_manual : altura_auto
            fondo_caja = [prof_input_cj, fondo_nodo - 10.mm].min
            if ancho_caja > (espesor * 2) && altura_caja > 25.mm && fondo_caja > (espesor * 2)
              (1..cantidad).each do |ci|
                base_x = x_min + holgura
                base_z = z_min + fuga_h + ((ci - 1) * (altura_caja + fuga_h))
                prefix = "H_CJ_#{nid}_#{ci}"
                # Se anida todo el cajon (laterales, frente, fondo, trasero y
                # frente exterior) dentro de un grupo propio para que un solo
                # atributo de posicion (Dynamic Components) lo deslice
                # completo, cajon y frente juntos, con la mano de Interactuar.
                # Las posiciones internas pasan a ser relativas a base_x/
                # y_min/base_z (el propio origen del grupo); por eso se anula
                # @offset_creacion mientras se arman las piezas hijas: ese
                # desplazamiento de modulo ya lo aplica el grupo contenedor
                # una sola vez, en su propia transformacion.
                grupo_cajon = entities.add_group
                # encapsular_modulo agrupa @piezas_modulo_actual como
                # entidades de nivel superior (entities.add_group(lista)):
                # las piezas hijas del cajon NO deben terminar ahi (quedaron
                # anidadas dentro de grupo_cajon, no como hijas directas del
                # modulo), asi que se desvia @piezas_modulo_actual a una
                # lista descartable mientras se arman, y solo grupo_cajon
                # (ya convertido a componente) se agrega a la lista real.
                piezas_reales = @piezas_modulo_actual
                @piezas_modulo_actual = []
                offset_guardado = @offset_creacion
                @offset_creacion = nil
                self.crear_pieza(grupo_cajon.entities, modulo_nombre, "#{prefix}_LAT_IZQ", espesor, fondo_caja, altura_caja, 0.mm, 0.mm, 0.mm, 1, 0)
                self.crear_pieza(grupo_cajon.entities, modulo_nombre, "#{prefix}_LAT_DER", espesor, fondo_caja, altura_caja, ancho_caja - espesor, 0.mm, 0.mm, 1, 0)
                pieza_frente_interno = self.crear_pieza(grupo_cajon.entities, modulo_nombre, "#{prefix}_FRENTE", ancho_caja - (espesor * 2), espesor, altura_caja, espesor, 0.mm, 0.mm, 1, 0)
                pieza_frente_interno.definition.set_attribute('LPenafiel', 'lleva_tiradera', lleva_tiradera ? 'SI' : 'NO') if pieza_frente_interno.respond_to?(:definition)
                self.crear_pieza(grupo_cajon.entities, modulo_nombre, "#{prefix}_POST", ancho_caja - (espesor * 2), espesor, altura_caja, espesor, fondo_caja - espesor, 0.mm, 1, 0)
                self.crear_pieza(grupo_cajon.entities, modulo_nombre, "#{prefix}_FONDO", ancho_caja - (espesor * 2), fondo_caja - (espesor * 2), espesor, espesor, espesor, 0.mm, 0, 0)
                # El frente exterior (a la altura de la puerta) solo tiene
                # sentido si este espacio NO tiene ya su propia puerta: si
                # ambos existieran a la vez competirian por el mismo plano
                # exterior. Con puerta propia, el cajon se queda con su
                # frente interno (el que ya arma crear_pieza mas arriba),
                # que nunca sobresale.
                # UNICO_INFERIOR: el frente solo se construye en el cajon mas
                # bajo (ci==1) y cubre TODO el espacio; los demas cajones de la
                # columna quedan sin frente propio, ocultos detras de ese
                # frente unico mientras estan cerrados.
                construir_frente_este_cajon = frente_cajon_activo && (estilo_frente != 'UNICO_INFERIOR' || ci == 1)
                if construir_frente_este_cajon
                  # Todos los frentes de esta columna salen con la MISMA
                  # altura (altura_frente_uniforme, calculada mas arriba
                  # repartiendo frente_alto en partes iguales) en vez de
                  # heredar la altura mecanica de su propio cajon -- por eso
                  # el primero y el ultimo ya no salian mas altos que los del
                  # medio. UNICO_INFERIOR usa un solo frente con el alto
                  # completo. El ancho sale igual que frente_ancho, sin
                  # restarle nada mas: front_box ya trae el margen de 1.5mm
                  # contra el casco/division, igual que una puerta ahi.
                  indice_frente = estilo_frente == 'UNICO_INFERIOR' ? 0 : (ci - 1)
                  alto_frente_ext = estilo_frente == 'UNICO_INFERIOR' ? frente_alto : altura_frente_uniforme
                  z_frente_abs = frente_z_min + (indice_frente * (altura_frente_uniforme + fuga_frente_ext))
                  z_frente_local = z_frente_abs - base_z
                  if frente_ancho > 0.mm && alto_frente_ext > 0.mm
                    pieza_frente_ext = self.crear_pieza(grupo_cajon.entities, modulo_nombre, "#{prefix}_FRENTE_EXT", frente_ancho, espesor, alto_frente_ext,
                      frente_x_min - base_x, -protrusion_frente - y_min, z_frente_local, 2, 2)
                    pieza_frente_ext.definition.set_attribute('LPenafiel', 'lleva_tiradera', lleva_tiradera ? 'SI' : 'NO') if pieza_frente_ext.respond_to?(:definition)
                  end
                end
                @offset_creacion = offset_guardado
                @piezas_modulo_actual = piezas_reales
                # OJO: to_component() debe llamarse ANTES de fijar la
                # transformacion (igual que hace crear_pieza en todos lados),
                # no despues -- fijarla sobre el Group y recien despues
                # convertirlo a componente la perdia (el grupo quedaba
                # colocado cerca del origen del mundo, muy lejos de donde
                # deberia estar el resto del modulo, viendose como una caja
                # invisible/aparte unida por una arista larguisima). Se
                # aplica sobre la instancia YA convertida, tal cual crear_pieza.
                instancia_cajon = grupo_cajon.to_component rescue grupo_cajon
                instancia_cajon.transformation = Geom::Transformation.new(Geom::Point3d.new(base_x, y_min, base_z) + (@offset_creacion || Geom::Vector3d.new(0, 0, 0)))
                @piezas_modulo_actual << instancia_cajon if @piezas_modulo_actual
                self.agregar_interactividad_cajon(instancia_cajon, fondo_caja)
              end
            end
            end
          end
        end

        # Los frentes se procesan en todos los nodos, incluidos padres que abarcan varios hijos.
        hierarchy_geometry['nodes'].each_with_index do |node, node_index|
          next unless node.is_a?(Hash)
          frente = node['front'].to_s.upcase
          frente = 'PUERTA_UNICA' if node['content'].to_s.upcase == 'CAJONES_PUERTA' && frente == 'NINGUNO'
          next if frente.empty? || frente == 'NINGUNO'
          puerta_interna = frente.include?('INTERNA')
          next if !puerta_interna && alcance_frentes != 'BY_SPACE'
          box = node['box'] || {}; fuga_h = [(node['gap'] || 3).to_f, 0.5].max.mm
          x_min = box['x'].to_f.mm; z_min = box['z'].to_f.mm; ancho_nodo = box['w'].to_f.mm; alto_nodo = box['h'].to_f.mm
          # Borde real del hueco/casco (antes de que front_box lo agrande con
          # el solape): sirve para medir cuánto solapa cada puerta sobre el
          # panel real de ese lado, y así saber qué tipo de bisagra le
          # corresponde (recta/semicodada/codada) según su altura de solape.
          cavidad_x_min = x_min; cavidad_x_max = x_min + ancho_nodo
          cavidad_z_min = z_min; cavidad_z_max = z_min + alto_nodo
          # Los valores antiguos de vidrio se abren como puertas sólidas para conservar proyectos.
          frente = frente.gsub('_VIDRIO', '').gsub('VIDRIO', 'UNICA')
          cantidad_solicitada = node['frontCount'].to_s.upcase
          cantidad = if cantidad_solicitada != '' && cantidad_solicitada != 'AUTO'
                       [[cantidad_solicitada.to_i, 1].max, 8].min
                     else
                       [[(ancho_nodo.to_mm / 600.0).ceil, 1].max, 8].min
                     end
          unless puerta_interna
            frente_box = node['front_box'].is_a?(Hash) ? node['front_box'] : nil
            if frente_box
              x_min = frente_box['x'].to_f.mm
              z_min = frente_box['z'].to_f.mm
              ancho_nodo = frente_box['w'].to_f.mm
              alto_nodo = frente_box['h'].to_f.mm
            elsif node['id'].to_s == 'root'
              x_min = 1.5.mm
              z_min = 1.5.mm
              ancho_nodo = ancho_total - 3.mm
              alto_nodo = alto_total - 3.mm
            end
            cantidad = [[(ancho_nodo.to_mm / 600.0).ceil, 1].max, 8].min if cantidad_solicitada == '' || cantidad_solicitada == 'AUTO'
          end
          grosor_puerta = [(datos['puerta_grosor'] || espesor.to_mm).to_f, 3.0].max.mm
          fuga_central = [(node['gapCenter'] || node['gap'] || 3).to_f, 0.5].max.mm
          margen_lateral = puerta_interna ? fuga_h : 0.mm
          ancho_puerta = (ancho_nodo - (margen_lateral * 2) - (fuga_central * (cantidad - 1))) / cantidad
          alto_puerta = alto_nodo - (margen_lateral * 2)
          next if ancho_puerta <= 0 || alto_puerta <= 0
          nid_puerta = id_pieza_jerarquia(node['id'], "IDX#{node_index + 1}")
          externa_embutida = !puerta_interna && (datos['montaje_puerta'] || 'SOLAPADA').to_s.upcase == 'EMBUTIDA'
          (1..cantidad).each do |pi|
            nombre_puerta = "H_PUERTA_#{puerta_interna ? 'INT' : 'EXT'}_#{nid_puerta}_#{pi}"
            # Externa solapada: ocupa el plano exterior, desde -grosor hasta el
            # frente Y=0. Externa embutida: queda a ras (Y=0), dentro del hueco
            # que ya calculó facadeBox con margen uniforme. Interna: nace
            # dentro del hueco del espacio seleccionado.
            protrusion_puerta = (puerta_interna || externa_embutida) ? grosor_puerta : calcular_protrusion_puerta.call(cavidad_x_min, cavidad_x_max, cavidad_z_min, cavidad_z_max, node['enclosure'], node['sobremedida'], grosor_puerta)
            y_puerta = puerta_interna ? box['y'].to_f.mm + 2.mm : (externa_embutida ? 0.mm : -protrusion_puerta)
            # Guarda el valor REAL usado por esta puerta externa solapada --
            # el remate lo reutiliza tal cual más abajo, así quedan siempre
            # en el mismo plano exacto (ver "protrusion_puerta_real" arriba).
            protrusion_puerta_real = protrusion_puerta if !puerta_interna && !externa_embutida
            x_puerta_izq = x_min + margen_lateral + ((pi - 1) * (ancho_puerta + fuga_central))
            # Con una sola puerta se respeta la bisagra elegida en "Apertura"
            # del espacio; con varias, las de los extremos abren hacia afuera
            # (la primera por la izquierda, la última por la derecha) como es
            # habitual en puertas dobles/triples.
            lado_bisagra_puerta = if cantidad == 1
                                     node['hinge'].to_s == 'Derecha' ? :derecha : :izquierda
                                   elsif pi == cantidad
                                     :derecha
                                   else
                                     :izquierda
                                   end
            instancia_puerta = if lado_bisagra_puerta == :derecha
                                  self.crear_pieza(entities, modulo_nombre, nombre_puerta, ancho_puerta, grosor_puerta, alto_puerta,
                                    x_puerta_izq + ancho_puerta, y_puerta, z_min + margen_lateral, 2, 2, true)
                                else
                                  self.crear_pieza(entities, modulo_nombre, nombre_puerta, ancho_puerta, grosor_puerta, alto_puerta,
                                    x_puerta_izq, y_puerta, z_min + margen_lateral, 2, 2)
                                end
            self.agregar_interactividad_puerta(instancia_puerta, lado_bisagra_puerta)
            # Solape real de la bisagra sobre el panel de ese lado (lateral
            # izq/der del borde de la puerta contra el borde real del hueco):
            # una puerta intermedia de una fachada de varias hojas sin
            # división física de por medio da 0 (sin apoyo firme detrás).
            borde_bisagra = lado_bisagra_puerta == :derecha ? (x_puerta_izq + ancho_puerta) : x_puerta_izq
            solape_mm = if lado_bisagra_puerta == :derecha
                          [(borde_bisagra - cavidad_x_max).to_mm, 0.0].max
                        else
                          [(cavidad_x_min - borde_bisagra).to_mm, 0.0].max
                        end
            embutida_efectiva = externa_embutida || puerta_interna
            if instancia_puerta.respond_to?(:definition)
              instancia_puerta.definition.set_attribute('LPenafiel', 'tipo_bisagra', tipo_bisagra_por_solape(solape_mm, espesor.to_mm, embutida_efectiva))
            end
          end
        end

        # Frente exterior global: una fachada independiente que cubre todo el módulo.
        if alcance_frentes == 'GLOBAL'
          modo = (datos['global_front_count_mode'] || 'AUTO').to_s.upcase
          maximo = [[(datos['global_front_auto_width'] || 600).to_f, 100.0].max, ancho_total.to_mm].min
          cantidad = modo == 'MANUAL' ? (datos['global_front_count'] || 1).to_i : (ancho_total.to_mm / maximo).ceil
          cantidad = [[cantidad, 1].max, 8].min
          fuga_izq = [(datos['global_front_gap_left'] || 3).to_f, 0.0].max.mm
          fuga_der = [(datos['global_front_gap_right'] || 3).to_f, 0.0].max.mm
          fuga_sup = [(datos['global_front_gap_top'] || 3).to_f, 0.0].max.mm
          fuga_inf = [(datos['global_front_gap_bottom'] || 3).to_f, 0.0].max.mm
          fuga_central = [(datos['global_front_gap_center'] || 3).to_f, 0.0].max.mm
          grosor_puerta = [(datos['puerta_grosor'] || espesor.to_mm).to_f, 3.0].max.mm
          ancho_puerta = (ancho_total - fuga_izq - fuga_der - fuga_central * (cantidad - 1)) / cantidad
          alto_puerta = alto_total - fuga_sup - fuga_inf
          if ancho_puerta > 0 && alto_puerta > 0
            # Frente global: por definicion toca los 4 lados del casco, asi
            # que se pasan los bordes exactos de coincidencia (sin necesidad
            # de detectar toque real como en el bucle por espacio).
            protrusion_global = calcular_protrusion_puerta.call(grosor_lat_izq, ancho_total - grosor_lat_der, grosor_inferior, alto_total - grosor_superior, nil, nil, grosor_puerta)
            (1..cantidad).each do |pi|
              # El grosor de la puerta (segundo argumento) no cambia -- solo
              # su posicion Y se adelanta hasta igualar al panel que mas
              # sobresale (protrusion_global), igual que en el bucle por
              # espacio de arriba.
              pieza = self.crear_pieza(entities, modulo_nombre, "G_PUERTA_EXT_#{pi}", ancho_puerta, grosor_puerta, alto_puerta,
                fuga_izq + ((pi - 1) * (ancho_puerta + fuga_central)), -protrusion_global, fuga_inf, 2, 2)
              regla_apertura = (datos['global_front_hinge'] || 'ALTERNADA').to_s.upcase
              apertura = if regla_apertura == 'IZQUIERDA' || regla_apertura == 'DERECHA'
                           regla_apertura
                         else
                           pi <= (cantidad / 2.0).ceil ? 'IZQUIERDA' : 'DERECHA'
                         end
              pieza.set_attribute('LPenafiel', 'apertura', apertura) if pieza
            end
          end
        end
      end

      caja_modulo_estructura = bounds_de_piezas(@piezas_modulo_actual)

      if num_cajones > 0
        fuga = [(datos['luz_frentes'] || datos['juego_general'] || 3).to_f, 1.5].max.mm
        sistema_corredera = (datos['sistema_corredera'] || "Telescopica estandar").to_s
        # Delegado a Modular3D::Herrajes (§6 nivel A): misma tabla de holguras
        # por defecto (Oculta 21mm, Automático máximo 15mm, cualquier otro
        # texto -- incluida "Telescopica estandar" -- 13mm), ahora editable
        # desde Modular_3D/herrajes/correderas.json sin tocar este archivo.
        holgura_lateral = Modular3D::Herrajes.holgura_para_sistema(sistema_corredera).mm
        retiro_cajones = (datos['ret_cajones'] || 0).to_f.mm
        ancho_disponible_cajon = num_divisiones > 0 ? ((ancho_util_mueble - (num_divisiones * espesor)) / (num_divisiones + 1)) : ancho_util_mueble
        ancho_caja_cajon = ancho_disponible_cajon - (holgura_lateral * 2)
        prof_caja_cajon = prof_input_cj

        nichos = []
        z_inicio_nicho_actual = grosor_inferior
        posiciones_repisas.each do |z_repisa|
          nichos << [z_inicio_nicho_actual, z_repisa]
          z_inicio_nicho_actual = z_repisa
        end
        nichos << [z_inicio_nicho_actual, z_limite_repisas]
        contador_cajon = 0

        nichos.each_with_index do |limites_nicho, indice_nicho|
          drawer_specs = if spaces_config.empty?
                           [{ 'column' => 0, 'drawers' => cajones_por_nicho[indice_nicho].to_i,
                              'front_type' => (tipos_cajon_por_nicho[indice_nicho] || 'INTERNO') }]
                         else
                           spaces_config.select do |space|
                             space['niche'].to_i == indice_nicho && space['content'].to_s == 'CAJONERA'
                           end
                         end
          drawer_specs.each do |drawer_space|
          cajones_en_nicho = drawer_space['drawers'].to_i
          next if cajones_en_nicho <= 0
          columna_cajon = [[drawer_space['column'].to_i, 0].max, num_divisiones].min

          z_inicio_nicho = limites_nicho[0]
          z_fin_nicho = limites_nicho[1]
          tipo_cajon_nicho = (drawer_space['front_type'] || "INTERNO").to_s.upcase
          altura_hueco_disponible = z_fin_nicho - z_inicio_nicho
          margen_caja = 30.mm
          total_espacio_fugas = (2 * margen_caja) + ((cajones_en_nicho - 1) * fuga)
          altura_caja_cajon = (altura_hueco_disponible - total_espacio_fugas) / cajones_en_nicho
          next if altura_caja_cajon <= 0

          (1..cajones_en_nicho).each do |j|
            contador_cajon += 1
            z_inicio_cajon = z_inicio_nicho + margen_caja + ((j - 1) * (altura_caja_cajon + fuga))
            ancho_lat_cajon = espesor; prof_lat_cajon = prof_caja_cajon; alto_lat_cajon = altura_caja_cajon
            ancho_frente_cajon = ancho_caja_cajon - (espesor * 2); prof_frente_cajon = espesor; alto_frente_cajon = altura_caja_cajon
            ancho_fondo_cajon = ancho_frente_cajon; prof_fondo_cajon = prof_caja_cajon - (espesor * 2); alto_fondo_cajon = espesor

            x_inicio_columna = grosor_lat_izq + (columna_cajon * (ancho_disponible_cajon + espesor))
            x_cj_lat_izq = x_inicio_columna + holgura_lateral
            self.crear_pieza(entities, modulo_nombre, "CJ_#{contador_cajon}_LAT_IZQ", ancho_lat_cajon, prof_lat_cajon, alto_lat_cajon, x_cj_lat_izq, retiro_cajones, z_inicio_cajon, 1, 0)
            x_cj_lat_der = x_cj_lat_izq + ancho_caja_cajon - espesor
            self.crear_pieza(entities, modulo_nombre, "CJ_#{contador_cajon}_LAT_DER", ancho_lat_cajon, prof_lat_cajon, alto_lat_cajon, x_cj_lat_der, retiro_cajones, z_inicio_cajon, 1, 0)
            x_cj_frente = x_cj_lat_izq + espesor
            # El frente va PEGADO por delante de la caja del cajón (que se
            # queda tal cual, en retiro_cajones) -- no a ras del mismo plano
            # que sus costados/fondo. Antes el frente arrancaba en
            # retiro_cajones igual que la caja, quedando a ras del plano del
            # casco (Y=0) en vez de sobresalir como una puerta o un remate
            # (que sí arrancan en -grosor), por lo que se veía embutido/
            # hundido frente a ellos aunque el frente use el mismo material y
            # plano visual que una puerta solapada.
            y_cj_frente = retiro_cajones - prof_frente_cajon
            self.crear_pieza(entities, modulo_nombre, "CJ_#{contador_cajon}_FRENTE", ancho_frente_cajon, prof_frente_cajon, alto_frente_cajon, x_cj_frente, y_cj_frente, z_inicio_cajon, 1, 0)
            y_cj_post = retiro_cajones + prof_caja_cajon - espesor
            self.crear_pieza(entities, modulo_nombre, "CJ_#{contador_cajon}_POSTERIOR", ancho_frente_cajon, prof_frente_cajon, alto_frente_cajon, x_cj_frente, y_cj_post, z_inicio_cajon, 1, 0)
            y_cj_fondo = retiro_cajones + espesor; z_cj_fondo = z_inicio_cajon
            self.crear_pieza(entities, modulo_nombre, "CJ_#{contador_cajon}_FONDO", ancho_fondo_cajon, prof_fondo_cajon, alto_fondo_cajon, x_cj_frente, y_cj_fondo, z_cj_fondo, 0, 0)
          end

          if tipo_cajon_nicho == "FRENTES"
            fuga_frente = [(datos['luz_perimetral'] || datos['luz_frentes'] || 1.5).to_f, 0.5].max.mm
            x_inicio_columna = grosor_lat_izq + (columna_cajon * (ancho_disponible_cajon + espesor))
            x_frente_exterior = x_inicio_columna + fuga_frente
            ancho_frente_exterior = ancho_disponible_cajon - (fuga_frente * 2)
            y_frente_exterior = -espesor
            z_frente_inferior = if indice_nicho == 0
                                  0.mm
                                else
                                  posiciones_repisas[indice_nicho - 1] - (espesor / 2.0)
                                end
            z_frente_superior = if posiciones_repisas[indice_nicho]
                                  posiciones_repisas[indice_nicho] + (espesor / 2.0)
                                else
                                  z_limite_repisas
                                end
            alto_total_frentes = z_frente_superior - z_frente_inferior
            next if ancho_frente_exterior <= 0 || alto_total_frentes <= 0

            alto_segmento_frente = alto_total_frentes / cajones_en_nicho
            (1..cajones_en_nicho).each do |f|
              z_segmento_inferior = z_frente_inferior + ((f - 1) * alto_segmento_frente)
              z_frente = z_segmento_inferior + fuga_frente
              alto_frente = alto_segmento_frente - (fuga_frente * 2)
              next if alto_frente <= 0

              frente = self.crear_pieza(entities, modulo_nombre, "CJ_FRENTE_EXTERIOR_#{indice_nicho + 1}_#{f}", ancho_frente_exterior, espesor, alto_frente, x_frente_exterior, y_frente_exterior, z_frente, 2, 2)
              offset = @offset_creacion || Geom::Vector3d.new(0, 0, 0)
              self.alinear_bounds(frente,
                :min_x => offset.x + x_frente_exterior,
                :min_y => offset.y + y_frente_exterior,
                :min_z => offset.z + z_segmento_inferior + fuga_frente
              )
            end
            offset_zona = @offset_creacion ? @offset_creacion.z : 0
            zonas_frentes_cajon << [z_frente_inferior + offset_zona, z_frente_superior + offset_zona]
          end
          end
        end
      end
      
      unless spaces_config.empty?
        ancho_celda = (ancho_util_mueble - (num_divisiones * espesor)) / (num_divisiones + 1)
        limites_nichos = []
        inicio_nicho = grosor_inferior
        posiciones_repisas.each do |z_repisa|
          limites_nichos << [inicio_nicho, z_repisa]
          inicio_nicho = z_repisa
        end
        limites_nichos << [inicio_nicho, z_limite_repisas]
        grosor_puerta_celda = (datos['puerta_grosor'] || 15).to_f.mm
        lado_puerta_celda = datos['puerta_bisagra'] == "Derecha" ? :derecha : :izquierda
        offset_celda = @offset_creacion || Geom::Vector3d.new(0, 0, 0)
        spaces_config.each do |space|
          contenido = space['content'].to_s.upcase
          next unless contenido == 'REPISAS'

          cantidad_repisas_celda = [[space['shelves'].to_i, 0].max, 12].min
          next if cantidad_repisas_celda <= 0

          nicho = space['niche'].to_i
          columna = space['column'].to_i
          next unless limites_nichos[nicho] && columna.between?(0, num_divisiones)

          x_min = grosor_lat_izq + (columna * (ancho_celda + espesor))
          z_min, z_max = limites_nichos[nicho]
          altura_celda = z_max - z_min
          next if altura_celda <= ((cantidad_repisas_celda + 1) * espesor)

          distancia_local = (altura_celda - (cantidad_repisas_celda * espesor)) / (cantidad_repisas_celda + 1)
          (1..cantidad_repisas_celda).each do |indice_repisa|
            z_repisa_celda = z_min + (indice_repisa * distancia_local) + ((indice_repisa - 1) * espesor)
            self.crear_pieza(
              entities, modulo_nombre, "REPISA_CELDA_#{nicho + 1}_#{columna + 1}_#{indice_repisa}",
              ancho_celda, prof_repisa_descontada, espesor,
              x_min, 0.mm, z_repisa_celda,
              rep_l, rep_c
            )
          end
        end
        spaces_config.each do |space|
          contenido = space['content'].to_s.upcase
          next unless contenido.start_with?('PUERTA')
          nicho = space['niche'].to_i
          columna = space['column'].to_i
          next unless limites_nichos[nicho] && columna.between?(0, num_divisiones)

          x_min = grosor_lat_izq + (columna * (ancho_celda + espesor))
          z_min, z_max = limites_nichos[nicho]
          caja_celda = Geom::BoundingBox.new
          caja_celda.add(
            Geom::Point3d.new(offset_celda.x + x_min, offset_celda.y, offset_celda.z + z_min),
            Geom::Point3d.new(offset_celda.x + x_min + ancho_celda, offset_celda.y + prof_total, offset_celda.z + z_max)
          )
          cantidad = contenido.include?('DOBLE') ? 2 : 1
          fuga_celda = [(space['gap'] || datos['luz_perimetral'] || 1.5).to_f, 0.5].max.mm
          self.crear_puertas_en_caja(entities, modulo_nombre, caja_celda, grosor_puerta_celda, lado_puerta_celda, nil, nil, cantidad, fuga_celda, (datos['montaje_puerta'] || 'SOLAPADA'))
        end
      end

      if !hierarchy_geometry && spaces_config.empty? && datos['crear_puerta'] == "SI"
        lado_puerta = datos['puerta_bisagra'] == "Derecha" ? :derecha : :izquierda
        grosor_puerta = (datos['puerta_grosor'] || 15).to_f.mm
        tipo_puerta = (datos['tipo_puerta'] || "AUTO").to_s.upcase
        cantidad_puertas = if tipo_puerta == "UNICA" || tipo_puerta == "VIDRIO"
                             1
                           elsif tipo_puerta == "DOBLE" || tipo_puerta == "DOBLE_VIDRIO"
                             2
                           else
                             nil
                           end
        z_min_puerta = zonas_frentes_cajon.empty? ? nil : zonas_frentes_cajon.map { |zona| zona[1] }.max
        unless caja_modulo_estructura.empty?
          montaje_puerta_modulo = (datos['montaje_puerta'] || 'SOLAPADA').to_s.upcase
          fuga_puertas = montaje_puerta_modulo == 'EMBUTIDA' ? (datos['luz_perimetral'] || datos['juego_general'] || 3).to_f.mm : (datos['luz_solape'] || 1.5).to_f.mm
          luz_superior = (datos['luz_sup_frente'] || 0).to_f.mm
          z_max_puerta = caja_modulo_estructura.max.z - luz_superior
          self.crear_puertas_en_caja(entities, modulo_nombre, caja_modulo_estructura, grosor_puerta, lado_puerta, z_min_puerta, z_max_puerta, cantidad_puertas, fuga_puertas, montaje_puerta_modulo)
        end
      end

      # --- Zócalo, premesón, cornisa y remates automáticos por tipo de módulo ---
      # Zócalo: tablero delgado (siempre 126x15mm) retranqueado 70mm desde
      # el frente, en Bajo/Auxiliar/Closet (cualquier módulo que llega al
      # piso), cubriendo el ancho TOTAL (tapa también el grosor de los
      # laterales). Va por FUERA de la caja del módulo: ocupa el piso real
      # (z=0..zocalo_alto), mientras que el casco entero ya se levantó
      # zocalo_alto más arriba en el método (ver "alto_carcasa_offset") para
      # quedar apoyado encima sin superponerse. Premesón: tapa la parte de
      # arriba, solo en Bajo, ancho total, en material crudo (sin rol de
      # color propio). Cornisa: equivalente arriba para Alto/Auxiliar/
      # Closet, OPCIONAL (a diferencia del zócalo) y con altura elegida por
      # el usuario, retranqueada 20mm desde el plano de la puerta; se apoya
      # sobre el tope real del casco (alto_total + alto_carcasa_offset).
      # Remates: paneles de 100mm en Auxiliar/Closet, desde el piso hasta
      # 2420mm fijo (se cortan a medida en obra). Remate de zócalo/cornisa:
      # cierran el bolsillo lateral que deja cada retranqueo.
      # Se restaura el offset ORIGINAL (sin el levante del casco) porque
      # estas piezas van relativas al piso/tope real del módulo, no al
      # casco ya levantado.
      # Deliberadamente SIN continuidad entre módulos vecinos en esta
      # ronda -- cada módulo genera sus propias piezas como si estuviera
      # solo; unir tramos entre módulos pegados es responsabilidad de un
      # comando aparte ("Sincronizar continuidad") que arma piezas propias
      # por tramo sin tocar este método.
      @offset_creacion = offset_creacion_base
      zocalo_grosor = 15.mm
      zocalo_retranqueo = 70.mm
      cornisa_grosor = 15.mm
      cornisa_retranqueo = 20.mm
      remate_ancho = 100.mm

      lleva_premeson = tipo_modulo == 'BAJO' && datos['premeson_activo'].to_s != 'NO'
      cornisa_disponible = %w[ALTO AUXILIAR CLOSET].include?(tipo_modulo)
      cornisa_activa = cornisa_disponible && (datos['cornisa_activa'] || 'NO').to_s == 'SI'
      # Disponible en los 4 tipos con casco automático (Alto/Bajo/Closet/
      # Auxiliar) -- antes solo Auxiliar/Closet, pero eso dejó desactivado
      # el check rápido "Izq"/"Der" del visor 3D para Alto y Bajo aunque la
      # UI ya lo permitía marcar.
      lleva_remates = tipo_modulo != 'PERSONALIZADO'

      if lleva_zocalo
        self.crear_pieza(entities, modulo_nombre, "ZOCALO", ancho_total, zocalo_grosor, zocalo_alto, 0.mm, zocalo_retranqueo, 0.mm, 1, 1)

        remate_zocalo_lado = (datos['remate_zocalo_lado'] || 'NINGUNO').to_s.upcase
        # Arranca DETRÁS del propio zócalo (retranqueo + su grosor), no en el
        # mismo Y -- si no, este remate se solapaba exactamente con el propio
        # ZOCALO en los primeros zocalo_grosor mm (mismo X, mismo Y, mismo Z),
        # compitiendo por el mismo espacio en esa esquina. El zócalo (la
        # pieza vista, "el frente") se queda intacto; el remate solo tapa el
        # bolsillo que queda DETRÁS de él, hacia la pared trasera.
        y_remate_zocalo = zocalo_retranqueo + zocalo_grosor
        fondo_remate_zocalo = prof_total - y_remate_zocalo
        if fondo_remate_zocalo > 0.mm
          if %w[IZQ AMBOS].include?(remate_zocalo_lado)
            self.crear_pieza(entities, modulo_nombre, "REMATE_ZOCALO_IZQ", zocalo_grosor, fondo_remate_zocalo, zocalo_alto, 0.mm, y_remate_zocalo, 0.mm, 0, 0)
          end
          if %w[DER AMBOS].include?(remate_zocalo_lado)
            self.crear_pieza(entities, modulo_nombre, "REMATE_ZOCALO_DER", zocalo_grosor, fondo_remate_zocalo, zocalo_alto, ancho_total - zocalo_grosor, y_remate_zocalo, 0.mm, 0, 0)
          end
        end
      end

      if lleva_premeson
        self.crear_pieza(entities, modulo_nombre, "PREMESON", ancho_total, prof_total, espesor, 0.mm, 0.mm, alto_total + alto_carcasa_offset, 1, 1)
      end

      if cornisa_activa
        cornisa_altura = [(datos['cornisa_altura'] || 100).to_f, 20.0].max.mm
        z_cornisa = alto_total + alto_carcasa_offset
        self.crear_pieza(entities, modulo_nombre, "CORNISA", ancho_total, cornisa_grosor, cornisa_altura, 0.mm, cornisa_retranqueo, z_cornisa, 1, 1)

        remate_cornisa_lado = (datos['remate_cornisa_lado'] || 'NINGUNO').to_s.upcase
        # Mismo criterio que remate de zócalo: arranca DETRÁS de la propia
        # cornisa (retranqueo + su grosor) para no solaparse con ella.
        y_remate_cornisa = cornisa_retranqueo + cornisa_grosor
        fondo_remate_cornisa = prof_total - y_remate_cornisa
        if fondo_remate_cornisa > 0.mm
          if %w[IZQ AMBOS].include?(remate_cornisa_lado)
            self.crear_pieza(entities, modulo_nombre, "REMATE_CORNISA_IZQ", cornisa_grosor, fondo_remate_cornisa, cornisa_altura, 0.mm, y_remate_cornisa, z_cornisa, 0, 0)
          end
          if %w[DER AMBOS].include?(remate_cornisa_lado)
            self.crear_pieza(entities, modulo_nombre, "REMATE_CORNISA_DER", cornisa_grosor, fondo_remate_cornisa, cornisa_altura, ancho_total - cornisa_grosor, y_remate_cornisa, z_cornisa, 0, 0)
          end
        end
      end

      if lleva_remates
        # Antes era un fijo de 2420mm "se corta a medida en obra" -- ahora se
        # adapta al tope REAL de este módulo: hasta el tope de la cornisa si
        # está activa (Alto/Auxiliar/Closet), hasta el tope del premesón si
        # está activo (Bajo), o si no hay ninguno de los dos, hasta el tope
        # del propio casco. El fijo de obra causaba que el remate quedara
        # más corto o más largo que el casco+cornisa/premesón real, viéndose
        # entrelazado con esas piezas en vez de alinearse con su borde.
        tope_casco = alto_total + alto_carcasa_offset
        remate_alto_total = if cornisa_activa
                              z_cornisa + cornisa_altura
                            elsif lleva_premeson
                              tope_casco + espesor
                            else
                              tope_casco
                            end
        grosor_frente_remate = [(datos['puerta_grosor'] || espesor.to_mm).to_f, 3.0].max.mm
        # El remate tiene que quedar en el MISMO plano que la puerta, sea cual
        # sea su montaje: Solapada (la puerta sobresale) o Embutida (la
        # puerta queda a ras, Y=0). Para Solapada, en vez de recalcular el
        # saliente por separado (que podía divergir del de la puerta real
        # por redondeos, sobremedidas de panel, u otro dato tomado de otro
        # lugar), se REUTILIZA tal cual el mismo valor que ya se usó para
        # construir la puerta de este módulo (protrusion_puerta_real,
        # capturado en el bucle de puertas más arriba) -- matemáticamente
        # imposible que queden en planos distintos porque es literalmente el
        # mismo número. Si no hay ninguna puerta externa solapada construida
        # (protrusion_puerta_real sigue nil), se usa grosor_frente_remate
        # como respaldo, igual que antes.
        montaje_puerta_general = (datos['montaje_puerta'] || 'SOLAPADA').to_s.upcase
        y_frente_remate = if montaje_puerta_general == 'EMBUTIDA'
                            0.mm
                          else
                            0.mm - (protrusion_puerta_real || grosor_frente_remate)
                          end
        remate_inicial = (datos['remate_inicial'] || 'NO').to_s == 'SI'
        remate_final = (datos['remate_final'] || 'NO').to_s == 'SI'
        if remate_inicial
          self.crear_pieza(entities, modulo_nombre, "REMATE_INICIAL", remate_ancho, grosor_frente_remate, remate_alto_total, 0.mm - remate_ancho, y_frente_remate, 0.mm, 0, 0)
        end
        if remate_final
          self.crear_pieza(entities, modulo_nombre, "REMATE_FINAL", remate_ancho, grosor_frente_remate, remate_alto_total, ancho_total, y_frente_remate, 0.mm, 0, 0)
        end
      end

      source = datos['__manifest_source'].to_s.empty? ? (datos['__legacy_migration'].to_s == 'SI' ? 'MIGRATED' : 'PARAMETRICO') : datos['__manifest_source'].to_s
      manifiesto = crear_manifiesto(@datos_modulo_actual, modulo_nombre, @modulo_uuid_actual, source)
      manifiesto['piece_inventory'] = inventario_geometrico(@piezas_modulo_actual)
      contenedor = encapsular_modulo(entities, @piezas_modulo_actual, manifiesto)
      contenedor.transformation = @transformacion_edicion if contenedor && actualizar_existente && @transformacion_edicion
      @ultimo_modulo_piezas = contenedor ? [contenedor] : @piezas_modulo_actual
      if contenedor
        model.selection.clear
        model.selection.add(contenedor)
      end
      unless datos['view_snapshot'].to_s.empty?
        # Se guarda con la clave del modulo REAL (modulo_uuid), no la firma
        # por dimensiones (modulo_despiece): dos modulos identicos en medidas
        # pisaban la misma foto entre si con la clave vieja.
        model.set_attribute('Modular3DViews', @modulo_uuid_actual.to_s, datos['view_snapshot'].to_s)
        model.set_attribute('Modular3DViewCameras', @modulo_uuid_actual.to_s, datos['view_camera_json'].to_s)
      end
      @piezas_modulo_actual = nil
      @offset_creacion = nil
      @modulo_despiece_actual = nil
      @datos_modulo_actual = nil
      @modulo_uuid_actual = nil
      @contenedor_edicion = nil
      @transformacion_edicion = nil
      @offset_edicion = nil if actualizar_existente
      model.commit_operation
      operacion_iniciada = false
      rescue => e
        model.abort_operation if operacion_iniciada
        @piezas_modulo_actual = nil
        @offset_creacion = nil
        @modulo_despiece_actual = nil
        @datos_modulo_actual = nil
        @offset_edicion = nil
        @seleccion_edicion = nil
        @transformacion_edicion = nil
        UI.messagebox("Modular_3D no pudo completar la operación:\n\n#{e.class}: #{e.message}")
      end
    end

    dialogo.show
    perfiles_json = JSON.generate(Modular3D::Profiles.listar)
    UI.start_timer(0.35, false) do
      begin
        dialogo.execute_script("window.__modular3dProfiles = #{perfiles_json}; if (window.Modular3DApplyProfileList) { window.Modular3DApplyProfileList(window.__modular3dProfiles); }") if dialogo
      rescue
        nil
      end
    end
    # Biblioteca de texturas incluidas (Modular_3D/textures/, con las marcas
    # de fabricante agregadas ademas de las 7 genericas originales): se
    # generan una sola vez en Ruby (manifiesto_texturas_incluidas, que ya
    # lee manifest.json recursivamente sin importar cuantas subcarpetas de
    # marca/coleccion tenga) y se empujan al dialogo para que el desplegable
    # "Textura incluida" las liste agrupadas por marca.
    texturas_json = JSON.generate(self.manifiesto_texturas_incluidas.values)
    UI.start_timer(0.35, false) do
      begin
        dialogo.execute_script("window.__modular3dIncludedTextures = #{texturas_json}; if (window.Modular3DApplyIncludedTextures) { window.Modular3DApplyIncludedTextures(window.__modular3dIncludedTextures); }") if dialogo
      rescue
        nil
      end
    end
    # Parámetros de Diseño (§3) y Principios de Espacio (§2): mismo patrón de
    # inyección diferida que Perfiles/Texturas, uno por uno para no acoplar
    # el fallo de uno con el otro.
    parametros_diseno_json = JSON.generate(Modular3D::ParametrosDiseno.listar)
    UI.start_timer(0.35, false) do
      begin
        dialogo.execute_script("window.__modular3dParametrosDiseno = #{parametros_diseno_json}; if (window.Modular3DApplyParametrosDisenoList) { window.Modular3DApplyParametrosDisenoList(window.__modular3dParametrosDiseno); }") if dialogo
      rescue
        nil
      end
    end
    principios_json = JSON.generate(Modular3D::Principios.listar)
    UI.start_timer(0.35, false) do
      begin
        dialogo.execute_script("window.__modular3dPrincipios = #{principios_json}; if (window.Modular3DApplyPrincipiosList) { window.Modular3DApplyPrincipiosList(window.__modular3dPrincipios); }") if dialogo
      rescue
        nil
      end
    end
    reglas_construccion_json = JSON.generate(Modular3D::ReglasConstruccion.listar)
    UI.start_timer(0.35, false) do
      begin
        dialogo.execute_script("window.__modular3dReglasConstruccion = #{reglas_construccion_json}; if (window.Modular3DApplyReglasConstruccionList) { window.Modular3DApplyReglasConstruccionList(window.__modular3dReglasConstruccion); }") if dialogo
      rescue
        nil
      end
    end
    if datos_iniciales && !datos_iniciales.empty?
      datos_json = JSON.generate(datos_iniciales)
      script = "window.__modular3dInitial = #{datos_json}; if (window.Modular3DLoadInitial) { window.Modular3DLoadInitial(window.__modular3dInitial); }"
      UI.start_timer(0.4, false) do
        begin
          dialogo.execute_script(script) if dialogo
        rescue
          nil
        end
      end
    end
  end

  # --- EDICIÓN POR LOTES (repintado) ---
  # Alcance deliberadamente acotado: repinta piezas existentes de varios
  # módulos Modular_3D seleccionados a la vez, sin tocar dimensiones. Un
  # cambio de medidas por lote implicaría reconstruir la geometría completa
  # de cada módulo con la misma lógica de ejecutarConstruccionMueble, que
  # vive dentro del callback del diálogo principal; separarla seguiría
  # siendo posible más adelante, pero no de forma segura sin poder probarlo
  # en vivo dentro de SketchUp. El repintado, en cambio, solo reasigna
  # material a piezas que ya existen y es seguro de principio a fin.
end
