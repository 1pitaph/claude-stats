<p align="center">
  <img src="docs/assets/claude-stats-icon.png" alt="Claude Stats app icon" width="128" height="128">
</p>

<h1 align="center">Claude Stats</h1>

<p align="center">
  Estadísticas nativas en la barra de menús de macOS, paneles de control, sincronización con compañero iOS, Notch Island, terminal y depuración de red para el trabajo de codificación con IA.
</p> 

<p align="center"> 
  <a href="#features">Características</a> ·
  <a href="#screens">Capturas</a> · 
  <a href="#install">Instalación</a> · 
  <a href="#ios-companion">Compañero iOS</a> · 
  <a href="#privacy--data">Privacidad y Datos</a> · 
  <a href="#build-from-source">Compilar desde el Código Fuente</a> · 
  <a href="#open-source--third-party-modules">Código Abierto</a> · 
  <a href="#contributing">Contribuir</a> · 
  <a href="README.zh-Hans.md">简体中文</a> 
</p> 

Claude Stats es una aplicación nativa de macOS de código abierto para personas que trabajan con herramientas de codificación de IA todo el día. Se ejecuta desde la barra de menús, lee los datos de uso y actividad local, y los convierte en respuestas rápidas sobre sesiones, tokens, costos, límites, actividad del repositorio, estado del sistema local, estado del proveedor y contexto de depuración. 

