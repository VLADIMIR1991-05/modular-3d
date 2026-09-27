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
      card.innerHTML = miniatura +
        '<strong>' + escapeHtml(item.name) + '</strong>' +
        '<span class="catalogo-item-cat">' + escapeHtml(item.category) + '</span>' +
        '<span>' + Math.round(item.ancho_mm || 0) + ' x ' + Math.round(item.alto_mm || 0) + ' x ' + Math.round(item.profundidad_mm || 0) + ' mm</span>' +
        '<span class="catalogo-item-autor">' + escapeHtml(item.created_by_name || '') + ' · usado ' + (item.usage_count || 0) + ' veces</span>' +
        '<button type="button" data-insertar="' + index + '">Insertar</button>';
      contenedor.appendChild(card);
    });
    contenedor.querySelectorAll('[data-insertar]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var item = ultimaLista[parseInt(btn.dataset.insertar, 10)];
        if (item) insertar(item.id);
      });
    });
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
    mensaje('catalogo_guardar_message', 'Guardando en el Catálogo Global...', false);
    sketchup.catalogoGuardar(categoria, nombre, (id('catalogo_guardar_descripcion').value || '').trim(), datos);
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
      return;
    }
    mensaje('catalogo_guardar_message', 'Guardado. Ya está disponible para todo el equipo con licencia activa.', false);
    if (cargado) actualizar();
  };

  if (id('catalogo_actualizar')) id('catalogo_actualizar').addEventListener('click', actualizar);
  if (id('catalogo_categoria')) id('catalogo_categoria').addEventListener('change', actualizar);
  if (id('catalogo_buscar')) id('catalogo_buscar').addEventListener('keydown', function (event) { if (event.key === 'Enter') actualizar(); });
  if (id('catalogo_guardar_boton')) id('catalogo_guardar_boton').addEventListener('click', guardar);

  window.addEventListener('modular3d:pageShown', function (event) {
    if (event.detail && event.detail.id === 'catalogo') cargarPrimeraVez();
  });
})();
