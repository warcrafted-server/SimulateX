# Notas de investigación — Nivel 1/2 de talentos (v0.7)

Registro de qué se comprobó por clase/spec al buscar variantes de talentos
con más DPS/HPS/TPS que la `StandardTalents` de wowsims, para no repetir la
investigación. Usa `Tools/buscar_margen_talentos.py --class-id X --game-class
Y --talents "..."` para listar los candidatos de una build nueva.

## Druida

- **Feral (feral_druid)**: única variante real posible con esta build
  (`mas_potp`, mueve 2 puntos de un talento de maná a Protector de la manada
  + Tenacidad primigenia). Da el MISMO DPS hasta el decimal que la estándar:
  Protector de la manada solo afecta en forma de Oso (no de Gato) y
  Tenacidad primigenia no está implementada en wowsims. Conclusión: la build
  estándar ya tiene todos los talentos ofensivos de Gato al máximo, sin
  ningún punto suelto con efecto real en DPS.
- **Equilibrio (balance_druid)**: sin variante posible. Los 3 candidatos con
  margen (Resplandor lunar 1/3, Alcance de la Naturaleza 1/2, Frenesí de
  buhíco 1/3) están en filas cuyo total acumulado es justo el mínimo para
  desbloquear la fila siguiente: mover cualquiera de ellos rompe la cascada
  de puntos por fila (`required_points`) de una fila posterior. Haría falta
  rediseñar varias filas a la vez, no un simple intercambio — eso es trabajo
  de Nivel 3, no de Nivel 2.
- **Restauración (restoration_druid)**: sin variante posible. Los 4
  candidatos con margen (Alcance de la Naturaleza, Sutileza, Espíritu
  sosegado, Obsequio de la Naturaleza) no aparecen referenciados en ningún
  `.go` de `sim/druid/`: son mecánicas que wowsims no simula (rango de
  hechizo, amenaza de sanación, daño recibido en formas, ninguna afecta al
  HPS medido).
- **Guardián (feral_tank_druid)**: sin variante simple. Único candidato con
  margen es Furor (3/5, probabilidad de rabia extra al entrar en forma de
  Oso — sí tiene efecto real), pero está en la primera fila del árbol de
  Restauración de esta build y no hay ningún punto suelto en ese árbol para
  subirlo sin sacarlo de Feral, lo que rompería la cascada de Feral (que ya
  está también al óptimo, ver más arriba).

**Patrón repetido en las 4 specs de Druida**: la build estándar de wowsims ya
gasta sus puntos en un óptimo local dentro de su propio total. Encontrar algo
mejor exigiría permitir cambiar varias filas a la vez (más o menos puntos
totales, o redistribuciones de varias filas simultáneas), que es
precisamente el problema del Nivel 3 (búsqueda combinatoria), no del Nivel 2.
