(function () {
  'use strict';
  /* Motor de reglas de visibilidad orientado a datos, inspirado en el
     LOGIC_DEFINITION declarativo de imos (FIELD(nombre).visible = IF(EQ(...))):
     en vez de que cada pestaña mantenga su propia función ad-hoc de mostrar/
     ocultar campos a mano (como existía antes por separado en
     hierarchical_config.js, interfaz.js y material_config.js), cada archivo
     declara sus condiciones una sola vez como DATOS (reglas) y este único
     motor compartido las evalúa y las aplica. Esto es lo que permite la
     "cascada de visibilidad" pedida: activar una opción (una puerta, un
     tipo de cajón, un respaldo, un material propio...) revela de inmediato
     sus propios sub-campos de configuración, en cualquier pestaña, sin
     tener que escribir una función nueva cada vez -- solo agregar una regla.

     Formato de una regla:
       { selector: '<selector CSS>', cuando: <condición> }
     Una condición es una de:
       { field:'id_campo', test:'checked'|'notChecked' }
       { field:'id_campo', test:'equals'|'notEquals', value:'X' }
       { field:'id_campo', test:'oneOf'|'notOneOf', value:['X','Y'] }
       { field:'id_campo', test:'startsWith'|'contains'|'notContains', value:'X' }
       { all:[condición, condición, ...] }   -- AND
       { any:[condición, condición, ...] }   -- OR
       { not: condición }                    -- NOT
     aplicarUna() alterna el inline style.display entre '' (deja que la
     hoja de estilos decida, sea grid/flex/block) y 'none' -- nunca fuerza
     un valor de display concreto, así una misma regla sirve para cualquier
     tipo de contenedor sin tener que conocer su CSS. */
  function campo(id) { return document.getElementById(id); }
  function valorCampo(id) {
    var el = campo(id); if (!el) return null;
    if (el.type === 'checkbox') return el.checked;
    return el.value;
  }
  function condicionSimple(cond) {
    var actual = valorCampo(cond.field);
    switch (cond.test) {
      case 'checked': return actual === true;
      case 'notChecked': return actual !== true;
      case 'equals': return String(actual) === String(cond.value);
      case 'notEquals': return String(actual) !== String(cond.value);
      case 'oneOf': return (cond.value || []).map(String).indexOf(String(actual)) >= 0;
      case 'notOneOf': return (cond.value || []).map(String).indexOf(String(actual)) < 0;
      case 'startsWith': return String(actual == null ? '' : actual).indexOf(String(cond.value)) === 0;
      case 'contains': return String(actual == null ? '' : actual).indexOf(String(cond.value)) >= 0;
      case 'notContains': return String(actual == null ? '' : actual).indexOf(String(cond.value)) < 0;
      default: return true;
    }
  }
  function evaluar(cond) {
    if (!cond) return true;
    if (cond.all) return cond.all.every(evaluar);
    if (cond.any) return cond.any.some(evaluar);
    if (cond.not) return !evaluar(cond.not);
    return condicionSimple(cond);
  }
  var reglas = [];
  function registrar(lista) { (lista || []).forEach(function (regla) { reglas.push(regla); }); }
  function aplicarUna(regla) {
    var visible = evaluar(regla.cuando);
    document.querySelectorAll(regla.selector).forEach(function (el) { el.style.display = visible ? '' : 'none'; });
    return visible;
  }
  function aplicar() { reglas.forEach(aplicarUna); }
  window.Modular3DReglas = { registrar: registrar, aplicar: aplicar, evaluar: evaluar, valorCampo: valorCampo };
}());
