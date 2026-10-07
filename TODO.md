# TODO de SimulateX

Estado tras la auditoría del 2026-10-07 (versión 0.11.0). Lo marcado «hecho» se quita de aquí al cerrarlo.

## Pendiente confirmado (cierre de la 0.11 y camino a la 1.0)

- [ ] **Reliquias (fase D de v0.11) — necesita decisión de diseño.** Ídolos, tótems, libramientos y sigilos (`INVTYPE_RELIC`, hueco `RangedSlot`) no se valoran ni salen en Mejoras. Cablearlas no basta: en la BD **no tienen estadísticas** (`stat_value1 = 0`), su efecto es un hechizo (`spellid_1`) que mejora una habilidad concreta, así que con pesos EP valdrían 0. Valorarlas exige simular cada reliquia en wowsims (cambiando el objeto en la petición base, como las variantes de talentos) y guardar su valor por spec. Ojo: en el código «reliquias» también designa los objetos heredados (escalado por nivel, `AddScalingStats`), que es otra cosa. Opciones y coste en la conversación del 2026-10-07; mientras no se decida, el tooltip no las valora.
- [ ] **Talentos de Caballero de la Muerte, Mago y Paladín.** La pestaña Talentos dibuja los árboles pero sin distribuciones: nunca se ejecutó `simular_talentos.py` ni `generar_db_talentos.py` para ellos. Specs: `deathknight`, `tank_deathknight`, `mage`, `retribution_paladin`, `protection_paladin`, `holy_paladin` (las de sanador, solo si tienen simulación). Después, regenerar con `generar_db_talentos.py --clase <Clase>`, listar el archivo en el `.toc` y revisar `SimulateX_TalentDataVars` (`SimulateX.lua:23-30`).
- [ ] **Volcar el Nivel 3 de Mago, Paladín Represalias, DK y Chamán Elemental al addon** si alguna búsqueda dio variante (las 4 cerraron sin mejora; solo hay que confirmar que la pestaña muestra el preset).
- [ ] **README.md y README.en.md** (siguen en v0.10): Talentos/Nivel 3/glifos, topes de golpe/pericia/penetración, gemas ideales, BiS por fase, aviso de bonus de conjunto, economía en el vendedor, profesiones y bolsas en Mejoras, zona de cada origen, filtro de armadura. Documentar los comandos `/simulatex debug [enlace]`, `/simulatex nivel <n>`, `/simulatex <build>`, `/simulatex` y `/simulatexconfig`. Añadir el enlace a https://portal.warcrafted.com/.
- [ ] **CHANGELOG:** cambiar «Pestaña Talentos (v0.7, en marcha)», añadir el Nivel 3 por spec (hay variante en Equilibrio, Feral, Cazador, Mejora, Sombra, Pícaro, Brujo y Guerrero; sin mejora en Elemental, Mago, Represalias y DK) y arreglar la entrada antigua sin versión (`## - 2026-09-26`).
- [ ] **Tres entradas sin fichero en `SimulateX_TalentDataVars`** (`SimulateX.lua:23-30`, DK, Paladín, Mago): se resuelve al generar sus datos de talentos.
- [ ] **Prueba en juego (la hace el usuario):** v0.10 (lista de la compra), v0.11 (profesiones, bolsas, zonas), `LoadAddOn` desde `ADDON_LOADED` y pestaña Talentos de las clases nuevas. Tras reiniciar el cliente completo si cambia algún `.toc`.
- [ ] **Publicar como 1.0.0** cuando lo anterior esté probado (el push exige aprobación del usuario; hay commits locales sin subir).

## Pendiente menor, a decidir

- [ ] **Sufijos aleatorios en Mejoras (fase E de v0.11):** proponer el mejor sufijo («del oso», «del águila»…) para la spec leyendo `item_enchantment_template`. Hoy solo se puntúa el sufijo que trae el objeto. Decidir: 0.12 o fuera de alcance.
- [ ] **Sanadores sin simulación de HPS** (`holy_paladin`, `restoration_druid`, `restoration_shaman` salen con 0 HPS o pesos del preset). Ver `.agents/plans/simulacion-wowsims/`.
- [ ] **Fórmula de nivel bajo** para 19 specs y relanzar simulaciones pendientes (ver el mismo plan).
- [ ] **Tres «Pendiente» en `Tools/NOTAS_TALENTOS_NIVEL2.md`** (líneas ~93, 102, 106): revisar si siguen vigentes.
- [ ] `Addon/SimulateX/Media/SimulateX.tga`: comprobar que se usa.

## Mejoras propuestas (pendientes de estudio y confirmación)

Ninguna se empieza sin confirmación. Por orden de valor estimado, no medido.

1. **Encantamientos y gemas recomendados por hueco** en la lista de la compra y en el tooltip: qué encantamiento falta en cada pieza equipada y cuánto aporta a la spec. Encaja con el objetivo de «guía de mejoras». Requiere simular o derivar el valor de cada encantamiento con los mismos pesos EP.
2. **Simulación real de HPS para sanadores** (hoy pesos del preset): wowsims los soporta en parte; habría que estudiar qué specs son viables.
3. **Nivel 3 también para tanques** con una métrica que no sacrifique la supervivencia (amenaza con límite de mitigación). Hoy excluidos a propósito.
4. **Recetas ya aprendidas** (hoy «fuera de alcance»): marcar en Mejoras las profesiones que el jugador ya sabe fabricar. Necesita leer la lista de recetas con la API 3.3.5a.
5. **Importar/exportar configuración** y perfiles por personaje.
6. **Aviso de objetos mejores en la bolsa** al abrirla (resumen: «tienes 2 mejoras sin equipar»).
7. **Comparador contra el equipo de otro jugador/bot** (hoy «inspección de bots» fuera de alcance): valorar si compensa.
8. **Pruebas automáticas** (CI local): ejecutar `probar_mejoras_lupa.py` para las 10 clases y validar sintaxis Lua en cada commit.
9. **Localización a otros idiomas** de la interfaz del addon (hoy solo esES).
10. **Revisar los porcentajes inflados a nivel bajo** (hueco vacío = comparación contra nada): mostrar «hueco libre» en lugar de un % enorme.
