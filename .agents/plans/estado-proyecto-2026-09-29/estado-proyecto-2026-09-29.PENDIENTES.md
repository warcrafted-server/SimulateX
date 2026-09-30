# SimulateX — pendientes (29-09-2026, 21:40, antes de un /clear)

Sustituye a `estado-proyecto-2026-09-29.INFORME.md` como punto de partida.
Repo: `/home/stark/Repos/addons/SimulateX`. Plan vigente:
`.agents/plans/mejoras-v0.8/mejoras-v0.8.PLAN.md` (+ diseños en esa carpeta).

## Reglas de trabajo (del usuario)

- Hablar en castellano. Un commit por cambio sin preguntar; **push solo
  cuando el usuario lo pida**. Datos de clase consolidados: commit propio.
- Todo configurable en el panel (`SimulateXOptions.lua`, `SimulateX_DB`).
- Nunca inventar datos: verificar ids contra la BD (`accesodb`, solo lectura)
  o DBC antes de pintarlos (los glifos de wowsims son ids de OBJETO).
- UI con aspecto nativo del juego. No hay binario Lua: validar sintaxis con
  `luaparser` y probar lógica con `lupa` en un venv del scratchpad
  (`python3 -m venv <scratch>/venv && <scratch>/venv/bin/pip install luaparser lupa`).
- Máquina compartida con los reinos (4 núcleos, carga ~10): procesos largos
  con `nice`, uno de simulación por tarea. Reinicio del servidor a las 04:00
  mata todo: relanzar (comandos abajo), todo es reanudable.
- Antes de cambiar a otra fase grande: proponer modelo/esfuerzo y pausar.

## Hecho y subido (push 0a87bf1)

v0.7 glifos (panel Sublime/Menor con los glifos de la petición simulada),
v0.8 completa (carga por clase `SimulateX_<Clase>` LoadOnDemand, venta de
grises, reparación, precio de venta, mejor recompensa de misión, panel con
scroll), v0.9 completa en código (topes golpe/pericia/ArP con
`Tools/modelo_caps.py` + `Tools/go/simx_stats`; gemas ideales + bonificación
de ranura; BiS por fase con fase máxima configurable; aviso de bonus de
conjunto). Detalle en `CHANGELOG.md`. Nada de esto está probado aún en juego:
esperar feedback del usuario.

## En marcha en segundo plano (comprobar con pgrep)

1. **Regeneración de datos v0.9** (`generar_db_addon.py --clase X`), orden
   Hunter ✔, Paladin ✔, Priest ✔, Shaman ✔, Druid ✔, Mage (en curso ~22:30).
   Driver: `regen_v09.sh` en el scratchpad de la sesión 743ad89d (log `regen_v09.log`).
   Al terminar cada clase: comprobar `caps/gems/bis` en el `.lua`, validar
   sintaxis y commit "Datos de <Clase> con topes, gemas ideales y BiS (v0.9)".
   Relanzar las que falten (una por una, con `nice -n 10`):
   `cd Tools && source ~/.simx_env && export SIMX_DBC_DIR=/home/stark/Servers/acore-playerbots/data/dbc && python3 generar_db_addon.py --clase <Clase>`
2. **Lote de simulación de equipo** `Tools/lote_simulaciones.sh`: rogue y
   warlock en curso; luego warrior, protection_warrior, deathknight,
   tank_deathknight (feral/balance ya hechos, se saltan). Ver
   `Data/logs/lote.log`. Relanzar:
   `cd /home/stark/Repos/addons/SimulateX && nohup nice -n 10 Tools/lote_simulaciones.sh > Data/logs/lote.log 2>&1 & disown`
   Al terminar cada clase: `generar_db_addon.py --clase <Clase>` (regenera
   solo el test Go y se niega si la spec aún se simula) + commit de datos.
3. **Talentos Nivel 3 de Feral** `Tools/talentos_nivel3.py --spec feral_druid`
   (1 mejora aceptada a las 21:40). Estado en `Data/talentos_n3/feral_druid.json`
   (el log sale vacío por el búfer de Python: mirar `history`/`current` del JSON). Relanzar (reanuda):
   `cd Tools && nohup nice -n 19 bash -c 'source ~/.simx_env; python3 -u talentos_nivel3.py --spec feral_druid' > /tmp/n3_feral.log 2>&1 &`
   Al terminar escribe la variante `nivel3` en `Data/talentos/feral_druid.json`:
   entonces `python3 generar_db_talentos.py --clase Druid`, commit, y
   anotar el resultado en `Tools/NOTAS_TALENTOS_NIVEL2.md`.

## Estado a 30-09 03:55 (antes del reinicio de las 04:00)

- Regeneración v0.9 terminada y con commit en todas las clases con datos
  (Hunter, Paladin, Priest, Shaman, Druid, Mage). Nivel 3 de Feral hecho.
- Lote: warlock simulado a las 03:51, **falta consolidarlo**
  (`generar_db_addon.py --clase Warlock` + commit). El reinicio corta el lote:
  relanzarlo (comando de arriba), sigue con rogue, warrior, protection_warrior,
  deathknight, tank_deathknight.
- v0.11: hechas las fases A (profesiones), B, C, F, G del plan
  `.agents/plans/mejoras-v0.11/`; quedan D (reliquias) y E (sufijos) con Opus
  medio, y H (documentación) con Sonnet. Push hecho hasta 8836877.


1. Terminar 1-3 de arriba (commits por clase).
2. Nivel 3 de `balance_druid`, luego cada spec DPS con datos (hunter, mage,
   retribution_paladin, shadow_priest, elemental/enhancement_shaman, y las
   que vayan saliendo del lote). Tanques y sanadores fuera (ver diseño).
3. Nivel 1/2 de talentos para las clases nuevas (Mago, Cazador...) si hace
   falta; el Nivel 3 lo cubre en la práctica para specs DPS.
4. **v0.10 lista de la compra**: hecha en código (commits 958ecef y 7966ebd,
   sin push). Orígenes: jefes (rank 3 o `instance_encounters`), criaturas de
   instancia, raros del mundo, cofres con algo BoP, vendedores y misiones
   (`Tools/generar_origenes.py`). Probada con lupa (arnés en el scratchpad de
   la sesión cf6ce5f6, `test_mejoras.py <Clase> <nivel> <facción>`); falta
   probarla en juego. Sin nombres de mazmorra: las DBC del cliente también
   están en inglés.
5. Documentación: `CLAUDE.md` roadmap (marcar v0.8, v0.9 y v0.10 hechas; está en
   `.gitignore`, no se commitea; editar con la skill `compact-docs-writer`,
   diff y aprobación del usuario) y lista de funciones de `README.md` /
   `README.en.md` (no mencionan v0.8/v0.9; v0.10 ya está).
6. Limitaciones conocidas (no bloquean): las gemas usan el peso del preset,
   así que con el golpe topado en el preset no se proponen gemas de golpe;
   los topes no cuentan golpe de talentos distintos de los del preset.
