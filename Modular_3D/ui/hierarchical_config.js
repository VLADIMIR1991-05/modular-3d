(function () {
  'use strict';
  var tree = null, selectedId = 'root', selectedPieceOwnerId = null, counter = 1, expanded = {root:true}, undoStack=[], redoStack=[];
  function snapshot(){return JSON.stringify({tree:tree,selectedId:selectedId,counter:counter});}
  function remember(){if(tree){undoStack.push(snapshot());if(undoStack.length>40)undoStack.shift();redoStack=[];}}
  function restoreState(raw){try{var state=JSON.parse(raw);tree=state.tree;selectedId=state.selectedId||'root';counter=state.counter||counter;render();}catch(_e){}}
  function undo(){if(!undoStack.length)return;redoStack.push(snapshot());restoreState(undoStack.pop());}
  function redo(){if(!redoStack.length)return;undoStack.push(snapshot());restoreState(redoStack.pop());}
  window.Modular3DHierarchyUndo=undo;window.Modular3DHierarchyRedo=redo;
  document.addEventListener('click',function(event){var target=event.target&&event.target.closest&&event.target.closest('button');if(!target)return;var mutation=['hierarchy_split','hierarchy_unsplit','hierarchy_duplicate','hierarchy_reset'];if(mutation.indexOf(target.id)<0)return;var node=tree&&nodeById(selectedId),message='';if(target.id==='hierarchy_reset')message='¿Restablecer toda la configuración jerárquica?';if(target.id==='hierarchy_unsplit'&&node&&(node.children||[]).length)message='Eliminar esta división también eliminará sus espacios y contenidos hijos. ¿Continuar?';if(target.id==='hierarchy_split'&&node&&(node.children||[]).length)message='Este espacio ya está dividido. Reemplazar la división eliminará su configuración hija. ¿Continuar?';if(message&&!confirm(message)){event.preventDefault();event.stopImmediatePropagation();return;}remember();},true);
  function id(x){ return document.getElementById(x); }
  function num(x, fallback){ var n=Number(id(x)&&id(x).value); return isFinite(n)?n:fallback; }
  // Reglas de visibilidad del inspector de espacio: cada una declara SOLO la
  // condición (qué campo revela qué sección), y el motor compartido
  // (reglas_visibilidad.js) se encarga de aplicarlas. "esTravesanos" y
  // "haySup" son las mismas condiciones compuestas que tenía el antiguo
  // toggleFields() a mano, ahora expresadas como datos.
  if (window.Modular3DReglas) window.Modular3DReglas.registrar([
    { selector: '.h-top-mode', cuando: { field: 'h_top', test: 'checked' } },
    { selector: '#h_top_travesano_row', cuando: { all: [ { field: 'h_top', test: 'checked' }, { field: 'h_top_mode', test: 'equals', value: 'TRAVESANOS' } ] } },
    { selector: '.h-shelves', cuando: { field: 'h_content', test: 'equals', value: 'REPISAS' } },
    { selector: '.h-drawers', cuando: { field: 'h_content', test: 'startsWith', value: 'CAJONES' } },
    { selector: '.h-drawer-frentes', cuando: { field: 'h_content', test: 'equals', value: 'CAJONES_FRENTES' } },
    { selector: '.h-front-puerta', cuando: { field: 'h_content', test: 'notEquals', value: 'CAJONES_FRENTES' } },
    { selector: '.h-external-fit', cuando: { all: [ { field: 'h_front', test: 'notEquals', value: 'NINGUNO' }, { not: { field: 'h_front', test: 'contains', value: 'INTERNA' } } ] } },
    { selector: '.h-front-overlays', cuando: { all: [ { field: 'h_front', test: 'notEquals', value: 'NINGUNO' }, { not: { field: 'h_front', test: 'contains', value: 'INTERNA' } }, { field: 'h_front_fit', test: 'equals', value: 'CUSTOM' } ] } },
    { selector: '.h-sob-izq', cuando: { field: 'h_left', test: 'checked' } },
    { selector: '.h-sob-der', cuando: { field: 'h_right', test: 'checked' } },
    { selector: '.h-sob-inferior', cuando: { field: 'h_bottom', test: 'checked' } },
    { selector: '.h-sob-superior', cuando: { all: [ { field: 'h_top', test: 'checked' }, { not: { field: 'h_top_mode', test: 'equals', value: 'TRAVESANOS' } } ] } },
    { selector: '.h-mount-izq', cuando: { field: 'h_left', test: 'checked' } },
    { selector: '.h-mount-der', cuando: { field: 'h_right', test: 'checked' } },
    { selector: '.h-mount-inferior', cuando: { field: 'h_bottom', test: 'checked' } },
    { selector: '.h-mount-superior', cuando: { field: 'h_top', test: 'checked' } },
    { selector: '.h-sob-panel', cuando: { any: [
      { field: 'h_left', test: 'checked' }, { field: 'h_right', test: 'checked' }, { field: 'h_bottom', test: 'checked' },
      { all: [ { field: 'h_top', test: 'checked' }, { not: { field: 'h_top_mode', test: 'equals', value: 'TRAVESANOS' } } ] }
    ] } }
  ]);
  // Parámetros de Diseño (§3): huelgos por defecto para los espacios NUEVOS
  // que se crean de aquí en más (raíz al iniciar/"Restablecer", e hijos al
  // "Dividir"). Arranca con los mismos valores que ya traía el plugin
  // (equivalentes a ParametrosDiseno::ESTANDAR en core/parametros_diseno.rb)
  // para que, sin tocar nada, el comportamiento sea idéntico a antes de que
  // este concepto existiera. interfaz.js llama a Modular3DSetHuelgosDefault
  // cuando el usuario elige otro Parámetro de Diseño en "1 Medidas"; NUNCA
  // reescribe espacios que ya existen, solo el molde de los nuevos.
  var huelgosActuales = { frontJoint:1.5, overlayLeft:13.5, overlayRight:13.5, overlayTop:13.5, overlayBottom:13.5, gap:3, gapCenter:3, drawerGap:1.5 };
  window.Modular3DSetHuelgosDefault = function (valores) {
    if (!valores) return;
    ['frontJoint','overlayLeft','overlayRight','overlayTop','overlayBottom','gap','gapCenter','drawerGap'].forEach(function (campo) {
      var v = Number(valores[campo]);
      if (isFinite(v)) huelgosActuales[campo] = v;
    });
  };
  window.Modular3DGetHuelgosActuales = function () { return JSON.parse(JSON.stringify(huelgosActuales)); };
  function freshSobremedida(){ return {frontalIzq:0,traseraIzq:0,frontalDer:0,traseraDer:0,frontalInferior:0,traseraInferior:0,frontalSuperior:0,traseraSuperior:0}; }
  // v6 §Fase B: montaje de cada panel de un espacio (interior/sobrepuesto,
  // + inglete 45° en laterales), generalizando al nivel de espacio el mismo
  // control que el casco general ya tenía (montaje_izq/der/superior/
  // inferior en "2 Casco"). Default pedido explícitamente: laterales
  // sobrepuestos (EXTERIOR), base/techo/travesaños internos (INTERIOR) --
  // misma convención que ya usa el casco general por defecto. Ver
  // enclosure.leftMount/rightMount/bottomMount/topMount mas abajo.
  function fresh(){ return {id:'root',name:'Módulo',content:'VACIO',front:'NINGUNO',frontCount:'AUTO',frontFit:'AUTO',frontJoint:huelgosActuales.frontJoint,overlayLeft:huelgosActuales.overlayLeft,overlayRight:huelgosActuales.overlayRight,overlayTop:huelgosActuales.overlayTop,overlayBottom:huelgosActuales.overlayBottom,drawers:0,shelves:0,gap:huelgosActuales.gap,gapCenter:huelgosActuales.gapCenter,drawerGap:huelgosActuales.drawerGap,drawerHeight:0,drawerFrontStyle:'POR_CAJON',enclosure:{left:false,right:false,bottom:false,top:false,back:false,leftMount:'EXTERIOR',rightMount:'EXTERIOR',bottomMount:'INTERIOR',topMount:'INTERIOR'},sobremedida:freshSobremedida(),children:[]}; }
  function walk(node, fn, parent){ if(!node)return null;if(fn(node,parent))return node;for(var i=0;i<(node.children||[]).length;i++){var r=walk(node.children[i],fn,node);if(r)return r;}return null; }
  function nodeById(nodeId){ return walk(tree,function(n){return n.id===nodeId;}); }
  function parentOf(nodeId){ var result=null;walk(tree,function(n,p){if(n.id===nodeId){result=p;return true;}return false;});return result; }
  function isExternalFront(value){var front=String(value||'NINGUNO');return front!=='NINGUNO'&&front.indexOf('INTERNA')<0;}
  function clearExternalDescendants(node){(node.children||[]).forEach(function(child){if(isExternalFront(child.front))child.front='NINGUNO';clearExternalDescendants(child);});}
  function resolveFrontConflicts(node,ancestorHasExternal){var own=isExternalFront(node.front);if(ancestorHasExternal&&own){node.front='NINGUNO';own=false;}(node.children||[]).forEach(function(child){resolveFrontConflicts(child,ancestorHasExternal||own);});}
  function parse(expr,total,separator){
    var tokens=String(expr||'').split(':').map(function(v){return v.trim();}).filter(Boolean);if(tokens.length<2)throw new Error('Escribe al menos dos estaciones, por ejemplo 1:1.');
    var usable=total-separator*(tokens.length-1);if(usable<=0)throw new Error('Los tableros ocupan todo el espacio.');var fixed=0,weight=0;
    var parts=tokens.map(function(t){var m=t.match(/^(\d+(?:\.\d+)?)\s*(mm|cm|m)$/i);if(m){var q=+m[1]*(m[2].toLowerCase()==='m'?1000:(m[2].toLowerCase()==='cm'?10:1));fixed+=q;return{fixed:q};}m=t.match(/^(\d+(?:\.\d+)?)%$/);if(m){var p=usable*(+m[1])/100;fixed+=p;return{fixed:p};}if(/^auto$/i.test(t)){weight+=1;return{weight:1};}if(/^\d+(?:\.\d+)?$/.test(t)&&+t>0){weight+=+t;return{weight:+t};}throw new Error('No se reconoce «'+t+'».');});
    var remaining=usable-fixed;if(remaining<-0.01)throw new Error('Las medidas fijas exceden el espacio seleccionado.');if(remaining>0.01&&!weight)throw new Error('Añade AUTO o una proporción para repartir el sobrante.');
    return parts.map(function(p){return p.fixed!=null?p.fixed:remaining*p.weight/weight;});
  }
  function rearReserve(){var depth=num('prof_total',580),mode=id('lleva_respaldo')?id('lleva_respaldo').value:'SI';if(mode==='NO')return 0;var back=num('grosor_resp',6),distance=num('distancia_plano_posterior',0);if(back>=15)return Math.min(depth-1,distance+back);var count=id('cantidad_ajustes')?id('cantidad_ajustes').value:'AUTO',active=count==='AUTO'||Number(count)>0;return Math.min(depth-1,distance+(active?num('grosor_ajuste',num('espesor',15))+num('separacion_ajuste_respaldo',2):0)+back);}
  function bounds(){var depth=num('prof_total',580);return{x:num('grosor_izq',15),z:num('grosor_inferior',15),y:0,w:Math.max(1,num('ancho_total',600)-num('grosor_izq',15)-num('grosor_der',15)),h:Math.max(1,num('alto_total',760)-num('grosor_superior',15)-num('grosor_inferior',15)),d:Math.max(1,depth-rearReserve())};}
  function solve(node,box,list,separators){node.box={x:box.x,y:box.y,z:box.z,w:box.w,d:box.d,h:box.h};list.push(node);if(!node.split||(node.children||[]).length<2)return;var axis=node.split.axis,sep=node.split.physical?node.split.thickness:0,total=axis==='X'?box.w:(axis==='Z'?box.h:box.d),sizes=parse(node.split.expr,total,sep),cursor=axis==='X'?box.x:(axis==='Z'?box.z:box.y);node.children.forEach(function(child,i){var b={x:box.x,y:box.y,z:box.z,w:box.w,d:box.d,h:box.h};if(axis==='X'){b.x=cursor;b.w=sizes[i];}else if(axis==='Z'){b.z=cursor;b.h=sizes[i];}else{b.y=cursor;b.d=sizes[i];}solve(child,b,list,separators);if(i<sizes.length-1&&sep>0){separators.push({axis:axis,x:axis==='X'?cursor+sizes[i]:box.x,y:axis==='Y'?cursor+sizes[i]:box.y,z:axis==='Z'?cursor+sizes[i]:box.z,w:axis==='X'?sep:box.w,d:axis==='Y'?sep:box.d,h:axis==='Z'?sep:box.h,parent:node.id});}cursor+=sizes[i]+sep;});}
  function facadeBox(node,rootBox,seps){var b=node.box,j=Math.max(0,Number(node.frontJoint==null?1.5:node.frontJoint)),eps=.05;if(String(node.frontFit||'AUTO')==='CUSTOM')return{x:b.x-Math.max(0,Number(node.overlayLeft)||0),z:b.z-Math.max(0,Number(node.overlayBottom)||0),w:b.w+Math.max(0,Number(node.overlayLeft)||0)+Math.max(0,Number(node.overlayRight)||0),h:b.h+Math.max(0,Number(node.overlayTop)||0)+Math.max(0,Number(node.overlayBottom)||0),y:b.y};if(id('montaje_puerta')&&id('montaje_puerta').value==='EMBUTIDA')return{x:b.x+j,z:b.z+j,w:Math.max(1,b.w-j*2),h:Math.max(1,b.h-j*2),y:b.y};var left=Math.abs(b.x-rootBox.x)<eps?0:b.x,right=Math.abs((b.x+b.w)-(rootBox.x+rootBox.w))<eps?num('ancho_total',600):b.x+b.w,bottom=Math.abs(b.z-rootBox.z)<eps?0:b.z,top=Math.abs((b.z+b.h)-(rootBox.z+rootBox.h))<eps?num('alto_total',760):b.z+b.h;seps.forEach(function(s){if(s.axis==='X'){if(Math.abs((s.x+s.w)-b.x)<eps)left=s.x+s.w/2;if(Math.abs(s.x-(b.x+b.w))<eps)right=s.x+s.w/2;}if(s.axis==='Z'){if(Math.abs((s.z+s.h)-b.z)<eps)bottom=s.z+s.h/2;if(Math.abs(s.z-(b.z+b.h))<eps)top=s.z+s.h/2;}});return{x:left+j,z:bottom+j,w:Math.max(1,right-left-j*2),h:Math.max(1,top-bottom-j*2),y:b.y};}
  function geometry(){var nodes=[],seps=[],rootBox=bounds();solve(tree,rootBox,nodes,seps);nodes.forEach(function(n){n.display_name=label(n);var esFrenteCajon=n.content==='CAJONES_FRENTES';if((n.front&&n.front!=='NINGUNO'&&String(n.front).indexOf('INTERNA')<0)||esFrenteCajon)n.front_box=facadeBox(n,rootBox,seps);});return{root:tree,nodes:nodes,separators:seps};}
  function nodePath(n){var parts=[],cur=n;while(cur&&cur.id!=='root'){var p=parentOf(cur.id);parts.unshift(String((p.children||[]).indexOf(cur)+1));cur=p;}return parts;}
  function alpha(index){var result='',value=Math.max(0,index);do{result=String.fromCharCode(65+(value%26))+result;value=Math.floor(value/26)-1;}while(value>=0);return result;}
  function label(n){if(n.id==='root')return 'Módulo';var p=nodePath(n),zone=alpha((parseInt(p[0],10)||1)-1),suffix=p.slice(1).join('.');if(p.length===1)return 'Zona '+zone;if(p.length===2)return 'Espacio '+zone+'.'+suffix;return 'Subespacio '+zone+'.'+suffix;}
  // El antiguo diagrama plano en HTML/CSS (mountPlan, .hierarchy-node,
  // .hierarchy-separator, .hierarchy-parent-front) se retiró: visor 2D y 3D
  // quedaron unificados en modular3d_view.js (botón "Vista 2D" del panel
  // MODULAR-3D VIEW, ortogonal de frente sobre la geometría real), así que
  // ya no hace falta mantener una segunda representación aproximada aquí.
  function renderTree(host,node,depth){if(!host)return;var has=(node.children||[]).length>0,row=document.createElement('div');row.className='hierarchy-tree-row';row.style.setProperty('--depth',depth);row.innerHTML='<button type="button" class="hierarchy-tree-toggle" '+(has?'':'disabled')+'>'+(has?(expanded[node.id]?'−':'+'):'·')+'</button><button type="button" class="hierarchy-tree-select '+(node.id===selectedId?'active':'')+'">'+label(node)+'</button><span class="hierarchy-tree-size">'+Math.round(node.box.w)+'×'+Math.round(node.box.h)+'</span>';row.children[0].onclick=function(){expanded[node.id]=!expanded[node.id];render(true);};row.children[1].onclick=function(){select(node.id);};host.appendChild(row);if(has&&expanded[node.id])node.children.forEach(function(child){renderTree(host,child,depth+1);});}
  // El inspector vive de forma fija dentro de "#interior .hierarchy-layout"
  // en el HTML estático; ya no existe una segunda página ("review") a la
  // que trasladarlo, así que esta función queda como no-op inofensivo por
  // si algún call site antiguo la sigue invocando.
  function moveInspector(){}
  function showEditorPage(pageId){document.querySelectorAll('.page').forEach(function(page){page.classList.toggle('active',page.id===pageId);});document.querySelectorAll('[data-page]').forEach(function(tab){tab.classList.toggle('active',tab.dataset.page===pageId);});moveInspector();}
  function render(selectionOnly){var g,status=id('hierarchy_status');try{g=geometry();if(status){status.className='hierarchy-status';status.textContent=g.nodes.length+' espacios · '+g.separators.length+' separadores físicos · cálculo exacto en mm';}}catch(e){if(status){status.className='hierarchy-status error';status.textContent=e.message;}return;}
    var host=id('hierarchy_tree');if(host){host.innerHTML='';renderTree(host,tree,0);}
    var path=[],cur=nodeById(selectedId);while(cur){path.unshift(cur);expanded[cur.id]=true;cur=parentOf(cur.id);}var breadcrumb=id('hierarchy_breadcrumb');if(breadcrumb){breadcrumb.innerHTML=path.map(function(n){return '<button type="button" data-path="'+n.id+'">'+label(n)+'</button>';}).join(' › ');breadcrumb.querySelectorAll('button').forEach(function(b){b.onclick=function(){select(b.dataset.path);};});}loadInspector();if(selectionOnly&&window.Modular3DView&&window.Modular3DView.selectSpace)window.Modular3DView.selectSpace(selectedPieceOwnerId?null:selectedId,false);else sync(); }
  function select(nodeId){if(!nodeById(nodeId))return;selectedPieceOwnerId=null;selectedId=nodeId;var cur=nodeById(nodeId);while(cur){expanded[cur.id]=true;cur=parentOf(cur.id);}render(true);}
  function loadInspector(){var n=nodeById(selectedId),b=n.box||bounds();id('hierarchy_summary').innerHTML='<b>'+label(n)+'</b><br>'+Math.round(b.w)+' × '+Math.round(b.h)+' × '+Math.round(b.d)+' mm';['left','right','bottom','top','back'].forEach(function(k){id('h_'+k).checked=!!(n.enclosure&&n.enclosure[k]);});if(id('h_top_mode'))id('h_top_mode').value=(n.enclosure&&n.enclosure.topMode)||'FULL';if(id('h_top_travesano'))id('h_top_travesano').value=(n.enclosure&&n.enclosure.topTravesano)||70;var encMount=n.enclosure||{};if(id('h_mount_left'))id('h_mount_left').value=encMount.leftMount||'EXTERIOR';if(id('h_mount_right'))id('h_mount_right').value=encMount.rightMount||'EXTERIOR';if(id('h_mount_bottom'))id('h_mount_bottom').value=encMount.bottomMount||'INTERIOR';if(id('h_mount_top'))id('h_mount_top').value=encMount.topMount||'INTERIOR';id('h_content').value=n.content||'VACIO';id('h_shelves').value=n.shelves||1;id('h_drawers').value=n.drawers||3;id('h_front').value=String(n.front||'NINGUNO').replace(/_VIDRIO/g,'').replace(/VIDRIO/g,'UNICA');id('h_front_count').value=String(n.frontCount||'AUTO');id('h_front_fit').value=n.frontFit||'AUTO';id('h_front_joint').value=n.frontJoint==null?1.5:n.frontJoint;id('h_overlay_left').value=n.overlayLeft==null?13.5:n.overlayLeft;id('h_overlay_right').value=n.overlayRight==null?13.5:n.overlayRight;id('h_overlay_top').value=n.overlayTop==null?13.5:n.overlayTop;id('h_overlay_bottom').value=n.overlayBottom==null?13.5:n.overlayBottom;id('h_hinge').value=n.hinge||'Izquierda';id('h_gap').value=n.gap==null?3:n.gap;id('h_gap_center').value=n.gapCenter==null?(n.gap==null?3:n.gap):n.gapCenter;if(id('h_drawer_gap'))id('h_drawer_gap').value=n.drawerGap==null?1.5:n.drawerGap;if(id('h_drawer_height'))id('h_drawer_height').value=n.drawerHeight==null?0:n.drawerHeight;if(id('h_drawer_front_style'))id('h_drawer_front_style').value=n.drawerFrontStyle||'POR_CAJON';if(id('h_tiradera'))id('h_tiradera').checked=n.tiradera==null?(n.content==='CAJONES_FRENTES'):!!n.tiradera;var sob=n.sobremedida||{};['frontalIzq','traseraIzq','frontalDer','traseraDer','frontalInferior','traseraInferior','frontalSuperior','traseraSuperior'].forEach(function(k){var f=id('h_sob_'+k.replace(/([A-Z])/g,function(m){return '_'+m.toLowerCase();}));if(f)f.value=sob[k]==null?0:sob[k];});toggleFields();}
  // Antes eran ~15 líneas de show/hide a mano por cada campo; las
  // condiciones ahora viven como datos (ver el registrar() más arriba) y
  // este único motor compartido (reglas_visibilidad.js) las aplica.
  function toggleFields(){ if(window.Modular3DReglas) window.Modular3DReglas.aplicar(); }
  function split(){var n=nodeById(selectedId);if(!n)return;var axis=id('hierarchy_axis').value,physical=id('hierarchy_physical').value==='FISICA',expr=id('hierarchy_expr').value,box=n.box||bounds(),total=axis==='X'?box.w:(axis==='Z'?box.h:box.d),sizes;try{sizes=parse(expr,total,physical?num('espesor',15):0);}catch(e){var statusEl=id('hierarchy_status');if(statusEl){statusEl.className='hierarchy-status error';statusEl.textContent=e.message;}return;}n.split={axis:axis,expr:expr,physical:physical,thickness:num('espesor',15)};n.children=sizes.map(function(){var hijo=childDefaults();hijo.id='space_'+counter++;return hijo;});expanded[n.id]=true;selectedId=n.children[0].id;render();}
  function apply(){var n=nodeById(selectedId);if(!n)return;n.enclosure=n.enclosure||{};['left','right','bottom','top','back'].forEach(function(k){n.enclosure[k]=id('h_'+k).checked;});n.enclosure.topMode=id('h_top_mode')?id('h_top_mode').value:'FULL';n.enclosure.topTravesano=Math.max(20,num('h_top_travesano',70));
    // v6 §Fase B: montaje por pieza del espacio (interior/sobrepuesto/
    // inglete), con la MISMA regla de conflicto de esquina que ya aplica el
    // casco general en core/jerarquia.rb (lineas ~120-134): un lateral y un
    // horizontal no pueden llegar los dos "de punta a punta" a la misma
    // esquina, asi que si un lateral queda sobrepuesto o con inglete, el
    // horizontal correspondiente se fuerza a interior. Ruby vuelve a aplicar
    // esta misma regla al construir -- esto es solo para que la UI ya
    // muestre el resultado correcto antes de construir.
    n.enclosure.leftMount=id('h_mount_left')?id('h_mount_left').value:'EXTERIOR';
    n.enclosure.rightMount=id('h_mount_right')?id('h_mount_right').value:'EXTERIOR';
    n.enclosure.bottomMount=id('h_mount_bottom')?id('h_mount_bottom').value:'INTERIOR';
    n.enclosure.topMount=id('h_mount_top')?id('h_mount_top').value:'INTERIOR';
    var lateralSobrepuesto=n.enclosure.leftMount!=='INTERIOR'||n.enclosure.rightMount!=='INTERIOR';
    if(lateralSobrepuesto){if(n.enclosure.bottomMount==='EXTERIOR')n.enclosure.bottomMount='INTERIOR';if(n.enclosure.topMount==='EXTERIOR')n.enclosure.topMount='INTERIOR';}
var contenidoAnterior=n.content;n.content=id('h_content').value;if(n.content!==contenidoAnterior&&id('h_tiradera'))id('h_tiradera').checked=n.content==='CAJONES_FRENTES';n.tiradera=id('h_tiradera')?!!id('h_tiradera').checked:(n.content==='CAJONES_FRENTES');n.shelves=Math.min(20,Math.max(0,parseInt(id('h_shelves').value,10)||0));n.drawers=Math.min(12,Math.max(0,parseInt(id('h_drawers').value,10)||0));n.front=id('h_front').value;n.frontCount=id('h_front_count').value||'AUTO';n.frontFit=id('h_front_fit').value||'AUTO';n.frontJoint=Math.max(0,num('h_front_joint',1.5));n.overlayLeft=Math.max(0,num('h_overlay_left',13.5));n.overlayRight=Math.max(0,num('h_overlay_right',13.5));n.overlayTop=Math.max(0,num('h_overlay_top',13.5));n.overlayBottom=Math.max(0,num('h_overlay_bottom',13.5));if(n.content==='CAJONES_PUERTA'&&n.front==='NINGUNO')n.front='PUERTA_UNICA';n.drawerFrontStyle=id('h_drawer_front_style')?id('h_drawer_front_style').value:'POR_CAJON';if(n.content==='CAJONES_FRENTES')n.front='NINGUNO';if(isExternalFront(n.front)){clearExternalDescendants(n);var ancestor=parentOf(n.id);while(ancestor){if(isExternalFront(ancestor.front))ancestor.front='NINGUNO';ancestor=parentOf(ancestor.id);}}n.hinge=id('h_hinge').value;n.gap=Math.max(0,num('h_gap',3));n.gapCenter=Math.max(0,num('h_gap_center',n.gap));n.drawerGap=Math.max(0,num('h_drawer_gap',1.5));n.drawerHeight=Math.max(0,num('h_drawer_height',0));n.sobremedida=n.sobremedida||freshSobremedida();['frontalIzq','traseraIzq','frontalDer','traseraDer','frontalInferior','traseraInferior','frontalSuperior','traseraSuperior'].forEach(function(k){var fieldId='h_sob_'+k.replace(/([A-Z])/g,function(m){return '_'+m.toLowerCase();}),v=num(fieldId,0);n.sobremedida[k]=Math.max(-200,Math.min(200,v));});render();}
  // --- Migracion opcional desde el formato plano/generaciones antiguas ---
  // Convierte un modulo guardado ANTES de que existiera la jerarquia (grid
  // de nichos x columnas via spaces_json, o el formato mas viejo todavia
  // con solo crear_puerta+cajones_por_nicho) a un arbol equivalente. Nunca
  // se ejecuta sola: el usuario la dispara con un boton, revisa el
  // resultado en la vista 3D y recien despues decide guardar -- el codigo
  // Ruby que construye el formato viejo no se toca ni se retira, sigue
  // siendo el que abre esos modulos si esta conversion no se usa.
  function childDefaults(){return {content:'VACIO',front:'NINGUNO',frontCount:'AUTO',frontFit:'AUTO',frontJoint:huelgosActuales.frontJoint,overlayLeft:huelgosActuales.overlayLeft,overlayRight:huelgosActuales.overlayRight,overlayTop:huelgosActuales.overlayTop,overlayBottom:huelgosActuales.overlayBottom,drawers:0,shelves:0,gap:huelgosActuales.gap,gapCenter:huelgosActuales.gapCenter,drawerGap:huelgosActuales.drawerGap,drawerHeight:0,drawerFrontStyle:'POR_CAJON',enclosure:{leftMount:'EXTERIOR',rightMount:'EXTERIOR',bottomMount:'INTERIOR',topMount:'INTERIOR'},sobremedida:freshSobremedida(),children:[]};}
  function nodeFromSpaceFlat(space,hingeGlobal){
    var n=childDefaults(),contenido=String((space&&space.content)||'VACIO').toUpperCase();
    if(contenido==='CAJONERA'){n.content=(space.front_type==='FRENTES')?'CAJONES_FRENTES':'CAJONES_INTERNOS';n.drawers=Math.max(1,parseInt(space.drawers,10)||3);if(space.gap)n.drawerGap=Number(space.gap)||1.5;}
    else if(contenido==='REPISAS'){n.content='REPISAS';n.shelves=Math.max(1,parseInt(space.shelves,10)||1);}
    else if(contenido.indexOf('PUERTA')===0){n.content='VACIO';n.front=contenido.indexOf('DOBLE')>=0?'PUERTA_DOBLE':'PUERTA_UNICA';if(space.gap)n.gap=Number(space.gap)||3;if(hingeGlobal)n.hinge=hingeGlobal;}
    else{n.content='VACIO';}
    return n;
  }
  function migrarDesdeFormatoPlano(){
    var d=window.__modular3dInitial||{};
    var warnings=[];
    if(String(d.lleva_maletera||'NO')==='SI')warnings.push('El módulo original tenía "maletera" (repisa retraída superior): esta conversión no la reproduce, agregala a mano en la jerarquía si hace falta.');
    var espesor=Number(d.espesor)||15;
    var numDiv=parseInt(d.num_divisiones,10)||0,numRep=parseInt(d.num_repisas,10)||0;
    var paramXExpr=String(d.param_x_expr||'').trim(),paramZExpr=String(d.param_z_expr||'').trim();
    var paramXVirtual=String(d.param_x_type||'').toUpperCase()==='VIRTUAL',paramZVirtual=String(d.param_z_type||'').toUpperCase()==='VIRTUAL';
    var hingeGlobal=d.puerta_bisagra||null;
    var spaces={};
    try{var raw=typeof d.spaces_json==='string'?JSON.parse(d.spaces_json||'[]'):(d.spaces_json||[]);raw.forEach(function(sp){spaces[String(sp.niche)+':'+String(sp.column)]=sp;});}catch(_e){}
    var hasGrid=numDiv>0||numRep>0||paramXExpr||paramZExpr||Object.keys(spaces).length>0;
    var root=fresh();
    if(!hasGrid){
      if(String(d.crear_puerta||'NO')==='SI'){
        var cajonesRoot=String(d.cajones_por_nicho||'').split(',').map(function(v){return parseInt(v,10)||0;})[0]||0;
        root.content=cajonesRoot>0?'CAJONES_PUERTA':'VACIO';
        if(cajonesRoot>0)root.drawers=cajonesRoot;
        root.front=String(d.tipo_puerta||'UNICA').toUpperCase()==='DOBLE'?'PUERTA_DOBLE':'PUERTA_UNICA';
        if(hingeGlobal)root.hinge=hingeGlobal;
      }else{
        warnings.push('No se encontraron divisiones, repisas ni puerta en los datos originales: el resultado es un módulo vacío de una sola pieza.');
      }
      return {tree:root,warnings:warnings};
    }
    var rows=numRep+1,cols=numDiv+1;
    var rowExpr=paramZExpr||Array(rows).fill('1').join(':');
    var colExpr=paramXExpr||Array(cols).fill('1').join(':');
    if(rows===1&&cols===1){
      var only=spaces['0:0'];
      if(only){var applied=nodeFromSpaceFlat(only,hingeGlobal);Object.assign(root,applied);}
    }else if(rows===1){
      root.split={axis:'X',expr:colExpr,physical:!paramXVirtual,thickness:espesor};
      root.children=[];
      for(var c0=0;c0<cols;c0++){var leafC=nodeFromSpaceFlat(spaces['0:'+c0],hingeGlobal);leafC.id='space_'+(counter++);root.children.push(leafC);}
    }else if(cols===1){
      root.split={axis:'Z',expr:rowExpr,physical:!paramZVirtual,thickness:espesor};
      root.children=[];
      for(var r0=0;r0<rows;r0++){var leafR=nodeFromSpaceFlat(spaces[r0+':0'],hingeGlobal);leafR.id='space_'+(counter++);root.children.push(leafR);}
    }else{
      root.split={axis:'Z',expr:rowExpr,physical:!paramZVirtual,thickness:espesor};
      root.children=[];
      for(var r=0;r<rows;r++){
        var rowNode=childDefaults();rowNode.id='space_'+(counter++);
        rowNode.split={axis:'X',expr:colExpr,physical:!paramXVirtual,thickness:espesor};
        rowNode.children=[];
        for(var c=0;c<cols;c++){var leaf=nodeFromSpaceFlat(spaces[r+':'+c],hingeGlobal);leaf.id='space_'+(counter++);rowNode.children.push(leaf);}
        root.children.push(rowNode);
      }
    }
    return {tree:root,warnings:warnings};
  }
  function ofrecerMigracionSiAplica(d){
    var notice=id('hierarchy_legacy_migrate_notice');if(!notice)return;
    var yaTieneJerarquia=!!(d&&d.hierarchy_json&&d.hierarchy_json!=='{}');
    var esEdicion=d&&d.__edit_mode==='SI';
    var numDiv=parseInt(d&&d.num_divisiones,10)||0,numRep=parseInt(d&&d.num_repisas,10)||0;
    var tieneSpaces=(function(){try{var raw=typeof (d&&d.spaces_json)==='string'?JSON.parse(d.spaces_json||'[]'):((d&&d.spaces_json)||[]);return raw.length>0;}catch(_e){return false;}})();
    var tienePuertaVieja=d&&d.crear_puerta==='SI';
    notice.style.display=(esEdicion&&!yaTieneJerarquia&&(numDiv>0||numRep>0||tieneSpaces||tienePuertaVieja))?'block':'none';
  }
  // --- Principios de Espacio (§2): "Guardar este espacio..." envía el nodo
  // ACTUAL (sin id/box/children, filtrado del lado Ruby en core/
  // principios.rb) a un archivo reutilizable; "Aplicar" mezcla los campos
  // guardados en un Principio sobre el espacio seleccionado, sin tocar su
  // id/box/children -- nunca crea ni borra subdivisiones.
  var principiosDisponibles = [];
  var CAMPOS_PRINCIPIO = ['content','front','frontCount','frontFit','frontJoint','overlayLeft','overlayRight','overlayTop','overlayBottom','drawers','shelves','gap','gapCenter','drawerGap','drawerHeight','drawerFrontStyle','tiradera','hinge','enclosure','sobremedida'];
  function mensajePrincipio(texto, esError){var host=id('principio_mensaje');if(!host)return;host.textContent=texto||'';host.className='hint-text'+(esError?' error':'');}
  function aplicarPrincipioANodo(nodo, principio){
    if(!principio||!principio.nodo)return;
    CAMPOS_PRINCIPIO.forEach(function(campo){
      if(principio.nodo[campo]===undefined)return;
      nodo[campo]=(campo==='enclosure'||campo==='sobremedida')?JSON.parse(JSON.stringify(principio.nodo[campo])):principio.nodo[campo];
    });
    if(!nodo.enclosure)nodo.enclosure={};
    if(!nodo.sobremedida)nodo.sobremedida=freshSobremedida();
  }
  window.Modular3DApplyPrincipiosList=function(lista){
    principiosDisponibles=Array.isArray(lista)?lista:[];
    var select=id('principio_id');if(!select)return;
    var actual=select.value;
    select.innerHTML='<option value="">Elegir...</option>';
    principiosDisponibles.forEach(function(item){
      var option=document.createElement('option');
      option.value=item.principio_id;
      option.textContent=(item.origen==='FABRICA'?'[Fábrica] ':'')+(item.nombre||item.principio_id);
      select.appendChild(option);
    });
    if(principiosDisponibles.some(function(item){return item.principio_id===actual;}))select.value=actual;
  };
  if(window.__modular3dPrincipios)window.Modular3DApplyPrincipiosList(window.__modular3dPrincipios);
  window.Modular3DPrincipioResult=function(resultado){
    mensajePrincipio(resultado&&resultado.message,!(resultado&&resultado.ok));
    if(resultado&&resultado.ok&&resultado.lista){
      window.Modular3DApplyPrincipiosList(resultado.lista);
      if(resultado.principio&&id('principio_id'))id('principio_id').value=resultado.principio.principio_id;
    }
  };
  function sync(){var json=JSON.stringify(tree);window.__hierarchyJSON=json;try{var d=window.datosFormulario?window.datosFormulario():null;if(d&&window.Modular3DView)window.Modular3DView.update(d);}catch(_e){}}
  function bind(){tree=fresh();id('hierarchy_split').onclick=split;id('hierarchy_unsplit').onclick=function(){var n=nodeById(selectedId);n.split=null;n.children=[];render();};id('hierarchy_parent').onclick=function(){var p=parentOf(selectedId);if(p)select(p.id);};id('hierarchy_duplicate').onclick=function(){var n=nodeById(selectedId),p=parentOf(selectedId);if(!p)return;p.children.forEach(function(s){if(s.id!==n.id){['content','front','frontCount','frontFit','frontJoint','overlayLeft','overlayRight','overlayTop','overlayBottom','drawers','shelves','gap','gapCenter','drawerGap','drawerHeight','drawerFrontStyle','tiradera','hinge'].forEach(function(k){s[k]=n[k];});s.enclosure=JSON.parse(JSON.stringify(n.enclosure||{}));s.sobremedida=JSON.parse(JSON.stringify(n.sobremedida||freshSobremedida()));}});render();};id('hierarchy_reset').onclick=function(){tree=fresh();selectedId='root';expanded={root:true};render();};id('h_content').onchange=toggleFields;['h_left','h_right','h_bottom','h_top','h_back'].forEach(function(key){id(key).addEventListener('change',function(){remember();apply();});});if(id('h_tiradera'))id('h_tiradera').addEventListener('change',function(){remember();apply();});['h_content','h_front','h_front_count','h_front_fit','h_front_joint','h_overlay_left','h_overlay_right','h_overlay_top','h_overlay_bottom','h_hinge','h_shelves','h_drawers','h_gap','h_gap_center','h_drawer_gap','h_drawer_height','h_drawer_front_style','h_top_mode','h_top_travesano','h_sob_frontal_izq','h_sob_trasera_izq','h_sob_frontal_der','h_sob_trasera_der','h_sob_frontal_inferior','h_sob_trasera_inferior','h_sob_frontal_superior','h_sob_trasera_superior'].forEach(function(key){var field=id(key);if(field)field.addEventListener(field.tagName==='SELECT'?'change':'input',function(){remember();apply();});});
    ['external_front_scope','montaje_puerta','global_front_count_mode','global_front_count','global_front_auto_width','global_front_gap_left','global_front_gap_right','global_front_gap_top','global_front_gap_bottom','global_front_gap_center','global_front_hinge'].forEach(function(key){var field=id(key);if(field)field.addEventListener(field.tagName==='SELECT'?'change':'input',function(){var controls=id('global_front_controls');if(controls)controls.style.display=id('external_front_scope').value==='GLOBAL'?'block':'none';sync();});});
    ['ancho_total','alto_total','prof_total','grosor_izq','grosor_der','grosor_superior','grosor_inferior','espesor','grosor_resp','grosor_ajuste','separacion_ajuste_respaldo','distancia_plano_posterior','cantidad_ajustes','lleva_respaldo'].forEach(function(k){var e=id(k);if(e)e.addEventListener('input',render);});
    var original=window.datosFormulario;window.datosFormulario=function(){var d=original();d.geometry_contract_version='4';d.hierarchy_json=JSON.stringify(tree);d.hierarchy_geometry_json=JSON.stringify(geometry());d.selected_space_id=selectedId;return d;};
    window.addEventListener('modular3d:spaceSelected3D',function(event){var detail=event.detail||{};if(detail.id)select(detail.id);});
    // El resaltado sobre el antiguo diagrama plano (.hierarchy-node,
    // .hierarchy-plan, .hierarchy-separator) ya no aplica: la pieza
    // seleccionada se resalta directamente en el visor 3D/2D unificado
    // (caja de selección azul en modular3d_view.js). Aquí solo queda mover
    // a la página del editor correcta, seleccionar el espacio dueño en el
    // árbol, y destellar el campo de origen en el inspector.
    window.addEventListener('modular3d:pieceSelected',function(event){var detail=event.detail||{},role=String(detail.role||''),shell=role.indexOf('shell-')===0,page=(shell||detail.category==='back'||detail.category==='adjustment')?'paneles':'interior',active=document.querySelector('.page.active');if(!active||active.id!=='diseno')showEditorPage(page);if(detail.ownerSpaceId&&nodeById(detail.ownerSpaceId)){selectedPieceOwnerId=detail.ownerSpaceId;selectedId=detail.ownerSpaceId;render(true);}setTimeout(function(){var field=detail.sourceField&&id(detail.sourceField),row=field&&field.closest&&field.closest('.row');if(row){row.classList.add('editor-focus');setTimeout(function(){row.classList.remove('editor-focus');},1600);}},40);});
    window.addEventListener('modular3d:editPieceSource',function(event){var detail=event.detail||{},shell=String(detail.role||'').indexOf('shell-')===0,page=(shell||detail.category==='back'||detail.category==='adjustment')?'paneles':'interior';showEditorPage(page);if(detail.ownerSpaceId&&nodeById(detail.ownerSpaceId)){selectedId=detail.ownerSpaceId;render(true);}setTimeout(function(){var field=detail.sourceField&&id(detail.sourceField);if(field){field.focus();field.scrollIntoView({behavior:'smooth',block:'center'});var row=field.closest&&field.closest('.row');if(row){row.classList.add('editor-focus');setTimeout(function(){row.classList.remove('editor-focus');},1800);}}},40);});
    document.querySelectorAll('[data-page]').forEach(function(tab){tab.addEventListener('click',function(){setTimeout(function(){moveInspector();render(true);},0);});});['step_prev','step_next'].forEach(function(buttonId){var button=id(buttonId);if(button)button.addEventListener('click',function(){setTimeout(function(){moveInspector();render(true);},0);});});
    if(id('btn_aplicar_principio'))id('btn_aplicar_principio').addEventListener('click',function(){
      var principioId=id('principio_id').value;
      var principio=principiosDisponibles.filter(function(item){return item.principio_id===principioId;})[0];
      if(!principio){mensajePrincipio('Elegí un Principio de la lista primero.',true);return;}
      var nodo=nodeById(selectedId);
      if(!nodo)return;
      remember();
      aplicarPrincipioANodo(nodo,principio);
      render(true);
      mensajePrincipio('Principio "'+(principio.nombre||principio.principio_id)+'" aplicado a este espacio.',false);
    });
    if(id('btn_guardar_principio'))id('btn_guardar_principio').addEventListener('click',function(){
      var nombre=window.prompt('Nombre del nuevo Principio de Espacio:','');
      if(nombre===null||!nombre.trim())return;
      if(!window.sketchup||!sketchup.principioGuardar){mensajePrincipio('Esta acción debe abrirse dentro de SketchUp.',true);return;}
      var nodo=nodeById(selectedId);
      if(!nodo)return;
      sketchup.principioGuardar(nodo,nombre.trim(),null);
    });
    if(id('hierarchy_legacy_migrate_btn'))id('hierarchy_legacy_migrate_btn').addEventListener('click',function(){
      if(!confirm('Esto reemplaza la configuración jerárquica actual por una versión convertida desde el formato antiguo. Podés revisarla y deshacerla (Ctrl+Z) si no queda bien. ¿Continuar?'))return;
      remember();
      var resultado=migrarDesdeFormatoPlano();
      tree=resultado.tree;selectedId='root';expanded={root:true};selectedPieceOwnerId=null;
      render();
      var notice=id('hierarchy_legacy_migrate_notice');if(notice)notice.style.display='none';
      var mensaje='Conversión aplicada. Revisá cada espacio en la vista 3D antes de guardar -- es una primera aproximación, no un reemplazo exacto.'+(resultado.warnings.length?'\n\n'+resultado.warnings.join('\n'):'');
      alert(mensaje);
    });
    var oldLoad=window.Modular3DLoadInitial;window.Modular3DLoadInitial=function(data){oldLoad(data);try{if(data.hierarchy_json){tree=typeof data.hierarchy_json==='string'?JSON.parse(data.hierarchy_json):data.hierarchy_json;selectedId=data.selected_space_id&&nodeById(data.selected_space_id)?data.selected_space_id:'root';expanded={root:true};resolveFrontConflicts(tree,false);walk(tree,function(n){var match=String(n.id||'').match(/(\d+)$/);if(match)counter=Math.max(counter,+match[1]+1);return false;});}}catch(_e){tree=fresh();}ofrecerMigracionSiAplica(data);var controls=id('global_front_controls');if(controls)controls.style.display=id('external_front_scope').value==='GLOBAL'?'block':'none';render();};var controls=id('global_front_controls');if(controls)controls.style.display=id('external_front_scope').value==='GLOBAL'?'block':'none';render();if(window.__modular3dInitial)window.Modular3DLoadInitial(window.__modular3dInitial);}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',function(){setTimeout(bind,0);});else setTimeout(bind,0);
}());
