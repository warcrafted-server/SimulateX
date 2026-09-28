# Comparador de equipo (v0.6) — PLAN

Addon WoW 3.3.5a (Interface 30300, cliente esES) en `Addon/SimulateX/`. Leer antes
`CLAUDE.md` del repo. El tooltip de v0.4 (una línea por spec con un único %) está aprobado
por el usuario; el comparador reutiliza exactamente su cálculo. La v0.5 del roadmap
(comparar contra lo equipado: anillos/abalorios contra el peor, 2M contra las dos manos,
flechas por debajo de 80) ya está hecha en `CompareAgainstEquipped` (paso 6 de v0.4): al
terminar esta fase, marcar v0.5 y v0.6 como hechas en el roadmap de `CLAUDE.md` (pasar
antes por `/compact-docs-writer`, regla de docs de gobierno).

## Decisiones del usuario (cerradas)

1. **Qué compara**: dos huecos, A y B. B vacío = A contra lo equipado (misma lógica que el
   tooltip: `CompareAgainstEquipped`). A y B de huecos incompatibles (casco vs anillo) →
   aviso "no van en el mismo hueco", sin cálculo.
2. **Qué enseña**: una línea por spec con el % de A frente a B (mismo formato y colores que
   el tooltip: `FormatPercent`/`GetPercentColor`, "(tu spec)", "≈ igual"), y debajo, para la
   spec activa: diferencia de cada estadística (A − B, verde/rojo) y **cuánto aporta cada
   una** al % de la spec activa, ordenado por |aporte|.
3. **Cómo se abre**: `/simulatex comparar`, botón en la hoja de personaje (C), botón de
   minimapa propio, objeto LibDataBroker para la barra de **wcdpanel**, y botón "Abrir
   SimulateX" en Interfaz > AddOns > SimulateX (panel existente, `SimulateXOptions.lua`).
4. **Memoria**: se vacía al cerrar.
5. **Aspecto**: mismo patrón que BotCommander (`/home/stark/Repos/addons/BotCommander/UI/
   AdvancedPanel.xml|.lua`, solo como referencia visual, no copiar código): fondo
   `Interface\DialogFrame\UI-DialogBox-Background` + borde `Interface\Tooltips\UI-Tooltip-Border`
   (tile 16), título `GameFontNormalLarge` centrado arriba, `UIPanelCloseButton`, tarjetas
   con `Interface\ChatFrame\ChatFrameBackground` (alpha 0.5, borde tooltip edgeSize 12),
   cabeceras de sección doradas (`GameFontNormal`) con línea bajo el texto, botones rojos
   `UIPanelButtonTemplate`. Columna izquierda de **pestañas con icono** (`Interface\Icons\…`,
   pestaña activa resaltada en dorado): de momento una sola, "Comparador"; la ventana es el
   "hub" de SimulateX donde irán Talentos (v0.7) y demás.
6. **Icono propio**: `Addon/SimulateX/Media/SimulateX.tga` (64×64, TGA 32 bits sin
   compresión, potencia de 2). Se usa en minimapa, LDB, botón del personaje y pestaña.

## Integración sin librerías de terceros

SimulateX es GPL-3.0 y no incluye librerías; no añadir LibStub/LDB/LibDBIcon al repo.
- **LDB**: `## OptionalDeps: wcdpanel` en el `.toc`. Si al cargar existe
  `LibStub and LibStub("LibDataBroker-1.1", true)` (lo aporta wcdpanel u otro addon), crear
  `NewDataObject("SimulateX", { type = "launcher", icon = <tga>, OnClick, OnTooltipShow })`.
  Clic izquierdo: abrir/cerrar la ventana; derecho: panel de opciones.
- **Minimapa**: botón propio (patrón de `BotCommander/UI/MinimapButton.lua`: radio 80,
  arrastre por ángulo guardado en `SimulateX_DB.minimapAngle`, borde
  `Interface\Minimap\MiniMap-TrackingBorder`, resaltado `UI-Minimap-ZoomButton-Highlight`).
  No crearlo si existe el global `WCDPanel` (wcdpanel ya enseña el objeto LDB; si no, su
  plugin MinimapButtons lo recogería y saldría duplicado). Casilla en el panel de opciones
  "Botón en el minimapa" (`SimulateX_DB.minimapHidden`).
- **Hoja de personaje**: botón pequeño (icono, 24 px) anclado en `PaperDollFrame`
  (verificar en `PaperDollFrame.xml` de FrameXML 3.3.5a un hueco libre que no tape nada;
  clonar `https://github.com/wowgaming/3.3.5-interface-files` en el scratchpad).

## Introducir objetos

- **Arrastrar**: cada hueco es un `Button` con `OnReceiveDrag`/`OnClick`: si
  `GetCursorInfo()` devuelve `"item", itemId, link`, poner el link y `ClearCursor()`.