La aplicación comenzó como una versión enfocada en macOS del proyecto de código abierto [Claude Statistics](https://github.com/sj719045032/claude-statistics). Ahora incluye una base multi-proveedor, un espacio de trabajo de panel de control (dashboard), sincronización via CloudKit para un compañero en iOS, tablas de clasificación públicas opcionales, una superficie de terminal impulsada por Warp, un Notch Island respaldado por Atoll y un depurador de red respaldado por Rockxy, manteniendo el nombre principal del producto como **Claude Stats**. 

Claude Stats se distribuye en dos variantes de macOS: la aplicación completa y **Claude Stats Lite**. La versión Lite conserva las estadísticas principales de la barra de menús, vistas de Git, informes diarios, Gantt, tablas de clasificación y sincronización de instantáneas de iCloud, omitiendo integraciones más pesadas como Diccionario, Linux.do, Warp, Config, Ops, Network, Local AI, Memory y Notch Island. Ambas aplicaciones utilizan identificadores de paquete y feeds de actualización de Sparkle separados, por lo que pueden instalarse lado a lado. 

## Características 

- Estadísticas de uso nativas en la barra de menús para sesiones de codificación con IA, tokens, costo estimado, lecturas de caché, actividad reciente, cambio de proveedor, actualización, exportación para compartir, actualizaciones, configuración y salida rápida. 
- Soporte de proveedores para logs de sesión de [Claude Code](https://docs.anthropic.com/en/docs/claude-code) y OpenAI Codex; Gemini, Kimi y MiniMax son reconocidos en la interfaz de usuario, mientras que sus analizadores de sesión en disco están en desarrollo. 
- Vistas de Dashboard y Uso con tarjetas de resumen, desgloses de modelos, composición de tokens, tasa de acierto de caché, modos de costo, navegación diaria, gráficos, tarjetas de estado de Claude/OpenAI, mapas de calor de GitHub y superposición de IA/GitHub. 
- Vistas de límites de uso y pronósticos para los proveedores compatibles, incluyendo flujos de puente de Claude Desktop y datos de estado de OpenAI/Codex. 
- Sesiones, análisis de transcripciones y herramientas de diccionario de términos técnicos para comprender las conversaciones locales de codificación con IA. 
- Espacios de trabajo de Informe Diario y Gantt que resumen los proyectos activos de IA por día y visualizan bloques de trabajo sincronizados, proveedores, intensidad de tokens, superposición de enfoque, límites y commits. 
- Vistas de actividad de Git y GitHub, incluyendo resúmenes de repositorio, diffs, vistas de grafo/detalle, herramientas de Git integradas opcionales para versiones de lanzamiento y asistencia en mensajes de commit. 
- Un compañero de iOS de solo lectura para iPhone y iPad que lee instantáneas privadas de iCloud/CloudKit publicadas por la aplicación de Mac. 
- Tablas de clasificación de CloudKit para puntuaciones agregadas opcionales que preservan la privacidad, apodos públicos, avatares Beam, texto de estado e historial de tendencias. 
- Espacios de trabajo de Monitor del Sistema y Ops para CPU, memoria, disco, red, energía, térmica, puertos de escucha, paquetes de Homebrew, servicios de inicio y verificaciones del entorno de desarrollo. 
- Espacios de trabajo de Config, Skills, LLM, Local AI y Memory para configuración de proveedores, habilidades locales/plugins, ajustes de modelo a nivel de aplicación, gestión de modelos locales y el sidecar opcional de memoria de Code Agent. 
- Integración nativa de lector de Linux.do con inicio de sesión asistido por navegador, listas de temas, lectura detallada de temas, caché y notificaciones. 
- Un espacio de trabajo de terminal embebido impulsado por Warp para compilaciones completas, con ajustes de tiempo de ejecución y apariencia. 
- Una superficie de Notch Island respaldada por Atoll con módulos opcionales para multimedia, estadísticas, temporizador, portapapeles, selector de color, calendario, estante, privacidad, grabación, enfoque, batería, Bluetooth, descargas, OSD, widgets de bloqueo, puente de extensiones, asistente de pantalla y superficies de terminal. 
- Un depurador de red respaldado por Rockxy con captura de tráfico, metadatos de HTTP/HTTPS/WebSocket/túnel, filtros, inspectores, repetición, flujos de intercepción/automatización, controles de proxy, encadenamiento ascendente, certificados, reglas, plugins y puntos de interrupción (breakpoints). 
- Una compilación Lite para usuarios que desean las estadísticas de la barra de menús, Git, informes diarios, Gantt, tablas de clasificación y sincronización con el compañero de iCloud sin las integraciones más pesadas. 
- Actualizaciones automáticas basadas en Sparkle para ambas variantes de macOS, con feeds separados para Full y Lite. 

## Capturas 

Las capturas de pantalla y demos en GIF se encuentran en [`docs/assets/screens`](docs/assets/screens), agrupadas aquí por área del producto. 

<details open>
<summary><strong>Extra de la barra de menús</strong></summary> 

<table>
  <tr> 
    <th align="left" width="33%">Panel de Uso</th> 
    <th align="left" width="33%">Panel de Actividad</th> 
    <th align="left" width="33%">Panel de Git</th> 
  </tr> 
  <tr> 
    <td valign="top" width="33%"> 
      <img src="docs/assets/screens/menubar-usage.gif" alt="Menu-bar extra usage panel" width="100%"> 
    </td> 
    <td valign="top" width="33%"> 
      <img src="docs/assets/screens/menubar-activity.gif" alt="Menu-bar extra activity panel" width="100%"> 
    </td> 
    <td valign="top" width="33%"> 
      <img src="docs/assets/screens/menubar-git.gif" alt="Menu-bar extra Git panel" width="100%"> 
    </td> 
  </tr> 
</table> 

<details>
<summary><strong>Exportación de estadísticas para compartir</strong></summary> 

<img src="docs/assets/screens/menubar-share-stats.gif" alt="Menu-bar share stats export flow"> 

</details> 

</details> 

<details open>
<summary><strong>Estadísticas y actividad</strong></summary> 

<p><strong>Vista general del Dashboard</strong></p> 
<img src="docs/assets/screens/dashboard-overview.png" alt="Claude Stats dashboard overview"> 

<p><strong>Vista general de Sesiones</strong></p> 
<img src="docs/assets/screens/sessions-overview.png" alt="Claude session statistics overview"> 

<p><strong>Uso de tokens y límites</strong></p> 
<img src="docs/assets/screens/usage-token-limits.png" alt="Token usage and usage limits"> 

<p><strong>Línea de tiempo de enfoque asistida por IA</strong></p> 
<img src="docs/assets/screens/activity-focus-timeline.png" alt="AI-assisted focus timeline"> 

<p><strong>Tablas de clasificación semanales</strong></p> 
<img src="docs/assets/screens/leaderboards-weekly.png" alt="Weekly usage leaderboard"> 

</details> 

<details>
<summary><strong>Comunidad y conocimiento local</strong></summary> 

<p><strong>Lector nativo de LinuxDo</strong></p> 
<img src="docs/assets/screens/linuxdo-reader.png" alt="LinuxDo native topic reader"> 

<p><strong>Navegador de planes y configuración</strong></p> 
<img src="docs/assets/screens/configs-plans-browser.png" alt="Plans and config browser"> 

<p><strong>Librería de habilidades (Skills)</strong></p> 
<img src="docs/assets/screens/skills-library.png" alt="Local and plugin skills library"> 

</details> 

<details>
<summary><strong>Herramientas de desarrollo</strong></summary> 

<p><strong>Cambiador de proveedor de API</strong></p> 
<img src="docs/assets/screens/provider-switcher.png" alt="API provider switcher"> 

<p><strong>Espacio de trabajo de repositorio</strong></p> 
<img src="docs/assets/screens/git-repository-workspace.png" alt="Git repository workspace"> 

</details> 

<details> 
<summary><strong>Ops, red y terminal</strong></summary> 

<p><strong>Puertos de escucha</strong></p> 
<img src="docs/assets/screens/ops-listening-ports.png" alt="Listening ports inspector"> 

<p><strong>Paquetes de Homebrew</strong></p> 
<img src="docs/assets/screens/ops-homebrew-packages.png" alt="Homebrew package inspector"> 

<p><strong>Verificación del entorno de desarrollo</strong></p> 
<img src="docs/assets/screens/ops-environment-check.png" alt="Developer environment check"> 

<p><strong>Tráfico de red</strong></p> 
<img src="docs/assets/screens/network-traffic.png" alt="Network traffic debugger"> 

<p><strong>Terminal embebida</strong></p> 
<img src="docs/assets/screens/terminal-session.png" alt="Embedded terminal session"> 

</details> 

<details> 
<summary><strong>Configuración</strong></summary> 

<p><strong>Activación de funciones (Toggles)</strong></p> 
<img src="docs/assets/screens/settings-features.png" alt="Feature settings"> 

<p><strong>Apariencia de la terminal</strong></p> 
<img src="docs/assets/screens/settings-terminal-appearance.png" alt="Terminal appearance settings"> 

</details> 

El compañero de iOS aún no se muestra en el conjunto de capturas actual. Está documentado más abajo y puede ejecutarse desde el proyecto de Xcode generado. 

## Instalación 

Las compilaciones empaquetadas de macOS se publican desde este repositorio: 

- [Último lanzamiento](https://github.com/1pitaph/claude-stats/releases/latest) 
- [Todos los lanzamientos de GitHub](https://github.com/1pitaph/claude-stats/releases) 
- [Appcast de Sparkle](https://1pitaph.github.io/claude-stats/appcast.xml) 
- [Appcast de Sparkle Lite](https://1pitaph.github.io/claude-stats/appcast-lite.xml) 

Cada lanzamiento etiquetado publica ambas variantes de la aplicación de macOS: 

| Variante | Recurso de lanzamiento | Feed de Sparkle | Notas |
| --- | --- | --- | --- | 
| Claude Stats | `ClaudeStats-<version>.dmg` | `appcast.xml` | App completa con Diccionario, Linux.do, Warp, Config, Ops, Network, Local AI, Memory y Notch Island. | 
| Claude Stats Lite | `ClaudeStatsLite-<version>.dmg` | `appcast-lite.xml` | App Lite con estadísticas básicas, Git, informes diarios, Gantt, tablas de clasificación y sincronización con compañero de iCloud. | 

El empaquetado de los lanzamientos admite compilaciones firmadas/notarizadas y compilaciones de respaldo no firmadas. Si utiliza una compilación no firmada, macOS Gatekeeper puede requerir abrirla haciendo clic derecho y luego seleccionando **Abrir**. 

Las aplicaciones Full y Lite se actualizan independientemente a través de Sparkle. Un lanzamiento puede contener ambos paquetes incluso cuando un cambio de función solo afecte a una variante, ya que el código compartido, los metadatos de versión, las correcciones de seguridad y las notas de lanzamiento se mueven juntos. Ajustes > Acerca de incluye una entrada de descarga para la otra variante, pero cambiar de variante es una elección de instalación y no una conversión de Sparkle en el lugar. 

### Compatibilidad 

Los lanzamientos empaquetados actuales de macOS son compatibles con Macs con Apple Silicon que ejecuten macOS 15 o posterior. El paquete de la aplicación aún mantiene un objetivo de despliegue de macOS 14 para el shell principal, pero los lanzamientos empaquetados incluyen componentes de tiempo de ejecución cuyo suelo práctico es macOS 15. 

Las Macs con Intel no son compatibles con los lanzamientos actuales. La última compilación universal pública con fragmentos `x86_64` y `arm64` fue la [v1.3.9](https://github.com/1pitaph/claude-stats/releases/tag/v1.3.9); los lanzamientos a partir de la v1.3.11 distribuyen un ejecutable principal `arm64`. 

El objetivo del compañero de iOS es compatible con iOS 17 o posterior en iPhone y iPad. Actualmente se compila desde el código fuente a través del esquema de Xcode `ClaudeStats iOS` en lugar de distribuirse como un paquete público de App Store/TestFlight desde este repositorio. 

## Compañero iOS 

Claude Stats incluye una aplicación compañera de iOS de solo lectura para consultar las estadísticas agregadas del lado de Mac en iPhone o iPad. No escanea archivos de iOS ni recopila actividad de codificación en el dispositivo. En su lugar, Claude Stats o Claude Stats Lite en el Mac publica un registro privado de CloudKit que contiene el `StatsSnapshot` codificado más reciente, y la aplicación de iOS lee ese registro de la misma cuenta de iCloud. 

La aplicación de iOS tiene actualmente tres pestañas: 

- **Dashboard**: fecha sincronizada, estado de la cuenta de iCloud, tokens, costo, sesiones, proyectos, tiempo de IA, días activos, estado del proveedor, tendencia de uso, mezcla de tokens, proveedores y límites de uso. 
- **Stats**: uso del período, actividad diaria, resúmenes de uso, modelos principales e informes diarios. 
- **Tool**: filas de Informe Diario, línea de tiempo de Gantt sincronizada y vista general de la actividad de Git. 

El estado del proveedor en iOS admite resúmenes de OpenAI y Claude, enlaces a páginas de estado, preferencias de filas de estado visibles, tiras de tiempo de actividad de 90 días, incidentes y mensajes de caché obsoleta. 

Para publicar datos reales, abra Ajustes > iCloud Sync en una compilación de Mac que tenga el permiso (entitlement) de CloudKit. Las versiones firmadas pueden hacer esto, y las compilaciones de desarrollo deben usar los esquemas `ClaudeStats CloudKit` o `ClaudeStats Lite CloudKit`. La compilación de Debug de macOS no firmada regular aún puede ejecutar la aplicación, pero no puede publicar una instantánea real de CloudKit sin el permiso correspondiente. 

## Privacidad y Datos 

Claude Stats prioriza lo local. Las estadísticas de uso principales se leen de los datos de herramientas locales como `~/.claude/projects/` y `~/.codex/sessions/`; las funciones opcionales de actividad, GitHub, monitoreo del sistema, límite de escritorio, Notch Island, terminal, red y memoria solo se ejecutan cuando están habilitadas o configuradas. Algunas funciones pueden solicitar permisos de macOS como Acceso Total al Disco, Accesibilidad, Grabación de Pantalla, acceso al Keychain, iCloud o aprobación de herramientas auxiliares. 

La sincronización de CloudKit para el compañero de iOS escribe en la base de datos privada de CloudKit del usuario. Sube tokens agregados, costos, recuentos de sesiones, resúmenes diarios, instantáneas de límites de uso, intervalos de actividad, totales del tablero, resúmenes de estado, filas de resumen de Git, campos de resumen de tablas de clasificación y etiquetas de proyecto anonimizadas como `Proyecto 1`. No sube prompts, texto de transcripciones, nombres de archivos, rutas de proyectos reales ni logs de sesión completos. 

Las tablas de clasificación de CloudKit son separadas y opcionales. Publican puntuaciones públicas agregadas más metadatos de perfil como el apodo, el avatar de Beam generado y el texto de estado. El flujo de la tabla de clasificación está diseñado para no publicar prompts, contenido de transcripciones, nombres de archivos, rutas reales, títulos de sesiones, nombres de modelos ni logs completos. 

Los secretos y cuentas se almacenan localmente a través de los almacenes seguros configurados de la aplicación, como Keychain para las credenciales. Las preferencias residen en el almacenamiento de la aplicación, y las cachés/índices residen bajo las ubicaciones de Application Support o Caches de la aplicación. 

Las funciones orientadas a la red son opcionales o específicas de cada función: Sparkle busca actualizaciones, las vistas de estado del proveedor pueden consultar páginas de estado públicas, la integración de Linux.do puede autenticarse a través del navegador, las funciones de GitHub usan un token configurado y el depurador de red solo actúa como proxy del tráfico que usted enrute a través de él. Las funciones de ayuda de Rockxy y certificados son herramientas de depuración potentes, por lo que revise el código fuente y los ajustes antes de habilitar la intercepción HTTPS. 

Las funciones de IA Local y Memoria son locales por defecto, pero pueden usar un proveedor de LLM en línea o local configurado dependiendo de Ajustes > LLM y los interruptores específicos de la función que habilite. 

## Compilar desde el Código Fuente 

Clonar con submódulos: 

```bash
git clone --recursive https://github.com/1pitaph/claude-stats.git
cd claude-stats
``` 

Instalar herramientas de compilación locales: 

```bash
brew install xcodegen
``` 

Generar el proyecto de Xcode si desea inspeccionarlo directamente: 

```bash
bash scripts/generate.sh
open ClaudeStats.xcodeproj 
``` 

Para el desarrollo normal de macOS, prefiera los scripts auxiliares: 

```bash 
bash scripts/run-debug.sh  # genera + compila Debug + lanza la app de la barra de menús
bash scripts/run-lite-debug.sh  # genera + compila Debug + lanza Claude Stats Lite 
bash scripts/run-tests.sh  # genera + compila dependencias de prueba + ejecuta pruebas unitarias de macOS 
``` 

`ClaudeStats.xcodeproj` se genera a partir de [`project.yml`](project.yml) con [XcodeGen](https://github.com/yonaskolb/XcodeGen). El lanzador de debug compila en la ruta canónica de DerivedData `/tmp/Codex-stats-build` y lanza la aplicación por ruta completa; esto evita conflictos de Launch Services con las compilaciones de barra de menús (`LSUIElement`) que comparten el mismo identificador de paquete. 

Para la publicación de instantáneas de CloudKit durante el desarrollo, use el esquema `ClaudeStats CloudKit` o `ClaudeStats Lite CloudKit` y una configuración de firma que incluya el permiso del contenedor `iCloud.com.claudestats.ClaudeStats`. 

### Compilar y Probar iOS 

El compañero de iOS reside en el proyecto generado como el esquema `ClaudeStats iOS`. Después de generar el proyecto, abra `ClaudeStats.xcodeproj`, elija ese esquema y ejecútelo en un simulador o dispositivo iOS 17+ que haya iniciado sesión en la misma cuenta de iCloud que usa para la aplicación de Mac. 

Ejecute las pruebas unitarias de iOS con: 

```bash
bash scripts/run-ios-tests.sh 
``` 

El script utiliza por defecto `platform=iOS Simulator,name=iPhone 17 Pro` y `/tmp/Codex-stats-ios-build`. Sobrescriba estos valores cuando sea necesario: 

```bash 
IOS_TEST_DESTINATION="platform=iOS Simulator,name=iPhone 17 Pro" bash scripts/run-ios-tests.sh 
IOS_DERIVED_DATA_PATH="/tmp/Codex-stats-ios-build" bash scripts/run-ios-tests.sh 
``` 

## Requisitos 

- Mac con Apple Silicon con macOS 15+ para los lanzamientos empaquetados de macOS 
- iPhone o iPad con iOS 17+ para la aplicación compañera 
- Xcode 26+ con modo de lenguaje Swift 6 
- XcodeGen para la generación del proyecto 

## Diseño del Proyecto 

```
ClaudeStats/
  App/          punto de entrada @main, entorno de la app, Info.plist, permisos 
  Features/     integraciones de la app específicas de funciones como Notch Island 
  Models/       tipos de valor Sendable e historial de lanzamientos generado 
  Providers/    protocolo de proveedor, registro y escáneres/analizadores por proveedor 
  Resources/    datos de precios, marcador de posición de herramientas Git, recursos de la app 
  Services/     almacenes, escáneres, depuración de red, integraciones del sistema 
  ViewModels/   modelos de vista por pantalla y función 
  Views/        barra de menús, ventana principal, ajustes, terminal, red, UI de actividad 
  Utilities/    formateadores, registro, ayudantes compartidos 
ClaudeStatsiOS/      UI de la aplicación compañera de iPhone/iPad y almacén de instantáneas 
ClaudeStatsShared/   paquete Swift compartido por macOS e iOS para estadísticas y sincronización de CloudKit 
AtollEmbed/          envoltorio del lado de la aplicación para la integración de Atoll/DynamicIsland 
RockxyBackendEmbed/  envoltorio del lado de la aplicación para el soporte de proxy/depuración de Rockxy 
WarpEmbed/           límite del lado de la aplicación para el tiempo de ejecución de Warp ADE embebido 
ThirdParty/          submódulos de git para Atoll, Rockxy, Warp, mem0 y Graphiti 
ClaudeStatsTests/    pruebas de analizador, escáner, ajustes, integración y funciones 
ClaudeStatsCoreTests/ pruebas de modelo de sincronización y estadísticas compartidas 
ClaudeStatsiOSTests/ pruebas del compañero de iOS 
docs/assets/         imágenes del README, iconos, capturas y GIFs 
scripts/             generación de proyecto, ejecución/prueba local, lanzamiento, herramientas de appcast 
``` 

## Código Abierto y Módulos de Terceros 

Claude Stats se publica bajo la [Licencia Pública General de Affero GNU v3.0](LICENSE). La aplicación también embebe y adapta varios proyectos importantes de código abierto: 

| Proyecto | Licencia | Cómo lo usa Claude Stats | 
| --- | --- | --- | 
| [Rockxy](https://github.com/1pitaph/Rockxy) | AGPL-3.0 | Integrado a través de `RockxyBackendEmbed` y `RockxyHelperTool` para el depurador de red, motor de proxy, manejo de reglas, certificados y flujo de ayuda privilegiada. | 
| [Atoll / DynamicIsland](https://github.com/1pitaph/Atoll) | GPL-3.0 | Integrado a través de `AtollEmbed` para la superficie y módulos opcionales de Notch Island. Sus archivos [`NOTICE`](ThirdParty/Atoll/NOTICE) y [`COPYRIGHT_ASSETS`](ThirdParty/Atoll/COPYRIGHT_ASSETS) siguen siendo parte del rastro de atribución. | 
| [Warp](https://github.com/1pitaph/Warp) | AGPL-3.0 / MIT para `warpui_core` y `warpui` | Integrado como el límite de embebido de terminal/ADE activo en ventana a través de `WarpEmbed`. | 
| [mem0](https://github.com/1pitaph/mem0) | Apache-2.0 | Integrado como un submódulo fork para el sidecar opcional de memoria de Code Agent. El modo local predeterminado mantiene el adaptador deshabilitado hasta que se configure un proveedor de embedding/LLM. | 
| [Graphiti](https://github.com/1pitaph/graphiti) | Apache-2.0 | Integrado como un submódulo fork para la proyección de grafo temporal opcional en el sidecar de memoria de Code Agent. El primer backend local apunta a Kuzu embebido. | 

Las dependencias adicionales de Swift Package Manager incluyen Sparkle, SwiftNIO, SwiftNIOSSL, Swift Certificates, Swift Crypto, Defaults, KeyboardShortcuts, SwiftUIIntrospect, Lottie, MacroVisionKit, SkyLightWindow, AtollExtensionKit, Swift Collections y SwiftSoup. Estos paquetes mantienen sus licencias y avisos originales. 

## Contribuir 

Los problemas (issues) y las solicitudes de extracción (pull requests) son bienvenidos. Antes de abrir un PR, ejecute: 

```bash
bash scripts/run-tests.sh 
``` 

Para cambios en el comportamiento de la aplicación, ejecute también: 

```bash 
bash scripts/run-debug.sh 
``` 

Para cambios en el compañero de iOS, ejecute: 

```bash 
bash scripts/run-ios-tests.sh 
``` 

Mantenga el código libre de advertencias de concurrencia estricta de Swift 6. Al cambiar el código de integración de Atoll, Rockxy o Warp, realice los cambios de código fuente en el submódulo/fork correspondiente primero, y luego actualice el puntero del submódulo en este repositorio.
