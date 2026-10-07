*Read this in other languages: [English](README.en.md).*

# SimulateX

**SimulateX** es un asistente avanzado, vistoso y moderno integrado directamente en el juego para **World of Warcraft: Wrath of the Lich King (3.3.5a, Build 12340)** con soporte estricto para el cliente en **Español de España (esES)**. 

El proyecto está diseñado para transformar por completo la forma en que los jugadores evalúan su equipamiento, ofreciendo métricas de rendimiento reales y precisas en lugar de cálculos estáticos abstractos o aproximados.

## Características Principales

*   **Datos Reales por Especialización y Nivel:** Los pesos de cada estadística salen de simulaciones de combate reales por especialización (motor WowSims), con el escalado por nivel calculado desde las tablas del propio servidor: no son aproximaciones genéricas.
*   **Indicadores de Mejora en Tooltips:** Visualiza de forma inmediata el rendimiento real que ganarás o perderás al pasar el ratolí sobre cualquier pieza de equipo (ej. `Feral (tu spec) +3.2 %`), con una línea por cada especialización de tu clase.
*   **Comparador Visual de Equipamiento:** Pon dos objetos (arrastrando o con Mayús+clic) y compáralos entre sí, o contra lo que llevas puesto, con el desglose de qué estadística marca la diferencia. Cada objeto se ve con sus estadísticas, nivel, tipo y requisitos; los anillos y abalorios se comparan con los dos que llevas y te dice cuál cambiar. La misma ventana tiene una pestaña de Configuración. Accesible desde `/simulatex comparar`, un botón en la hoja de personaje, el minimapa o la barra de **wcdpanel**.
*   **Lista de la Compra (pestaña Mejoras):** Para cada hueco, las mejores mejoras para tu especialización y dónde conseguirlas: jefe y dificultad, cofre, criaturas de mazmorra, raros del mundo, vendedor (con su coste en oro, emblemas u honor) o misión, con la probabilidad de botín. Funciona también mientras subes de nivel y con objetos que nunca has visto. Filtros en la configuración: mejoras por hueco, heroicos, bandas de 25, vendedores, misiones, facción y probabilidad mínima.
*   **Talentos y glifos:** La pestaña Talentos muestra los tres árboles, variantes simuladas y sus resultados, incluido el Nivel 3, junto con los glifos sublimes y menores de cada build.
*   **Valoración más precisa:** A nivel 80, golpe, pericia y penetración de armadura dejan de aportar al superar sus topes. Se valoran las gemas ideales y la bonificación de ranura, y el tooltip indica si una pieza es BiS para una fase.
*   **Bonus de conjunto:** Un aviso señala si un cambio activa o hace perder un bonus de conjunto.
*   **Mejoras con más contexto:** Los orígenes muestran su zona o instancia; también se indican profesiones y bolsas de recompensa. La lista filtra por tipo de armadura.
*   **Vendedor:** Puede vender automáticamente objetos grises según una lista blanca, reparar automáticamente y mostrar el precio de venta en el tooltip; cada opción se puede configurar.
*   **Configuración:** El panel tiene desplazamiento para acceder a todas las opciones, y la ventana del comparador incluye una pestaña Configuración.
*   **Diseño Vanguardista:** Interfaz fluida y reactiva, alejada de la estética tosca y obsoleta de los addons clásicos.

## Comandos

*   `/simulatex`: vuelve a la detección automática de build.
*   `/simulatex comparar`: abre o cierra el comparador de equipo.
*   `/simulatex debug [enlace]`: muestra datos de depuración del objeto enlazado; sin enlace, indica que pegues uno.
*   `/simulatex nivel <n>`: fuerza un nivel durante la sesión; sin un número válido, desactiva el nivel forzado.
*   `/simulatex <build>`: fuerza la build indicada; `/simulatex` sin argumentos restaura la detección automática.
*   `/simulatexconfig`: abre las opciones de SimulateX.

Proyecto: [portal.warcrafted.com](https://portal.warcrafted.com/).

## Estructura del Repositorio

Este repositorio contiene exclusivamente el código fuente del Addon oficial para el cliente de juego:

```text
Addon/
├── SimulateX/              # Addon principal: lógica, UI y datos comunes (todas las clases)
│   ├── SimulateX.toc
│   ├── SimulateX.lua
│   ├── SimulateX_DB.lua
│   ├── Data/                # Solo datos comunes (niveles, tipos y estadísticas de objeto)
│   └── UI/
├── SimulateX_<Clase>/       # Un sub-addon por clase (LoadOnDemand): datos de
│                             # simulación y talentos de esa clase. SimulateX
│                             # carga solo el de tu clase al iniciar sesión.
└── SimulateX_Origenes/      # Dónde se consigue cada objeto (LoadOnDemand): se
                              # carga al abrir la pestaña Mejoras.
```

*Nota: Todas las herramientas automatizadas de extracción de datos, motores de cálculo externos y scripts de sincronización se ejecutan de forma local y privada para mantener el repositorio limpio y enfocado exclusivamente en el rendimiento in-game.*

## Instalación

1. Descarga el contenido de la carpeta `Addon/`.
2. Copia **todas** las carpetas que empiezan por `SimulateX` (`SimulateX`, `SimulateX_Origenes` y cada `SimulateX_<Clase>`) dentro de `World of Warcraft/Interface/AddOns/`. El addon solo carga en memoria los datos de tu clase; los sub-addons de las demás clases se quedan inactivos aunque estén instalados.
3. Asegúrate de tener los addons activos en la pantalla de selección de personaje e inicia el juego.

## Créditos y Licencia

Las estadísticas de rendimiento (DPS/HPS) que utiliza este addon se generan mediante
simulaciones offline realizadas con el motor de código abierto
[**WowSims**](https://github.com/wowsims/wotlk) (licencia MIT). SimulateX no
redistribuye su código fuente; únicamente utiliza sus resultados de simulación
como fuente de datos para el addon.

Este proyecto se distribuye bajo la licencia **GPL-3.0**. Consulta el archivo
[LICENSE](LICENSE) para más detalles.
