# frozen_string_literal: true

module LPenafiel_GeneradorMueblesExacto
  # v6 §Fase D-1: motor de inventario de piezas REALES para el plano 2D
  # (elevaciones, planta, corte, isométrica, explosionado), calculado SOLO a
  # partir de `datos` (el mismo Hash que llega a "ejecutarConstruccionMueble")
  # y de `hierarchy_geometry` (el mismo hierarchy_geometry_json ya guardado en
  # el manifiesto) -- sin necesidad de que el módulo esté construido en
  # SketchUp. Es deliberadamente un CÁLCULO PARALELO, no una lectura de
  # entidades: reproduce en Ruby puro (Float, milímetros) las mismas fórmulas
  # que "ejecutarConstruccionMueble" (core/jerarquia.rb) usa para fabricar
  # cada pieza real, para que el plano coincida siempre con lo que el plugin
  # construiría con esos mismos datos.
  #
  # A propósito, deja FUERA del inventario (documentado, no oculto):
  # - El interior mecánico de cada cajón (laterales/frente/post/fondo): queda
  #   escondido detrás de su frente en cualquier vista externa (elevación,
  #   isométrica cerrada); sí se dibuja el FRENTE visible de cada cajón.
  # - Herrajes (bisagras/correderas): ya tienen su propio dominio en
  #   despiece.rb/presupuesto.rb: una elevación o isométrica técnica de este
  #   tipo no acostumbra mostrar el herraje individual.
  # - Repisas/divisiones del configurador legado (num_repisas/num_divisiones
  #   sin jerarquía): igual que el resto del plano 2D (ver plano2d.rb), el
  #   plano solo está disponible para módulos con hierarchy_geometry_json.
  module VistaPrevia2D
    module_function

    def f(valor, defecto = 0.0)
      (valor.nil? || valor.to_s.strip.empty?) ? defecto.to_f : valor.to_f
    end

    def si?(valor, defecto = 'SI')
      (valor.nil? || valor.to_s.strip.empty? ? defecto : valor.to_s) != 'NO'
    end

    # Devuelve { 'envolvente' => {...}, 'piezas' => [ {codigo,grupo,contenido,
    # x,y,z,w,d,h} ... ] }, todo en milímetros (Float), mismo sistema de
    # coordenadas que el resto del plugin (X=ancho, Y=profundidad con el
    # frente hacia Y negativo, Z=altura).
    def calcular_inventario_piezas(datos, hierarchy_geometry)
      piezas = []
      agregar = lambda do |codigo, grupo, x, y, z, w, d, h, extra = {}|
        next if w <= 0 || d <= 0 || h <= 0
        piezas << { 'codigo' => codigo, 'grupo' => grupo, 'x' => x, 'y' => y, 'z' => z, 'w' => w, 'd' => d, 'h' => h }.merge(extra)
      end

      ancho_total = f(datos['ancho_total'], 600)
      alto_total = f(datos['alto_total'], 760)
      prof_total = f(datos['prof_total'], 580)
      espesor = f(datos['espesor'], 15)
      grosor_lat_izq = f(datos['grosor_izq'], espesor)
      grosor_lat_der = f(datos['grosor_der'], espesor)
      grosor_superior = f(datos['grosor_superior'], espesor)
      grosor_inferior = f(datos['grosor_inferior'], espesor)

      montaje_superior = (datos['montaje_superior'] || 'INTERIOR').to_s
      montaje_inferior = (datos['montaje_inferior'] || 'INTERIOR').to_s
      montaje_izq = (datos['montaje_izq'] || 'EXTERIOR').to_s
      montaje_der = (datos['montaje_der'] || 'EXTERIOR').to_s
      if montaje_izq != 'INTERIOR' || montaje_der != 'INTERIOR'
        montaje_superior = 'INTERIOR' if montaje_superior == 'EXTERIOR'
        montaje_inferior = 'INTERIOR' if montaje_inferior == 'EXTERIOR'
      end

      sobremedida_frontal_superior = f(datos['sobremedida_frontal_superior'])
      sobremedida_trasera_superior = f(datos['sobremedida_trasera_superior'])
      sobremedida_frontal_inferior = f(datos['sobremedida_frontal_inferior'])
      sobremedida_trasera_inferior = f(datos['sobremedida_trasera_inferior'])
      sobremedida_frontal_izq = f(datos['sobremedida_frontal_izq'])
      sobremedida_trasera_izq = f(datos['sobremedida_trasera_izq'])
      sobremedida_frontal_der = f(datos['sobremedida_frontal_der'])
      sobremedida_trasera_der = f(datos['sobremedida_trasera_der'])
      retranqueo_frontal_superior = -sobremedida_frontal_superior
      retranqueo_trasero_superior = -sobremedida_trasera_superior
      retranqueo_frontal_inferior = -sobremedida_frontal_inferior
      retranqueo_trasero_inferior = -sobremedida_trasera_inferior
      retranqueo_frontal_izq = -sobremedida_frontal_izq
      retranqueo_trasero_izq = -sobremedida_trasera_izq
      retranqueo_frontal_der = -sobremedida_frontal_der
      retranqueo_trasero_der = -sobremedida_trasera_der

      puerta_protrusion_override_raw = datos['puerta_protrusion_override_mm'].to_s.strip
      puerta_protrusion_override = puerta_protrusion_override_raw.empty? ? nil : [puerta_protrusion_override_raw.to_f, 0.0].max

      existe_lat_izq = si?(datos['lleva_lateral_izq'])
      existe_lat_der = si?(datos['lleva_lateral_der'])
      existe_base = si?(datos['lleva_base'])
      existe_techo = si?(datos['lleva_techo'])

      ancho_interno = ancho_total - grosor_lat_izq - grosor_lat_der
      ancho_util_mueble = ancho_interno - (datos['madeval'] == 'SI' ? 1.0 : 0.0)

      # --- Envolvente: laterales ---
      prof_lat_izq = prof_total - retranqueo_frontal_izq - retranqueo_trasero_izq
      prof_lat_der = prof_total - retranqueo_frontal_der - retranqueo_trasero_der
      alto_lat_izq = montaje_izq == 'INTERIOR' ? (alto_total - grosor_superior - grosor_inferior) : alto_total
      alto_lat_der = montaje_der == 'INTERIOR' ? (alto_total - grosor_superior - grosor_inferior) : alto_total
      z_lat_izq = montaje_izq == 'INTERIOR' ? grosor_inferior : 0.0
      z_lat_der = montaje_der == 'INTERIOR' ? grosor_inferior : 0.0
      agregar.call('LAT_IZQ', 'CASCO', 0.0, retranqueo_frontal_izq, z_lat_izq, grosor_lat_izq, prof_lat_izq, alto_lat_izq) if existe_lat_izq
      agregar.call('LAT_DER', 'CASCO', ancho_total - grosor_lat_der, retranqueo_frontal_der, z_lat_der, grosor_lat_der, prof_lat_der, alto_lat_der) if existe_lat_der

      # --- Envolvente: base/techo (panel completo o 2 travesaños) ---
      base_modo_general = (datos['tipo_inferior'] || 'FULL').to_s.upcase
      techo_modo_general = (datos['tipo_superior'] || 'FULL').to_s.upcase
      ancho_base = montaje_inferior == 'EXTERIOR' ? ancho_total : ancho_util_mueble
      x_base = montaje_inferior == 'EXTERIOR' ? 0.0 : grosor_lat_izq
      prof_base = prof_total - retranqueo_frontal_inferior - retranqueo_trasero_inferior
      if existe_base
        if base_modo_general == 'TRAVESANOS'
          ancho_trav_base = [f(datos['travesano_ancho_inferior'], 70), 20.0].max
          agregar.call('BASE_TRAV_DEL', 'TRAVESANO', x_base, 0.0, 0.0, ancho_base, ancho_trav_base, grosor_inferior)
          agregar.call('BASE_TRAV_TRAS', 'TRAVESANO', x_base, prof_total - ancho_trav_base, 0.0, ancho_base, ancho_trav_base, grosor_inferior)
        else
          agregar.call('BASE', 'CASCO', x_base, retranqueo_frontal_inferior, 0.0, ancho_base, prof_base, grosor_inferior)
        end
      end
      ancho_techo = montaje_superior == 'EXTERIOR' ? ancho_total : ancho_util_mueble
      x_techo = montaje_superior == 'EXTERIOR' ? 0.0 : grosor_lat_izq
      prof_techo = prof_total - retranqueo_frontal_superior - retranqueo_trasero_superior
      z_techo = alto_total - grosor_superior
      if existe_techo
        if techo_modo_general == 'TRAVESANOS'
          ancho_trav_techo = [f(datos['travesano_ancho_superior'], 70), 20.0].max
          agregar.call('TECHO_TRAV_DEL', 'TRAVESANO', x_techo, 0.0, z_techo, ancho_techo, ancho_trav_techo, grosor_superior)
          agregar.call('TECHO_TRAV_TRAS', 'TRAVESANO', x_techo, prof_total - ancho_trav_techo, z_techo, ancho_techo, ancho_trav_techo, grosor_superior)
        else
          agregar.call('TECHO', 'CASCO', x_techo, retranqueo_frontal_superior, z_techo, ancho_techo, prof_techo, grosor_superior)
        end
      end

      # --- Ajustes (posterior y frontal) ---
      cantidad_ajustes_raw = (datos['cantidad_ajustes'] || 'AUTO').to_s.upcase
      alto_ajuste = f(datos['alto_ajuste'], 60)
      grosor_ajuste = f(datos['grosor_ajuste'], espesor)
      separacion_ajuste_respaldo = f(datos['separacion_ajuste_respaldo'], 2)
      distancia_plano_posterior = f(datos['distancia_plano_posterior'], 0)
      grosor_resp = f(datos['grosor_resp'], 6)
      respaldo_estructural = grosor_resp >= 15.0
      lleva_respaldo = (datos['lleva_respaldo'] || 'SI').to_s
      cantidad_ajustes = 0
      if lleva_respaldo != 'NO' && !respaldo_estructural
        cantidad_ajustes = cantidad_ajustes_raw == 'AUTO' ? (alto_total > 760.0 ? 2 : 1) : cantidad_ajustes_raw.to_i
        cantidad_ajustes = [[cantidad_ajustes, 0].max, 4].min
      end
      y_ajuste = prof_total - distancia_plano_posterior - grosor_ajuste
      z_superior_ajuste = alto_total - grosor_superior - alto_ajuste
      agregar_escuadras = lambda do |prefijo, y_inicio|
        agregar.call("#{prefijo}_ESCUADRA_IZQ", 'AJUSTE', grosor_lat_izq, y_inicio, z_superior_ajuste, grosor_ajuste, alto_ajuste, grosor_ajuste)
        agregar.call("#{prefijo}_ESCUADRA_DER", 'AJUSTE', ancho_total - grosor_lat_der - grosor_ajuste, y_inicio, z_superior_ajuste, grosor_ajuste, alto_ajuste, grosor_ajuste)
      end
      if cantidad_ajustes > 0
        if (datos['ajuste_posterior_orientacion'] || 'HORIZONTAL').to_s.upcase == 'VERTICAL'
          agregar_escuadras.call('AJUSTE_POSTERIOR', y_ajuste)
        else
          agregar.call('AJUSTE_SUPERIOR', 'AJUSTE', grosor_lat_izq, y_ajuste, z_superior_ajuste, ancho_util_mueble, grosor_ajuste, alto_ajuste)
        end
        if cantidad_ajustes > 1
          (2..cantidad_ajustes).each do |idx|
            espacio_posterior = alto_total - grosor_superior - grosor_inferior - alto_ajuste
            fraccion = idx == 2 ? 0.5 : (cantidad_ajustes - idx + 1).to_f / cantidad_ajustes
            z_ajuste = grosor_inferior + (espacio_posterior * fraccion) - (alto_ajuste / 2)
            z_ajuste = [[z_ajuste, grosor_inferior].max, z_superior_ajuste - alto_ajuste].min
            agregar.call("AJUSTE_POSTERIOR_#{idx - 1}", 'AJUSTE', grosor_lat_izq, y_ajuste, z_ajuste, ancho_util_mueble, grosor_ajuste, alto_ajuste)
          end
        end
      end
      if (datos['ajuste_frontal_activo'] || 'NO').to_s == 'SI'
        if (datos['ajuste_frontal_orientacion'] || 'HORIZONTAL').to_s.upcase == 'VERTICAL'
          agregar_escuadras.call('AJUSTE_FRONTAL', 0.0)
        else
          agregar.call('AJUSTE_FRONTAL', 'AJUSTE', grosor_lat_izq, 0.0, z_superior_ajuste, ancho_util_mueble, grosor_ajuste, alto_ajuste)
        end
      end

      # --- Respaldo ---
      if lleva_respaldo == 'SI'
        profundidad_ranura = f(datos['profundidad_ranura'], 5)
        ancho_respaldo = ancho_interno + (profundidad_ranura * 2)
        alto_respaldo = (alto_total - grosor_superior - grosor_inferior) + (profundidad_ranura * 2)
        espacio_libre_atras = respaldo_estructural ? (distancia_plano_posterior + grosor_resp) : (distancia_plano_posterior + grosor_ajuste + separacion_ajuste_respaldo + grosor_resp)
        agregar.call('RESPALDO', 'RESPALDO', grosor_lat_izq - profundidad_ranura, prof_total - espacio_libre_atras, grosor_inferior - profundidad_ranura, ancho_respaldo, grosor_resp, alto_respaldo)
      elsif lleva_respaldo == 'INTERNO'
        y_respaldo = respaldo_estructural ? (prof_total - distancia_plano_posterior - grosor_resp) : (y_ajuste - separacion_ajuste_respaldo - grosor_resp)
        agregar.call('RESPALDO_INTERNO', 'RESPALDO', grosor_lat_izq, y_respaldo, grosor_inferior, ancho_interno, grosor_resp, alto_total - grosor_superior - grosor_inferior)
      elsif lleva_respaldo == 'SOBREPUESTO'
        holgura = 1.5
        agregar.call('RESPALDO_SOBREPUESTO', 'RESPALDO', holgura, prof_total - distancia_plano_posterior - grosor_resp, holgura, ancho_total - (holgura * 2), grosor_resp, alto_total - (holgura * 2))
      end

      calcular_protrusion_puerta = lambda do |cav_x_min, cav_x_max, cav_z_min, cav_z_max, enc_nodo, sob_nodo, grosor_puerta_local|
        next puerta_protrusion_override if puerta_protrusion_override
        eps = 0.5
        candidatos = [grosor_puerta_local]
        candidatos << sobremedida_frontal_izq if existe_lat_izq && (cav_x_min - grosor_lat_izq).abs <= eps
        candidatos << sobremedida_frontal_der if existe_lat_der && (cav_x_max - (ancho_total - grosor_lat_der)).abs <= eps
        candidatos << sobremedida_frontal_inferior if existe_base && base_modo_general != 'TRAVESANOS' && (cav_z_min - grosor_inferior).abs <= eps
        candidatos << sobremedida_frontal_superior if existe_techo && techo_modo_general != 'TRAVESANOS' && (cav_z_max - (alto_total - grosor_superior)).abs <= eps
        if enc_nodo.is_a?(Hash)
          sob_nodo = {} unless sob_nodo.is_a?(Hash)
          candidatos << f(sob_nodo['frontalIzq']) if enc_nodo['left']
          candidatos << f(sob_nodo['frontalDer']) if enc_nodo['right']
          candidatos << f(sob_nodo['frontalInferior']) if enc_nodo['bottom']
          candidatos << f(sob_nodo['frontalSuperior']) if enc_nodo['top'] && enc_nodo['topMode'].to_s.upcase != 'TRAVESANOS'
        end
        candidatos.max
      end

      if hierarchy_geometry.is_a?(Hash) && hierarchy_geometry['nodes'].is_a?(Array)
        # Separadores físicos (divisores/repisas de la jerarquía).
        separadores_por_padre = Hash.new(0)
        (hierarchy_geometry['separators'] || []).each do |separador|
          next unless separador.is_a?(Hash)
          ancho_s = f(separador['w']); fondo_s = f(separador['d']); alto_s = f(separador['h'])
          next if ancho_s <= 0 || fondo_s <= 0 || alto_s <= 0
          axis = separador['axis'].to_s.upcase
          padre_id = LPenafiel_GeneradorMueblesExacto.id_pieza_jerarquia(separador['parent'], 'ROOT')
          separadores_por_padre[padre_id] += 1
          sufijo = "#{padre_id}_#{separadores_por_padre[padre_id]}"
          codigo = axis == 'X' ? "H_DIV_X_#{sufijo}" : (axis == 'Z' ? "H_REP_Z_#{sufijo}" : "H_DIV_Y_#{sufijo}")
          agregar.call(codigo, 'DIVISOR', f(separador['x']), f(separador['y']), f(separador['z']), ancho_s, fondo_s, alto_s)
        end

        # Cierres de cada espacio (montaje interior/sobrepuesto por nodo).
        hierarchy_geometry['nodes'].each_with_index do |node, node_index|
          next unless node.is_a?(Hash) && node['box'].is_a?(Hash) && node['enclosure'].is_a?(Hash)
          box = node['box']; enc = node['enclosure']
          x = f(box['x']); y = f(box['y']); z = f(box['z']); w = f(box['w']); d = f(box['d']); h = f(box['h'])
          nid = LPenafiel_GeneradorMueblesExacto.id_pieza_jerarquia(node['id'], "IDX#{node_index + 1}")
          sob = node['sobremedida'].is_a?(Hash) ? node['sobremedida'] : {}
          rf = lambda { |clave| -f(sob["frontal#{clave}"]) }
          rt = lambda { |clave| -f(sob["trasera#{clave}"]) }
          mount_izq_nodo = (enc['leftMount'] || 'EXTERIOR').to_s.upcase
          mount_der_nodo = (enc['rightMount'] || 'EXTERIOR').to_s.upcase
          mount_inf_nodo = (enc['bottomMount'] || 'INTERIOR').to_s.upcase
          mount_sup_nodo = (enc['topMount'] || 'INTERIOR').to_s.upcase
          if mount_izq_nodo != 'INTERIOR' || mount_der_nodo != 'INTERIOR'
            mount_inf_nodo = 'INTERIOR' if mount_inf_nodo == 'EXTERIOR'
            mount_sup_nodo = 'INTERIOR' if mount_sup_nodo == 'EXTERIOR'
          end
          if enc['left']
            rfv = rf.call('Izq'); rtv = rt.call('Izq')
            alto_izq_nodo = mount_izq_nodo == 'INTERIOR' ? (h - (enc['bottom'] ? espesor : 0.0) - (enc['top'] ? espesor : 0.0)) : h
            z_izq_nodo = mount_izq_nodo == 'INTERIOR' && enc['bottom'] ? z + espesor : z
            agregar.call("H_CIERRE_IZQ_#{nid}", 'NODO_PANEL', x, y + rfv, z_izq_nodo, espesor, d - rfv - rtv, alto_izq_nodo)
          end
          if enc['right']
            rfv = rf.call('Der'); rtv = rt.call('Der')
            alto_der_nodo = mount_der_nodo == 'INTERIOR' ? (h - (enc['bottom'] ? espesor : 0.0) - (enc['top'] ? espesor : 0.0)) : h
            z_der_nodo = mount_der_nodo == 'INTERIOR' && enc['bottom'] ? z + espesor : z
            agregar.call("H_CIERRE_DER_#{nid}", 'NODO_PANEL', x + w - espesor, y + rfv, z_der_nodo, espesor, d - rfv - rtv, alto_der_nodo)
          end
          if enc['bottom']
            rfv = rf.call('Inferior'); rtv = rt.call('Inferior')
            ancho_base_nodo = mount_inf_nodo == 'INTERIOR' ? (w - (enc['left'] ? espesor : 0.0) - (enc['right'] ? espesor : 0.0)) : w
            x_base_nodo = mount_inf_nodo == 'INTERIOR' && enc['left'] ? x + espesor : x
            agregar.call("H_BASE_#{nid}", 'NODO_PANEL', x_base_nodo, y + rfv, z, ancho_base_nodo, d - rfv - rtv, espesor)
          end
          if enc['top']
            ancho_top_nodo = mount_sup_nodo == 'INTERIOR' ? (w - (enc['left'] ? espesor : 0.0) - (enc['right'] ? espesor : 0.0)) : w
            x_top_nodo = mount_sup_nodo == 'INTERIOR' && enc['left'] ? x + espesor : x
            if enc['topMode'].to_s.upcase == 'TRAVESANOS'
              ancho_trav = [f(enc['topTravesano'], 70), 20.0].max
              agregar.call("H_TRAV_DEL_#{nid}", 'TRAVESANO', x_top_nodo, y, z + h - espesor, ancho_top_nodo, ancho_trav, espesor)
              agregar.call("H_TRAV_TRAS_#{nid}", 'TRAVESANO', x_top_nodo, y + d - ancho_trav, z + h - espesor, ancho_top_nodo, ancho_trav, espesor)
            else
              rfv = rf.call('Superior'); rtv = rt.call('Superior')
              agregar.call("H_TECHO_#{nid}", 'NODO_PANEL', x_top_nodo, y + rfv, z + h - espesor, ancho_top_nodo, d - rfv - rtv, espesor)
            end
          end
          agregar.call("H_RESP_#{nid}", 'RESPALDO', x, y + d - grosor_resp, z, w, grosor_resp, h) if enc['back']
        end

        # Repisas y frentes visibles de cajones por espacio hoja.
        leaf_nodes = hierarchy_geometry['nodes'].select { |node| node.is_a?(Hash) && (!node['children'].is_a?(Array) || node['children'].empty?) }
        leaf_nodes.each_with_index do |node, node_index|
          box = node['box'] || {}
          x_min = f(box['x']); y_min = f(box['y']); z_min = f(box['z'])
          ancho_nodo = f(box['w']); fondo_nodo = f(box['d']); alto_nodo = f(box['h'])
          next if ancho_nodo <= 0 || fondo_nodo <= 0 || alto_nodo <= 0
          nid = LPenafiel_GeneradorMueblesExacto.id_pieza_jerarquia(node['id'], "IDX#{node_index + 1}")
          contenido = node['content'].to_s.upcase
          tiene_puerta_interna_local = node['front'].to_s.upcase.include?('INTERNA')
          grosor_puerta_local = tiene_puerta_interna_local ? [f(datos['puerta_grosor'], espesor), 3.0].max : 0.0
          if contenido == 'REPISAS'
            cantidad = [[node['shelves'].to_i, 1].max, 20].min
            distancia = (alto_nodo - (cantidad * espesor)) / (cantidad + 1)
            fondo_repisa = fondo_nodo - grosor_puerta_local
            y_repisa = y_min + grosor_puerta_local
            if fondo_repisa > 0
              (1..cantidad).each do |ri|
                z_rep = z_min + (ri * distancia) + ((ri - 1) * espesor)
                agregar.call("H_REP_LOCAL_#{nid}_#{ri}", 'REPISA', x_min, y_repisa, z_rep, ancho_nodo, fondo_repisa, espesor)
              end
            end
          end
          next unless contenido.start_with?('CAJONES')
          alcance_frentes = (datos['external_front_scope'] || 'BY_SPACE').to_s.upcase
          sin_puerta_propia = node['front'].to_s.empty? || node['front'].to_s.upcase == 'NINGUNO'
          frente_cajon_activo = contenido == 'CAJONES_FRENTES' && alcance_frentes != 'GLOBAL' && sin_puerta_propia
          next unless frente_cajon_activo
          estilo_frente = (node['drawerFrontStyle'] || 'POR_CAJON').to_s.upcase
          fuga_frente_ext = [f(node['gap'], 3), 0.5].max
          frente_box_cajon = node['front_box'].is_a?(Hash) ? node['front_box'] : nil
          frente_x_min = frente_box_cajon ? f(frente_box_cajon['x']) : x_min
          frente_ancho = frente_box_cajon ? f(frente_box_cajon['w']) : ancho_nodo
          frente_z_min = frente_box_cajon ? f(frente_box_cajon['z']) : z_min
          frente_alto = frente_box_cajon ? f(frente_box_cajon['h']) : alto_nodo
          # FALSO y UNICO_INFERIOR son, en los hechos, el mismo caso que
          # POR_CAJON con "1 frente visible": un único frente que cubre todo
          # el alto disponible (ver jerarquia.rb ~L730-736 y ~L737-742: con
          # cantidad_frentes_visibles = 1, altura_frente_uniforme = frente_alto,
          # que es exactamente lo que FALSO construye por su propio camino).
          cantidad_frentes_visibles = estilo_frente == 'POR_CAJON' ? [[node['drawers'].to_i, 1].max, 12].min : 1
          next if frente_ancho <= 0 || frente_alto <= 0
          altura_frente_uniforme = (frente_alto - (fuga_frente_ext * [cantidad_frentes_visibles - 1, 0].max)) / cantidad_frentes_visibles
          (1..cantidad_frentes_visibles).each do |fi|
            z_frente = frente_z_min + ((fi - 1) * (altura_frente_uniforme + fuga_frente_ext))
            agregar.call("H_CJ_#{nid}_FRENTE_#{fi}", 'FRENTE_CAJON', frente_x_min, -espesor, z_frente, frente_ancho, espesor, altura_frente_uniforme, 'contenido' => 'CAJONES')
          end
        end

        # Puertas por espacio (internas y externas).
        hierarchy_geometry['nodes'].each_with_index do |node, node_index|
          next unless node.is_a?(Hash)
          frente = node['front'].to_s.upcase
          frente = 'PUERTA_UNICA' if node['content'].to_s.upcase == 'CAJONES_PUERTA' && frente == 'NINGUNO'
          next if frente.empty? || frente == 'NINGUNO'
          puerta_interna = frente.include?('INTERNA')
          alcance_frentes = (datos['external_front_scope'] || 'BY_SPACE').to_s.upcase
          next if !puerta_interna && alcance_frentes != 'BY_SPACE'
          box = node['box'] || {}
          fuga_h = [f(node['gap'], 3), 0.5].max
          x_min = f(box['x']); z_min = f(box['z']); ancho_nodo = f(box['w']); alto_nodo = f(box['h'])
          cavidad_x_min = x_min; cavidad_x_max = x_min + ancho_nodo
          cavidad_z_min = z_min; cavidad_z_max = z_min + alto_nodo
          frente = frente.gsub('_VIDRIO', '').gsub('VIDRIO', 'UNICA')
          cantidad_solicitada = node['frontCount'].to_s.upcase
          cantidad = if cantidad_solicitada != '' && cantidad_solicitada != 'AUTO'
                       [[cantidad_solicitada.to_i, 1].max, 8].min
                     else
                       [[(ancho_nodo / 600.0).ceil, 1].max, 8].min
                     end
          unless puerta_interna
            frente_box = node['front_box'].is_a?(Hash) ? node['front_box'] : nil
            if frente_box
              x_min = f(frente_box['x']); z_min = f(frente_box['z'])
              ancho_nodo = f(frente_box['w']); alto_nodo = f(frente_box['h'])
            elsif node['id'].to_s == 'root'
              x_min = 1.5; z_min = 1.5
              ancho_nodo = ancho_total - 3.0; alto_nodo = alto_total - 3.0
            end
            cantidad = [[(ancho_nodo / 600.0).ceil, 1].max, 8].min if cantidad_solicitada == '' || cantidad_solicitada == 'AUTO'
          end
          grosor_puerta = [f(datos['puerta_grosor'], espesor), 3.0].max
          fuga_central = [f(node['gapCenter'] || node['gap'], 3), 0.5].max
          margen_lateral = puerta_interna ? fuga_h : 0.0
          ancho_puerta = (ancho_nodo - (margen_lateral * 2) - (fuga_central * (cantidad - 1))) / cantidad
          alto_puerta = alto_nodo - (margen_lateral * 2)
          next if ancho_puerta <= 0 || alto_puerta <= 0
          nid_puerta = LPenafiel_GeneradorMueblesExacto.id_pieza_jerarquia(node['id'], "IDX#{node_index + 1}")
          externa_embutida = !puerta_interna && (datos['montaje_puerta'] || 'SOLAPADA').to_s.upcase == 'EMBUTIDA'
          (1..cantidad).each do |pi|
            protrusion_puerta = (puerta_interna || externa_embutida) ? grosor_puerta : calcular_protrusion_puerta.call(cavidad_x_min, cavidad_x_max, cavidad_z_min, cavidad_z_max, node['enclosure'], node['sobremedida'], grosor_puerta)
            y_puerta = puerta_interna ? f(box['y']) + 2.0 : (externa_embutida ? 0.0 : -protrusion_puerta)
            x_puerta_izq = x_min + margen_lateral + ((pi - 1) * (ancho_puerta + fuga_central))
            agregar.call("H_PUERTA_#{puerta_interna ? 'INT' : 'EXT'}_#{nid_puerta}_#{pi}", 'PUERTA', x_puerta_izq, y_puerta, z_min + margen_lateral, ancho_puerta, grosor_puerta, alto_puerta)
          end
        end

        # Frente exterior global.
        if (datos['external_front_scope'] || 'BY_SPACE').to_s.upcase == 'GLOBAL'
          modo = (datos['global_front_count_mode'] || 'AUTO').to_s.upcase
          maximo = [[f(datos['global_front_auto_width'], 600), 100.0].max, ancho_total].min
          cantidad = modo == 'MANUAL' ? f(datos['global_front_count'], 1).to_i : (ancho_total / maximo).ceil
          cantidad = [[cantidad, 1].max, 8].min
          fuga_izq = [f(datos['global_front_gap_left'], 3), 0.0].max
          fuga_der = [f(datos['global_front_gap_right'], 3), 0.0].max
          fuga_sup = [f(datos['global_front_gap_top'], 3), 0.0].max
          fuga_inf = [f(datos['global_front_gap_bottom'], 3), 0.0].max
          fuga_central = [f(datos['global_front_gap_center'], 3), 0.0].max
          grosor_puerta = [f(datos['puerta_grosor'], espesor), 3.0].max
          ancho_puerta = (ancho_total - fuga_izq - fuga_der - (fuga_central * (cantidad - 1))) / cantidad
          alto_puerta = alto_total - fuga_sup - fuga_inf
          if ancho_puerta > 0 && alto_puerta > 0
            protrusion_global = calcular_protrusion_puerta.call(grosor_lat_izq, ancho_total - grosor_lat_der, grosor_inferior, alto_total - grosor_superior, nil, nil, grosor_puerta)
            (1..cantidad).each do |pi|
              agregar.call("G_PUERTA_EXT_#{pi}", 'PUERTA', fuga_izq + ((pi - 1) * (ancho_puerta + fuga_central)), -protrusion_global, fuga_inf, ancho_puerta, grosor_puerta, alto_puerta)
            end
          end
        end
      end

      { 'envolvente' => { 'ancho_total' => ancho_total, 'alto_total' => alto_total, 'prof_total' => prof_total }, 'piezas' => piezas }
    end
  end
end
