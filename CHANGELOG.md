# Changelog - SimulateX

Todos los cambios notables de este proyecto serán documentados en este archivo.

## v0.3.0 - 2026-09-27
### Añadido
- Panel de configuración en Interfaz > AddOns (`/simulatexconfig` como alternativa): activar/desactivar el modo estimado de nivel 1-79, y elegir qué sub-especializaciones de la clase se muestran en el tooltip.

## Sin publicar
### Cambiado
- Flecha de mejora más visible: textura `Interface\Buttons\Arrow-Up-Up` desaturada y teñida (verde 20 px para la spec activa, naranja 15 px para otra spec), con silueta negra de contorno y por encima del borde del botón.
### Corregido
- El DPS de arma no contaba en la puntuación EP: dos armas con DPS muy distinto salían "≈ igual". Ahora se usan los pesos de DPS de arma de wowsims (`pseudoStats`: mano principal, mano izquierda o a distancia según el hueco). En Feral el DPS de arma solo aporta PA feral, que el servidor calcula como `int(dps × 14) − 767` sin bajar de 0, así que por debajo de ~54.8 DPS el arma no suma nada.
- La extracción de objetos de nivel 1-79 (`extraer_objetos_bd.py`) excluía por error todos los objetos con `RequiredLevel = 0` en `item_template` (frecuente en objetos de misión/mundo antiguos, ej. Bastón del purificador, Cinturón acuario). Regenerados los datos de Druida: 13569 objetos puntuados (antes 7963).
- La generación de simulación de nivel 80 fallaba para holy_paladin y restoration_druid: `generar_extractores_go.py` dejaba variables sin usar en el código Go generado cuando la spec no usa rotación por APL, y Go no compila con eso. No era una limitación de wowsims (como se documentó por error antes), sino un bug propio del generador.

## v0.2.1 - 2026-09-27
### Añadido
- Icono overlay de mejora (flecha verde = mejora en la spec activa, naranja = mejora en otra sub-spec de la clase) sobre el icono del objeto en bolsas, botín y recompensa de misión.
### Corregido
- Se perdía el coloreado nativo del juego (ej. "Malla" en rojo cuando la clase no puede vestirla) en la ventana de recompensa de misión: `tooltip:GetItem()` es conocido por fallar en tooltips poblados con `SetQuestItem`/`SetQuestLogItem`; ahora se detecta ese origen y se usa la API de misión en su lugar.

## v0.2.0 - 2026-09-27
### Añadido
- Tooltip multi-spec: en vez de una sola línea, muestra el delta de cada sub-spec real de la clase (ej. Beast Mastery/Marksman/Survival en Cazador), con puntos y porcentaje de cambio (`%+.1f%%`), marcando con `*` la spec activa detectada por talentos.

## - 2026-09-26
### Añadido
- Esqueleto inicial del addon en `Addon/SimulateX/` (`SimulateX.toc`, `SimulateX.lua`, `SimulateX_DB.lua`).
- Primer script de extracción `Tools/extraer_objetos.py` (pendiente de implementar contra `db.warcrafted.com`).
- Inicialización del repositorio git local.
- Creación de la estructura base del repositorio del proyecto.
- Configuración del entorno de desarrollo guiado por Inteligencia Artificial mediante `CLAUDE.md`.
- Inclusión de filtros estrictos en `.gitignore` para proteger las herramientas de extracción de datos privadas.
- Documentación inicial del proyecto en castellano (`README.md`) e inglés (`README.en.md`).
- Establecidas las bases para la integración de datos locales procedentes de la base de datos de `db.warcrafted.com`.
- Pipeline completo de simulación de nivel 80 con el motor `wowsims/wotlk`: extracción de builds de referencia (`generar_builds.py`, `emparejar_builds.py`), generación de `RaidSimRequest` por spec (`generar_extractores_go.py`), procesado de objetos extraídos (`procesar_objetos.py`) y orquestador de simulación con cálculo de delta por objeto (`simular_builds.py`).
- Licencia del proyecto fijada en GPL-3.0 (`LICENSE`); añadida atribución obligatoria a wowsims (licencia MIT) en `README.md`/`README.en.md`, ya que sus resultados de simulación son la fuente de las estadísticas del addon.
- Lógica del addon (`SimulateX.lua`): hook de tooltip, detección automática de build por talentos activos (con opción de forzarla manualmente vía `/simulatex`), y comparación estimada para niveles 1-79 contra el equipo actual del jugador.
- Primeros datos reales generados para Druida Feral: 5 builds de nivel 80 simuladas con wowsims (`SimulateX_Data_Druid.lua`) y 7963 objetos de nivel 1-79 puntuados por prioridad de estadística, extraídos de `acore_world` (acceso de solo lectura).
- Corregido un fallo de precisión: los objetos de armadura (tela/cuero/malla/placas) sin restricción de clase listada explícitamente en el tooltip se consideraban compatibles con cualquier clase; ahora se infiere del subtipo de armadura.
