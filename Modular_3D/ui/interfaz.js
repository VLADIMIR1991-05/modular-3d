    window.Modular3DLicense = {
      busy: false,
      receive: function(result) {
        result = result || {};
        this.busy = false;
        var button = document.getElementById('license_login');
        var message = document.getElementById('license_message');
        button.disabled = false;
        button.textContent = 'Entrar a Modular_3D';

        if (result.ok) {
          document.body.classList.remove('license-locked');
          document.getElementById('license_overlay').style.display = 'none';
          document.getElementById('license_session').classList.add('show');
          document.getElementById('license_identity').textContent = result.email || document.getElementById('license_email').value || 'Licencia activa';
          message.classList.remove('show');
          return;
        }

        var messages = {
          LOGIN_REQUIRED: 'Ingresa tus datos para activar Modular_3D.',
          INVALID_CREDENTIALS: 'Correo o contrasena incorrectos.',
          LICENSE_EXPIRED: 'La suscripcion esta vencida. Solicita una renovacion.',
          LICENSE_BLOCKED: 'La licencia fue bloqueada por el administrador.',
          DEVICE_CONFLICT: 'Esta licencia ya esta vinculada a otra computadora.',
          SERVER_UNAVAILABLE: 'No se pudo conectar al servidor de licencias. Verifica tu conexion a Internet.',
          TOKEN_EXPIRED: 'La sesion vencio. Inicia sesion nuevamente.'
        };
        document.body.classList.add('license-locked');
        document.getElementById('license_overlay').style.display = 'flex';
        document.getElementById('license_session').classList.remove('show');
        message.textContent = result.message || messages[result.code] || 'No se pudo validar la licencia.';
        message.classList.add('show');
      },
      login: function() {
        if (this.busy) return;
        var email = document.getElementById('license_email').value.trim();
        var password = document.getElementById('license_password').value;
        if (!email || !password) {
          this.receive({ ok: false, message: 'Completa el correo y la contrasena.' });
          return;
        }
        this.busy = true;
        var button = document.getElementById('license_login');
        button.disabled = true;
        button.textContent = 'Validando...';
        if (window.sketchup && sketchup.licenciaLogin) {
          sketchup.licenciaLogin(email, password, document.getElementById('license_transfer').checked);
        } else {
          this.receive({ ok: false, message: 'Esta validacion debe abrirse dentro de SketchUp.' });
        }
      },
      check: function() {
        if (window.sketchup && sketchup.licenciaEstado) sketchup.licenciaEstado();
      }
    };

    var presets = {
      BAJO: [600, 760, 580, 15, 1, 'NO'],
      ALTO: [600, 760, 320, 15, 1, 'NO'],
      CLOSET: [1200, 2120, 580, 15, 4, 'SI'],
      AUXILIAR: [600, 2120, 580, 15, 4, 'NO']
    };
    var paneles = [
      ['superior', 'Tapa superior'],
      ['inferior', 'Base inferior'],
      ['izq', 'Lateral izquierdo'],
      ['der', 'Lateral derecho']
    ];
    var selectedSpace = 0;
    // Estado independiente por celda. La clave usa el nicho contado desde abajo
    // y la columna desde la izquierda: "nicho:columna".
    var spaceState = {};
    var editMode = false;
    var syncingFields = false;
    var linkedThickness = {
      grosor_superior: true,
      grosor_inferior: true,
      grosor_izq: true,
      grosor_der: true,
      puerta_grosor: true,
      grosor_ajuste: true
    };
    var stepPages = ['inicial', 'paneles', 'interior', 'diseno'];
    var fieldCategories = {
      num_repisas: 'interior', num_divisiones: 'interior', retranqueo_interior: 'interior',
      lleva_respaldo: 'back', grosor_resp: 'back', profundidad_ranura: 'back', cantidad_ajustes: 'back', alto_ajuste: 'back',
      puerta_grosor: 'front', luz_frentes: 'front', ret_cajones: 'front',
      grosor_superior: 'top', grosor_inferior: 'horizontal', grosor_izq: 'lateral', grosor_der: 'lateral'
    };

    function el(id) { return document.getElementById(id); }
    function htmlSeguro(valor) {
      return String(valor == null ? '' : valor)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
    }
    function numero(id, fallback) {
      var value = parseFloat(el(id).value);
      return isFinite(value) ? value : (fallback || 0);
    }
    function setValue(id, value) {
      if (el(id)) el(id).value = value;
    }
    function syncThicknessFromGeneral(force) {
      var thickness = Math.max(3, numero('espesor', 15));
      syncingFields = true;
      Object.keys(linkedThickness).forEach(function(id) {
        if (force || linkedThickness[id]) setValue(id, thickness);
      });
      syncingFields = false;
    }
    function restoreThicknessSync() {
      Object.keys(linkedThickness).forEach(function(id) { linkedThickness[id] = true; });
      syncThicknessFromGeneral(true);
      actualizarVista();
    }
    function markManualThickness(id) {
      if (!syncingFields && linkedThickness.hasOwnProperty(id)) linkedThickness[id] = false;
    }
    function crearPaneles() {
      var thickness = Math.max(3, numero('espesor', 15));
      el('panel_grid').innerHTML = paneles.map(function(panel) {
        var category = panel[0] === 'superior' ? 'top' : (panel[0] === 'inferior' ? 'horizontal' : 'lateral');
        return '<div class="panel-card" data-editor-card="' + panel[0] + '" data-editor-category="' + category + '"><h3>' + panel[1] + '</h3>' +
          '<div class="row"><label>Construccion</label><select id="montaje_' + panel[0] + '"><option value="INTERIOR"' + ((panel[0] === 'superior' || panel[0] === 'inferior') ? ' selected' : '') + '>Montaje interior</option><option value="EXTERIOR"' + ((panel[0] === 'izq' || panel[0] === 'der') ? ' selected' : '') + '>Sobrepuesto exterior</option></select></div>' +
          '<div class="row"><label>Grosor (mm)</label><input type="number" class="grosor-panel" id="grosor_' + panel[0] + '" value="' + thickness + '" min="3"></div>' +
          '<div class="row"><label>Sobremedida delantera (mm)</label><input type="number" id="sobremedida_frontal_' + panel[0] + '" value="0" step=".5"></div>' +
          '<div class="row"><label>Sobremedida trasera (mm)</label><input type="number" id="sobremedida_trasera_' + panel[0] + '" value="0" step=".5"></div>' +
          '<small>Positivo = agranda este panel hacia ese lado (sobresale). Negativo = lo achica (se retranquea hacia adentro). Fondo resultante = fondo total + sobremedida delantera + sobremedida trasera.</small>' +
          '<small class="retranqueo-result" id="sobremedida_resultado_' + panel[0] + '"></small></div>';
      }).join('');
    }
    function aplicarPreset() {
      var tipo = el('tipo_modulo').value;
      var p = presets[tipo];
      if (!p) return;
      el('modulo_nombre').value = tipo;
      el('ancho_total').value = p[0];
      el('alto_total').value = p[1];
      el('prof_total').value = p[2];
      el('espesor').value = p[3];
      el('num_repisas').value = p[4];
      el('lleva_maletera').value = p[5];
      restoreThicknessSync();
      actualizarNichos();
      actualizarVista();
    }
    function actualizarNichos() {
      var cantidad = Math.max(1, parseInt(el('num_repisas').value, 10) + 1 || 1);
      var anteriores = Array.prototype.map.call(document.querySelectorAll('.cajones-nicho'), function(c) { return c.value; });
      var tipos = Array.prototype.map.call(document.querySelectorAll('.tipo-cajon-nicho'), function(c) { return c.value; });
      var html = '';
      for (var i = 0; i < cantidad; i++) {
        html += '<div class="row"><label>Nicho ' + (i + 1) + '</label><input class="cajones-nicho" type="number" min="0" value="' + (anteriores[i] || 0) + '"></div>' +
          '<div class="row"><label>Frente del nicho ' + (i + 1) + '</label><select class="tipo-cajon-nicho"><option value="INTERNO">Cajon interno</option><option value="FRENTES"' + (tipos[i] === 'FRENTES' ? ' selected' : '') + '>Con frente exterior</option></select></div>';
      }
      el('nichos_cajones').innerHTML = html;
      normalizeSpaceState();
    }

    function nichosActuales() {
      return Array.prototype.map.call(document.querySelectorAll('.cajones-nicho'), function(c) { return parseInt(c.value, 10) || 0; });
    }
    function tiposActuales() {
      return Array.prototype.map.call(document.querySelectorAll('.tipo-cajon-nicho'), function(c) { return c.value; });
    }
    function layoutColumns() { return Math.max(1, (parseInt(el('num_divisiones').value, 10) || 0) + 1); }
    function layoutRows() { return Math.max(1, (parseInt(el('num_repisas').value, 10) || 0) + 1); }
    function cellMetrics(d) {
      var cols = Math.max(1, (parseInt(d.num_divisiones, 10) || 0) + 1);
      var rows = Math.max(1, (parseInt(d.num_repisas, 10) || 0) + 1);
      return {
        cols: cols,
        rows: rows,
        width: (d.ancho_total - d.grosor_izq - d.grosor_der - ((cols - 1) * d.espesor)) / cols,
        height: (d.alto_total - d.grosor_superior - d.grosor_inferior - ((rows - 1) * d.espesor)) / rows
      };
    }
    function normalizeSpaceState() {
      var cols = layoutColumns();
      var rows = layoutRows();
      var clean = {};
      Object.keys(spaceState).forEach(function(key) {
        var space = spaceState[key] || {};
        var niche = Math.max(0, Math.min(rows - 1, parseInt(space.niche, 10) || 0));
        var column = Math.max(0, Math.min(cols - 1, parseInt(space.column, 10) || 0));
        space.niche = niche;
        space.column = column;
        clean[spaceKey(niche, column)] = space;
      });
      spaceState = clean;
      if (selectedSpace >= cols * rows) selectedSpace = 0;
    }
    function syncLegacyFieldsFromSpaces() {
      normalizeSpaceState();
      var rows = layoutRows();
      var drawers = Array(rows).fill(0);
      var types = Array(rows).fill('INTERNO');
      Object.keys(spaceState).forEach(function(key) {
        var space = spaceState[key];
        var niche = Math.max(0, Math.min(rows - 1, parseInt(space.niche, 10) || 0));
        if (space.content === 'CAJONERA') {
          drawers[niche] += Math.max(0, parseInt(space.drawers, 10) || 0);
          if (space.front_type === 'FRENTES') types[niche] = 'FRENTES';
        }
      });
      if (Object.keys(spaceState).length) {
        document.querySelectorAll('.cajones-nicho').forEach(function(campo, i) { campo.value = drawers[i] || 0; });
        document.querySelectorAll('.tipo-cajon-nicho').forEach(function(campo, i) { campo.value = types[i] || 'INTERNO'; });
      }
    }
    function changeStructure(kind, delta) {
      if (kind === 'column') el('num_divisiones').value = Math.max(0, Math.min(20, numero('num_divisiones') + delta));
      if (kind === 'row') {
        el('num_repisas').value = Math.max(0, Math.min(30, numero('num_repisas') + delta));
        actualizarNichos();
      }
      normalizeSpaceState();
      actualizarVista();
    }
    function cantidadAjustes(d) {
      var grosor = parseFloat(d.grosor_resp) || 6;
      if (d.lleva_respaldo === 'NO' || grosor >= 15) return 0;
      if (String(d.cantidad_ajustes || 'AUTO') !== 'AUTO') return Math.max(0, parseInt(d.cantidad_ajustes, 10) || 0);
      return (parseFloat(d.alto_total) || 0) > 760 ? 2 : 1;
    }
    function sincronizarReglasRespaldo() {
      var grosor = numero('grosor_resp', 6);
      var cantidad = cantidadAjustes(datosFormulario());
      var hint = el('ajustes_hint');
      if (hint) hint.textContent = grosor >= 15 ? 'Respaldo estructural de ' + grosor + ' mm: ajustes posteriores apagados automáticamente.' : 'Desde atrás: ' + numero('distancia_plano_posterior',0) + ' mm libres + ajuste ' + numero('grosor_ajuste',15) + ' mm + separación ' + numero('separacion_ajuste_respaldo',2) + ' mm + respaldo ' + grosor + ' mm. Ajustes activos: ' + cantidad + '.';
    }
    function setCajonesNichos(valores, tipos) {
      actualizarNichos();
      document.querySelectorAll('.cajones-nicho').forEach(function(campo, i) { campo.value = valores[i] || 0; });
      document.querySelectorAll('.tipo-cajon-nicho').forEach(function(campo, i) { campo.value = (tipos && tipos[i]) || campo.value || 'INTERNO'; });
    }
    function iluminarCategoria(categoria, mensaje) {
      if (window.Modular3DPreview && window.Modular3DPreview.highlight) window.Modular3DPreview.highlight(categoria);
      var hint = el('editing_hint');
      if (!hint) return;
      hint.textContent = mensaje || ('Editando: ' + categoria);
      hint.className = 'editing-hint show';
    }
    function campoParaPieza(detail) {
      var name = String(detail.name || '').toLowerCase();
      var category = detail.category || '';
      if (category === 'front' || category === 'handle' || category === 'drawer') return { page: 'interior', field: category === 'drawer' ? 'luz_frentes' : 'puerta_grosor', label: 'frentes' };
      if (name.indexOf('ajuste') >= 0) return { page: 'paneles', field: 'cantidad_ajustes', label: 'ajustes posteriores' };
      if (category === 'back') return { page: 'paneles', field: 'grosor_resp', label: 'respaldo' };
      if (category === 'interior') return { page: 'interior', field: name.indexOf('division') >= 0 ? 'num_divisiones' : 'num_repisas', label: 'interior' };
      if (category === 'top' || name.indexOf('superior') >= 0) return { page: 'paneles', field: 'grosor_superior', label: 'tapa superior' };
      if (category === 'horizontal' || name.indexOf('inferior') >= 0) return { page: 'paneles', field: 'grosor_inferior', label: 'base inferior' };
      if (name.indexOf('derecho') >= 0 || name.indexOf('derecha') >= 0) return { page: 'paneles', field: 'grosor_der', label: 'lateral derecho' };
      if (name.indexOf('izquierdo') >= 0 || name.indexOf('izquierda') >= 0) return { page: 'paneles', field: 'grosor_izq', label: 'lateral izquierdo' };
      return { page: 'paneles', field: 'grosor_izq', label: 'laterales' };
    }
    function enfocarEditor(fieldId) {
      document.querySelectorAll('.editor-focus').forEach(function(node) { node.classList.remove('editor-focus'); });
      var field = el(fieldId);
      if (!field) return;
      var row = field.closest ? field.closest('.row') : null;
      var card = field.closest ? field.closest('.panel-card, .card') : null;
      if (row) row.classList.add('editor-focus');
      if (card) card.classList.add('editor-focus');
      field.focus({ preventScroll: true });
      if (card && card.scrollIntoView) card.scrollIntoView({ behavior: 'smooth', block: 'center' });
      window.setTimeout(function() {
        if (row) row.classList.remove('editor-focus');
        if (card) card.classList.remove('editor-focus');
      }, 2600);
    }
    function categoriaPorCampo(id) {
      if (fieldCategories[id]) return fieldCategories[id];
      if (id.indexOf('grosor_') === 0 || id.indexOf('montaje_') === 0 || id.indexOf('sobremedida_') === 0) return 'lateral';
      return '';
    }
    window.addEventListener('modular3d:pieceSelected', function(event) {
      var detail = event.detail || {};
      var target = campoParaPieza(detail);
      var activePage=document.querySelector('.page.active');
      if(!activePage||activePage.id!=='diseno')mostrarPagina(target.page);
      document.querySelectorAll('.panel-card').forEach(function(card){card.classList.remove('piece-card-selected');});
      var roleMap={'shell-left':'izq','shell-right':'der','shell-bottom':'inferior','shell-top':'superior'},cardKey=roleMap[String(detail.role||'')];
      if(cardKey){var selectedCard=document.querySelector('.panel-card[data-editor-card="'+cardKey+'"]');if(selectedCard)selectedCard.classList.add('piece-card-selected');}
      iluminarCategoria(detail.category, 'Seleccionado en 3D: ' + (detail.name || detail.category) + '. Edita aqui las dimensiones y grosores de ' + target.label + '.');
      if(!activePage||activePage.id!=='diseno')window.setTimeout(function() { enfocarEditor(target.field); }, 60);
    });
    window.Modular3DLoadInitial = function(datos) {
      if (!datos) return;
      editMode = datos.__edit_mode === 'SI';
      var sourceNotice=el('edit_source_notice');
      if(sourceNotice){
        if(datos.__modified_outside==='SI'){sourceNotice.textContent='Este módulo fue modificado fuera de Modular_3D. Al actualizar se reconstruirá desde su manifiesto paramétrico guardado.';sourceNotice.className='message warn show';}
        else if(datos.__manifest_source==='IMPORTED'||datos.conversion_requires_review==='SI'){sourceNotice.textContent='Módulo importado: revisa medidas, clasificación y los cuatro pasos antes de reemplazar la geometría original.';sourceNotice.className='message warn show';}
        else if(editMode){sourceNotice.textContent='Edición paramétrica activa. Se conservarán nombre, posición, rotación, jerarquía y materiales del módulo.';sourceNotice.className='message warn show';}
        else sourceNotice.className='message warn';
      }
      Object.keys(datos).forEach(function(id) {
        if (el(id)) {
          if (el(id).type === 'checkbox') el(id).checked = datos[id] === 'SI' || datos[id] === true;
          else el(id).value = datos[id];
        }
      });
      el('btn_actualizar_modulo').classList.toggle('show', editMode);
      actualizarNichos();
      if (datos.cajones_por_nicho) setCajonesNichos(String(datos.cajones_por_nicho).split(',').map(function(v) { return parseInt(v, 10) || 0; }), datos.tipos_cajon_por_nicho ? String(datos.tipos_cajon_por_nicho).split(',') : null);
      spaceState = {};
      try {
        var savedSpaces = typeof datos.spaces_json === 'string' ? JSON.parse(datos.spaces_json || '[]') : (datos.spaces_json || []);
        savedSpaces.forEach(function(space) {
          spaceState[String(space.niche) + ':' + String(space.column)] = space;
        });
      } catch (e) { spaceState = {}; }
      mostrarPagina('inicial');
      actualizarVista();
      if(datos.view_camera_json&&window.Modular3DView&&window.Modular3DView.restoreCamera)window.setTimeout(function(){window.Modular3DView.restoreCamera(datos.view_camera_json);},60);
    };
    function spaceKey(niche, column) { return String(niche) + ':' + String(column); }

    function solveParametricExpression(expr, total, separator) {
      var tokens = String(expr || '').split(':').map(function(v){return v.trim();}).filter(Boolean);
      if (!tokens.length) return [];
      var usable=total-Math.max(0,tokens.length-1)*(separator||0);
      if(usable<=0)throw new Error('Los separadores exceden el espacio.');
      var fixed=0, flex=0;
      var items=tokens.map(function(t){
        var m=t.match(/^(\d+(?:\.\d+)?)\s*(mm|cm|m)$/i);
        if(m){var v=+m[1],u=m[2].toLowerCase(),q=u==='mm'?v:(u==='cm'?v*10:v*1000);fixed+=q;return['f',q];}
        m=t.match(/^(\d+(?:\.\d+)?)%$/); if(m){var q=usable*(+m[1])/100;fixed+=q;return['f',q];}
        if(/^auto$/i.test(t)){flex+=1;return['r',1];}
        m=t.match(/^(\d+(?:\.\d+)?)$/); if(m&&+m[1]>0){flex+=+m[1];return['r',+m[1]];}
        throw new Error('No entiendo "'+t+'"');
      });
      var rem=usable-fixed;if(rem < -0.01)throw new Error('Las medidas fijas exceden el espacio.');
      if(rem>0.01 && flex<=0)throw new Error('Queda espacio sin repartir: añade AUTO o proporción.');
      return items.map(function(i){return i[0]==='f'?i[1]:rem*i[1]/flex;});
    }
    function updateParametricFeedback(){
      [['param_x_expr','param_x_result','X'],['param_z_expr','param_z_result','Z']].forEach(function(cfg){
        var input=el(cfg[0]),out=el(cfg[1]); if(!input||!out)return;
        if(!input.value.trim()){out.className='param-result';out.textContent='Vacío = conserva la distribución tradicional.';return;}
        try{
          var total=cfg[2]==='X' ? Math.max(1,numero('ancho_total')-numero('grosor_izq')-numero('grosor_der')) : Math.max(1,numero('alto_total')-numero('grosor_superior')-numero('grosor_inferior'));
          var physical=el(cfg[2]==='X'?'param_x_type':'param_z_type').value==='FISICA';
          var vals=solveParametricExpression(input.value,total,physical?numero('espesor',15):0);
          out.className='param-result ok';out.textContent=vals.map(function(v,i){return 'E'+(i+1)+' '+v.toFixed(1)+' mm';}).join('  ·  ');
          if(cfg[2]==='X')el('num_divisiones').value=Math.max(0,vals.length-1);else el('num_repisas').value=Math.max(0,vals.length-1);
        }catch(e){out.className='param-result bad';out.textContent='⚠ '+e.message;}
      });
    }

    function datosFormulario() {
      var datos = {};
      document.querySelectorAll('input[id], select[id]').forEach(function(campo) {
        datos[campo.id] = campo.type === 'checkbox' ? (campo.checked ? 'SI' : 'NO') : (campo.type === 'number' ? parseFloat(campo.value) : campo.value);
      });
      /* Algunos valores numéricos viven en select o input hidden. Sin esta
         normalización JavaScript concatena texto (15 + 2 + "6" = "176") y
         bloquea erróneamente la construcción. */
      ['ancho_total','alto_total','prof_total','espesor','grosor_izq','grosor_der','grosor_superior','grosor_inferior','grosor_resp','grosor_ajuste','alto_ajuste','separacion_ajuste_respaldo','distancia_plano_posterior','profundidad_ranura','num_repisas','num_divisiones','retranqueo_interior','prof_input_cj','ret_cajones','puerta_grosor','juego_general'].forEach(function(idNumerico){
        var valor=parseFloat(datos[idNumerico]);
        if(isFinite(valor))datos[idNumerico]=valor;
      });
      normalizeSpaceState();
      var hasDesignedSpaces = Object.keys(spaceState).length > 0;
      if (hasDesignedSpaces) syncLegacyFieldsFromSpaces();
      datos.crear_puerta = 'NO';
      datos.tipo_puerta = 'AUTO';
      datos.modo_frentes = 'POR_NICHO';
      datos.cajones_por_nicho = Array.prototype.map.call(document.querySelectorAll('.cajones-nicho'), function(c) { return parseInt(c.value, 10) || 0; }).join(',');
      var tipos = Array.prototype.map.call(document.querySelectorAll('.tipo-cajon-nicho'), function(c) { return c.value; });
      if (!hasDesignedSpaces) {
        if (datos.modo_frentes === 'TODOS') tipos = tipos.map(function(_, i) { return (parseInt(datos.cajones_por_nicho.split(',')[i], 10) || 0) > 0 ? 'FRENTES' : 'INTERNO'; });
        if (datos.modo_frentes === 'NINGUNO') tipos = tipos.map(function() { return 'INTERNO'; });
      }
      datos.tipos_cajon_por_nicho = tipos.join(',');
      updateParametricFeedback();
      datos.spaces_json = JSON.stringify(Object.keys(spaceState).map(function(key) { return spaceState[key]; }));
      datos.num_cajones = Object.keys(spaceState).reduce(function(total, key) {
        return total + (spaceState[key].content === 'CAJONERA' ? (parseInt(spaceState[key].drawers, 10) || 0) : 0);
      }, 0);
      if (!datos.num_cajones) datos.num_cajones = datos.cajones_por_nicho.split(',').reduce(function(total, value) { return total + (parseInt(value, 10) || 0); }, 0);
      return datos;
    }

    function validar() {
      var d = datosFormulario();
      var errores = [];
      var avisos = [];
      if (!(d.ancho_total >= 150 && d.ancho_total <= 3000)) errores.push('La anchura debe estar entre 150 y 3000 mm.');
      if (!(d.alto_total >= 150 && d.alto_total <= 4000)) errores.push('La altura debe estar entre 150 y 4000 mm.');
      if (!(d.prof_total >= 100 && d.prof_total <= 1500)) errores.push('La profundidad debe estar entre 100 y 1500 mm.');
      if (d.grosor_izq + d.grosor_der >= d.ancho_total) errores.push('Los laterales ocupan todo el ancho.');
      if (d.grosor_superior + d.grosor_inferior >= d.alto_total) errores.push('Los paneles horizontales ocupan toda la altura.');
      if (!(d.grosor_ajuste >= 3 && d.grosor_ajuste <= 40)) errores.push('El grosor del ajuste posterior debe estar entre 3 y 40 mm.');
      if (d.separacion_ajuste_respaldo < 0 || d.distancia_plano_posterior < 0) errores.push('Las separaciones posteriores no pueden ser negativas.');
      if (d.lleva_respaldo !== 'NO' && d.grosor_resp < 15 && d.grosor_ajuste + d.separacion_ajuste_respaldo + d.grosor_resp + d.distancia_plano_posterior >= d.prof_total) errores.push('El sistema posterior ocupa toda la profundidad disponible.');
      var metrics = cellMetrics(d);
      if (metrics.width <= 30) errores.push('Las divisiones dejan columnas sin ancho util.');
      if (metrics.height <= 30) errores.push('Las repisas dejan niveles sin altura util.');
      if (metrics.width > 30 && metrics.width < 180) avisos.push('Columnas menores de 180 mm limitan correderas y bisagras.');
      if (metrics.height > 30 && metrics.height < 120) avisos.push('Niveles menores de 120 mm limitan cajones y accesorios.');
      var maximaSobremedida = Math.min(d.prof_total * 0.4, 200);
      paneles.forEach(function(p) {
        var frontal = d['sobremedida_frontal_' + p[0]] || 0, trasero = d['sobremedida_trasera_' + p[0]] || 0;
        var profundidad = d.prof_total + frontal + trasero;
        if (profundidad <= 30) errores.push(p[1] + ' queda sin profundidad util.');
        if (frontal > maximaSobremedida) errores.push(p[1] + ': la sobremedida delantera no puede sobresalir mas de ' + Math.round(maximaSobremedida) + ' mm.');
        if (trasero > maximaSobremedida) errores.push(p[1] + ': la sobremedida trasera no puede sobresalir mas de ' + Math.round(maximaSobremedida) + ' mm.');
      });
      var spaces = Object.keys(spaceState).map(function(key) { return spaceState[key]; });
      var seen = {};
      spaces.forEach(function(space) {
        var key = spaceKey(space.niche, space.column);
        if (seen[key]) errores.push('Hay dos configuraciones en la misma celda ' + key + '.');
        seen[key] = true;
        if (space.content === 'CAJONERA') {
          var drawers = parseInt(space.drawers, 10) || 0;
          if (drawers < 1 || drawers > 12) errores.push('Cada cajonera debe tener entre 1 y 12 cajones.');
          if (drawers > 0 && metrics.height / drawers < 45) errores.push('Los cajones no caben en la altura del espacio.');
          if (metrics.width < 170) errores.push('La columna es demasiado angosta para una cajonera con correderas.');
        }
        if (String(space.content || '').indexOf('PUERTA') === 0 && String(space.content).indexOf('DOBLE') >= 0 && metrics.width < 500) {
          errores.push('Una puerta doble necesita al menos 500 mm de ancho por celda.');
        }
      });
      var cajones = spaces.length ? spaces.reduce(function(s, space) { return s + (space.content === 'CAJONERA' ? (parseInt(space.drawers, 10) || 0) : 0); }, 0) : d.cajones_por_nicho.split(',').reduce(function(s, n) { return s + parseInt(n || 0, 10); }, 0);
      if (cajones && (d.prof_input_cj + d.ret_cajones > d.prof_total - 20)) errores.push('La profundidad del cajon no cabe en el cuerpo.');
      if (cajones > 8) avisos.push('Mas de 8 cajones puede complicar fabricacion e instalacion.');
      if (d.num_repisas > 8) avisos.push('Mas de 8 repisas puede producir nichos demasiado pequenos.');
      if (d.alto_total > 2100) avisos.push('Revisa la direccion de veta antes de optimizar el corte.');
      if (el('space_rule_hint')) {
        el('space_rule_hint').textContent = errores.length ? errores[0] : (avisos[0] || 'Diseno 2D coherente: medidas, celdas, cajones y frentes estan sincronizados.');
      }
      return { errores: errores, avisos: avisos };
    }
    function actualizarResultadoRetranqueos(d) {
      var maximaSobremedida = Math.min(d.prof_total * 0.4, 200);
      paneles.forEach(function(p) {
        var host = el('sobremedida_resultado_' + p[0]);
        if (!host) return;
        var frontal = d['sobremedida_frontal_' + p[0]] || 0, trasero = d['sobremedida_trasera_' + p[0]] || 0;
        var profundidad = d.prof_total + frontal + trasero;
        var estado = 'ok';
        if (profundidad <= 30 || frontal > maximaSobremedida || trasero > maximaSobremedida) estado = 'error';
        else if (profundidad < 80) estado = 'warn';
        host.textContent = 'Fondo resultante de este panel: ' + Math.round(profundidad) + ' mm';
        host.className = 'retranqueo-result' + (estado === 'ok' ? '' : ' ' + estado);
      });
    }
    function actualizarVista() {
      var d = datosFormulario();
      actualizarResultadoRetranqueos(d);
      var ancho = Math.max(0, d.ancho_total - d.grosor_izq - d.grosor_der);
      var alto = Math.max(0, d.alto_total - d.grosor_superior - d.grosor_inferior);
      var cajones = d.cajones_por_nicho.split(',').reduce(function(s, n) { return s + parseInt(n || 0, 10); }, 0);
      var tipoPuerta = d.tipo_puerta || 'AUTO';
      var puertas = d.crear_puerta === 'SI' ? ((tipoPuerta === 'DOBLE' || tipoPuerta === 'DOBLE_VIDRIO' || (tipoPuerta === 'AUTO' && d.ancho_total > 619)) ? 2 : 1) : 0;
      var frentesCajon = d.tipos_cajon_por_nicho.split(',').reduce(function(s, tipo, i) {
        return s + (tipo === 'FRENTES' ? (parseInt(d.cajones_por_nicho.split(',')[i], 10) || 0) : 0);
      }, 0);
      var configuredSpaces = Object.keys(spaceState).map(function(key) { return spaceState[key]; });
      if (configuredSpaces.length) {
        cajones = configuredSpaces.reduce(function(total, space) { return total + (space.content === 'CAJONERA' ? (parseInt(space.drawers, 10) || 0) : 0); }, 0);
        frentesCajon = configuredSpaces.reduce(function(total, space) { return total + (space.content === 'CAJONERA' && space.front_type === 'FRENTES' ? (parseInt(space.drawers, 10) || 0) : 0); }, 0);
        puertas = configuredSpaces.reduce(function(total, space) {
          if (String(space.content).indexOf('PUERTA') !== 0) return total;
          return total + (String(space.content).indexOf('DOBLE') >= 0 ? 2 : 1);
        }, 0);
      }
      var ajustes = cantidadAjustes(d);
      var piezas = 4 + (Number(d.num_repisas)||0) + (Number(d.num_divisiones)||0) + ajustes + (d.lleva_respaldo !== 'NO' ? 1 : 0) + cajones * 5 + puertas + frentesCajon;
      el('m_ancho').textContent = Math.round(ancho) + ' mm';
      el('m_alto').textContent = Math.round(alto) + ' mm';
      el('m_prof').textContent = Math.round(d.prof_total) + ' mm';
      el('m_piezas').textContent = piezas;
      var chequeo = validar();
      el('errores').textContent = chequeo.errores.join('\n');
      el('errores').className = 'message error' + (chequeo.errores.length ? ' show' : '');
      el('avisos').textContent = chequeo.avisos.join('\n');
      el('avisos').className = 'message warn' + (chequeo.avisos.length ? ' show' : '');
      el('lista_piezas').innerHTML = '<p><strong>Dimensiones interiores:</strong> ' + Math.round(ancho) + ' x ' + Math.round(alto) + ' x ' + Math.round(d.prof_total) + ' mm</p>' +
        '<p><strong>Estimacion:</strong> ' + piezas + ' piezas, ' + d.num_repisas + ' repisas, ' + d.num_divisiones + ' divisiones, ' + cajones + ' cajones, ' + frentesCajon + ' frentes y ' + puertas + ' puerta(s).</p>' +
        '<p><strong>Sistema de corredera:</strong> ' + (d.sistema_corredera || 'Telescopica estandar') + '.</p>';
      if (window.Modular3DPreview) window.Modular3DPreview.update(d);
      return chequeo.errores.length === 0;
    }
    function mostrarPagina(id) {
      document.querySelectorAll('.page').forEach(function(p) { p.classList.toggle('active', p.id === id); });
      document.querySelectorAll('[data-page]').forEach(function(t) { t.classList.toggle('active', t.dataset.page === id); });
      actualizarVista();
      updateStepStatus(id);
      window.dispatchEvent(new CustomEvent('modular3d:pageShown',{detail:{id:id}}));
    }
    function currentStepIndex() {
      var active = document.querySelector('.page.active');
      var id = active ? active.id : 'inicial';
      var index = stepPages.indexOf(id);
      return index < 0 ? 0 : index;
    }
    function updateStepStatus(id) {
      var prev = el('step_prev');
      var next = el('step_next');
      var status = el('step_status');
      if (!prev || !next || !status) return;
      if (id === 'resultado') {
        prev.disabled = false;
        next.textContent = 'Construir';
        status.textContent = 'Revision final';
        return;
      }
      var index = stepPages.indexOf(id || 'inicial');
      if (index < 0) index = currentStepIndex();
      prev.disabled = index <= 0;
      next.textContent = index >= stepPages.length - 1 ? 'Construir' : 'Siguiente';
      status.textContent = 'Paso ' + (index + 1) + ' de ' + stepPages.length + ' - ' + (document.querySelector('[data-page=\"' + stepPages[index] + '\"]') || {}).textContent;
    }
    function stepMove(delta) {
      var active = document.querySelector('.page.active');
      if (active && active.id === 'resultado') {
        if (delta < 0) return mostrarPagina(stepPages[stepPages.length - 1]);
        return construir();
      }
      var index = currentStepIndex();
      if (delta > 0 && index >= stepPages.length - 1) return construir();
      var next = Math.max(0, Math.min(stepPages.length - 1, index + delta));
      mostrarPagina(stepPages[next]);
    }
    function construir() {
      if (!actualizarVista()) {
        mostrarPagina('resultado');
        return;
      }
      var datos = datosFormulario();
      if(window.Modular3DView){datos.view_snapshot=window.Modular3DView.cleanSnapshot?window.Modular3DView.cleanSnapshot():(window.Modular3DView.snapshot?window.Modular3DView.snapshot():'');datos.view_camera_json=JSON.stringify(window.Modular3DView.cameraState?window.Modular3DView.cameraState():null);}
      datos.__edit_mode = editMode ? 'SI' : 'NO';
      if (window.sketchup && sketchup.ejecutarConstruccionMueble) {
        sketchup.ejecutarConstruccionMueble(datos);
      } else {
        el('avisos').textContent = 'Vista web: abre esta interfaz desde SketchUp para construir el modulo.';
        el('avisos').className = 'message warn show';
        mostrarPagina('resultado');
      }
    }
    function actualizarModuloExistente() {
      if (!actualizarVista()) return;
      var datos = datosFormulario();
      if(window.Modular3DView){datos.view_snapshot=window.Modular3DView.cleanSnapshot?window.Modular3DView.cleanSnapshot():(window.Modular3DView.snapshot?window.Modular3DView.snapshot():'');datos.view_camera_json=JSON.stringify(window.Modular3DView.cameraState?window.Modular3DView.cameraState():null);}
      datos.__edit_mode = 'SI';
      if (window.sketchup && sketchup.ejecutarConstruccionMueble) {
        sketchup.ejecutarConstruccionMueble(datos);
      }
    }

    var perfilesDisponibles = [];
    window.Modular3DApplyProfileList = function(perfiles) {
      perfilesDisponibles = Array.isArray(perfiles) ? perfiles : [];
      var select = el('modulo_plantilla');
      if (!select) return;
      perfilesDisponibles.forEach(function(perfil) {
        var option = document.createElement('option');
        option.value = perfil.id;
        option.textContent = perfil.label || perfil.id;
        select.appendChild(option);
      });
    };
    if (window.__modular3dProfiles) window.Modular3DApplyProfileList(window.__modular3dProfiles);
    function aplicarPlantillaSeleccionada() {
      var id = el('modulo_plantilla').value;
      var descripcion = el('modulo_plantilla_desc');
      var perfil = perfilesDisponibles.filter(function(item) { return item.id === id; })[0];
      if (descripcion) descripcion.textContent = perfil && perfil.description ? perfil.description : '';
      if (!perfil || !perfil.fields) return;
      Object.keys(perfil.fields).forEach(function(campo) {
        var elemento = el(campo);
        if (!elemento) return;
        elemento.value = perfil.fields[campo];
        elemento.dispatchEvent(new Event(elemento.tagName === 'SELECT' ? 'change' : 'input', { bubbles: true }));
      });
      actualizarVista();
    }
    el('modulo_plantilla').addEventListener('change', aplicarPlantillaSeleccionada);

    crearPaneles();
    actualizarNichos();
    sincronizarReglasRespaldo();
    document.addEventListener('input', function(event) {
      if (event.target.id === 'espesor') {linkedThickness.grosor_ajuste=!!el('sincronizar_ajuste').checked;syncThicknessFromGeneral(false);}
      if (event.target.id === 'material_casco_color') {
        if (el('material_respaldo_custom') && !el('material_respaldo_custom').checked && el('material_respaldo_color')) el('material_respaldo_color').value = event.target.value;
        if (el('material_ajuste_custom') && !el('material_ajuste_custom').checked && el('material_ajuste_color')) el('material_ajuste_color').value = event.target.value;
      }
      markManualThickness(event.target.id || '');
      var category = categoriaPorCampo(event.target.id || '');
      if (category) iluminarCategoria(category, 'Estas modificando: ' + (event.target.labels && event.target.labels[0] ? event.target.labels[0].textContent : event.target.id));
      actualizarVista();
    });
    document.addEventListener('change', function(event) {
      if(event.target.id==='sincronizar_ajuste'){linkedThickness.grosor_ajuste=event.target.checked;if(event.target.checked){setValue('grosor_ajuste',numero('espesor',15));actualizarVista();}}
      if ((event.target.id === 'material_respaldo_custom' || event.target.id === 'material_ajuste_custom') && !event.target.checked) {
        var targetColorId = event.target.id === 'material_respaldo_custom' ? 'material_respaldo_color' : 'material_ajuste_color';
        if (el('material_casco_color') && el(targetColorId)) el(targetColorId).value = el('material_casco_color').value;
      }
      if (event.target.id === 'espesor') {linkedThickness.grosor_ajuste=!!el('sincronizar_ajuste').checked;syncThicknessFromGeneral(false);}
      markManualThickness(event.target.id || '');
      if (event.target.id === 'tipo_modulo') aplicarPreset();
      if (event.target.id === 'num_repisas' || event.target.id === 'num_divisiones') { actualizarNichos(); normalizeSpaceState(); }
      if (event.target.id === 'grosor_resp' || event.target.id === 'lleva_respaldo' || event.target.id === 'cantidad_ajustes' || event.target.id === 'alto_ajuste' || event.target.id === 'grosor_ajuste' || event.target.id === 'separacion_ajuste_respaldo' || event.target.id === 'distancia_plano_posterior') sincronizarReglasRespaldo();
      actualizarVista();
    });
    document.addEventListener('click', function(event) {
      var panelCard = event.target.closest && event.target.closest('.panel-card[data-editor-card]');
      if (panelCard && !event.target.matches('input,select,option')) {
        var map={izq:'LAT_IZQ',der:'LAT_DER',inferior:'BASE',superior:'TECHO',back:'RESPALDO',adjustments:'AJUSTE_SUPERIOR'};
        if(window.Modular3DView&&map[panelCard.dataset.editorCard])window.Modular3DView.selectPieceByKey(map[panelCard.dataset.editorCard]);
      }
    });
    document.addEventListener('focusin',function(event){
      var panelCard=event.target.closest&&event.target.closest('.panel-card[data-editor-card]');
      var map={izq:'LAT_IZQ',der:'LAT_DER',inferior:'BASE',superior:'TECHO',back:'RESPALDO',adjustments:'AJUSTE_SUPERIOR'};
      if(panelCard&&window.Modular3DView&&map[panelCard.dataset.editorCard])window.Modular3DView.selectPieceByKey(map[panelCard.dataset.editorCard]);
    });
    document.querySelectorAll('[data-page]').forEach(function(t) { t.addEventListener('click', function() { mostrarPagina(t.dataset.page); }); });
    el('step_prev').addEventListener('click', function() { stepMove(-1); });
    el('step_next').addEventListener('click', function() { stepMove(1); });
    el('restore_sync').addEventListener('click', restoreThicknessSync);
    el('btn_orientacion').addEventListener('click', function() {
      var ancho = el('ancho_total').value, alto = el('alto_total').value;
      el('ancho_total').value = alto;
      el('alto_total').value = ancho;
      el('ancho_total').dispatchEvent(new Event('input', { bubbles: true }));
      el('alto_total').dispatchEvent(new Event('input', { bubbles: true }));
      actualizarVista();
    });
    el('btn_revisar').addEventListener('click', function() { mostrarPagina('resultado'); });
    el('btn_construir').addEventListener('click', construir);
    el('btn_actualizar_modulo').addEventListener('click', actualizarModuloExistente);
    el('license_login').addEventListener('click', function() { window.Modular3DLicense.login(); });
    el('license_password').addEventListener('keydown', function(event) { if (event.key === 'Enter') window.Modular3DLicense.login(); });
    el('license_logout').addEventListener('click', function() { if (window.sketchup && sketchup.licenciaLogout) sketchup.licenciaLogout(); });
    if (window.Modular3DPreview) window.Modular3DPreview.init();
    actualizarVista();
    updateStepStatus('inicial');
    if (window.__modular3dInitial) window.Modular3DLoadInitial(window.__modular3dInitial);
    window.Modular3DLicense.check();
    window.setInterval(function() {
      if (!document.body.classList.contains('license-locked') && window.sketchup && sketchup.licenciaHeartbeat) {
        sketchup.licenciaHeartbeat();
      }
    }, 900000);
  
    ['param_x_expr','param_z_expr','param_x_type','param_z_type','ancho_total','alto_total','grosor_izq','grosor_der','grosor_superior','grosor_inferior'].forEach(function(id){
      var node=el(id); if(node) node.addEventListener('input', function(){updateParametricFeedback();actualizarVista();});
    });
    updateParametricFeedback();
