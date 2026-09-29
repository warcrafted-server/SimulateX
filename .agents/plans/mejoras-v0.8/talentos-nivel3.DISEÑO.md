# SimulateX — Talentos Nivel 3 (búsqueda de la mejor distribución)

Bloque 5 de `mejoras-v0.8.PLAN.md`. Repo: `/home/stark/Repos/addons/SimulateX`.
Contexto previo: `Tools/NOTAS_TALENTOS_NIVEL2.md` (mover 1-2 puntos sueltos
no mejora: el margen está en talentos sin efecto simulado o lo bloquea la
cascada de puntos por fila).

## Hechos verificados (29-09-2026)

- **Cadena ↔ motor, exacto**: `core.FillTalentsProto` asigna el dígito i del
  árbol t al campo proto nº `offset_t + i + 1` de `<Clase>Talents`
  (`proto/<clase>.proto`). El orden coincide con el de la DBC
  (`tree_talents` de `validar_talentos.py`: fila, columna); comprobado en
  Druida, 85/85 campos. Campo Go = CamelCase del nombre proto.
- **Talento "vivo"**: su campo aparece como `Talents.<Campo>` en
  `sim/<clase>/**/*.go` (sin `*_test.go` ni `zzz_*`). El resto no cambia la
  simulación: solo sirve de relleno para la regla de 5 puntos por fila.
- **Coste**: cambiar `talentsString` en el RaidSimRequest base y lanzar
  `wowsimcli sim` directamente: ~1,5 s a 1000 iteraciones (sin `go test`).
  Semilla fija: mismo resultado en cada ejecución (15962,2 Feral P4).
- **Máquina**: 4 núcleos compartidos con los reinos de WoW (carga ~9 con el
  lote en marcha). Un solo proceso de simulación, `nice -n 19`.

## Algoritmo (`Tools/talentos_nivel3.py --spec <spec>`)

1. Build de referencia: `simular_talentos.pick_reference_build` (fase más
   alta con datos). Petición base una vez con `run_go_extractor`.
2. Punto de partida: la mejor entre el `talent_set` del preset y las
   variantes de `Data/talentos/<spec>.json`.
3. Estado = rangos de los talentos vivos. `realizar(vivos)` construye la
   cadena completa: prerrequisitos muertos forzados, relleno muerto desde la
   fila 0 hasta cumplir 5 puntos por fila, sobrante a talentos muertos
   (primero los que ya tenía el estándar: conservan su utilidad), total 71.
   Inválido si no cabe. Toda cadena pasa `validar_talentos.validate_build`.
4. Vecindario: mover 1 punto de a→b, mover todo el rango de a a b, +1 a un
   vivo (quitando relleno), −1 a un vivo (a relleno).
5. Por ronda: simular todos los vecinos válidos no vistos (1000 it.); el
   mejor, si supera al actual en > 0,1 %, se confirma a 5000 it. contra el
   actual (misma semilla) y se acepta si mantiene > 0,05 %. Sin mejora
   confirmada: fin.
6. Reanudable: `Data/talentos_n3/<spec>.json` guarda caché cadena→métrica,
   actual e historial tras cada simulación (reinicio de las 04:00).
7. Salida: si hay mejora confirmada, variante `nivel3` en
   `Data/talentos/<spec>.json`; `generar_db_talentos.py` la lleva al addon
   (etiqueta "Óptima (búsqueda)"). Si no, se anota en
   `NOTAS_TALENTOS_NIVEL2.md`.

## Alcance

- Solo specs DPS con pesos simulados. Tanques fuera (optimizar amenaza
  quitaría talentos de supervivencia) y sanadores fuera (pesos preset, sin
  simulación de HPS).
- Druida primero: `feral_druid`, `balance_druid`. Luego cada clase DPS en
  cuanto termine su simulación de equipo.
- Métrica: la del rol (`dps`).
