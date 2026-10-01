// Modular_3D — Catálogo Global de Tipos de Módulo (pestaña "5 Catálogo").
//
// Llama a Modular3D::Catalogo (core/catalogo.rb) por acciones puntuales, NUNCA
// al abrir el diálogo -- la carga inicial de la pestaña se dispara sola, una
// sola vez, la primera vez que el usuario la abre (evento
// "modular3d:pageShown" que ya dispara mostrarPagina() en interfaz.js), para
// no sumarle latencia de red a la apertura del configurador para quien nunca
// usa el catálogo en esa sesión.
//
// "Insertar" reutiliza tal cual window.Modular3DLoadInitial (el mismo motor
// que ya usan "Editar módulo" y "Configuración de Proyecto") sobre el
// manifiesto guardado -- así que ancho/alto/profundidad quedan editables
// exactamente igual que cualquier otro módulo cargado. "Guardar en el
// catálogo" reutiliza tal cual window.datosFormulario() (ya envuelto por
// hierarchical_config.js con hierarchy_geometry_json) -- ningún dato nuevo,
// el mismo manifiesto que ya usa "Construir módulo".
(function () {
  function id(x) { return document.getElementById(x); }

  function mensaje(elId, texto, esError) {
    var el = id(elId);
    if (!el) return;
    el.textContent = texto || '';
    el.className = 'message ' + (esError ? 'error' : 'warn') + (texto ? ' show' : '');
  }

  function escapeHtml(text) {
    return String(text == null ? '' : text).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  var ultimaLista = [];
  var cargado = false;
  var compartirActualId = null;
  var usuariosCompartiblesCache = [];
  var snapshotPendiente = null;

  // Reutiliza tal cual el mecanismo de captura de pantalla que ya usa el
  // despiece (modular3d_view.js#snapshot/cleanSnapshot) -- pedido explícito
  // del usuario: "debe mostrarse la foto en miniatura real" del módulo
  // completo, no un ícono genérico.
  function capturarSnapshot() {
    if (!window.Modular3DView) return '';
    try {
      if (window.Modular3DView.cleanSnapshot) return window.Modular3DView.cleanSnapshot() || '';
      if (window.Modular3DView.snapshot) return window.Modular3DView.snapshot() || '';
    } catch (e) { /* sin visor 3D disponible todavía: se guarda sin miniatura */ }
    return '';
  }

  function renderCategorias(categorias) {
    var lista = Array.isArray(categorias) ? categorias : [];
    var select = id('catalogo_categoria');
    if (select) {
      var actual = select.value;
      select.innerHTML = '<option value="">Todas</option>';
      lista.forEach(function (cat) {
        var opt = document.createElement('option');
        opt.value = cat; opt.textContent = cat;
        select.appendChild(opt);
      });
      select.value = actual;
    }
    var datalist = id('catalogo_categorias_datalist');
    if (datalist) {
      datalist.innerHTML = '';
      lista.forEach(function (cat) {
        var opt = document.createElement('option');
        opt.value = cat;
        datalist.appendChild(opt);
      });
    }
  }

  function renderLista(items) {
    ultimaLista = Array.isArray(items) ? items : [];
    var contenedor = id('catalogo_lista');
    if (!contenedor) return;
    if (!ultimaLista.length) {
      contenedor.innerHTML = '<p class="hint-text">Todavía no hay Tipos de Módulo guardados para esta categoría o búsqueda.</p>';
      return;
    }
    contenedor.innerHTML = '';
    ultimaLista.forEach(function (item, index) {
      var card = document.createElement('div');
      card.className = 'catalogo-item';
      var miniatura = item.thumbnail_url
        ? '<img src="' + escapeHtml(item.thumbnail_url) + '" alt="">'
        : '<div class="catalogo-item-sinfoto">Sin miniatura</div>';
      var esGlobal = item.visibility === 'global';
      card.innerHTML = miniatura +
        '<span class="catalogo-item-visibilidad ' + (esGlobal ? 'global">Global' : 'private">Privado') + '</span>' +
        '<strong>' + escapeHtml(item.name) + '</strong>' +
        '<span class="catalogo-item-cat">' + escapeHtml(item.category) + '</span>' +
        '<span>' + Math.round(item.ancho_mm || 0) + ' x ' + Math.round(item.alto_mm || 0) + ' x ' + Math.round(item.profundidad_mm || 0) + ' mm</span>' +
        '<span class="catalogo-item-autor">' + escapeHtml(item.created_by_name || '') + ' · usado ' + (item.usage_count || 0) + ' veces</span>' +
        '<button type="button" data-insertar="' + index + '">Insertar</button>' +
        '<button type="button" class="secondary" data-compartir="' + index + '">Compartir</button>' +
        '<button type="button" class="secondary" data-miniatura="' + index + '">' + (item.thumbnail_url ? 'Actualizar miniatura' : 'Agregar miniatura') + '</button>' +
        '<button type="button" class="secondary" data-borrar="' + index + '">Borrar</button>';
      contenedor.appendChild(card);
    });
    contenedor.querySelectorAll('[data-insertar]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var item = ultimaLista[parseInt(btn.dataset.insertar, 10)];
        if (item) insertar(item.id);
      });
    });
    contenedor.querySelectorAll('[data-compartir]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var item = ultimaLista[parseInt(btn.dataset.compartir, 10)];
        if (item) abrirCompartir(item);
      });
    });
    contenedor.querySelectorAll('[data-miniatura]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var item = ultimaLista[parseInt(btn.dataset.miniatura, 10)];
        if (item) subirMiniaturaPara(item);
      });
    });
    contenedor.querySelectorAll('[data-borrar]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var item = ultimaLista[parseInt(btn.dataset.borrar, 10)];
        if (item) borrar(item);
      });
    });
  }

  // "Actualizar miniatura" sobre un módulo YA guardado: usa la vista 3D
  // actual (la que se está viendo en ese momento en el configurador), no
  // hace falta volver a guardar todo el módulo para refrescar solo la foto.
  function subirMiniaturaPara(item) {
    if (!window.sketchup || !sketchup.catalogoSubirMiniatura) return;
    var snapshot = capturarSnapshot();
    if (!snapshot) {
      mensaje('catalogo_message', 'No hay una vista 3D disponible ahora mismo para usar como miniatura.', true);
      return;
    }
    mensaje('catalogo_message', 'Subiendo miniatura...', false);
    sketchup.catalogoSubirMiniatura(item.id, snapshot);
  }

  // --- Compartir / visibilidad -- pedido explícito del usuario: cada quien
  // es dueño de lo que guarda, puede compartirlo con usuarios puntuales o
  // hacerlo global, y un administrador tiene acceso total. El servidor
  // rechaza (FORBIDDEN) cualquiera de estas acciones si quien las pide no
  // es el dueño ni un admin -- acá solo se muestra ese error tal cual, no
  // se duplica esa verificación en el cliente.
  function mensajeCompartir(texto, esError) { mensaje('catalogo_compartir_message', texto, esError); }

  function renderCompartidos(usuarios) {
    var contenedor = id('catalogo_compartir_lista_actual');
    if (!contenedor) return;
    var lista = Array.isArray(usuarios) ? usuarios : [];
    if (!lista.length) {
      contenedor.innerHTML = '<p class="hint-text">Todavía no está compartido con nadie en particular.</p>';
      return;
    }
    contenedor.innerHTML = '';
    lista.forEach(function (usuario) {
      var fila = document.createElement('div');
      fila.className = 'catalogo-compartido-fila';
      fila.innerHTML = '<span>' + escapeHtml(usuario.name || usuario.email) + '</span><button type="button" class="secondary" data-quitar-usuario="' + usuario.id + '">Quitar</button>';
      contenedor.appendChild(fila);
    });
    contenedor.querySelectorAll('[data-quitar-usuario]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        if (compartirActualId == null || !window.sketchup || !sketchup.catalogoCompartidosActualizar) return;
        mensajeCompartir('Quitando...', false);
        sketchup.catalogoCompartidosActualizar(compartirActualId, [], [parseInt(btn.dataset.quitarUsuario, 10)]);
      });
    });
  }

  function renderUsuariosCompartibles(usuarios) {
    usuariosCompartiblesCache = Array.isArray(usuarios) ? usuarios : [];
    var select = id('catalogo_compartir_agregar');
    if (!select) return;
    select.innerHTML = '<option value="">Elegí un usuario...</option>';
    usuariosCompartiblesCache.forEach(function (usuario) {
      var opt = document.createElement('option');
      opt.value = usuario.id;
      opt.textContent = usuario.name || usuario.email;
      select.appendChild(opt);
    });
  }

  function abrirCompartir(item) {
    compartirActualId = item.id;
    if (id('catalogo_compartir_nombre')) id('catalogo_compartir_nombre').textContent = item.name || '';
    if (id('catalogo_compartir_visibilidad')) id('catalogo_compartir_visibilidad').value = item.visibility === 'global' ? 'global' : 'private';
    if (id('catalogo_compartir_card')) id('catalogo_compartir_card').style.display = '';
    mensajeCompartir('', false);
    if (id('catalogo_compartir_lista_actual')) id('catalogo_compartir_lista_actual').innerHTML = '<p class="hint-text">Cargando...</p>';
    if (window.sketchup && sketchup.catalogoCompartidosListar) sketchup.catalogoCompartidosListar(item.id);
    if (window.sketchup && sketchup.catalogoUsuariosCompartibles) sketchup.catalogoUsuariosCompartibles();
  }

  function cerrarCompartir() {
    compartirActualId = null;
    if (id('catalogo_compartir_card')) id('catalogo_compartir_card').style.display = 'none';
  }

  function cambiarVisibilidad() {
    if (compartirActualId == null || !window.sketchup || !sketchup.catalogoCambiarVisibilidad) return;
    mensajeCompartir('Guardando...', false);
    sketchup.catalogoCambiarVisibilidad(compartirActualId, id('catalogo_compartir_visibilidad').value);
  }

  function agregarCompartido() {
    var select = id('catalogo_compartir_agregar');
    var valor = select && select.value;
    if (!valor || compartirActualId == null || !window.sketchup || !sketchup.catalogoCompartidosActualizar) return;
    mensajeCompartir('Agregando...', false);
    sketchup.catalogoCompartidosActualizar(compartirActualId, [parseInt(valor, 10)], []);
    select.value = '';
  }

  function borrar(item) {
    if (!window.sketchup || !sketchup.catalogoEliminar) return;
    if (!window.confirm('¿Borrar "' + item.name + '" del Catálogo Global? Esto no se puede deshacer.')) return;
    mensaje('catalogo_message', 'Borrando...', false);
    sketchup.catalogoEliminar(item.id);
  }

  function actualizar() {
    if (!window.sketchup || !sketchup.catalogoListar) { mensaje('catalogo_message', 'Esta acción debe abrirse dentro de SketchUp.', true); return; }
    mensaje('catalogo_message', 'Buscando en el catálogo...', false);
    sketchup.catalogoListar(id('catalogo_categoria').value, id('catalogo_buscar').value);
  }

  function insertar(itemId) {
    if (!window.sketchup || !sketchup.catalogoDetalle) return;
    mensaje('catalogo_message', 'Cargando módulo del catálogo...', false);
    sketchup.catalogoDetalle(itemId);
  }

  function guardar() {
    var categoria = (id('catalogo_guardar_categoria').value || '').trim();
    var nombre = (id('catalogo_guardar_nombre').value || '').trim();
    if (!categoria || !nombre) { mensaje('catalogo_guardar_message', 'Completa categoría y nombre antes de guardar.', true); return; }
    if (!window.sketchup || !sketchup.catalogoGuardar) { mensaje('catalogo_guardar_message', 'Esta acción debe abrirse dentro de SketchUp.', true); return; }
    var datos = typeof window.datosFormulario === 'function' ? window.datosFormulario() : {};
    var visibilidad = (id('catalogo_guardar_visibilidad') && id('catalogo_guardar_visibilidad').value) || 'private';
    snapshotPendiente = capturarSnapshot();
    mensaje('catalogo_guardar_message', 'Guardando en el Catálogo Global...', false);
    sketchup.catalogoGuardar(categoria, nombre, (id('catalogo_guardar_descripcion').value || '').trim(), datos, visibilidad);
  }

  function cargarPrimeraVez() {
    if (cargado) return;
    cargado = true;
    if (window.sketchup && sketchup.catalogoCategorias) sketchup.catalogoCategorias();
    actualizar();
  }

  window.Modular3DCatalogoCategoriasResult = function (resultado) {
    if (resultado && resultado.ok) renderCategorias(resultado.categories);
  };

  window.Modular3DCatalogoListaResult = function (resultado) {
    if (!resultado || !resultado.ok) {
      mensaje('catalogo_message', (resultado && resultado.message) || 'No se pudo cargar el catálogo.', true);
      renderLista([]);
      return;
    }
    mensaje('catalogo_message', '', false);
    renderLista(resultado.items);
  };

  window.Modular3DCatalogoDetalleResult = function (resultado) {
    if (!resultado || !resultado.ok || !resultado.item) {
      mensaje('catalogo_message', (resultado && resultado.message) || 'No se pudo cargar ese Tipo de Módulo.', true);
      return;
    }
    var datos = resultado.item.data || {};
    // Insertar desde el catálogo es conceptualmente un módulo NUEVO, no una
    // edición de uno ya construido -- se fuerza __edit_mode a NO aunque el
    // módulo original se haya guardado en modo edición.
    datos.__edit_mode = 'NO';
    delete datos.conversion_requires_review;
    if (typeof window.Modular3DLoadInitial === 'function') window.Modular3DLoadInitial(datos);
    mensaje('catalogo_message', 'Insertado "' + resultado.item.name + '". Revisa ancho, alto y profundidad en "1 Medidas" antes de construir.', false);
  };

  window.Modular3DCatalogoGuardarResult = function (resultado) {
    if (!resultado || !resultado.ok) {
      mensaje('catalogo_guardar_message', (resultado && resultado.message) || 'No se pudo guardar en el Catálogo Global.', true);
      snapshotPendiente = null;
      return;
    }
    var esGlobal = id('catalogo_guardar_visibilidad') && id('catalogo_guardar_visibilidad').value === 'global';
    mensaje('catalogo_guardar_message', esGlobal ? 'Guardado como Global. Ya está disponible para todo el equipo con licencia activa.' : 'Guardado como Privado. Usá "Compartir" en la lista para darle acceso a usuarios puntuales o hacerlo Global después.', false);
    if (snapshotPendiente && resultado.id && window.sketchup && sketchup.catalogoSubirMiniatura) {
      sketchup.catalogoSubirMiniatura(resultado.id, snapshotPendiente);
    }
    snapshotPendiente = null;
    if (cargado) actualizar();
  };

  window.Modular3DCatalogoMiniaturaResult = function (resultado) {
    if (!resultado || !resultado.ok) {
      mensaje('catalogo_message', (resultado && resultado.message) || 'No se pudo subir la miniatura.', true);
      return;
    }
    if (cargado) actualizar();
  };

  window.Modular3DCatalogoVisibilidadResult = function (resultado) {
    if (!resultado || !resultado.ok) {
      mensajeCompartir((resultado && resultado.message) || 'No se pudo cambiar la visibilidad (¿sos el dueño de este módulo?).', true);
      return;
    }
    mensajeCompartir('Visibilidad actualizada.', false);
    actualizar();
  };

  window.Modular3DCatalogoUsuariosCompartiblesResult = function (resultado) {
    if (!resultado || !resultado.ok) { mensajeCompartir((resultado && resultado.message) || 'No se pudo cargar la lista de usuarios.', true); return; }
    renderUsuariosCompartibles(resultado.users);
  };

  window.Modular3DCatalogoCompartidosListaResult = function (resultado) {
    if (!resultado || !resultado.ok) {
      mensajeCompartir((resultado && resultado.message) || 'No se pudo cargar con quién está compartido (¿sos el dueño de este módulo?).', true);
      renderCompartidos([]);
      return;
    }
    mensajeCompartir('', false);
    renderCompartidos(resultado.users);
  };

  window.Modular3DCatalogoCompartidosActualizarResult = function (resultado) {
    if (!resultado || !resultado.ok) {
      mensajeCompartir((resultado && resultado.message) || 'No se pudo actualizar (¿sos el dueño de este módulo?).', true);
      return;
    }
    mensajeCompartir('Actualizado.', false);
    if (compartirActualId != null && window.sketchup && sketchup.catalogoCompartidosListar) sketchup.catalogoCompartidosListar(compartirActualId);
  };

  window.Modular3DCatalogoEliminarResult = function (resultado) {
    if (!resultado || !resultado.ok) {
      mensaje('catalogo_message', (resultado && resultado.message) || 'No se pudo borrar (¿sos el dueño de este módulo?).', true);
      return;
    }
    mensaje('catalogo_message', 'Borrado.', false);
    cerrarCompartir();
    actualizar();
  };

  if (id('catalogo_actualizar')) id('catalogo_actualizar').addEventListener('click', actualizar);
  if (id('catalogo_categoria')) id('catalogo_categoria').addEventListener('change', actualizar);
  if (id('catalogo_buscar')) id('catalogo_buscar').addEventListener('keydown', function (event) { if (event.key === 'Enter') actualizar(); });
  if (id('catalogo_guardar_boton')) id('catalogo_guardar_boton').addEventListener('click', guardar);
  if (id('catalogo_compartir_cerrar')) id('catalogo_compartir_cerrar').addEventListener('click', cerrarCompartir);
  if (id('catalogo_compartir_visibilidad')) id('catalogo_compartir_visibilidad').addEventListener('change', cambiarVisibilidad);
  if (id('catalogo_compartir_agregar')) id('catalogo_compartir_agregar').addEventListener('change', agregarCompartido);

  window.addEventListener('modular3d:pageShown', function (event) {
    if (event.detail && event.detail.id === 'catalogo') cargarPrimeraVez();
  });
})();
