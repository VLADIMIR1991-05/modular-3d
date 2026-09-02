(function () {
  'use strict';

  var scene, camera, renderer, controls, model, grid, floor, selected, selectionBox, spaceSelection;
  var meshes = [], spaceMeshes = [], selectedSpaceId = null, currentData = {}, needsRender = true, orthographic = false;
  var selectionMode = 'space', isolated = false;
  var exploded = 0, transparent = false, shadows = true, edgesVisible = true;
  var technical = false, dimensionsVisible = false, gridWanted = true, sky, dimensionGroup;
  var raycaster = new THREE.Raycaster(), pointer = new THREE.Vector2();
  var pointerStart = null;
  var originalCenter = new THREE.Vector3(), originalSize = new THREE.Vector3();
  var COLORS = {
    lateral: 0xc99258, horizontal: 0xe0b37c, interior: 0xd7a66e,
    back: 0xcdbda8, front: 0xf06424, drawer: 0xb87543,
    glass: 0x73b9d6, handle: 0x4d5963
  };

  function materialGroup(category, role) {
    if (category === 'front') return 'frentes';
    if (category === 'drawer') return 'cajones';
    if (category === 'back') return 'respaldo';
    if (category === 'adjustment') return 'ajuste';
    if (category === 'handle') return 'herrajes';
    if (category === 'interior' || String(role || '').indexOf('local-') === 0 || String(role || '').indexOf('separator-') === 0) return 'interior';
    return 'casco';
  }
  function stableHierarchyId(value, fallback) {
    var clean = String(value == null ? '' : value).toUpperCase().replace(/[^A-Z0-9]+/g, '_').replace(/^_+|_+$/g, '');
    return clean || String(fallback == null ? 'N' : fallback);
  }
  function colorNumber(value, fallback) {
    var text = String(value || '').replace('#','');
    return /^[0-9a-f]{6}$/i.test(text) ? parseInt(text,16) : fallback;
  }
  function resolvedPieceStyle(category, role, pieceId, materialKey, fallback) {
    var group=materialGroup(category,role),overrides={},textures={},textureMeta={};
    try{overrides=JSON.parse(currentData.material_overrides_json||'{}')||{};}catch(_e){overrides={};}
    try{textures=JSON.parse(currentData.material_textures_json||'{}')||{};}catch(_t){textures={};}
    try{textureMeta=JSON.parse(currentData.material_texture_meta_json||'{}')||{};}catch(_m){textureMeta={};}
    var override=overrides[materialKey]||overrides[pieceId]||null;
    var useGlobal=currentData.material_unico==='SI',groupCustom=currentData['material_'+group+'_custom']==='SI';
    var groupColor=useGlobal&&!groupCustom?currentData.material_global_color:currentData['material_'+group+'_color'],groupName=useGlobal&&!groupCustom?currentData.material_global_nombre:currentData['material_'+group+'_nombre'];
    var resolvedColor=colorNumber(override&&override.color, colorNumber(groupColor,fallback)),edgeMode=String(currentData.edge_mode||'MIXED'),edge=(override&&override.edge&&override.edge!=='INHERIT')?override.edge:(edgeMode==='ALL_HARD'?'HARD':(edgeMode==='ALL_PVC'?'PVC':(group==='frentes'?'HARD':'PVC'))),edgeColor=(override&&override.edgeColor&&override.edgeColor!=='INHERIT')?override.edgeColor:('#'+resolvedColor.toString(16).padStart(6,'0'));
    var textureKey=useGlobal&&!groupCustom?'global':group,meta=textureMeta[textureKey]||{};
    return {group:group,color:resolvedColor,name:(override&&override.name)||groupName||group,custom:!!override,texture:(override&&override.texture)||textures[textureKey]||'',rotation:Number(override&&override.rotation!=='INHERIT'?override.rotation:meta.rotation)||0,scale:Number(meta.scale)||600,edge:edge,edgeColor:edgeColor};
  }

  function byId(id) { return document.getElementById(id); }
  function number(data, key, fallback) {
    var value = Number(data[key]);
    return isFinite(value) ? value : fallback;
  }
  function requestRender() { needsRender = true; }
  function disposeMaterial(material) {
    if (!material) return;
    if (Array.isArray(material)) { material.forEach(disposeMaterial); return; }
    if (material.map) material.map.dispose();
    material.dispose();
  }
  function disposeObject(object){if(!object)return;scene.remove(object);object.traverse(function(item){if(item.geometry)item.geometry.dispose();if(item.material)disposeMaterial(item.material);});}
  function clearModel() {
    if (selectionBox) disposeObject(selectionBox);
    if (spaceSelection) scene.remove(spaceSelection);
    selectionBox = null;
    spaceSelection = null;
    selected = null;
    isolated = false;
    if(byId('view_piece_isolate'))byId('view_piece_isolate').classList.remove('active');
    spaceMeshes.forEach(function(mesh){scene.remove(mesh);if(mesh.geometry)mesh.geometry.dispose();if(mesh.material)disposeMaterial(mesh.material);});
    spaceMeshes = [];
    if (model) {
      scene.remove(model);
      model.traverse(function (item) {
        if (item.geometry) item.geometry.dispose();
        if (item.material) disposeMaterial(item.material);
      });
    }
    model = new THREE.Group();
    scene.add(model);
    meshes = [];
  }

  function addSpaceHit(node) {
    var b=node&&node.box;if(!b||b.w<=0||b.h<=0||b.d<=0)return;
    var geometry=new THREE.BoxGeometry(b.w,b.h,b.d),hit=new THREE.Mesh(geometry,new THREE.MeshBasicMaterial({color:0xff6b1a,transparent:true,opacity:0.012,depthWrite:false,side:THREE.DoubleSide}));
    hit.position.set(b.x+b.w/2,b.z+b.h/2,-(b.y+b.d/2));hit.userData={spaceId:node.id,spaceNode:node,spaceVolume:b.w*b.h*b.d};hit.renderOrder=900;scene.add(hit);spaceMeshes.push(hit);
  }

  function selectSpace(nodeId, emitEvent) {
    if(emitEvent&&nodeId)selectPiece(null);
    if(spaceSelection){scene.remove(spaceSelection);spaceSelection.traverse(function(item){if(item.geometry)item.geometry.dispose();if(item.material)disposeMaterial(item.material);});spaceSelection=null;}
    selectedSpaceId=nodeId||null;var hit=spaceMeshes.filter(function(item){return item.userData.spaceId===selectedSpaceId;})[0];
    var badge=byId('view_space_badge'),badgeText=byId('view_space_text');
    if(hit){var node=hit.userData.spaceNode,b=node.box,group=new THREE.Group();var fill=new THREE.Mesh(new THREE.BoxGeometry(b.w,b.h,b.d),new THREE.MeshBasicMaterial({color:0xff5a16,transparent:true,opacity:0.16,depthTest:false,depthWrite:false,side:THREE.DoubleSide}));var edge=new THREE.LineSegments(new THREE.EdgesGeometry(fill.geometry),new THREE.LineBasicMaterial({color:0xff4b00,depthTest:false,transparent:true,opacity:1}));fill.position.copy(hit.position);edge.position.copy(hit.position);fill.renderOrder=995;edge.renderOrder=996;group.add(fill,edge);scene.add(group);spaceSelection=group;if(badge)badge.classList.add('show');if(badgeText)badgeText.textContent=(node.display_name||node.name||node.id)+' · '+Math.round(b.w)+' × '+Math.round(b.h)+' × '+Math.round(b.d)+' mm';}
    else if(badge)badge.classList.remove('show');
    if(emitEvent&&selectedSpaceId)window.dispatchEvent(new CustomEvent('modular3d:spaceSelected3D',{detail:{id:selectedSpaceId}}));requestRender();
  }

  function setSelectionMode(mode) {
    selectionMode=mode==='piece'?'piece':'space';
    if(byId('view_mode_space'))byId('view_mode_space').classList.toggle('active',selectionMode==='space');
    if(byId('view_mode_piece'))byId('view_mode_piece').classList.toggle('active',selectionMode==='piece');
    renderer&&renderer.domElement&&renderer.domElement.setAttribute('data-selection-mode',selectionMode);
  }

  function material(color, glass) {
    var result = new THREE.MeshStandardMaterial({
      color: color,
      roughness: glass ? 0.16 : 0.58,
      metalness: glass ? 0.04 : 0.01,
      transparent: glass || transparent,
      opacity: glass ? 0.38 : (transparent ? 0.42 : 1),
      side: THREE.DoubleSide
    });
    result.userData.baseOpacity = glass ? 0.38 : 1;
    return result;
  }
  function applyTexture(target, source, scale, rotation){
    if(!source||!target)return;
    var configure=function(baseTexture){var texture=baseTexture.clone();texture.needsUpdate=true;texture.wrapS=texture.wrapT=THREE.RepeatWrapping;texture.repeat.set(Math.max(.1,600/(Number(scale)||600)),Math.max(.1,600/(Number(scale)||600)));texture.center.set(.5,.5);texture.rotation=(Number(rotation)||0)*Math.PI/180;texture.anisotropy=renderer&&renderer.capabilities?Math.min(8,renderer.capabilities.getMaxAnisotropy()):1;target.map=texture;target.needsUpdate=true;requestRender();};
    if(textureCache[source]){configure(textureCache[source]);return;}
    var loader=new THREE.TextureLoader();loader.setCrossOrigin('anonymous');loader.load(source,function(texture){textureCache[source]=texture;configure(texture);},undefined,function(){/* URL sin CORS: conserva el color configurado. */});
  }

  var MITER_CORNERS = ['front_left', 'front_right', 'back_right', 'back_left'];
  var MITER_CORNERS_HORIZONTAL = ['bottom_inner', 'bottom_outer', 'top_outer', 'top_inner'];
  function resolvedMiter(pieceId, materialKey) {
    var overrides = {};
    try { overrides = JSON.parse(currentData.miter_overrides_json || '{}') || {}; } catch (_e) { overrides = {}; }
    var entry = overrides[materialKey] || overrides[pieceId] || null;
    if (!entry) return null;
    var size = Number(entry.size) || 0;
    if (size <= 0) return null;
    if (MITER_CORNERS.indexOf(entry.corner) >= 0) return { corner: entry.corner, size: size, axis: 'vertical' };
    if (MITER_CORNERS_HORIZONTAL.indexOf(entry.corner) >= 0) return { corner: entry.corner, size: size, axis: 'horizontal' };
    return null;
  }
  /* Prisma con una esquina vertical del footprint (X/Z locales, constante en
     toda la altura Y) cortada a 45°. Replica exactamente puntos_footprint_
     biselado + pushpull de plugin.rb para que la previsualización coincida
     con la pieza real. Centrado en el origen como BoxGeometry, para que el
     posicionamiento de addPiece no necesite cambios. */
  function chamferedBoxGeometry(width, height, depth, corner, size) {
    var hw = width / 2, hh = height / 2, hd = depth / 2;
    var s = Math.min(size, width * 0.48, depth * 0.48);
    if (!(s > 0)) return new THREE.BoxGeometry(width, height, depth);
    var base = { front_left: [-hw, hd], front_right: [hw, hd], back_right: [hw, -hd], back_left: [-hw, -hd] };
    var order = ['front_left', 'front_right', 'back_right', 'back_left'];
    var poly = [];
    order.forEach(function (name) {
      var p = base[name];
      if (name !== corner) { poly.push(p); return; }
      if (name === 'front_left') { poly.push([p[0], p[1] - s], [p[0] + s, p[1]]); }
      else if (name === 'front_right') { poly.push([p[0] - s, p[1]], [p[0], p[1] - s]); }
      else if (name === 'back_right') { poly.push([p[0], p[1] + s], [p[0] - s, p[1]]); }
      else { poly.push([p[0] + s, p[1]], [p[0], p[1] + s]); }
    });
    var positions = [];
    function pushTri(a, b, c) { positions.push(a[0], a[1], a[2], b[0], b[1], b[2], c[0], c[1], c[2]); }
    var top = poly.map(function (p) { return [p[0], hh, p[1]]; });
    var bottom = poly.map(function (p) { return [p[0], -hh, p[1]]; });
    for (var i = 1; i < top.length - 1; i += 1) pushTri(top[0], top[i], top[i + 1]);
    for (var j = 1; j < bottom.length - 1; j += 1) pushTri(bottom[0], bottom[j + 1], bottom[j]);
    for (var k = 0; k < poly.length; k += 1) {
      var next = (k + 1) % poly.length;
      pushTri(bottom[k], bottom[next], top[next]);
      pushTri(bottom[k], top[next], top[k]);
    }
    var geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
    geometry.computeVertexNormals();
    return geometry;
  }
  /* Variante horizontal: corta el canto superior/inferior donde un lateral se
     une al techo o la base (constante en toda la profundidad, no en la
     altura). Replica perfil_biselado_horizontal + pushpull(-prof) de
     plugin.rb: el perfil vive en el plano ancho x alto (X/Y locales) y se
     extruye a lo largo de la profundidad (Z local de la geometría). */
  function chamferedBoxGeometryHorizontal(width, height, depth, corner, size) {
    var hw = width / 2, hh = height / 2, hd = depth / 2;
    var s = Math.min(size, width * 0.48, height * 0.48);
    if (!(s > 0)) return new THREE.BoxGeometry(width, height, depth);
    var base = { bottom_inner: [-hw, -hh], bottom_outer: [hw, -hh], top_outer: [hw, hh], top_inner: [-hw, hh] };
    var order = ['bottom_inner', 'bottom_outer', 'top_outer', 'top_inner'];
    var poly = [];
    order.forEach(function (name) {
      var p = base[name];
      if (name !== corner) { poly.push(p); return; }
      if (name === 'bottom_inner') { poly.push([p[0], p[1] + s], [p[0] + s, p[1]]); }
      else if (name === 'bottom_outer') { poly.push([p[0] - s, p[1]], [p[0], p[1] + s]); }
      else if (name === 'top_outer') { poly.push([p[0], p[1] - s], [p[0] - s, p[1]]); }
      else { poly.push([p[0] + s, p[1]], [p[0], p[1] - s]); }
    });
    var positions = [];
    function pushTri(a, b, c) { positions.push(a[0], a[1], a[2], b[0], b[1], b[2], c[0], c[1], c[2]); }
    var front = poly.map(function (p) { return [p[0], p[1], hd]; });
    var back = poly.map(function (p) { return [p[0], p[1], -hd]; });
    for (var i = 1; i < front.length - 1; i += 1) pushTri(front[0], front[i], front[i + 1]);
    for (var j = 1; j < back.length - 1; j += 1) pushTri(back[0], back[j + 1], back[j]);
    for (var k = 0; k < poly.length; k += 1) {
      var next = (k + 1) % poly.length;
      pushTri(back[k], back[next], front[next]);
      pushTri(back[k], front[next], front[k]);
    }
    var geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
    geometry.computeVertexNormals();
    return geometry;
  }
  function addPiece(name, width, height, depth, x, y, z, color, category, glass, metadata) {
    if (width <= 0 || height <= 0 || depth <= 0) return null;
    metadata=metadata||{};
    var generatedId=metadata.pieceId||('piece_' + (meshes.length + 1)),materialKey=metadata.materialKey||generatedId,style=resolvedPieceStyle(category,metadata.role||category,generatedId,materialKey,color);
    var miter = resolvedMiter(generatedId, materialKey);
    var geometry = miter ? (miter.axis === 'horizontal' ? chamferedBoxGeometryHorizontal(width, height, depth, miter.corner, miter.size) : chamferedBoxGeometry(width, height, depth, miter.corner, miter.size)) : new THREE.BoxGeometry(width, height, depth);
    var pieceMaterial=material(style.color, glass);applyTexture(pieceMaterial,style.texture,style.scale,style.rotation);var piece = new THREE.Mesh(geometry, pieceMaterial);
    // Modelo: X=derecha, Y=fondo, Z=arriba. Three.js usa Z=-fondo.
    piece.position.set(x + width / 2, y + height / 2, -(z + depth / 2));
    piece.castShadow = shadows;
    piece.receiveShadow = shadows;
    piece.userData = {
      selectable: true, name: name, category: category,
      dimensions: { length: Math.max(width, height, depth), width: [width, height, depth].sort(function(a,b){return b-a;})[1], thickness: Math.min(width, height, depth) },
      size: { x: width, y: height, z: depth }, original: piece.position.clone(), glass: !!glass,
      pieceId: generatedId, materialKey:materialKey, materialGroup:style.group, materialName:style.name, materialColor:'#'+style.color.toString(16).padStart(6,'0'), materialCustom:style.custom, edgeType:style.edge, edgeColor:style.edgeColor,
      role: metadata.role || category,
      ownerSpaceId: metadata.ownerSpaceId || null,
      parentSpaceId: metadata.parentSpaceId || null,
      sourceField: metadata.sourceField || null,
      realMaterial: pieceMaterial, technicalMaterial: null
    };
    var edge = new THREE.LineSegments(
      new THREE.EdgesGeometry(geometry),
      new THREE.LineBasicMaterial({ color: 0x58483d, transparent: true, opacity: 0.48 })
    );
    edge.name = '__edges';
    edge.visible = edgesVisible;
    piece.add(edge);
    model.add(piece);
    meshes.push(piece);
    return piece;
  }

  function stationSizes(expression, total, separator) {
    var tokens = String(expression || '').split(':').map(function(v){ return v.trim(); }).filter(Boolean);
    if (!tokens.length) return null;
    var usable = total - Math.max(0, tokens.length - 1) * separator;
    if (usable <= 0) return null;
    var fixed = 0, flexible = 0;
    var items = tokens.map(function(token) {
      var match = token.match(/^(\d+(?:\.\d+)?)\s*(mm|cm|m)$/i);
      if (match) {
        var raw = Number(match[1]), unit = match[2].toLowerCase();
        var mm = unit === 'mm' ? raw : (unit === 'cm' ? raw * 10 : raw * 1000);
        fixed += mm; return ['fixed', mm];
      }
      match = token.match(/^(\d+(?:\.\d+)?)%$/);
      if (match) { var percent = usable * Number(match[1]) / 100; fixed += percent; return ['fixed', percent]; }
      if (/^auto$/i.test(token)) { flexible += 1; return ['flex', 1]; }
      match = token.match(/^(\d+(?:\.\d+)?)$/);
      if (match && Number(match[1]) > 0) { flexible += Number(match[1]); return ['flex', Number(match[1])]; }
      return ['invalid', 0];
    });
    if (items.some(function(item){ return item[0] === 'invalid'; }) || fixed > usable) return null;
    var remaining = usable - fixed;
    if (remaining > 0.01 && flexible <= 0) return null;
    return items.map(function(item){ return item[0] === 'fixed' ? item[1] : remaining * item[1] / flexible; });
  }

  function cumulative(sizes, start, separator) {
    var result = [], cursor = start;
    sizes.forEach(function(size) { result.push(cursor); cursor += size + separator; });
    return result;
  }

  var selectedPieceKey = null;
  var textureCache = {};
  function build(data) {
    currentData = data || {};
    var hadModel=meshes.length>0,priorPosition=camera&&camera.position?camera.position.clone():null,priorTarget=controls&&controls.target?controls.target.clone():null,priorPieceKey=selectedPieceKey;
    clearModel();
    var width = number(data, 'ancho_total', 600), height = number(data, 'alto_total', 760), depth = number(data, 'prof_total', 580);
    var general = number(data, 'espesor', 15), leftT = number(data, 'grosor_izq', general), rightT = number(data, 'grosor_der', general);
    var topT = number(data, 'grosor_superior', general), bottomT = number(data, 'grosor_inferior', general);
    var innerW = Math.max(1, width - leftT - rightT), innerH = Math.max(1, height - topT - bottomT);
    var interiorSetback = number(data, 'retranqueo_interior', 38), interiorDepth = Math.max(1, depth - interiorSetback);
    var hierarchyGeometry = null;
    try { hierarchyGeometry = JSON.parse(data.hierarchy_geometry_json || 'null'); } catch (_hierarchyError) { hierarchyGeometry = null; }
    var hasHierarchy = !!(hierarchyGeometry && Array.isArray(hierarchyGeometry.nodes));
    var frontScope = String(data.external_front_scope || 'BY_SPACE').toUpperCase();
    var physicalX = String(data.param_x_type || 'FISICA') !== 'VIRTUAL';
    var physicalZ = String(data.param_z_type || 'FISICA') !== 'VIRTUAL';
    var colSizes = stationSizes(data.param_x_expr, innerW, physicalX ? general : 0);
    var rowSizes = stationSizes(data.param_z_expr, innerH, physicalZ ? general : 0);
    var divisions = Math.max(0, parseInt(data.num_divisiones, 10) || 0), shelves = Math.max(0, parseInt(data.num_repisas, 10) || 0);
    if (!colSizes) colSizes = Array(divisions + 1).fill((innerW - divisions * general) / (divisions + 1));
    if (!rowSizes) rowSizes = Array(shelves + 1).fill((innerH - shelves * general) / (shelves + 1));
    var colSeparator = physicalX ? general : 0, rowSeparator = physicalZ ? general : 0;
    var colStarts = cumulative(colSizes, leftT, colSeparator), rowStarts = cumulative(rowSizes, bottomT, rowSeparator);

    /* Casco: replica EXACTA de la lógica de plugin.rb (montaje interior/exterior,
       retranqueos por panel y paneles activables) para que la previsualización
       nunca difiera de la geometría real que se construye en SketchUp. */
    var madevalDelta = String(data.madeval || 'NO') === 'SI' ? 1 : 0;
    var usableW = Math.max(1, innerW - madevalDelta);
    var mountLeft = String(data.montaje_izq || 'EXTERIOR').toUpperCase();
    var mountRight = String(data.montaje_der || 'EXTERIOR').toUpperCase();
    var mountTop = String(data.montaje_superior || 'INTERIOR').toUpperCase();
    var mountBottom = String(data.montaje_inferior || 'INTERIOR').toUpperCase();
    var hasLeft = String(data.lleva_lateral_izq || 'SI') !== 'NO';
    var hasRight = String(data.lleva_lateral_der || 'SI') !== 'NO';
    var hasBottom = String(data.lleva_base || 'SI') !== 'NO';
    var hasTop = String(data.lleva_techo || 'SI') !== 'NO';
    // Sobremedida: positivo = panel mas grande hacia ese lado (sobresale),
    // negativo = mas chico (se retranquea). Se niega para reusar el mismo
    // calculo de fondo/posicion de mas abajo (setback = -sobremedida).
    var setbackFrontTop = -number(data, 'sobremedida_frontal_superior', 0), setbackBackTop = -number(data, 'sobremedida_trasera_superior', 0);
    var setbackFrontBottom = -number(data, 'sobremedida_frontal_inferior', 0), setbackBackBottom = -number(data, 'sobremedida_trasera_inferior', 0);
    var setbackFrontLeft = -number(data, 'sobremedida_frontal_izq', 0), setbackBackLeft = -number(data, 'sobremedida_trasera_izq', 0);
    var setbackFrontRight = -number(data, 'sobremedida_frontal_der', 0), setbackBackRight = -number(data, 'sobremedida_trasera_der', 0);

    var depthLeft = Math.max(1, depth - setbackFrontLeft - setbackBackLeft);
    var depthRight = Math.max(1, depth - setbackFrontRight - setbackBackRight);
    var heightLeft = mountLeft === 'INTERIOR' ? innerH : height, heightRight = mountRight === 'INTERIOR' ? innerH : height;
    var zLeft = mountLeft === 'INTERIOR' ? bottomT : 0, zRight = mountRight === 'INTERIOR' ? bottomT : 0;
    if (hasLeft) addPiece('Lateral izquierdo', leftT, heightLeft, depthLeft, 0, zLeft, setbackFrontLeft, COLORS.lateral, 'lateral', false, {pieceId:'shell-left',materialKey:'LAT_IZQ',role:'shell-left',sourceField:'grosor_izq'});
    if (hasRight) addPiece('Lateral derecho', rightT, heightRight, depthRight, width - rightT, zRight, setbackFrontRight, COLORS.lateral, 'lateral', false, {pieceId:'shell-right',materialKey:'LAT_DER',role:'shell-right',sourceField:'grosor_der'});

    var bottomW = mountBottom === 'EXTERIOR' ? width : usableW, bottomX = mountBottom === 'EXTERIOR' ? 0 : leftT;
    var bottomDepth = Math.max(1, depth - setbackFrontBottom - setbackBackBottom);
    if (hasBottom) addPiece('Panel inferior', bottomW, bottomT, bottomDepth, bottomX, 0, setbackFrontBottom, COLORS.horizontal, 'horizontal', false, {pieceId:'shell-bottom',materialKey:'BASE',role:'shell-bottom',sourceField:'grosor_inferior'});

    var topW = mountTop === 'EXTERIOR' ? width : usableW, topX = mountTop === 'EXTERIOR' ? 0 : leftT;
    var topDepth = Math.max(1, depth - setbackFrontTop - setbackBackTop);
    if (hasTop) addPiece('Panel superior', topW, topT, topDepth, topX, height - topT, setbackFrontTop, COLORS.horizontal, 'top', false, {pieceId:'shell-top',materialKey:'TECHO',role:'shell-top',sourceField:'grosor_superior'});

    if (!hasHierarchy && physicalX) for (var c = 0; c < colSizes.length - 1; c += 1) {
      addPiece('División vertical ' + (c + 1), general, innerH, interiorDepth, colStarts[c] + colSizes[c], bottomT, interiorSetback, COLORS.interior, 'interior');
    }
    if (!hasHierarchy && physicalZ) for (var r = 0; r < rowSizes.length - 1; r += 1) {
      addPiece('Repisa ' + (r + 1), usableW, general, interiorDepth, leftT, rowStarts[r] + rowSizes[r], interiorSetback, COLORS.interior, 'interior');
    }

    /* Sistema posterior: mismas 3 variantes y la misma secuencia atrás->adelante
       que plugin.rb (distancia posterior -> ajuste -> separación -> respaldo). */
    var backMode = String(data.lleva_respaldo == null ? 'SI' : data.lleva_respaldo).toUpperCase();
    var adjustmentT = number(data, 'grosor_ajuste', general), adjustmentH = number(data, 'alto_ajuste', 60);
    var rearOffset = number(data, 'distancia_plano_posterior', 0), rearGap = number(data, 'separacion_ajuste_respaldo', 2);
    var backT = number(data, 'grosor_resp', 6), structuralBack = backT >= 15;
    var adjustmentCountRaw = String(data.cantidad_ajustes == null ? 'AUTO' : data.cantidad_ajustes).toUpperCase();
    var adjustmentCount = 0;
    if (backMode !== 'NO' && !structuralBack) {
      adjustmentCount = adjustmentCountRaw === 'AUTO' ? (height > 760 ? 2 : 1) : Math.max(0, parseInt(adjustmentCountRaw, 10) || 0);
      adjustmentCount = Math.max(0, Math.min(4, adjustmentCount));
    }
    var adjustmentY = Math.max(0, depth - rearOffset - adjustmentT);
    var zTopAdjustment = height - topT - adjustmentH;
    function addAdjustmentSquares(prefix, yStart) {
      addPiece(prefix + ' · escuadra izq.', adjustmentT, adjustmentT, adjustmentH, leftT, zTopAdjustment, yStart, COLORS.handle, 'adjustment', false, {role:'rear-adjustment',sourceField:'grosor_ajuste'});
      addPiece(prefix + ' · escuadra der.', adjustmentT, adjustmentT, adjustmentH, width - rightT - adjustmentT, zTopAdjustment, yStart, COLORS.handle, 'adjustment', false, {role:'rear-adjustment',sourceField:'grosor_ajuste'});
    }
    if (adjustmentCount > 0) {
      var rearOrientation = String(data.ajuste_posterior_orientacion || 'HORIZONTAL').toUpperCase();
      if (rearOrientation === 'VERTICAL') addAdjustmentSquares('Ajuste posterior', adjustmentY);
      else addPiece('Ajuste superior', usableW, adjustmentH, adjustmentT, leftT, zTopAdjustment, adjustmentY, COLORS.handle, 'adjustment', false, {role:'rear-adjustment',sourceField:'grosor_ajuste'});
      if (adjustmentCount > 1) for (var aidx = 2; aidx <= adjustmentCount; aidx += 1) {
        var rearSpan = height - topT - bottomT - adjustmentH;
        var fraction = aidx === 2 ? 0.5 : (adjustmentCount - aidx + 1) / adjustmentCount;
        var az = bottomT + (rearSpan * fraction) - (adjustmentH / 2);
        az = Math.max(bottomT, Math.min(zTopAdjustment - adjustmentH, az));
        addPiece('Ajuste posterior ' + (aidx - 1), usableW, adjustmentH, adjustmentT, leftT, az, adjustmentY, COLORS.handle, 'adjustment', false, {role:'rear-adjustment',sourceField:'grosor_ajuste'});
      }
    }
    if (String(data.ajuste_frontal_activo || 'NO').toUpperCase() === 'SI') {
      var frontOrientation = String(data.ajuste_frontal_orientacion || 'HORIZONTAL').toUpperCase();
      if (frontOrientation === 'VERTICAL') addAdjustmentSquares('Ajuste frontal', 0);
      else addPiece('Ajuste frontal', usableW, adjustmentH, adjustmentT, leftT, zTopAdjustment, 0, COLORS.handle, 'adjustment', false, {role:'front-adjustment',sourceField:'grosor_ajuste'});
    }

    if (backMode === 'SI') {
      var groove = number(data, 'profundidad_ranura', 5);
      var backW = innerW + groove * 2, backH = innerH + groove * 2;
      var rearClearance = structuralBack ? (rearOffset + backT) : (rearOffset + adjustmentT + rearGap + backT);
      var backY = depth - rearClearance;
      addPiece('Respaldo', backW, backH, backT, leftT - groove, bottomT - groove, backY, COLORS.back, 'back', false, {pieceId:'back',materialKey:'RESPALDO',role:'back',sourceField:'grosor_resp'});
    } else if (backMode === 'INTERNO') {
      var backYInterno = structuralBack ? (depth - rearOffset - backT) : (adjustmentY - rearGap - backT);
      addPiece('Respaldo interno', innerW, innerH, backT, leftT, bottomT, backYInterno, COLORS.back, 'back', false, {pieceId:'back',materialKey:'RESPALDO_INTERNO',role:'back',sourceField:'grosor_resp'});
    } else if (backMode === 'SOBREPUESTO') {
      var overlayGap = 1.5, backYSobre = depth - rearOffset - backT;
      addPiece('Respaldo sobrepuesto', width - overlayGap * 2, height - overlayGap * 2, backT, overlayGap, overlayGap, backYSobre, COLORS.back, 'back', false, {pieceId:'back',materialKey:'RESPALDO_SOBREPUESTO',role:'back',sourceField:'grosor_resp'});
    }

    /* Configuración jerárquica: la geometría resuelta alimenta directamente al visor. */
    if (hierarchyGeometry && Array.isArray(hierarchyGeometry.separators)) {
      (hierarchyGeometry.nodes || []).forEach(addSpaceHit);
      var separatorsByParent = {};
      hierarchyGeometry.separators.forEach(function(separator, index) {
        var parentId = stableHierarchyId(separator.parent, 'ROOT');
        separatorsByParent[parentId] = (separatorsByParent[parentId] || 0) + 1;
        var suffix = parentId + '_' + separatorsByParent[parentId];
        addPiece(
          (separator.axis === 'X' ? 'Divisor vertical ' : (separator.axis === 'Z' ? 'Repisa ' : 'Separador de profundidad ')) + (index + 1),
          separator.w, separator.h, separator.d, separator.x, separator.z, separator.y,
          COLORS.interior, 'interior', false, {pieceId:'separator_'+index,materialKey:(separator.axis==='X'?'H_DIV_X_':(separator.axis==='Z'?'H_REP_Z_':'H_DIV_Y_'))+suffix,role:'separator-'+String(separator.axis||'').toLowerCase(),ownerSpaceId:separator.parent,parentSpaceId:separator.parent,sourceField:'hierarchy_expr'}
        );
      });
      (hierarchyGeometry.nodes || []).forEach(function(node,nodeIndex) {
        var b = node.box, nodeLabel=node.display_name||node.name||node.id, content = String(node.content || 'VACIO'), gap = Number(node.gap == null ? 3 : node.gap), drawerCount = Math.max(0, parseInt(node.drawers, 10) || 0);
        var isLeaf = !(node.children || []).length, enclosure = node.enclosure || {};
        var nid = stableHierarchyId(node.id, 'IDX' + (nodeIndex + 1));
        var localMeta=function(role,field,suffix){var prefixes={'local-left':'H_CIERRE_IZQ_','local-right':'H_CIERRE_DER_','local-bottom':'H_BASE_','local-top':'H_TECHO_','local-back':'H_RESP_','local-shelf':'H_REP_LOCAL_','door':'H_PUERTA_','drawer-front':'H_CJ_'};return{pieceId:role+'_'+node.id+(suffix||''),materialKey:(prefixes[role]||('H_'+role.toUpperCase().replace(/-/g,'_')+'_'))+nid+(suffix||''),role:role,ownerSpaceId:node.id,parentSpaceId:node.id,sourceField:field};};
        if (enclosure.left) addPiece('Lateral local · '+nodeLabel,general,b.h,b.d,b.x,b.z,b.y,COLORS.interior,'interior',false,localMeta('local-left','h_left'));
        if (enclosure.right) addPiece('Lateral local · '+nodeLabel,general,b.h,b.d,b.x+b.w-general,b.z,b.y,COLORS.interior,'interior',false,localMeta('local-right','h_right'));
        if (enclosure.bottom) addPiece('Base local · '+nodeLabel,b.w,general,b.d,b.x,b.z,b.y,COLORS.interior,'interior',false,localMeta('local-bottom','h_bottom'));
        if (enclosure.top) addPiece('Techo local · '+nodeLabel,b.w,general,b.d,b.x,b.z+b.h-general,b.y,COLORS.interior,'interior',false,localMeta('local-top','h_top'));
        if (enclosure.back) addPiece('Respaldo local · '+nodeLabel,b.w,b.h,number(data,'grosor_resp',6),b.x,b.z,b.y+b.d-number(data,'grosor_resp',6),COLORS.back,'back',false,localMeta('local-back','h_back'));
        var shelfCount = isLeaf && content === 'REPISAS' ? Math.min(20, Math.max(1, parseInt(node.shelves, 10) || 1)) : 0;
        for (var hs = 1; hs <= shelfCount; hs += 1) addPiece('Repisa interna · ' + nodeLabel + ' ' + hs, b.w, general, b.d, b.x, b.z + b.h * hs / (shelfCount + 1) - general / 2, b.y, COLORS.interior, 'interior',false,localMeta('local-shelf','h_shelves','_'+hs));
        if (isLeaf && content.indexOf('CAJONES') === 0) {
          drawerCount = Math.min(12, Math.max(1, drawerCount || 3));
          // Espacio entre cajones: propio (drawerGap, 30mm por defecto), no
          // el mismo "gap" que usan las puertas. Altura manual si se pidio
          // una y entra junto con las fugas; si no, automatica.
          var drawerGap = Number(node.drawerGap == null ? 30 : node.drawerGap);
          var drawerHeightAuto = Math.max(20, (b.h - drawerGap * (drawerCount + 1)) / drawerCount);
          var drawerHeightManual = Number(node.drawerHeight) || 0;
          var drawerHeightFits = drawerHeightManual > 0 && (drawerHeightManual * drawerCount + drawerGap * (drawerCount + 1)) <= b.h;
          var drawerHeight = drawerHeightFits ? drawerHeightManual : drawerHeightAuto;
          var nodeSinPuertaPropia = !node.front || String(node.front).toUpperCase() === 'NINGUNO';
          var frenteCajonActivo = content === 'CAJONES_FRENTES' && frontScope !== 'GLOBAL' && nodeSinPuertaPropia;
          var estiloFrenteCajon = frenteCajonActivo ? String(node.drawerFrontStyle || 'POR_CAJON').toUpperCase() : 'POR_CAJON';
          // El frente se alinea al mismo plano/ancho que tendria una puerta
          // ahi (front_box, con el mismo solape sobre el casco/division):
          // sale del hueco interno del cajon igual que una puerta vecina, en
          // vez de quedarse angosto dentro de su propio espacio disponible.
          var fb = node.front_box || b;
          if (frenteCajonActivo && estiloFrenteCajon === 'FALSO') {
            // Frente falso: un unico panel fijo, sin ningun cajon detras.
            var fugaFalso = gap / 2;
            addPiece('Frente falso · ' + nodeLabel, Math.max(1,fb.w-fugaFalso*2), Math.max(1,fb.h-fugaFalso*2), general, fb.x+fugaFalso, fb.z+fugaFalso, -general-3, COLORS.drawer, 'front', false, localMeta('drawer-front','h_drawer_front_style'));
          } else {
            for (var hd = 0; hd < drawerCount; hd += 1) {
              var baseZ = b.z + drawerGap + hd * (drawerHeight + drawerGap);
              var construirFrenteEsteCajon = frenteCajonActivo && (estiloFrenteCajon !== 'UNICO_INFERIOR' || hd === 0);
              if (!construirFrenteEsteCajon) {
                addPiece('Cajón interno · ' + nodeLabel + ' ' + (hd + 1), Math.max(1,b.w-gap*2), drawerHeight, general, b.x+gap, baseZ, b.y+12, COLORS.drawer, 'drawer', false, localMeta('drawer','h_drawers'));
                continue;
              }
              // La zona de este frente llega hasta la MITAD de la fuga
              // mecanica (drawerGap) con el cajon vecino, no hasta el borde de
              // su propia caja: asi el frente se traga ese hueco mecanico
              // entero y solo deja una junta fina y fija de 3mm (1.5+1.5)
              // contra el frente vecino, sin importar cuanta fuga mecanica se
              // pida entre cajones. Contra el borde real del espacio deja el
              // mismo 1.5mm. Igual que en Ruby (plugin.rb).
              var fugaFrenteExt = gap / 2;
              var zonaInferior, zonaSuperior;
              if (estiloFrenteCajon === 'UNICO_INFERIOR') {
                zonaInferior = fb.z; zonaSuperior = fb.z + fb.h;
              } else {
                zonaInferior = hd === 0 ? fb.z : (baseZ - drawerGap / 2);
                zonaSuperior = hd === drawerCount - 1 ? (fb.z + fb.h) : (baseZ + drawerHeight + drawerGap / 2);
              }
              var altoFrente = (zonaSuperior - zonaInferior) - fugaFrenteExt * 2;
              var zFrente = zonaInferior + fugaFrenteExt;
              addPiece('Frente cajón · ' + nodeLabel + ' ' + (hd + 1), Math.max(1,fb.w-fugaFrenteExt*2), altoFrente, general, fb.x+fugaFrenteExt, zFrente, -general-3, COLORS.drawer, 'front', false, localMeta('drawer-front','h_drawers'));
            }
          }
        }
        var front = String(node.front || (content === 'CAJONES_PUERTA' ? 'PUERTA_UNICA' : 'NINGUNO')).replace(/_VIDRIO/g,'').replace(/VIDRIO/g,'UNICA');
        if (front !== 'NINGUNO') {
          var internalFront=front.indexOf('INTERNA')>=0,fb=internalFront?b:(node.front_box||((node.id==='root')?{x:1.5,z:1.5,w:width-3,h:height-3,y:0}:b));
          if (!internalFront && frontScope !== 'BY_SPACE') return;
          var requestedCount=String(node.frontCount||'AUTO').toUpperCase();
          var frontCount=requestedCount==='AUTO'?Math.max(1,Math.min(8,Math.ceil(fb.w/600))):Math.max(1,Math.min(8,parseInt(requestedCount,10)||1));
          var gapCenter=Math.max(0.5,Number(node.gapCenter==null?gap:node.gapCenter));
          var frontW = Math.max(1,(fb.w-(internalFront?gap*2:0)-gapCenter*(frontCount-1))/frontCount), frontH = Math.max(1,fb.h-(internalFront?gap*2:0)), frontT = number(data,'puerta_grosor',general);
          for (var hf=0;hf<frontCount;hf+=1) {
            var doorMeta=localMeta('door','h_front','_'+(hf+1));
            doorMeta.materialKey='H_PUERTA_'+(internalFront?'INT':'EXT')+'_'+nid+'_'+(hf+1);
            var externalEmbutida=!internalFront&&String(data.montaje_puerta||'SOLAPADA').toUpperCase()==='EMBUTIDA';
            addPiece((internalFront?'Puerta interna · ':'Puerta externa · ')+nodeLabel+' '+(hf+1),frontW,frontH,frontT,fb.x+(internalFront?gap:0)+hf*(frontW+gapCenter),fb.z+(internalFront?gap:0),internalFront?fb.y+2:(externalEmbutida?0:-frontT),COLORS.front,'front',false,doorMeta);
          }
        }
      });
      if(frontScope==='GLOBAL'){
        var globalMode=String(data.global_front_count_mode||'AUTO').toUpperCase();
        var autoWidth=Math.max(100,number(data,'global_front_auto_width',600));
        var globalCount=globalMode==='MANUAL'?Math.max(1,Math.min(8,parseInt(data.global_front_count,10)||1)):Math.max(1,Math.min(8,Math.ceil(width/autoWidth)));
        var gl=Math.max(0,number(data,'global_front_gap_left',3)),gr=Math.max(0,number(data,'global_front_gap_right',3));
        var gt=Math.max(0,number(data,'global_front_gap_top',3)),gb=Math.max(0,number(data,'global_front_gap_bottom',3)),gc=Math.max(0,number(data,'global_front_gap_center',3));
        var globalT=number(data,'puerta_grosor',general),globalW=Math.max(1,(width-gl-gr-gc*(globalCount-1))/globalCount),globalH=Math.max(1,height-gt-gb);
        for(var gf=0;gf<globalCount;gf+=1)addPiece('Puerta exterior global '+(gf+1),globalW,globalH,globalT,gl+gf*(globalW+gc),gb,-globalT,COLORS.front,'front',false,{pieceId:'global_front_'+(gf+1),materialKey:'G_PUERTA_EXT_'+(gf+1),role:'door',ownerSpaceId:'root',parentSpaceId:'root',sourceField:'global_front_count'});
      }
    }

    var spaces = [];
    try { spaces = JSON.parse(data.spaces_json || '[]'); } catch (_error) { spaces = []; }
    if (!Array.isArray(spaces)) spaces = [];
    if (!hasHierarchy) spaces.forEach(function(space) {
      var col = Math.max(0, Math.min(colSizes.length - 1, parseInt(space.column, 10) || 0));
      var row = Math.max(0, Math.min(rowSizes.length - 1, parseInt(space.niche, 10) || 0));
      var x = colStarts[col], y = rowStarts[row], cellW = colSizes[col], cellH = rowSizes[row];
      var content = String(space.content || 'VACIO'), gap = Number(space.gap == null ? 2 : space.gap);
      if (content === 'REPISAS') {
        var countShelves = Math.max(1, parseInt(space.shelves, 10) || 1);
        for (var localShelf = 1; localShelf <= countShelves; localShelf += 1) {
          addPiece('Repisa local ' + (localShelf), cellW, general, interiorDepth, x, y + cellH * localShelf / (countShelves + 1) - general / 2, interiorSetback, COLORS.interior, 'interior');
        }
      }
      if (content === 'CAJONERA') {
        var drawers = Math.max(1, parseInt(space.drawers, 10) || 3), drawerH = Math.max(20, (cellH - gap * (drawers + 1)) / drawers);
        for (var drawer = 0; drawer < drawers; drawer += 1) {
          var drawerY = y + gap + drawer * (drawerH + gap), external = space.front_type !== 'INTERNO';
          addPiece((external ? 'Frente cajón ' : 'Cajón interno ') + (drawer + 1), Math.max(1, cellW - gap * 2), drawerH, general, x + gap, drawerY, external ? -general - 3 : interiorSetback + 12, COLORS.drawer, external ? 'front' : 'drawer');
        }
      }
      if (content.indexOf('PUERTA') === 0) {
        var doubleDoor = content.indexOf('DOBLE') >= 0, glass = content.indexOf('VIDRIO') >= 0, doors = doubleDoor ? 2 : 1;
        var doorT = number(data, 'puerta_grosor', general);
        var doorEmbutida = String(data.montaje_puerta || 'SOLAPADA').toUpperCase() === 'EMBUTIDA';
        var doorW = doorEmbutida ? Math.max(1, (cellW - gap * (doors + 1)) / doors) : Math.max(1, (cellW / doors) - gap * 2);
        var doorH = Math.max(1, cellH - gap * 2);
        var doorZ = doorEmbutida ? 0 : -doorT;
        for (var door = 0; door < doors; door += 1) addPiece('Puerta ' + (door + 1), doorW, doorH, doorT, x + gap + door * (doorW + gap), y + gap, doorZ, glass ? COLORS.glass : COLORS.front, 'front', glass);
      }
    });

    if (!hasHierarchy && !spaces.length && data.crear_puerta === 'SI') {
      var doorThickness = number(data, 'puerta_grosor', general);
      var legacyEmbutida = String(data.montaje_puerta || 'SOLAPADA').toUpperCase() === 'EMBUTIDA';
      var gapDoor = legacyEmbutida ? number(data, 'luz_perimetral', number(data, 'juego_general', 3)) : number(data, 'luz_solape', 1.5);
      var isDouble = data.tipo_puerta === 'DOBLE' || data.tipo_puerta === 'DOBLE_VIDRIO' || (data.tipo_puerta === 'AUTO' && width > 619);
      var isGlass = String(data.tipo_puerta).indexOf('VIDRIO') >= 0, legacyDoors = isDouble ? 2 : 1;
      var legacyDoorW = legacyEmbutida ? (width - gapDoor * (legacyDoors + 1)) / legacyDoors : (width / legacyDoors) - gapDoor * 2;
      var legacyZ = legacyEmbutida ? 0 : -doorThickness;
      for (var ld = 0; ld < legacyDoors; ld += 1) addPiece('Puerta ' + (ld + 1), legacyDoorW, height - gapDoor * 2, doorThickness, gapDoor + ld * (legacyDoorW + gapDoor), gapDoor, legacyZ, isGlass ? COLORS.glass : COLORS.front, 'front', isGlass);
    }

    var box = new THREE.Box3().setFromObject(model);
    originalCenter = box.getCenter(new THREE.Vector3());
    originalSize = box.getSize(new THREE.Vector3());
    meshes.forEach(function(mesh){ mesh.userData.original.copy(mesh.position); });
    buildDimensionLabels();
    applyVisualState();
    applyBackdropState();
    if(hadModel&&priorPosition&&priorTarget){camera.position.copy(priorPosition);controls.target.copy(priorTarget);camera.lookAt(priorTarget);controls.update();}else frameModel();
    buildTree();
    updateModuleInfo(width, height, depth);
    selectPiece(null, true);
    var restoredPiece=priorPieceKey&&meshes.filter(function(item){return item.userData.materialKey===priorPieceKey||item.userData.pieceId===priorPieceKey;})[0];
    if(restoredPiece)selectPiece(restoredPiece,false,true);else selectSpace(data.selected_space_id || selectedSpaceId, false);
    requestRender();
  }

  function applyVisualState() {
    meshes.forEach(function(mesh) {
      var real = mesh.userData.realMaterial;
      var base = real.userData.baseOpacity || 1;
      real.opacity = mesh.userData.glass ? base : (transparent ? 0.38 : 1);
      real.transparent = mesh.userData.glass || transparent;
      real.depthWrite = !(mesh.userData.glass || transparent);
      if (technical) {
        if (!mesh.userData.technicalMaterial) mesh.userData.technicalMaterial = new THREE.MeshBasicMaterial({ color: 0xf2f0ea, side: THREE.DoubleSide });
        mesh.material = mesh.userData.technicalMaterial;
      } else {
        mesh.material = real;
      }
      mesh.castShadow = shadows && !technical;
      mesh.receiveShadow = shadows && !technical;
      var direction = mesh.userData.original.clone().sub(originalCenter).normalize();
      mesh.position.copy(mesh.userData.original).add(direction.multiplyScalar(exploded));
      var edge = mesh.getObjectByName('__edges');
      if (edge) {
        edge.visible = edgesVisible || technical;
        edge.material.color.set(technical ? 0x1a1a1a : 0x58483d);
        edge.material.opacity = technical ? 0.9 : 0.48;
      }
    });
    updateDimensionLabels();
    requestRender();
  }

  /* Aparte de applyVisualState a propósito: cleanSnapshot() manipula grid/
     floor/scene.background directamente para una captura limpia y luego
     llama a applyVisualState() para el resto del estado (explosión,
     transparencia). Si esta función también tocara esos tres campos, cada
     llamada de cleanSnapshot los pisaría de vuelta. */
  function applyBackdropState() {
    if (grid) grid.visible = gridWanted && !technical;
    if (floor) floor.visible = !technical;
    if (sky) sky.visible = !technical;
    if (scene) scene.background = technical ? new THREE.Color(0xe9e7e1) : (sky ? null : new THREE.Color(0x11161b));
    requestRender();
  }

  function makeTextSprite(text, color) {
    var canvas = document.createElement('canvas'), size = 256;
    canvas.width = size; canvas.height = size / 4;
    var ctx = canvas.getContext('2d');
    ctx.fillStyle = 'rgba(17,22,27,0.82)';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.font = 'bold 42px Segoe UI, Arial, sans-serif';
    ctx.fillStyle = color || '#ffffff';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(text, canvas.width / 2, canvas.height / 2 + 2);
    var texture = new THREE.CanvasTexture(canvas);
    texture.needsUpdate = true;
    var spriteMaterial = new THREE.SpriteMaterial({ map: texture, depthTest: false, transparent: true });
    var sprite = new THREE.Sprite(spriteMaterial);
    sprite.renderOrder = 999;
    return sprite;
  }

  function buildDimensionLabels() {
    if (dimensionGroup) { disposeObject(dimensionGroup); dimensionGroup = null; }
    if (!originalSize.x && !originalSize.y && !originalSize.z) return;
    dimensionGroup = new THREE.Group();
    var pad = Math.max(originalSize.x, originalSize.y, originalSize.z) * 0.08 + 30;
    var min = originalCenter.clone().sub(originalSize.clone().multiplyScalar(0.5));
    var max = originalCenter.clone().add(originalSize.clone().multiplyScalar(0.5));
    function addLabel(text, position, scaleRef) {
      var sprite = makeTextSprite(text);
      sprite.position.copy(position);
      var scale = Math.max(40, scaleRef * 0.09);
      sprite.scale.set(scale * 2, scale * 0.5, 1);
      dimensionGroup.add(sprite);
    }
    addLabel('Ancho ' + Math.round(originalSize.x) + ' mm', new THREE.Vector3(originalCenter.x, min.y - pad * 0.4, max.z + pad * 0.1), originalSize.x);
    addLabel('Alto ' + Math.round(originalSize.y) + ' mm', new THREE.Vector3(min.x - pad * 0.5, originalCenter.y, max.z + pad * 0.1), originalSize.y);
    addLabel('Fondo ' + Math.round(originalSize.z) + ' mm', new THREE.Vector3(max.x + pad * 0.5, min.y - pad * 0.3, originalCenter.z), originalSize.z);
    dimensionGroup.visible = dimensionsVisible;
    scene.add(dimensionGroup);
  }

  function updateDimensionLabels() {
    if (dimensionGroup) dimensionGroup.visible = dimensionsVisible;
  }

  function updateModuleInfo(width, height, depth) {
    if (byId('view_module_width')) byId('view_module_width').textContent = Math.round(width) + ' mm';
    if (byId('view_module_height')) byId('view_module_height').textContent = Math.round(height) + ' mm';
    if (byId('view_module_depth')) byId('view_module_depth').textContent = Math.round(depth) + ' mm';
    if (byId('view_health')) byId('view_health').textContent = meshes.length + ' piezas · render local';
  }

  function buildTree(filter) {
    var host = byId('view_tree'); if (!host) return;
    var term = String(filter || '').toLowerCase();
    host.innerHTML = '';
    meshes.filter(function(mesh){ return !term || mesh.userData.name.toLowerCase().indexOf(term) >= 0; }).forEach(function(mesh, index) {
      var button = document.createElement('button');
      button.type = 'button'; button.className = 'm3dv-tree-item' + (mesh === selected ? ' active' : '');
      button.textContent = mesh.userData.name;
      button.addEventListener('click', function(){ selectPiece(mesh); });
      host.appendChild(button);
    });
  }

  function selectPiece(mesh, preserveKey, silent) {
    var previousKey=selected&&selected.userData?(selected.userData.materialKey||selected.userData.pieceId):null;
    if(mesh&&spaceSelection)selectSpace(null,false);
    if (selectionBox) disposeObject(selectionBox);
    selected = mesh || null; selectionBox = null;
    if(selected)selectedPieceKey=selected.userData.materialKey||selected.userData.pieceId;
    else if(!preserveKey)selectedPieceKey=null;
    if (selected) {
      selectionBox = new THREE.Group();
      var pieceBounds=new THREE.Box3().setFromObject(selected),pieceSize=pieceBounds.getSize(new THREE.Vector3()),pieceCenter=pieceBounds.getCenter(new THREE.Vector3());
      var pieceFill=new THREE.Mesh(new THREE.BoxGeometry(pieceSize.x,pieceSize.y,pieceSize.z),new THREE.MeshBasicMaterial({color:0x66c9f3,transparent:true,opacity:.18,depthTest:false,depthWrite:false,side:THREE.DoubleSide}));
      var pieceEdge=new THREE.LineSegments(new THREE.EdgesGeometry(pieceFill.geometry),new THREE.LineBasicMaterial({color:0x45b9e8,transparent:true,opacity:1,depthTest:false}));
      pieceFill.position.copy(pieceCenter);pieceEdge.position.copy(pieceCenter);pieceFill.renderOrder=997;pieceEdge.renderOrder=998;selectionBox.add(pieceFill,pieceEdge);
      scene.add(selectionBox);
      var d = selected.userData.dimensions;
      byId('view_piece_name').textContent = selected.userData.name;
      byId('view_piece_length').textContent = Math.round(d.length) + ' mm';
      byId('view_piece_width').textContent = Math.round(d.width) + ' mm';
      byId('view_piece_thickness').textContent = Math.round(d.thickness) + ' mm';
      byId('view_piece_category').textContent = selected.userData.category;
      if(byId('view_piece_edge'))byId('view_piece_edge').textContent=selected.userData.edgeType==='HARD'?'Canto duro':(selected.userData.edgeType==='NONE'?'Sin canto':'PVC');
      if(byId('view_piece_edge_color'))byId('view_piece_edge_color').textContent=selected.userData.edgeColor;
      if(byId('view_piece_owner'))byId('view_piece_owner').textContent=selected.userData.ownerSpaceId?'Pertenece a '+selected.userData.ownerSpaceId:'Pieza general del casco';
      byId('view_piece_panel').hidden = false;
      if(!silent&&previousKey!==selectedPieceKey)window.dispatchEvent(new CustomEvent('modular3d:pieceSelected', { detail: { pieceId:selected.userData.pieceId,materialKey:selected.userData.materialKey,materialGroup:selected.userData.materialGroup,materialName:selected.userData.materialName,materialColor:selected.userData.materialColor,edgeType:selected.userData.edgeType,edgeColor:selected.userData.edgeColor,name: selected.userData.name, category: selected.userData.category,role:selected.userData.role,ownerSpaceId:selected.userData.ownerSpaceId,sourceField:selected.userData.sourceField } }));
    } else if (byId('view_piece_panel')) byId('view_piece_panel').hidden = true;
    buildTree(byId('view_search') ? byId('view_search').value : '');
    requestRender();
  }

  function hitPiece(event) {
    if(pointerStart&&Math.hypot(event.clientX-pointerStart.x,event.clientY-pointerStart.y)>5){pointerStart=null;return;}pointerStart=null;
    var rect = renderer.domElement.getBoundingClientRect();
    pointer.set((event.clientX - rect.left) / rect.width * 2 - 1, -(event.clientY - rect.top) / rect.height * 2 + 1);
    raycaster.setFromCamera(pointer, camera);
    if(selectionMode==='piece'){
      var pieceHit=raycaster.intersectObjects(meshes,false)[0];selectPiece(pieceHit?pieceHit.object:null);return;
    }
    var spaceHits=raycaster.intersectObjects(spaceMeshes,false);
    if(spaceHits.length){spaceHits.sort(function(a,b){return a.object.userData.spaceVolume-b.object.userData.spaceVolume;});selectSpace(spaceHits[0].object.userData.spaceId,true);return;}
    var hit = raycaster.intersectObjects(meshes, false)[0];selectPiece(hit ? hit.object : null);
  }

  function modelMaxSize() { return Math.max(originalSize.x, originalSize.y, originalSize.z, 1); }
  function switchProjection(useOrtho) {
    if (!renderer || orthographic === useOrtho) return;
    orthographic = useOrtho;
    var stage = byId('view_stage'), aspect = stage.clientWidth / stage.clientHeight;
    var position = camera.position.clone(), target = controls.target.clone(), up = camera.up.clone(), max = modelMaxSize();
    camera = useOrtho ? new THREE.OrthographicCamera(-max * aspect, max * aspect, max, -max, 0.1, max * 100) : new THREE.PerspectiveCamera(38, aspect, 0.1, max * 100);
    camera.position.copy(position); camera.up.copy(up); camera.lookAt(target);
    controls.object = camera; controls.target.copy(target); controls.update();
    var button = byId('view_projection');
    if (button) { button.textContent = useOrtho ? 'Ortogonal' : 'Perspectiva'; button.classList.toggle('active', useOrtho); }
    requestRender();
  }

  function setView(name) {
    if (!camera || !controls) return;
    var max = modelMaxSize(), center = originalCenter.clone(), direction;
    if (name === 'front') direction = new THREE.Vector3(0, 0, 1);
    else if (name === 'back') direction = new THREE.Vector3(0, 0, -1);
    else if (name === 'left') direction = new THREE.Vector3(-1, 0, 0);
    else if (name === 'right') direction = new THREE.Vector3(1, 0, 0);
    else if (name === 'top') direction = new THREE.Vector3(0, 1, 0);
    else if (name === 'bottom') direction = new THREE.Vector3(0, -1, 0);
    else direction = new THREE.Vector3(1, 0.72, 1);
    switchProjection(name !== 'iso');
    camera.up.set(0, name === 'top' || name === 'bottom' ? 0 : 1, name === 'top' ? -1 : (name === 'bottom' ? 1 : 0));
    camera.position.copy(center).add(direction.normalize().multiplyScalar(max * 3.25));
    controls.target.copy(center); camera.lookAt(center); controls.update();
    if (orthographic) { camera.left = -max * 1.05; camera.right = max * 1.05; camera.top = max * 1.05; camera.bottom = -max * 1.05; camera.updateProjectionMatrix(); }
    requestRender();
  }

  function setViewVector(value) {
    if (!camera || !controls) return;
    var parts = String(value || '').split(',').map(Number);
    if (parts.length !== 3 || parts.some(function(n){ return !isFinite(n); })) return;
    var direction = new THREE.Vector3(parts[0], parts[1], parts[2]);
    if (!direction.lengthSq()) return;
    switchProjection(false);
    var center = originalCenter.clone(), max = modelMaxSize();
    camera.up.set(0, 1, 0);
    camera.position.copy(center).add(direction.normalize().multiplyScalar(max * 3.25));
    controls.target.copy(center); camera.lookAt(center); controls.update(); syncNavigator(); requestRender();
  }

  /* Cubo de navegación 3D real (CSS transform-style:preserve-3d), inspirado
     en github.com/VLADIMIR1991-05/MODULAR-3D-VIEW: 6 caras absolutas con su
     propia rotateX/Y/translateZ, cada una con una grilla de 9 botones
     (centro = vista de frente; bordes y esquinas = vistas oblicuas). A
     diferencia del cubo SVG plano anterior, este gira de verdad para
     reflejar el ángulo de cámara actual. Los clics reutilizan setViewVector,
     ya usado por el resto del visor (view cube -> misma cámara, sin duplicar
     lógica de movimiento).
   */
  var NAV_CUBE_FACES = [
    { name: 'front', label: 'FRENTE', dir: [0, 0, 1], right: [1, 0, 0], up: [0, 1, 0] },
    { name: 'back', label: 'ATRÁS', dir: [0, 0, -1], right: [-1, 0, 0], up: [0, 1, 0] },
    { name: 'right', label: 'DER.', dir: [1, 0, 0], right: [0, 0, -1], up: [0, 1, 0] },
    { name: 'left', label: 'IZQ.', dir: [-1, 0, 0], right: [0, 0, 1], up: [0, 1, 0] },
    { name: 'top', label: 'ARRIBA', dir: [0, 1, 0], right: [1, 0, 0], up: [0, 0, -1] },
    { name: 'bottom', label: 'ABAJO', dir: [0, -1, 0], right: [1, 0, 0], up: [0, 0, 1] }
  ];
  var navigatorDragging = false;
  function buildNavCube() {
    var cube = byId('view_cube');
    if (!cube || cube.childElementCount) return;
    var rows = [1, 0, -1], columns = [-1, 0, 1];
    NAV_CUBE_FACES.forEach(function (face) {
      var element = document.createElement('div');
      element.className = 'nav-cube-face cube-' + face.name;
      rows.forEach(function (row) {
        columns.forEach(function (column) {
          var direction = new THREE.Vector3(face.dir[0], face.dir[1], face.dir[2])
            .addScaledVector(new THREE.Vector3(face.right[0], face.right[1], face.right[2]), column)
            .addScaledVector(new THREE.Vector3(face.up[0], face.up[1], face.up[2]), row);
          var button = document.createElement('button');
          button.type = 'button';
          button.dataset.view = direction.toArray().join(',');
          if (row === 0 && column === 0) { button.className = 'nav-center'; button.textContent = face.label; button.title = 'Vista ' + face.label.toLowerCase(); }
          else button.title = 'Vista oblicua desde ' + face.label.toLowerCase();
          button.addEventListener('click', function () {
            if (navigatorDragging) return;
            setViewVector(button.dataset.view);
          });
          element.appendChild(button);
        });
      });
      cube.appendChild(element);
    });
    var face = byId('view_cube_face'), previous = null;
    face.addEventListener('pointerdown', function (event) { navigatorDragging = false; previous = { x: event.clientX, y: event.clientY }; });
    face.addEventListener('pointermove', function (event) {
      if (!previous) return;
      var dx = event.clientX - previous.x, dy = event.clientY - previous.y;
      if (Math.abs(dx) + Math.abs(dy) > 2 && !navigatorDragging) { navigatorDragging = true; face.setPointerCapture(event.pointerId); }
      if (navigatorDragging) {
        if (Math.abs(dx) >= 1) orbitStep(dx > 0 ? 'right' : 'left', Math.abs(dx) * .01);
        if (Math.abs(dy) >= 1) orbitStep(dy > 0 ? 'down' : 'up', Math.abs(dy) * .01);
        previous = { x: event.clientX, y: event.clientY };
      }
    });
    var endDrag = function () { previous = null; setTimeout(function () { navigatorDragging = false; }, 0); };
    face.addEventListener('pointerup', endDrag);
    face.addEventListener('pointercancel', endDrag);
    document.querySelectorAll('[data-orbit]').forEach(function (button) {
      button.addEventListener('click', function () { orbitStep(button.dataset.orbit); });
    });
  }
  function orbitStep(action, angle) {
    if (!camera || !controls) return;
    angle = angle || Math.PI / 8;
    var offset = camera.position.clone().sub(controls.target), distance = offset.length();
    if (!distance) return;
    offset.normalize();
    if (action === 'left' || action === 'right') {
      offset.applyAxisAngle(new THREE.Vector3(0, 1, 0), action === 'left' ? angle : -angle);
    } else {
      var spherical = new THREE.Spherical().setFromVector3(offset);
      spherical.phi = THREE.MathUtils.clamp(spherical.phi + (action === 'up' ? -angle : angle), 0.06, Math.PI - 0.06);
      offset.setFromSpherical(spherical);
    }
    camera.position.copy(controls.target).add(offset.multiplyScalar(distance));
    camera.up.set(0, 1, 0);
    camera.lookAt(controls.target);
    controls.update();
    syncNavigator();
    requestRender();
  }
  function syncNavigator() {
    if (!camera || !controls) return;
    var direction = camera.position.clone().sub(controls.target).normalize();
    var yaw = THREE.MathUtils.radToDeg(Math.atan2(direction.x, direction.z));
    var pitch = THREE.MathUtils.radToDeg(Math.asin(THREE.MathUtils.clamp(direction.y, -1, 1)));
    var cube = byId('view_cube');
    if (cube) cube.style.transform = 'rotateX(' + pitch + 'deg) rotateY(' + (-yaw) + 'deg)';
    document.querySelectorAll('.nav-cube-face [data-view]').forEach(function (button) {
      var parts = button.dataset.view.split(',').map(Number);
      var candidate = new THREE.Vector3(parts[0], parts[1], parts[2]).normalize();
      button.classList.toggle('active', candidate.dot(direction) > .995);
    });
  }

  function frameModel() { setView('iso'); }
  function focusSelected(){if(!selected)return;var box=new THREE.Box3().setFromObject(selected),center=box.getCenter(new THREE.Vector3()),size=box.getSize(new THREE.Vector3()),distance=Math.max(size.x,size.y,size.z,20)*2.8,direction=camera.position.clone().sub(controls.target).normalize();controls.target.copy(center);camera.position.copy(center).add(direction.multiplyScalar(distance));camera.lookAt(center);controls.update();requestRender();}
  function isolateSelected(){isolated=!isolated;meshes.forEach(function(mesh){mesh.visible=!isolated||mesh===selected;});if(byId('view_piece_isolate'))byId('view_piece_isolate').classList.toggle('active',isolated);requestRender();}
  function toggleSelectedVisibility(){if(!selected)return;selected.visible=!selected.visible;if(selectionBox)selectionBox.visible=selected.visible;requestRender();}
  function editSelected(){if(!selected)return;window.dispatchEvent(new CustomEvent('modular3d:editPieceSource',{detail:selected.userData}));}
  function highlight(category) {
    meshes.forEach(function(mesh){
      if (!mesh.material.emissive) return;
      mesh.material.emissive.setHex(mesh.userData.category === category ? 0x6b2206 : 0x000000);
      mesh.material.emissiveIntensity = mesh.userData.category === category ? 0.28 : 0;
    });
    requestRender();
  }

  function bind(id, action) { var element = byId(id); if (element) element.addEventListener('click', action); }
  /* Fondo tipo estudio fotográfico: una esfera invertida con degradado
     vertical por color de vértice (sin shader propio ni HDRI externo, solo
     THREE.js base) en vez del color plano anterior. Se desactiva en modo
     técnico, donde el fondo pasa a un gris liso de plano de línea oculta. */
  function buildStudioSky() {
    var geometry = new THREE.SphereGeometry(9000, 24, 16);
    var top = new THREE.Color(0x2a333c), horizon = new THREE.Color(0x181d24), bottom = new THREE.Color(0x0c0f13);
    var colors = [], position = geometry.attributes.position;
    for (var i = 0; i < position.count; i += 1) {
      var t = Math.max(-1, Math.min(1, position.getY(i) / 9000));
      var color = t >= 0 ? horizon.clone().lerp(top, t) : horizon.clone().lerp(bottom, -t);
      colors.push(color.r, color.g, color.b);
    }
    geometry.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
    var material = new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.BackSide, fog: false, depthWrite: false });
    var mesh = new THREE.Mesh(geometry, material);
    mesh.renderOrder = -1000;
    return mesh;
  }

  function initialize() {
    var stage = byId('view_stage'); if (!stage || typeof THREE === 'undefined') return;
    if (renderer) return;
    scene = new THREE.Scene();
    scene.background = new THREE.Color(0x11161b);
    camera = new THREE.PerspectiveCamera(38, stage.clientWidth / stage.clientHeight, 0.1, 100000);
    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false, preserveDrawingBuffer: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75));
    renderer.setSize(stage.clientWidth, stage.clientHeight, false);
    renderer.outputEncoding = THREE.sRGBEncoding;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.08;
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    renderer.localClippingEnabled = true;
    stage.appendChild(renderer.domElement);
    controls = new THREE.OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true; controls.dampingFactor = 0.08;
    controls.screenSpacePanning = true; controls.minDistance = 20; controls.maxDistance = 20000;
    controls.addEventListener('change', function(){ requestRender(); syncNavigator(); });
    scene.add(new THREE.HemisphereLight(0xffffff, 0x26313b, 1.65));
    var key = new THREE.DirectionalLight(0xffffff, 2.4); key.position.set(1200, 1600, 900); key.castShadow = true;
    key.shadow.mapSize.set(2048, 2048); key.shadow.camera.near = 1; key.shadow.camera.far = 5000;
    key.shadow.camera.left = -2200; key.shadow.camera.right = 2200; key.shadow.camera.top = 2200; key.shadow.camera.bottom = -2200;
    var fill = new THREE.DirectionalLight(0xffd8b7, 0.75); fill.position.set(-900, 700, -800);
    scene.add(key, fill);
    grid = new THREE.GridHelper(4000, 40, 0x53616d, 0x2b343c); grid.position.y = -1; scene.add(grid);
    floor = new THREE.Mesh(new THREE.PlaneGeometry(4000, 4000), new THREE.ShadowMaterial({ color: 0x000000, opacity: 0.22 }));
    floor.rotation.x = -Math.PI / 2; floor.position.y = -2; floor.receiveShadow = true; scene.add(floor);
    sky = buildStudioSky(); scene.add(sky);
    clearModel();
    renderer.domElement.addEventListener('pointerdown',function(event){pointerStart={x:event.clientX,y:event.clientY};});
    renderer.domElement.addEventListener('pointerup', hitPiece);
    window.addEventListener('resize', function(){
      var w = stage.clientWidth, h = stage.clientHeight;
      if (!w || !h) return;
      if (camera.isPerspectiveCamera) camera.aspect = w / h;
      else { var span = modelMaxSize() * 0.72; camera.left = -span * w / h; camera.right = span * w / h; camera.top = span; camera.bottom = -span; }
      camera.updateProjectionMatrix(); renderer.setSize(w, h, false); requestRender();
    });
    buildNavCube();
    bind('view_home', frameModel); bind('view_iso', function(){ setView('iso'); });
    bind('view_mode_space',function(){setSelectionMode('space');});bind('view_mode_piece',function(){setSelectionMode('piece');});
    bind('view_piece_focus',focusSelected);bind('view_piece_isolate',isolateSelected);bind('view_piece_visibility',toggleSelectedVisibility);bind('view_piece_edit',editSelected);
    bind('view_front', function(){ setView('front'); }); bind('view_back', function(){ setView('back'); });
    bind('view_left', function(){ setView('left'); }); bind('view_right', function(){ setView('right'); });
    bind('view_top', function(){ setView('top'); }); bind('view_bottom', function(){ setView('bottom'); });
    bind('view_projection', function(){ switchProjection(!orthographic); });
    bind('view_transparency', function(){ transparent = !transparent; byId('view_transparency').classList.toggle('active', transparent); applyVisualState(); });
    bind('view_edges', function(){ edgesVisible = !edgesVisible; byId('view_edges').classList.toggle('active', edgesVisible); applyVisualState(); });
    bind('view_shadows', function(){ shadows = !shadows; renderer.shadowMap.enabled = shadows; byId('view_shadows').classList.toggle('active', shadows); applyVisualState(); });
    bind('view_grid', function(){ gridWanted = !gridWanted; byId('view_grid').classList.toggle('active', gridWanted); applyBackdropState(); });
    bind('view_technical', function(){ technical = !technical; byId('view_technical').classList.toggle('active', technical); applyVisualState(); applyBackdropState(); });
    bind('view_dimensions', function(){ dimensionsVisible = !dimensionsVisible; byId('view_dimensions').classList.toggle('active', dimensionsVisible); if (dimensionsVisible && !dimensionGroup) buildDimensionLabels(); updateDimensionLabels(); requestRender(); });
    var explosion = byId('view_explosion'); if (explosion) explosion.addEventListener('input', function(){ exploded = Number(explosion.value) || 0; applyVisualState(); });
    var search = byId('view_search'); if (search) search.addEventListener('input', function(){ buildTree(search.value); });
    renderer.setAnimationLoop(function(){
      if (document.hidden) return;
      var changed = controls.update();
      if (!changed && !needsRender) return;
      renderer.render(scene, camera); needsRender = false;
    });
    setSelectionMode('space');setTimeout(function(){ build({}); }, 0);
  }

  function pieceList(){return meshes.map(function(mesh){return{name:mesh.userData.name,pieceId:mesh.userData.pieceId,materialKey:mesh.userData.materialKey,group:mesh.userData.materialGroup,color:mesh.userData.materialColor,materialName:mesh.userData.materialName,edgeType:mesh.userData.edgeType,edgeColor:mesh.userData.edgeColor,category:mesh.userData.category,role:mesh.userData.role,ownerSpaceId:mesh.userData.ownerSpaceId};});}
  function selectPieceByKey(key,notify){var mesh=meshes.filter(function(item){return item.userData.materialKey===key||item.userData.pieceId===key;})[0];if(mesh){setSelectionMode('piece');selectPiece(mesh,false,notify!==true);}return !!mesh;}
  function snapshot(){try{return renderer&&renderer.domElement?renderer.domElement.toDataURL('image/png'):'';}catch(_e){return '';}}
  function cleanSnapshot(){
    if(!renderer||!camera||!controls)return '';
    try{
      var background=scene.background,gridVisible=grid&&grid.visible,floorVisible=floor&&floor.visible,skyVisible=sky&&sky.visible,dimensionsWereVisible=dimensionsVisible;
      var selectionVisible=selectionBox&&selectionBox.visible,spaceVisible=spaceSelection&&spaceSelection.visible;
      var hitVisibility=spaceMeshes.map(function(hit){return hit.visible;});
      var oldExploded=exploded,oldTransparent=transparent,oldPosition=camera.position.clone(),oldTarget=controls.target.clone();
      scene.background=new THREE.Color(0xffffff);if(grid)grid.visible=false;if(floor)floor.visible=false;if(sky)sky.visible=false;dimensionsVisible=false;
      if(selectionBox)selectionBox.visible=false;if(spaceSelection)spaceSelection.visible=false;spaceMeshes.forEach(function(hit){hit.visible=false;});
      exploded=0;transparent=false;applyVisualState();
      var direction=oldPosition.clone().sub(oldTarget),distance=direction.length();
      if(distance>0)camera.position.copy(oldTarget).add(direction.normalize().multiplyScalar(distance*.78));
      camera.lookAt(oldTarget);controls.update();renderer.render(scene,camera);
      var result=renderer.domElement.toDataURL('image/png');
      scene.background=background;if(grid)grid.visible=gridVisible;if(floor)floor.visible=floorVisible;if(sky)sky.visible=skyVisible;dimensionsVisible=dimensionsWereVisible;
      if(selectionBox)selectionBox.visible=selectionVisible;if(spaceSelection)spaceSelection.visible=spaceVisible;spaceMeshes.forEach(function(hit,index){hit.visible=hitVisibility[index];});
      exploded=oldExploded;transparent=oldTransparent;camera.position.copy(oldPosition);controls.target.copy(oldTarget);camera.lookAt(oldTarget);controls.update();applyVisualState();renderer.render(scene,camera);
      return result;
    }catch(_e){return snapshot();}
  }
  function cameraState(){if(!camera||!controls)return null;return{position:camera.position.toArray(),target:controls.target.toArray(),up:camera.up.toArray(),orthographic:orthographic};}
  function restoreCamera(raw){try{var state=typeof raw==='string'?JSON.parse(raw):raw;if(!state||!Array.isArray(state.position)||!Array.isArray(state.target))return false;switchProjection(!!state.orthographic);camera.position.fromArray(state.position);controls.target.fromArray(state.target);if(Array.isArray(state.up))camera.up.fromArray(state.up);camera.lookAt(controls.target);controls.update();syncNavigator();requestRender();return true;}catch(_e){return false;}}
  window.Modular3DView = { init: initialize, update: build, highlight: highlight, selectSpace: selectSpace, selectMode:setSelectionMode, setView: setView, setViewVector: setViewVector, frame: frameModel, getPieces:pieceList, selectPieceByKey:selectPieceByKey, snapshot:snapshot, cleanSnapshot:cleanSnapshot, cameraState:cameraState, restoreCamera:restoreCamera };
  window.Modular3DPreview = window.Modular3DView;
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', initialize);
  else initialize();
}());
