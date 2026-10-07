# TODO de SimulateX

Estado tras la auditoría del 2026-10-07 (versión 0.13.0). Lo marcado «hecho» se quita de aquí al cerrarlo.

## Pendiente confirmado (camino a la 1.0)

- [ ] **Pestaña Talentos en DK, Mago y Paladín (decidir).** No es un fallo de datos: su búsqueda Nivel 3 no halló nada mejor que la distribución estándar de wowsims, así que no tienen fichero de variantes (`TALENT_VARIANTS` vacío, ver `Tools/NOTAS_TALENTOS_NIVEL2.md`). Pero la pestaña dice «Sin distribuciones simuladas todavía» (`UI/Talentos.lua:471`), que parece algo pendiente. Propuesta: mostrar la distribución estándar con su DPS y la nota «óptima según la búsqueda de SimulateX». Pide generar el fichero de la clase con solo la variante `estandar` o cambiar el texto.
- [ ] Entradas de `SimulateX_TalentDataVars` (`SimulateX.lua:23-30`) de DK, Paladín y Mago apuntan a tablas que no existen: inofensivo, pero limpiar o documentar.
- [ ] **Prueba en juego (la hace el usuario):** v0.10 (lista de la compra), v0.11 (profesiones, bolsas, zonas), `LoadAddOn` desde `ADDON_LOADED` y pestaña Talentos de las clases nuevas. Tras reiniciar el cliente completo si cambia algún `.toc`.
- [ ] **Publicar como 1.0.0** cuando lo anterior esté probado (el push exige aprobación del usuario; hay commits locales sin subir).

## Pendiente menor, a decidir

- [ ] Reliquias de sanadores y tanques sin valorar (sin simulación de HPS/amenaza para ellas).
- [ ] Algunos valores bajos (~0,3-0,5 %) de reliquias pueden ser ruido de simulación: considerar subir `NOISE_THRESHOLD_PCT` para reliquias o simularlas con más iteraciones.
- [ ] **Sufijos aleatorios en Mejoras (fase E de v0.11):** proponer el mejor sufijo («del oso», «del águila»…) para la spec leyendo `item_enchantment_template`. Hoy solo se puntúa el sufijo que trae el objeto. Decidir: 0.12 o fuera de alcance.
- [ ] **Sanadores sin simulación de HPS** (`holy_paladin`, `restoration_druid`, `restoration_shaman` salen con 0 HPS o pesos del preset). Ver `.agents/plans/simulacion-wowsims/`.
- [ ] **Fórmula de nivel bajo** para 19 specs y relanzar simulaciones pendientes (ver el mismo plan).
- [ ] **Tres «Pendiente» en `Tools/NOTAS_TALENTOS_NIVEL2.md`** (líneas ~93, 102, 106): revisar si siguen vigentes.
- [ ] `Addon/SimulateX/Media/SimulateX.tga`: comprobar que se usa.
- [ ] Encantamientos: no se indica la reputación o el pergamino necesarios (cabeza y hombros); solo se valoran niveles 80; sin estadísticas no se puntúan.

## Mejoras propuestas (pendientes de estudio y confirmación)

Ninguna se empieza sin confirmación. Por orden de valor estimado, no medido.

1. **Simulación real de HPS para sanadores** (hoy pesos del preset): wowsims los soporta en parte; habría que estudiar qué specs son viables.
2. **Nivel 3 también para tanques** con una métrica que no sacrifique la supervivencia (amenaza con límite de mitigación). Hoy excluidos a propósito.
3. **Recetas ya aprendidas** (hoy «fuera de alcance»): marcar en Mejoras las profesiones que el jugador ya sabe fabricar. Necesita leer la lista de recetas con la API 3.3.5a.
4. **Importar/exportar configuración** y perfiles por personaje.
5. **Aviso de objetos mejores en la bolsa** al abrirla (resumen: «tienes 2 mejoras sin equipar»).
6. **Comparador contra el equipo de otro jugador/bot** (hoy «inspección de bots» fuera de alcance): valorar si compensa.
7. **Localización a otros idiomas** de la interfaz del addon (hoy solo esES).
8. **Revisar los porcentajes inflados a nivel bajo** (hueco vacío = comparación contra nada): mostrar «hueco libre» en lugar de un % enorme.
