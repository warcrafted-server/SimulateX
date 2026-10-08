# TODO de SimulateX

Estado tras la auditoría del 2026-10-07 (versión 0.13.0). Lo marcado «hecho» se quita de aquí al cerrarlo.

## Pendiente confirmado (camino a la 1.0)

- [ ] **Prueba en juego (la hace el usuario):** v0.10 (lista de la compra), v0.11 (profesiones, bolsas, zonas), `LoadAddOn` desde `ADDON_LOADED` y pestaña Talentos de las clases nuevas. Tras reiniciar el cliente completo si cambia algún `.toc`.
- [ ] **Publicar como 1.0.0** cuando lo anterior esté probado (el push exige aprobación del usuario; hay commits locales sin subir).

## Pendiente menor, a decidir

- [ ] Reliquias de sanadores y tanques sin valorar (sin simulación de HPS/amenaza para ellas).
- [ ] Algunos valores bajos (~0,3-0,5 %) de reliquias pueden ser ruido de simulación: considerar subir `NOISE_THRESHOLD_PCT` para reliquias o simularlas con más iteraciones.
- [ ] **Sufijos aleatorios en Mejoras (fase E de v0.11):** proponer el mejor sufijo («del oso», «del águila»…) para la spec leyendo `item_enchantment_template`. Hoy solo se puntúa el sufijo que trae el objeto. Decidir: 0.12 o fuera de alcance.
- [ ] **Pesos fiables para sanadores** (estado del chamán Restauración y del estudio del 2026-10-08, abajo).
- [ ] **Fórmula de nivel bajo** para 19 specs y relanzar simulaciones pendientes (ver el mismo plan).
- [ ] **Tres «Pendiente» en `Tools/NOTAS_TALENTOS_NIVEL2.md`** (líneas ~93, 102, 106): revisar si siguen vigentes.
- [ ] Encantamientos: no se indica la reputación o el pergamino necesarios (cabeza y hombros); solo se valoran niveles 80; sin estadísticas no se puntúan.

## Mejoras propuestas (pendientes de decisión del usuario)

Los estudios siguientes están hechos; sus conclusiones quedan pendientes de decisión del usuario. El resto sigue por orden de valor estimado, no medido.

1. **HPS simulado para sanadores** (estudio del 2026-10-08, estado parcial). El sacerdote (`healing_priest`, disciplina y sagrado) conserva pesos simulados. El chamán Restauración ya tiene APL propio y produjo 7584 HPS en la fase PreRaid, pero sus pesos HPS de 5000 iteraciones dieron celeridad negativa (-0,53) y desviaciones grandes para intelecto, espíritu, MP5 y crítico; `SPECS_PESOS_NO_FIABLES` en `Tools/extraer_ep_stats.py` lo mantiene en preset. El paladín Sagrado y el druida Restauración siguen sin ser viables sin portar sus hechizos de curación al fork de wowsims en Go. Los pesos del chamán dependen del APL escrito a mano.
2. **Nivel 3 también para tanques** (pendiente de decisión del usuario; estudio 2026-10-08). Es viable con una simulación por cadena y una métrica que promedie las mejoras relativas de TPS y de -DTPS; requiere cambios pequeños-medios en `Tools/talentos_nivel3.py` (`ROLE_METRIC`, `Simulator.run`/`value` y una función `score` nueva). Antes de decidir, medir la dispersión con 5000 iteraciones en `feral_tank_druid`, `protection_paladin`, `tank_deathknight` y `protection_warrior`, y valorar TMI (el proto lo tiene, pero hoy no se extrae). Con 1000 iteraciones, la dispersión de DTPS es del orden de los umbrales (0,01-0,05 %); coste estimado total de 4-12 h de CPU. No promover builds de tanque que solo ganen en TPS.
3. **Importar/exportar configuración** y perfiles por personaje.
4. **Aviso de objetos mejores en la bolsa** al abrirla (resumen: «tienes 2 mejoras sin equipar»).
5. **Comparador contra el equipo de otro jugador/bot** (hoy «inspección de bots» fuera de alcance): valorar si compensa.
6. **Localización a otros idiomas** de la interfaz del addon (hoy solo esES).
