*Read this in other languages: [English](README.en.md).*

# SimulateX

**SimulateX** es un asistente avanzado, vistoso y moderno integrado directamente en el juego para **World of Warcraft: Wrath of the Lich King (3.3.5a, Build 12340)** con soporte estricto para el cliente en **Español de España (esES)**. 

El proyecto está diseñado para transformar por completo la forma en que los jugadores evalúan su equipamiento, ofreciendo métricas de rendimiento reales y precisas en lugar de cálculos estáticos abstractos o aproximados.

## Características Principales

*   **Indicadores de Mejora en Tooltips:** Visualiza de forma inmediata el rendimiento real que ganarás o perderás al pasar el ratolí sobre cualquier pieza de equipo (ej. `+145 DPS`).
*   **Comparador Visual de Equipamiento:** Una interfaz moderna, limpia e interactiva para contrastar piezas de equipamiento en paralelo, analizando el impacto global en tu personaje.
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
