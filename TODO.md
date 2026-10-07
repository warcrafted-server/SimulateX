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
- [ ] **Decidir si se simula HPS para sanadores** (estudio del 2026-10-08; conclusiones y decisión pendiente abajo).
- [ ] **Fórmula de nivel bajo** para 19 specs y relanzar simulaciones pendientes (ver el mismo plan).
- [ ] **Tres «Pendiente» en `Tools/NOTAS_TALENTOS_NIVEL2.md`** (líneas ~93, 102, 106): revisar si siguen vigentes.
- [ ] `Addon/SimulateX/Media/SimulateX.tga`: comprobar que se usa.
- [ ] Encantamientos: no se indica la reputación o el pergamino necesarios (cabeza y hombros); solo se valoran niveles 80; sin estadísticas no se puntúan.

## Mejoras propuestas (pendientes de decisión del usuario)

Los estudios siguientes están hechos; sus conclusiones quedan pendientes de decisión del usuario. El resto sigue por orden de valor estimado, no medido.

1. **Simulación real de HPS para sanadores** (pendiente de decisión del usuario; estudio 2026-10-08). El sacerdote (`healing_priest`, disciplina y sagrado) ya tiene pesos simulados. El chamán Restauración es viable con esfuerzo medio: el simulador ya tiene sus curaciones, pero falta un APL y quitarlo de `SPECS_SIN_ROTACION` en `Tools/extraer_ep_stats.py`. El paladín Sagrado y el druida Restauración no son viables sin portar sus hechizos de curación al fork de wowsims en Go; el esfuerzo sería grande y no se recomienda, porque sus pesos no serían más fiables que los del preset. Además, los pesos dependen del APL escrito a mano.
2. **Nivel 3 también para tanques** (pendiente de decisión del usuario; estudio 2026-10-08). Es viable con una simulación por cadena y una métrica que promedie las mejoras relativas de TPS y de -DTPS; requiere cambios pequeños-medios en `Tools/talentos_nivel3.py` (`ROLE_METRIC`, `Simulator.run`/`value` y una función `score` nueva). Antes de decidir, medir la dispersión con 5000 iteraciones en `feral_tank_druid`, `protection_paladin`, `tank_deathknight` y `protection_warrior`, y valorar TMI (el proto lo tiene, pero hoy no se extrae). Con 1000 iteraciones, la dispersión de DTPS es del orden de los umbrales (0,01-0,05 %); coste estimado total de 4-12 h de CPU. No promover builds de tanque que solo ganen en TPS.
3. **Recetas ya aprendidas** (hoy «fuera de alcance»): marcar en Mejoras las profesiones que el jugador ya sabe fabricar. Necesita leer la lista de recetas con la API 3.3.5a.
4. **Importar/exportar configuración** y perfiles por personaje.
5. **Aviso de objetos mejores en la bolsa** al abrirla (resumen: «tienes 2 mejoras sin equipar»).
6. **Comparador contra el equipo de otro jugador/bot** (hoy «inspección de bots» fuera de alcance): valorar si compensa.
7. **Localización a otros idiomas** de la interfaz del addon (hoy solo esES).
