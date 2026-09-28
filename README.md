*Read this in other languages: [English](README.en.md).*

# SimulateX

**SimulateX** es un asistente avanzado, vistoso y moderno integrado directamente en el juego para **World of Warcraft: Wrath of the Lich King (3.3.5a, Build 12340)** con soporte estricto para el cliente en **Español de España (esES)**. 

El proyecto está diseñado para transformar por completo la forma en que los jugadores evalúan su equipamiento, ofreciendo métricas de rendimiento reales y precisas en lugar de cálculos estáticos abstractos o aproximados.

## Características Principales

*   **Datos Reales por Especialización y Nivel:** Los pesos de cada estadística salen de simulaciones de combate reales por especialización (motor WowSims), con el escalado por nivel calculado desde las tablas del propio servidor: no son aproximaciones genéricas.
*   **Indicadores de Mejora en Tooltips:** Visualiza de forma inmediata el rendimiento real que ganarás o perderás al pasar el ratolí sobre cualquier pieza de equipo (ej. `Feral (tu spec) +3.2 %`), con una línea por cada especialización de tu clase.
*   **Comparador Visual de Equipamiento:** Pon dos objetos (arrastrando o con Mayús+clic) y compáralos entre sí, o contra lo que llevas puesto, con el desglose de qué estadística marca la diferencia. Accesible desde `/simulatex comparar`, un botón en la hoja de personaje, el minimapa o la barra de **wcdpanel**.
*   **Asistente de Búsqueda (Lista de la Compra):** Una guía visual que te indica de forma ordenada qué objetos necesitas buscar para mejorar tu personaje y qué jefes de banda, mazmorras o intendentes los proporcionan.
*   **Diseño Vanguardista:** Interfaz fluida y reactiva, alejada de la estética tosca y obsoleta de los addons clásicos.

## Estructura del Repositorio

Este repositorio contiene exclusivamente el código fuente del Addon oficial para el cliente de juego:

```text
Addon/
├── SimulateX.toc        # Índice y configuración nativa del juego
├── SimulateX.lua        # Lògica principal de la interfaz y tooltips
├── SimulateX_DB.lua     # Base de datos local optimizada de rendimiento
└── UI/                  # Diseños de interfaz, marcos y elementos visuales
```

*Nota: Todas las herramientas automatizadas de extracción de datos, motores de cálculo externos y scripts de sincronización se ejecutan de forma local y privada para mantener el repositorio limpio y enfocado exclusivamente en el rendimiento in-game.*

## Instalación

1. Descarga el contenido de la carpeta `Addon/`.
2. Copia la carpeta interna `SimulateX` dentro del directorio de tu juego: `World of Warcraft/Interface/AddOns/`.
3. Asegúrate de tener los addons activos en la pantalla de selección de personaje e inicia el juego.

## Créditos y Licencia

Las estadísticas de rendimiento (DPS/HPS) que utiliza este addon se generan mediante
simulaciones offline realizadas con el motor de código abierto
[**WowSims**](https://github.com/wowsims/wotlk) (licencia MIT). SimulateX no
redistribuye su código fuente; únicamente utiliza sus resultados de simulación
como fuente de datos para el addon.

Este proyecto se distribuye bajo la licencia **GPL-3.0**. Consulta el archivo
[LICENSE](LICENSE) para más detalles.
