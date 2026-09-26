# Changelog - SimulateX

Todos los cambios notables de este proyecto serán documentados en este archivo.

## v0.2.0 - 2026-09-27
### Añadido
- Tooltip multi-spec: en vez de una sola línea, muestra el delta de cada sub-spec real de la clase (ej. Beast Mastery/Marksman/Survival en Cazador), con puntos y porcentaje de cambio (`%+.1f%%`), marcando con `*` la spec activa detectada por talentos.
### Pendiente (siguiente parte de v0.2)
- Icono de flecha (verde = spec activa, naranja = otra spec de la clase) sobre el icono del objeto en bolsas, botín y recompensa de misión.

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