- **Mayús+clic** con la ventana abierta: `hooksecurefunc("ChatEdit_InsertLink", fn)`; si la
  ventana está visible y no hay caja de chat activa (`ChatEdit_GetActiveWindow()` nil),
  meter el link en A si está vacío, si no en B. Verificado en FrameXML: `HandleModifiedItemClick`
  llama a `ChatEdit_InsertLink` (así lo usa también el buscador de la Casa de Subastas).
- Clic derecho en un hueco: vaciarlo. Tooltip del objeto al pasar por encima
  (`GameTooltip:SetHyperlink`, esto no rompe el rojo porque es el tooltip visible normal).
- Al cerrar (`OnHide`): vaciar A y B.

## Cálculo (reutilizar, no duplicar)

En `SimulateX.lua`, generalizar `EvaluateBuild`/`GetItemEvaluations` con un parámetro
opcional `againstLink`:
- Sin `againstLink`: comportamiento actual (tooltip, flechas).
- Con `againstLink`: ganancia = A − B con `ComparePair(A, idA, B, idB, build, weights,
  metric, hand)` (decisión 5 de v0.4: exacto solo si ambos tienen dato en `build.items`, si
  no EP para los dos). `hand` según el hueco de A (`GetDefaultHand`). Tanques: igual media
  1:1 con la vista de supervivencia (`GetSurvivalBuild`, métrica `"surv"`). % con
  `ComputePercent` (mismo denominador que el tooltip).
- Aporte por estadística (spec activa): para cada clave de `GetItemStatsFromData(A)` ∪
  `(B)`: `diff = sA − sB`; `aporte = peso(nivel) × diff / denominador × 100`, con el mismo
  denominador de `ComputePercent`. DPS de arma: `ScoreWeaponDps(A) − ScoreWeaponDps(B)`.
  Huecos de gema: `socketValue`/`metaSocketValue` × diferencia de huecos. Tanque: aporte =
  media de las dos vistas. Si el % de la spec viene de dato exacto (nivel 80, simulado),
  la suma de aportes (EP) no coincidirá: poner debajo "desglose estimado".
- Nombres de estadística en castellano: usar las globales del cliente `_G[key]` para las
  claves `ITEM_MOD_*_SHORT` (existen en 3.3.5a y están traducidas), con respaldo a la clave.
- Exponer lo necesario al fichero nuevo como tabla `SimulateX_API` (única global nueva
  además del frame); no convertir funciones existentes en globales.

## Ficheros

- Nuevo `Addon/SimulateX/UI/Comparador.lua` (ventana, pestañas, huecos, lista de specs,
  desglose) y `Addon/SimulateX/UI/Lanzadores.lua` (minimapa, LDB, botón del personaje).
  Añadirlos al `.toc` después de `SimulateX.lua` y avisar al usuario: **un fichero nuevo en
  el .toc exige reiniciar el cliente entero**, no basta `/reload`.
- `SimulateXOptions.lua`: botón "Abrir SimulateX" y casilla del minimapa.
- `SimulateX.lua`: `SimulateX_API`, generalización de `EvaluateBuild`, subcomando
  `/simulatex comparar`.
- Solo API 3.3.5a: nada de `C_*`, `C_Timer`, `SetShown`, `Mixin`. Referencia:
  `/home/stark/Repos/addons/BotCommander/docs/api_335a_references.md`.

## Pasos

1. Icono `Media/SimulateX.tga` (validar: 64×64, 32 bits, origen abajo-izquierda como
   espera el cliente) y vista previa PNG para el usuario.
2. `SimulateX_API` + `EvaluateBuild` con `againstLink` + desglose por estadística. Probar la
   lógica fuera del juego si es viable (Lua 5.1 con mocks mínimos de `UnitStat`,
   `GetItemInfo`, etc.) comparando con el tooltip: A contra B vacío debe dar el mismo %
   que el tooltip de A.
3. Ventana (`UI/Comparador.lua`) con el estilo descrito; huecos con arrastrar, mayús+clic y
   clic derecho; lista de specs; desglose.
4. Lanzadores (`UI/Lanzadores.lua`), comando y botón en opciones.
5. Validar sintaxis (luaparser en un venv del scratchpad; no hay `luac` en el servidor),
   actualizar README/README.en/CHANGELOG, `.toc` a 0.6.0, pedir permiso para commit + push
   (este commit NO está cubierto por la autorización de commits por clase), y pedir prueba
   en juego.

## A verificar en juego

- Arrastrar y mayús+clic desde bolsas, banco, botín, enlaces del chat.
- El rojo nativo de "no usable" se conserva en los tooltips con la ventana abierta.
- Icono en minimapa, en wcdpanel (con y sin su plugin LDB activo) y en la hoja de personaje.
- A contra B vacío = mismo % que el tooltip de A.

## Modelo

Pasos 1-5: Sonnet, esfuerzo alto (UI y lógica sutil). Las consolidaciones por clase de v0.4
que vayan saliendo en paralelo: Sonnet, esfuerzo medio.
