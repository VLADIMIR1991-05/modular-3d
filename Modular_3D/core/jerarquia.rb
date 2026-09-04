# frozen_string_literal: true

module LPenafiel_GeneradorMueblesExacto
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

    ruta_html = File.expand_path('../ui/interfaz.html', __dir__)
    
    if File.exist?(ruta_html)
      dialogo.set_file(ruta_html)
    else
      UI.messagebox("Error crítico: no se encontró el archivo 'interfaz.html'.")
      return
    end

    enviar_estado_licencia = lambda do |estado|
      dialogo.execute_script("window.Modular3DLicense && window.Modular3DLicense.receive(#{JSON.generate(estado)});")
    end

    dialogo.add_action_callback("licenciaEstado") do |_action_context|
      enviar_estado_licencia.call(Modular3D::License.status)
    end

    dialogo.add_action_callback("licenciaLogin") do |_action_context, email, password, force_transfer|
      enviar_estado_licencia.call(Modular3D::License.login(email, password, force_transfer == true))
    end

    dialogo.add_action_callback("licenciaHeartbeat") do |_action_context|
      enviar_estado_licencia.call(Modular3D::License.heartbeat)
    end

    dialogo.add_action_callback("licenciaLogout") do |_action_context|
      Modular3D::License.logout
      enviar_estado_licencia.call(ok: false, code: "LOGIN_REQUIRED", message: "Sesión cerrada.")
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
      alto_ajuste = (datos['alto_ajuste'] || 60).to_f.mm
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
      @offset_creacion = actualizar_existente ? @offset_edicion : offset_siguiente_modulo
      @datos_modulo_actual = datos.reject { |clave, _valor| clave.to_s.start_with?("__") || clave.to_s == 'view_snapshot' }
      @modulo_uuid_actual = datos['__manifest_uuid'].to_s unless datos['__manifest_uuid'].to_s.empty?
      @modulo_uuid_actual = @datos_modulo_actual['module_uuid'].to_s if @modulo_uuid_actual.to_s.empty? && !@datos_modulo_actual['module_uuid'].to_s.empty?
      @modulo_uuid_actual = SecureRandom.uuid if @modulo_uuid_actual.to_s.empty?
      @datos_modulo_actual['module_uuid'] = @modulo_uuid_actual
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

      ancho_base = montaje_inferior == "EXTERIOR" ? ancho_total : ancho_util_mueble
      x_base = montaje_inferior == "EXTERIOR" ? 0.mm : grosor_lat_izq
      prof_base = prof_total - retranqueo_frontal_inferior - retranqueo_trasero_inferior
      self.crear_pieza(entities, modulo_nombre, "BASE", ancho_base, prof_base, grosor_inferior, x_base, retranqueo_frontal_inferior, 0, hz_l, hz_c) if existe_base

      ancho_techo = montaje_superior == "EXTERIOR" ? ancho_total : ancho_util_mueble
      x_techo = montaje_superior == "EXTERIOR" ? 0.mm : grosor_lat_izq
      prof_techo = prof_total - retranqueo_frontal_superior - retranqueo_trasero_superior
      z_techo = alto_total - grosor_superior
      self.crear_pieza(entities, modulo_nombre, "TECHO", ancho_techo, prof_techo, grosor_superior, x_techo, retranqueo_frontal_superior, z_techo, hz_l, hz_c) if existe_techo

      respaldo_estructural = grosor_resp >= 15.mm
      cantidad_ajustes = 0
      if lleva_respaldo != "NO" && !respaldo_estructural
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
          if enc['left']
            rf = ret_frontal_de.call('Izq'); rt = ret_trasera_de.call('Izq')
            self.crear_pieza(entities, modulo_nombre, "H_CIERRE_IZQ_#{nid}", espesor, d - rf - rt, h, x, y + rf, z, 1, 1)
          end
          if enc['right']
            rf = ret_frontal_de.call('Der'); rt = ret_trasera_de.call('Der')
            self.crear_pieza(entities, modulo_nombre, "H_CIERRE_DER_#{nid}", espesor, d - rf - rt, h, x + w - espesor, y + rf, z, 1, 1)
          end
          if enc['bottom']
            rf = ret_frontal_de.call('Inferior'); rt = ret_trasera_de.call('Inferior')
            self.crear_pieza(entities, modulo_nombre, "H_BASE_#{nid}", w, d - rf - rt, espesor, x, y + rf, z, 1, 0)
          end
          if enc['top']
            if enc['topMode'].to_s.upcase == 'TRAVESANOS'
              # Cierre superior alternativo: 2 travesaños (adelante y atras) en
              # vez de un techo completo -- ahorra material cuando no hace
              # falta un panel entero encima (p. ej. debajo de una encimera).
              # No aplica sobremedida: son listones angostos, no un panel.
              ancho_trav = [(enc['topTravesano'] || 70).to_f, 20.0].max.mm
              self.crear_pieza(entities, modulo_nombre, "H_TRAV_DEL_#{nid}", w, ancho_trav, espesor, x, y, z + h - espesor, 1, 0)
              self.crear_pieza(entities, modulo_nombre, "H_TRAV_TRAS_#{nid}", w, ancho_trav, espesor, x, y + d - ancho_trav, z + h - espesor, 1, 0)
            else
              rf = ret_frontal_de.call('Superior'); rt = ret_trasera_de.call('Superior')
              self.crear_pieza(entities, modulo_nombre, "H_TECHO_#{nid}", w, d - rf - rt, espesor, x, y + rf, z + h - espesor, 1, 0)
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
          if contenido == 'REPISAS'
            cantidad = [[node['shelves'].to_i, 1].max, 20].min
            distancia = (alto_nodo - (cantidad * espesor)) / (cantidad + 1)
            (1..cantidad).each do |ri|
              z_rep = z_min + (ri * distancia) + ((ri - 1) * espesor)
              self.crear_pieza(entities, modulo_nombre, "H_REP_LOCAL_#{nid}_#{ri}", ancho_nodo, fondo_nodo, espesor, x_min, y_min, z_rep, 1, 0)
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
            estilo_frente = frente_cajon_activo ? (node['drawerFrontStyle'] || 'POR_CAJON').to_s.upcase : 'POR_CAJON'
            fuga_frente_ext = ([(node['gap'] || 3).to_f, 0.5].max / 2.0).mm
            # El frente de cajon se alinea al mismo plano/ancho que tendria una
            # puerta ahi (front_box, calculado en JS con el mismo solape sobre
            # el casco/division que usan las puertas): asi los frentes salen
            # del hueco interno del cajon y solapan los laterales igual que
            # una puerta vecina, en vez de quedarse angostos dentro de su
            # propio espacio disponible.
            frente_box_cajon = node['front_box'].is_a?(Hash) ? node['front_box'] : nil
            frente_x_min = frente_box_cajon ? frente_box_cajon['x'].to_f.mm : x_min
            frente_ancho = frente_box_cajon ? frente_box_cajon['w'].to_f.mm : ancho_nodo
            frente_z_min = frente_box_cajon ? frente_box_cajon['z'].to_f.mm : z_min
            frente_alto = frente_box_cajon ? frente_box_cajon['h'].to_f.mm : alto_nodo

            if frente_cajon_activo && estilo_frente == 'FALSO'
              ancho_falso = frente_ancho - (fuga_frente_ext * 2)
              alto_falso = frente_alto - (fuga_frente_ext * 2)
              if ancho_falso > 0.mm && alto_falso > 0.mm
                self.crear_pieza(entities, modulo_nombre, "H_CJ_#{nid}_FRENTE_FALSO", ancho_falso, espesor, alto_falso,
                  frente_x_min + fuga_frente_ext, -espesor, frente_z_min + fuga_frente_ext, 2, 2)
              end
            else
            cantidad = [[node['drawers'].to_i, 1].max, 12].min
            # Espacio mecanico entre cajones: 1.5mm por defecto (misma fuga
            # que usan las puertas), aplicado entre cajon y cajon y entre el
            # primero/ultimo y la base/techo/repisa que los encierra. Editable
            # por espacio con "Espacio entre cajones" -- si el sistema de
            # corredera necesita mas holgura mecanica real, se sube ahi.
            fuga_h = [(node['drawerGap'] || 1.5).to_f, 0.5].max.mm
            holgura = 13.mm
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
                self.crear_pieza(grupo_cajon.entities, modulo_nombre, "#{prefix}_FRENTE", ancho_caja - (espesor * 2), espesor, altura_caja, espesor, 0.mm, 0.mm, 1, 0)
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
                  # La zona que le toca cubrir a ESTE frente va hasta la MITAD
                  # de la fuga mecanica (fuga_h, hoy 30mm por defecto) con el
                  # cajon vecino -- no hasta el borde de su propia caja -- para
                  # que el frente se trague ese hueco mecanico por completo y
                  # solo deje una junta fina y fija de 3mm (1.5+1.5) contra el
                  # frente vecino, sin importar cuanta fuga mecanica se pida
                  # entre cajones. Contra el borde real del espacio (arriba del
                  # todo o abajo del todo) deja el mismo 1.5mm, igual que
                  # contra una puerta vecina en otro nodo. UNICO_INFERIOR
                  # siempre usa el espacio completo, ignorando las cajas
                  # intermedias que tapa.
                  # Los bordes exteriores (arriba del primero, abajo del
                  # ultimo) llegan hasta frente_z_min/frente_alto -- el mismo
                  # plano que tendria una puerta ahi -- en vez de quedarse en
                  # el borde del hueco interno del cajon.
                  if estilo_frente == 'UNICO_INFERIOR'
                    zona_inferior = frente_z_min
                    zona_superior = frente_z_min + frente_alto
                  else
                    zona_inferior = ci == 1 ? frente_z_min : (base_z - (fuga_h / 2.0))
                    zona_superior = ci == cantidad ? (frente_z_min + frente_alto) : (base_z + altura_caja + (fuga_h / 2.0))
                  end
                  ancho_frente_ext = frente_ancho - (fuga_frente_ext * 2)
                  alto_frente_ext = (zona_superior - zona_inferior) - (fuga_frente_ext * 2)
                  z_frente_local = (zona_inferior - base_z) + fuga_frente_ext
                  if ancho_frente_ext > 0.mm && alto_frente_ext > 0.mm
                    self.crear_pieza(grupo_cajon.entities, modulo_nombre, "#{prefix}_FRENTE_EXT", ancho_frente_ext, espesor, alto_frente_ext,
                      (frente_x_min + fuga_frente_ext) - base_x, -espesor - y_min, z_frente_local, 2, 2)
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
            y_puerta = puerta_interna ? box['y'].to_f.mm + 2.mm : (externa_embutida ? 0.mm : -grosor_puerta)
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
            # DEBUG TEMPORAL (a retirar en cuanto se confirme el fix del bug
            # "puerta derecha/izq aparece desplazada"): compara la posicion
            # que se le pidio a crear_pieza contra los bounds reales de la
            # instancia ya insertada en el modelo. Se ve en Window > Ruby
            # Console. No cambia ningun comportamiento, solo imprime.
            if instancia_puerta && instancia_puerta.respond_to?(:bounds)
              bp = instancia_puerta.bounds
              puts "[Modular_3D DEBUG puerta] #{nombre_puerta} lado=#{lado_bisagra_puerta} esperado x=#{x_puerta_izq.to_mm.round(1)}mm y=#{y_puerta.to_mm.round(1)}mm z=#{(z_min + margen_lateral).to_mm.round(1)}mm ancho=#{ancho_puerta.to_mm.round(1)}mm alto=#{alto_puerta.to_mm.round(1)}mm | bounds_real min=(#{bp.min.x.to_mm.round(1)}, #{bp.min.y.to_mm.round(1)}, #{bp.min.z.to_mm.round(1)}) max=(#{bp.max.x.to_mm.round(1)}, #{bp.max.y.to_mm.round(1)}, #{bp.max.z.to_mm.round(1)})"
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
            (1..cantidad).each do |pi|
              pieza = self.crear_pieza(entities, modulo_nombre, "G_PUERTA_EXT_#{pi}", ancho_puerta, grosor_puerta, alto_puerta,
                fuga_izq + ((pi - 1) * (ancho_puerta + fuga_central)), -grosor_puerta, fuga_inf, 2, 2)
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
        holgura_lateral = if sistema_corredera.downcase.include?("oculta")
                            21.mm
                          elsif sistema_corredera.downcase.include?("maximo")
                            15.mm
                          else
                            13.mm
                          end
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
            self.crear_pieza(entities, modulo_nombre, "CJ_#{contador_cajon}_FRENTE", ancho_frente_cajon, prof_frente_cajon, alto_frente_cajon, x_cj_frente, retiro_cajones, z_inicio_cajon, 1, 0)
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
        model.set_attribute('Modular3DViews', @modulo_despiece_actual.to_s, datos['view_snapshot'].to_s)
        model.set_attribute('Modular3DViewCameras', @modulo_despiece_actual.to_s, datos['view_camera_json'].to_s)
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
