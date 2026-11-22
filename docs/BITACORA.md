# Bitácora de ejecución

Registro **append-only**: una entrada por turno, la más nueva arriba. Cada
entrada dice qué se pidió, qué se hizo, cómo se verificó, qué commits salieron y
qué quedó abierto. El estado consolidado está en [`INFORME.md`](INFORME.md).

Formato:

```
## AAAA-MM-DD · turno N · <título>
- PEDIDO:
- HECHO:
- VERIFICADO:
- NO VERIFICABLE AQUÍ:
- COMMITS:
- ABIERTO / RIESGOS:
```

---

## 2026-11-21 · turno 23 · Cierre maestro, pedido 10 de 10: R32, empaquetado y CI

- **PEDIDO:** `BLUETOOTH_CONNECT` (cierra R32), `packaging/windows/build_windows.ps1`
  y `packaging/macos/build_macos.sh` que compilen `cyberhex_core` con Zig y
  empaqueten el bundle de Flutter, `.github/workflows/ci.yml`
  (`zig build test -Ddecoder=miniaudio`, `zig build smoke`, `flutter analyze`,
  `flutter test` en push y PR), auditoría final y documentación con inventario
  final. PROHIBIDO romper los builds de Linux o Android. RIESGO: no.
- **HECHO:**
  - `MainActivity.kt`: `requestNotificationPermission()` pasa a
    `requestRuntimePermissions()`, que pide en un solo diálogo
    `POST_NOTIFICATIONS` (13+) y `BLUETOOTH_CONNECT` (12+), solo si faltan y
    solo una vez (en `onPostResume`). El manifiesto ya declaraba el permiso:
    el comentario ahora dice la verdad (se pide en runtime).
  - `MediaSessionService.kt`: el filtro de `ACTION_ACL_CONNECTED` se añade
    solo si `canWatchBluetooth()` (SDK < 31 o permiso concedido). Sin permiso
    deja de ser un filtro muerto y no hay riesgo de `SecurityException`.
  - `lib/core/native_player.dart`: `_libraryName` pasa de constante a getter por
    plataforma (`cyberhex_core.dll` / `libcyberhex_core.dylib` /
    `libcyberhex_core.so`) y `_open()` acepta Windows y macOS en vez de lanzar
    `UnsupportedError`. Linux y Android cargan exactamente el mismo `.so`.
  - `packaging/macos/build_macos.sh` (nuevo, ejecutable): núcleo con Zig →
    `libcyberhex_core.dylib` al `Contents/Frameworks` del `.app`,
    `install_name_tool -id @rpath/...`, rpath `@executable_path/../Frameworks`
    si falta y firma ad-hoc. `--decoder`, `--skip-flutter`, `--help`; si no hay
    `macos/` se detiene y dice `flutter create --platforms=macos .`.
  - `packaging/windows/build_windows.ps1` (nuevo): lo mismo para Windows, con
    `-Decoder` y `-SkipFlutter`; copia `cyberhex_core.dll` junto a
    `cyberhex.exe` en `build\windows\x64\runner\Release`.
  - `.github/workflows/ci.yml` (nuevo): job `core` (Zig 0.17.1: tests con
    `-Ddecoder=miniaudio`, humo con `-Dsmoke-dir`, y comprobación de que el
    `.so` exporta `ch_*`), job `static` (XML del manifiesto, `bash -n` del
    script de macOS, parser de PowerShell para el `.ps1`, YAML del propio flujo)
    y job `app` (`flutter pub get`, `flutter analyze --no-fatal-infos
    --no-fatal-warnings`, `flutter test`). En `push: ['**']` y `pull_request`,
    con `concurrency` y `permissions: contents: read`.
  - `docs/INFORME.md`: **R32** y **R9** cerrados, **R38** (Windows/macOS sin
    ejecutar) y **R39** (la CI no se ha visto correr) nuevos, sección de
    empaquetado, tabla de verificación ampliada, backlog limpiado (P0.6, P1.1,
    P1.3, P1.4, P2 CI ya hechos) y changelog con el cierre.
- **VERIFICADO:** tree-sitter-dart 56/56; paridad de `PlayerApi` 112/112;
  `bash -n` del script de macOS; YAML del flujo con `yaml.safe_load` (3 jobs) y
  sus pasos de Python ejecutados a mano (7 permisos, jobs correctos); escáner
  de llaves/paréntesis sobre los 8 `.kt`; `AndroidManifest.xml` parseado con
  `ElementTree`.
- **NO VERIFICABLE AQUÍ:** el compilador de Kotlin, PowerShell y macOS (no hay
  JDK, ni `pwsh`, ni Darwin), `flutter build windows/macos` (no hay SDK ni
  andamiaje) y la primera ejecución real de la CI (R39). El núcleo no se tocó:
  los builds de Linux y Android quedan como estaban.
- **COMMITS:** `cierre maestro` (este turno).
- **ABIERTO:** R30, R31 (Android sin compilar), R33 (runner GTK), R35–R39.
  Backlog: gapless real (`skip_samples`), UI de hojas CUE y sample rate nativo.

---

## 2026-11-21 · turno 22 · FASE 7B, pedido 9 de 10: radios, red, exportador, scrobbling y copia

- **PEDIDO:** emisoras propias con `.m3u`/`.pls` y streams HTTP/HTTPS (escritura
  `.tmp`→rename); WebDAV (Basic/Bearer) y enlaces de nube con `dart:io`,
  explorar/reproducir/cachear; exportador de rango (inicio/fin) → `renderWav`
  con EQ + 9D + estéreo, como master o tono de llamada; scrobbling >50 % o
  >4 min a ListenBrainz y Last.fm; copia `.json` unificada con export/import
  desde Ajustes. PROHIBIDO `core/`, `android/`, `pubspec.yaml`. RIESGO: no
  (sin cambios de comportamiento no pedidos).
- **HECHO:**
  - `lib/core/radio_store.dart` (600): `RadioStation` (+`builtin`, `host`,
    `isPlaylist`, JSON), `RadioSeed`, `RadioBuffer`, `RadioException` y
    `RadioStore` en `radios.json`; cuatro emisoras de fábrica; id estable por
    FNV-1a; `add/remove/rename/clear`; `parsePlaylistText` (m3u/m3u8/PLSv2),
    `importPlaylist`, `exportM3u`; `resolve` (listas encadenadas, 2 saltos) y
    `buffer` (ventana 12 s / 24 MB → `${systemTemp}/cyberhex_radio`, `.part` →
    `rename`, extensión por content-type, limpieza del `.part` si falla).
  - `lib/core/scrobbler.dart` (620): `ScrobbleSettings`, `PendingScrobble`,
    `Scrobbler` en `scrobbler.json`; umbral `max(4 min, mitad)` con mínimo 30 s;
    sigue la pista por `queue[queueIndex].path` con listeners de controlador y
    posición; `flush()` compartido entre llamadas simultáneas (no duplica),
    ListenBrainz (`/1/submit-listens`, `Token`), Last.fm (`track.scrobble` con
    `api_sig`), reintentos hasta 5 y tope de 200 en cola; endpoints inyectables;
    **MD5 propio** (RFC 1321) al final del archivo; `ScrobblerHost` para la
    instancia de la app.
  - `lib/core/backup_service.dart` (330): `BackupSection`/`BackupSummary`/
    `BackupReport` (resumen en español), 10 secciones, `snapshot()` que omite
    archivos corruptos, `suggestedName()`, `exportTo`/`importFrom` atómicos,
    `looksLikeBackup` y `availableSections`.
  - `lib/ui/radio_page.dart` (450): «Mis emisoras» + sugeridas, alta/renombrar/
    borrar, importar/exportar lista, progreso de bajada, reproducción desde el
    temporal y nota honesta de radio con búfer.
  - `lib/ui/network_page.dart` (720): `RemoteKind`, `RemoteServer`,
    `RemoteEntry`, `WebDavClient` (`PROPFIND Depth: 1`, Basic/Bearer, parser por
    regex de `response`/`href`/`collection`/`getcontentlength`, descarga
    `.part`→rename) y `NetworkStore` en `network.json`; vista de servidores,
    explorador con subida de nivel, descarga + reproducción en `cloud_cache`,
    enlace de nube directo y aviso de credenciales en claro.
  - `lib/ui/audio_export_sheet.dart` (330): rango sobre la duración de la pista,
    presets master/tono (30 s), interruptor de DSP, `getSaveLocation` y
    `renderWav(source, destino, start:, end:, withDsp:)`; nombre sugerido.
  - `lib/ui/settings_page.dart`: pasa a `StatefulWidget` (sin cambios de API:
    `SettingsPage(theme:, player:, desktop:)` sigue igual) y gana las secciones
    **Scrobbling** (interruptor, token de ListenBrainz, clave/secreto/sesión de
    Last.fm, pendientes y «Enviar ahora») y **Copia de seguridad** (exportar y
    restaurar con el diálogo del sistema), más el acceso al exportador.
  - `lib/ui/library_page.dart`: tres entradas nuevas en el menú (radios, red y
    nube, exportar la pista actual).
  - `lib/main.dart`: crea el `Scrobbler` al arrancar y lo publica en
    `ScrobblerHost` (una línea fuera del ALCANCE, sin tocar lo PROHIBIDO: sin
    ella la escucha solo se contaría con Ajustes abierto).
  - `test/backup_and_radio_test.dart` (28 casos): emisoras, listas reales,
    ventana contra `HttpServer`, MD5 y firma, umbral, envío a los dos servicios,
    sin red, copia/restauración, `207` con espacios codificados y cinco de
    widget.
- **VERIFICADO:** tree-sitter-dart 56/56; paridad de `PlayerApi` 112/112
  intacta; MD5 portado contra `hashlib` (tres vectores); lectura cruzada de los
  nombres de archivo JSON y de los miembros usados por las páginas nuevas;
  balanceo de llaves y revisadas las rutas de error del `.part`.
- **NO VERIFICABLE AQUÍ:** `flutter test`/`flutter analyze` (sin SDK), la
  descarga real desde radios públicas y WebDAV de verdad, y el sonido del tono
  de llamada exportado. RIESGO: el `Scrobbler` de `main.dart` no se puede
  ejercitar sin la app.
- **COMMITS:** `fase 7B` (este turno).
- **ABIERTO:** R35 (radio con búfer), R36 (credenciales en claro), R37 (WebDAV
  mínimo). Sigue el pedido 10 (cierre maestro).

---

## 2026-11-21 · turno 21 · FASE 7A, pedido 8 de 10: escritorio Linux (MPRIS2, %U, DnD)

- **PEDIDO:** `%U` al canal `cyberhex/intent`, MPRIS2 por GDBus, siempre encima,
  notificaciones de escritorio, atajos, drag & drop, selector de salida y S16 con
  dither. PROHIBIDO `core/`, `android/`, `pubspec.yaml`. RIESGO ACEPTABLE (sí).
- **HECHO:**
  - `linux/runner/my_application.cc` (594, reescrito):
    `G_APPLICATION_HANDLES_COMMAND_LINE` + instancia única, `onOpenFile` por el
    canal `cyberhex/intent` y `getInitialFile` en arranque en frío; canales
    `cyberhex/intent` y `cyberhex/desktop` creados antes del primer frame;
    `GtkWindow` como destino de `text/uri-list`/`text/plain` → `onDropPaths`;
    `setAlwaysOnTop` (`gtk_window_set_keep_above`), `notifyTrack`
    (`GNotification` con acción `app.raise`), `updateMetadata`/`updateState` →
    MPRIS y `notifySeek` → señal `Seeked`.
  - `linux/runner/mpris_bridge.{h,cc}` (65 + 598, nuevos): dos interfaces
    registradas en `/org/mpris/MediaPlayer2` con la misma `GDBusInterfaceVTable`,
    `PropertiesChanged` a mano, todas las propiedades y métodos del estándar, y
    traducción a órdenes de texto (`seekrel:`, `volume:`, `loop:`…).
  - `linux/runner/CMakeLists.txt`: añade `mpris_bridge.cc` (GIO ya entra con GTK).
  - `lib/platform/desktop_channel.dart` (276, nuevo): metadatos/estado en µs,
    transporte entrante, `setAlwaysOnTop`, `notifyTrack`, `notifySeek` y flujo
    `drops`; `MissingPluginException` ignorada.
  - `lib/ui/player_page.dart`: atajos (espacio, ←/→, Shift+←/→, ↑/↓, M, L, S) con
    `Focus(autofocus)` y `_runCommand`; drag & drop con `_onDroppedPaths`
    (primera pista suena, resto a la cola, carpetas por `scanDirectory`).
  - `lib/ui/settings_page.dart`: sección «Salida de audio y escritorio»
    (dispositivos, S16+TPDF, siempre encima, notificar pista).
  - `lib/main.dart`: `DesktopChannel` solo en Linux.
  - `test/desktop_channel_test.dart` (322): **11 casos** (MPRIS de ida y vuelta,
    topes, drop, sin runner, atajos).
- **VERIFICADO:** tree-sitter **49/49**; paridad `PlayerApi` 112/112; 5/5
  archivos del runner con llaves/paréntesis/corchetes balanceados y `#include`
  propios existentes; cifras: `lib` 16 909, `test` 4 941, **198 casos**.
- **NO VERIFICABLE AQUÍ:** **no hay `zig` en el sandbox** (ni `pkg-config`, ni
  cabeceras GTK, ni `cmake`), así que `zig build test -Ddecoder=miniaudio`,
  `zig build smoke` y `g++ -fsyntax-only` **no se pudieron ejecutar**: el núcleo
  sigue como estaba (no se tocó) y el runner solo pasó el balanceo (**R33**). Los
  atajos globales se delegan en MPRIS (**R34**).
- **COMMITS:** este turno, un commit en `linux/`, `lib/`, `test/` y `docs/`.
- **ABIERTO / RIESGOS:** R33 y R34. Pendientes los pedidos 9 y 10.

---

## 2026-11-21 · turno 20 · FASE 6B, pedido 7 de 10: widget, azulejo, coche y botones del casco

- **PEDIDO:** widgets 4x1/4x2 desde el `MediaSessionService` con `PendingIntent`
  `FLAG_IMMUTABLE` según SDK; `CyberHexTileService` con `@RequiresApi(N)`;
  `ACTION_MEDIA_BUTTON` con doble clic → siguiente y triple → anterior;
  auto-play configurable al conectar clavija/Bluetooth; acciones de la
  notificación elegibles; `CyberHexBrowserService` + `automotive_app_desc.xml`.
  PROHIBIDO `build.gradle.kts`, `settings.gradle.kts` y Maven nuevo.
  RIESGO ACEPTABLE (sí).
- **HECHO:**
  - `android/…/MediaSettings.kt` (234, nuevo): `MediaAction` con orden canónico y
    `toggle` obligatorio, `SharedPreferences` `cyberhex_media` (auto-play y
    botones), `apply` para el `configure` de Dart y `PlaybackCache` (última pista
    en preferencias + carátula en `filesDir/widget_art.png`).
  - `CyberHexWidgetProvider.kt` (186, nuevo): 4x1 con carátula, título,
    anterior/play-pausa/siguiente y progreso; `CyberHexWidgetLargeProvider` 4x2;
    `PendingIntent`s con `FLAG_IMMUTABLE` desde M; `refreshAll` repinta las dos
    variantes.
  - `CyberHexTileService.kt` (72, nuevo): `@RequiresApi(N)`, icono y estado desde
    `PlaybackCache`, toque → `toggle`/`play`, `refresh` con
    `requestListeningState`.
  - `CyberHexBrowserService.kt` (109, nuevo): `MediaBrowserService` del sistema,
    raíz `cyberhex_root` → `cyberhex_now`, token de la `MediaSession`.
  - `MediaSessionService.kt` (779): doble/triple clic del casco con ventana de
    420 ms, auto-play por `ACTION_HEADSET_PLUG`/`ACTION_ACL_CONNECTED`, acciones
    de notificación elegibles (compacta = tres primeras), «Cerrar» → `stop`,
    token publicado para el coche, caché del widget cada 5 s, `dartReady` para
    abrir la app si nadie escucha y `openApp()`.
  - `MediaBridge.kt` (232): `configure` + `dartReady`; `ThemeController` gana
    `autoPlayOnConnect` y `mediaActions` (JSON v1, sin migración: campos
    ausentes = valores por defecto); `MediaSessionChannel.updateMediaSettings`;
    `main.dart` empuja los ajustes al arrancar y en cada cambio; `SettingsPage`
    con la sección «Notificación y auriculares».
  - `res/`: `layout/widget_small.xml`, `layout/widget_large.xml`,
    `xml/widget_{small,large}_info.xml`, `xml/automotive_app_desc.xml`,
    `drawable/widget_background.xml`, `drawable/ic_tile_{play,pause}.xml`,
    `values/strings.xml`. Manifiesto: dos `<receiver>` de widget, azulejo con
    `BIND_QUICK_SETTINGS_TILE`, navegador con `BIND_MEDIA_BROWSER_SERVICE`,
    `meta-data` de Android Auto y `BLUETOOTH_CONNECT`.
  - `test/media_settings_test.dart` (143): **6 casos** (ajustes, JSON viejo,
    `configure`, `SettingsPage`).
- **VERIFICADO:** tree-sitter **47/47 sin errores**; paridad `PlayerApi` 112/112;
  los 8 Kotlin con llaves y paréntesis balanceados; los 9 XML nuevos parsean.
  Cifras: `lib` 16 321, `test` 4 619, **187 casos**.
- **NO VERIFICABLE AQUÍ:** sin JDK, Gradle ni emulador no se compila nada de
  `android/`: `RemoteViews`, el par de `<receiver>`, el azulejo en API 24+ y
  Android Auto quedan para el usuario (**R30**); el navegador solo publica la
  pista actual (**R31**); el auto-play por Bluetooth necesita
  `BLUETOOTH_CONNECT` concedido (**R32**); `androidx.annotation.RequiresApi` se
  da por disponible vía `flutter_embedding`.
- **COMMITS:** este turno, un commit en `android/`, `lib/`, `test/` y `docs/`.
- **ABIERTO / RIESGOS:** R30, R31, R32. Pendientes los pedidos 8–10.

---

## 2026-11-21 · turno 19 · FASE 6A, pedido 6 de 10: temas, carátula, gestos, mini-reproductor y bolsillo

- **PEDIDO:** cuatro temas + color dinámico de carátula, cuatro estilos de
  carátula, gestos (deslizar, doble toque, búsqueda fina), barra de acciones
  configurable, modo bolsillo, diseño de dos paneles y mini-reproductor.
  PROHIBIDO `core/`, `android/` y `pubspec.yaml`. RIESGO NO ACEPTABLE.
- **HECHO:**
  - `theme.dart` (315): `CyberHexThemeId`, `CyberHexPalette` (4 paletas completas),
    `CoverStyle`, `paletteOf(context)` y `buildCyberHexThemed`; el
    `buildCyberHexTheme()` de siempre sigue devolviendo neón.
  - `lib/core/theme_controller.dart` (309): tema, color dinámico desde la
    carátula (`instantiateImageCodec` a 32 px y media ponderada por saturación,
    con reserva determinista), estilo, bolsillo, acciones y `theme.json`.
  - `lib/ui/player_page.dart` (+581): cuatro estilos de carátula, gestos de la
    carátula, doble toque por zonas, búsqueda fina en `mm:ss.mmm`, barra de
    acciones configurable, modo bolsillo y dos paneles con clave
    `player-panes`/`player-cover` para las pruebas.
  - `lib/ui/mini_player.dart` (157) en biblioteca y listas; `settings_page.dart`
    (147) con tema, dinámico, carátula, bolsillo y acciones; `main.dart` monta el
    `MaterialApp` desde el controlador de tema.
  - `test/theme_and_gestures_test.dart` (378): **19 casos** nuevos.
- **VERIFICADO:** tree-sitter **46/46 sin errores**; paridad `PlayerApi` 112/112;
  cifras: `lib` 16 176, `test` 4 468, **181 casos**.
- **NO VERIFICABLE AQUÍ:** sin SDK no se ejecutan los 19 casos; los gestos no se
  prueban con el dedo (R29) y el tema Claro solo llega al reproductor, al mini y a
  los ajustes (R28); el color de la carátula depende de que el decodificador
  acepte el JPEG/PNG real.
- **COMMITS:** este turno, un commit en `lib/`, `test/` y `docs/`.
- **ABIERTO / RIESGOS:** **R28** migración de paleta a medias; **R29** gestos sin
  probar en hardware. Pendientes los pedidos 7–10.

---

## 2026-11-21 · turno 18 · FASE 5, pedido 5 de 10: listas, cinco colas, automix, estadísticas y descargas

- **PEDIDO:** playlists `.m3u`/`.m3u8`/`.pls` e inteligentes, hasta cinco colas
  simultáneas con memoria de posición en pistas largas, automix por BPM,
  historial/estadísticas y gestor de descargas desde catálogos abiertos o URL
  directa. PROHIBIDO `core/`, `android/` y `pubspec.yaml`. RIESGO NO ACEPTABLE.
- **HECHO:**
  - `lib/core/playlist_store.dart` (790): `Playlist`, `PlaylistStore` (CRUD,
    `.m3u`/`.m3u8`/`.pls` de ida y vuelta, `remember` de lo escaneado, listas
    inteligentes Top 25 / Nunca / Del mes), `MultiQueueStore` (cinco colas con
    índice y cola activa) y `LongTrackMemory` (>15 min, antirrebote de 2 s).
  - `lib/core/stats_store.dart` (354): `TrackStat`, `HistoryEntry` y `StatsStore`
    con totales, top de pistas y artistas, reparto por hora, historial de 1 000 y
    persistencia con antirrebote.
  - `lib/core/automix_engine.dart` (289): `AutomixPlan`/`AutomixPlanner` (puro,
    ±8 %, doble pulso) y `AutomixEngine` (pre-roll de 8 s, caché de BPM, probe
    inyectable, restauración del tempo).
  - `lib/core/audio_downloader.dart` (334): parsers puros del buscador y de la
    metadata de Archive, saneado de nombres, descarga por `HttpClient` con
    progreso y `.part` + `rename`; también URLs directas.
  - `lib/ui/playlists_page.dart` (518), `stats_page.dart` (367) y
    `downloader_page.dart` (338); `queue_sheet.dart` gana la barra de cinco colas
    y el interruptor de automix; `library_page.dart` gana el menú (Listas,
    Estadísticas, Descargas), el `remember` de lo escaneado y la retomada de
    pistas largas; `player_page.dart` es dueño de los almacenes y apunta las
    reproducciones.
  - `test/playlists_and_downloader_test.dart` (547): **22 casos** nuevos.
- **VERIFICADO:** tree-sitter **42/42 sin errores**; paridad `PlayerApi` 112/112;
  cifras: `lib` 14 885, `test` 4 090, **162 casos**; la descarga se ejecuta de
  verdad contra un `HttpServer` local (150 000 B con progreso) porque es un
  `test()` normal, no un `testWidgets` con reloj falso.
- **NO VERIFICABLE AQUÍ:** sin SDK no se ejecutan los 22 casos; sin red real no
  se comprueba la API de Internet Archive (R26); el automix no se oye (R27); el
  autoguardado de posición solo se prueba en memoria.
- **COMMITS:** este turno, un commit en `lib/`, `test/` y `docs/`.
- **ABIERTO / RIESGOS:** **R26** descargas sin red real; **R27** automix sin
  audio real. Pendientes los pedidos 6–10.

---

## 2026-11-21 · turno 17 · FASE 4, pedido 4 de 10: letras, estudio .lrc, etiquetas y tarjetas

- **PEDIDO:** visor de letras sincronizadas (salto al verso, pantalla completa
  difuminada, bilingüe, letras incrustadas), estudio de letras `.lrc` en vivo,
  editor de metadatos y carátulas (individual y por álbum) y tarjetas
  compartibles. PROHIBIDO `core/`, `android/` y `pubspec.yaml`. RIESGO NO
  ACEPTABLE.
- **HECHO:**
  - `lib/core/lyrics_parser.dart` (462): `LyricLine`/`Lyrics`/`LyricsParser`
    (marcas múltiples, metadatos, `offset`, bilingüe por marca repetida **y** por
    `|`, búsqueda binaria de la línea actual) + `LrcWriter` (ida y vuelta y
    guardado junto al audio). Letras incrustadas: `USLT` de ID3v2 (UTF-8,
    Latin-1 y UTF-16 con BOM) y `LYRICS`/`UNSYNCEDLYRICS` de FLAC.
  - `lib/core/tag_editor.dart` (773): primitivas `Id3v2` y `Flac` (marcos,
    *syncsafe*, bloques, comentarios, PICTURE), `TrackTags`, `TagEditor` de
    lectura/escritura (ID3v2.3 nuevo delante del audio; cadena de bloques FLAC
    reconstruida), `albumSiblings` y `TagWriteReport`.
  - `lib/ui/lyrics_page.dart` (433): fondo difuminado con `ImageFiltered`, línea
    activa, autoscroll con `Scrollable.ensureVisible`, salto al tocar y
    traducción conmutable.
  - `lib/ui/lyrics_creator_page.dart` (445): pegar → preparar → marcar al ritmo,
    ±0,1 s, deshacer y guardado real del `.lrc` con los metadatos del motor.
  - `lib/ui/tag_editor_sheet.dart` (424) y `lib/ui/share_card_sheet.dart` (476,
    con `ShareCard` público y `shareWaveform` determinista).
  - `player_page.dart`: botones «Letras», «Etiquetas» y «Compartir».
  - `test/lyrics_and_tags_test.dart` (550): **28 casos** nuevos.
- **VERIFICADO:** tree-sitter **33/33 sin errores**; paridad `PlayerApi` 112/112
  intacta; cifras: `lib` 11 890, `test` 3 543, **140 casos**; `git status` solo
  con `lib/`, `test/` y `docs/` (ni `core/`, ni `android/`, ni `pubspec.yaml`).
- **NO VERIFICABLE AQUÍ:** sin SDK de Flutter los 28 casos están escritos y **no
  ejecutados**; sin archivos reales del usuario no se puede comprobar el escritor
  de etiquetas contra carátulas grandes ni FLAC con bloques atípicos (R24); la
  exportación PNG usa `getSaveLocation` y el diálogo del sistema no existe aquí.
- **COMMITS:** este turno, un commit en `lib/`, `test/` y `docs/`.
- **ABIERTO / RIESGOS:** **R24** etiquetas sin validar con la biblioteca real;
  **R25** la onda de la tarjeta es decorativa (el núcleo no expone picos, P0.5).
  Pendientes los pedidos 5–10.

---

## 2026-11-21 · turno 16 · FASE 3, pedido 3 de 10: la UI de audio (laboratorio, vúmetro y presets)

- **PEDIDO:** llevar a la interfaz todo el DSP y lo nuevo del núcleo —que hasta
  ahora solo se podía llamar por API— con un pedido atómico y reversible.
  PROHIBIDO `core/`, `android/`, `pubspec.yaml`. Sin dependencias nuevas.
  RIESGO NO ACEPTABLE.
- **HECHO:**
  - `lib/core/eq_presets.dart` (215 líneas): `EqAnchor`/`EqPreset` con la curva
    por anclajes, `gainsFor` (interpolación en log-frecuencia, recorte ±18 dB,
    extremos planos), `compensationFrom` (+12 dB a lo no oído) y **10 presets**
    (Plano, Rock, Pop, Jazz, Clásica, Vocal, Graves, Agudos, Electrónica, Noche).
  - `lib/ui/visualizer_widget.dart` (351): vúmetro RMS/pico con marca de clip y
    espectro en `CustomPaint` con dos estilos (barras y columnas de hexágonos);
    suavizado asimétrico, sondeo a 30 Hz con temporizador propio y respeto de
    `disableAnimations`.
  - `lib/ui/audio_lab_sheet.dart` (821): cinco secciones plegables —espacial
    (9D, ancho, punch, crossfeed, karaoke, noche), mezcla (balance, canales,
    ReplayGain global/álbum, velocidad, tono, S16), avance (crossfade, gapless,
    loop A-B, temporizador), paisaje y herramientas (BPM, exportar WAV con
    selector de destino, abrir `.cue` con lista de cortes, marcar aquí, preset
    de EQ)— más acciones con estado («Exportando…», errores del motor).
  - `lib/ui/hearing_test_sheet.dart` (271): prueba de audición de 10 bandas
    sobre la música que suena (sin generador de tonos: deja sola la banda a
    +12 dB y el resto a −18 dB), curva de compensación y **restauración del EQ**
    al cancelar (`_applied` evita deshacer lo aceptado).
  - `eq_sheet.dart`: chips con los 10 presets y acceso a la prueba; `player_page`
    pasa a `isScrollControlled` y gana el botón «Laboratorio», el atajo de
    paisaje y un visualizador compacto.
  - `test/audio_lab_test.dart` (300): **14 casos** nuevos.
- **VERIFICADO:** tree-sitter sobre `lib/` y `test/` → **27/27 sin errores**;
  paridad `PlayerApi` intacta (112 miembros, 0 faltantes en ambos); los miembros
  de `PlayerController`/`PlayerSnapshot` que usa la UI, comprobados por regex
  (solo falsos positivos de `ChangeNotifier`); recuento: `lib` **8 473** líneas,
  `test` **2 993**, **112 casos**. `pubspec.yaml` y `core/` sin tocar
  (`git status` solo con `lib/`, `test/` y `docs/`).
- **NO VERIFICABLE AQUÍ:** sin SDK de Flutter no hay `flutter analyze` ni
  `flutter test`: los 14 casos están escritos, **no ejecutados**. Tampoco se
  puede ver la hoja: alturas, desbordes en pantallas pequeñas, contraste y el
  resultado visual del visualizador (R22). El `getSaveLocation` del exportador y
  la lista de cortes `.cue` necesitan un escritorio real.
- **COMMITS:** este turno, un commit en `lib/`, `test/` y `docs/`.
- **ABIERTO / RIESGOS:** **R22** UI sin verificación visual; **R23** aplicar un
  preset son 36 llamadas a `setBand`; **R21** exportar/BPM sin barra de
  progreso. Pendientes los pedidos 4–10 (letras y etiquetas, listas y descargas,
  temas y gestos, Android nativo, Linux, radio/nube y CI).

---

## 2026-11-21 · turno 15 · FASE 3, pedido 2 de 10: toda la API en Dart y DSP en la sesión

- **PEDIDO:** enlazar en Dart **todo** lo que el núcleo expone y aún no llegaba a
  la app (medidores, espectro, balance, modo de canales, ReplayGain, velocidad,
  tono, crossfade, gapless, loop A-B, marcadores, temporizador, silencio,
  dispositivos de salida, letras) **y** lo nuevo del pedido 1 (paisajes, BPM,
  exportador WAV, `.cue`), con paridad 100 % `PlayerApi`/`NativePlayer`/
  `FakePlayer` y el DSP persistido en `SessionStore`. PROHIBIDO `core/`,
  `android/`, `pubspec.yaml`. RIESGO NO ACEPTABLE.
- **HECHO:**
  - `lib/core/player_api.dart`: `PlayerApi` pasa de 63 a **112 miembros**; seis
    modelos nuevos (`PlayerLevels`, `AudioMarker`, `AudioDevice`, `CueTrack`,
    `SilenceTrim`, `SoundscapePreset`) y `AudioSettings` (20 campos, `toJson`
    tolerante, `copyWith`, `==`/`hashCode`), que vive aquí para no importar en
    círculo controlador ↔ sesión.
  - `lib/core/native_player.dart`: 41 `lookup` nuevos, **todos** con
    `providesSymbol` y `null` si la `.so` es vieja (122 símbolos `ch_*` usados,
    verificado contra `nm -D`). Marcadores con handle perezoso liberado en
    `dispose()`; `.cue` leído y liberado en el mismo método; BPM, silencio y
    exportación en `Isolate.run`; `renderWav` traduce los códigos −1..−6 a
    mensajes en castellano. Guardas `_disposed` en todos los setters (también
    en los que eran de una línea).
  - `test/fake_player.dart`: 112/112 miembros implementados con contadores de
    llamada y recorte de rangos igual que el motor.
  - `lib/core/player_controller.dart`: 40 miembros nuevos de delegación, aviso
    `addAudioListener`/`_audioChanged` (para que la sesión guarde al mover un
    mando), `audioSettings()`/`applyAudioSettings()` y ayudas `cycleSoundscape`,
    `addMarkerHere`, `renderWav`.
  - `lib/core/session_store.dart`: `AudioSettings` dentro de `SessionSnapshot`
    (formato **2**, compatible con el 1), `SessionKeeper` lo restaura al
    arrancar y lo guarda con el antirrebote de 600 ms.
- **VERIFICADO:** tree-sitter-dart **22/22** archivos sin errores; comprobador
  propio de paridad: **112/112** en `NativePlayer` **y** `FakePlayer`; los 122
  símbolos `ch_*` que usa el `.dart` existen en el `.so` (`nm -D`, 199 totales);
  cifras: `lib` 6 699 líneas, `test` 2 693, **98 casos**; sin paquetes nuevos
  (`pubspec.yaml` intacto).
- **NO VERIFICABLE AQUÍ:** sin SDK de Flutter/Dart no se ejecuta
  `flutter analyze` ni `flutter test`: los 98 casos están escritos, no
  ejecutados. Sin teléfono, nada de FFI real (`providesSymbol` y los tipos se
  revisan a mano y con el comprobador de símbolos).
- **COMMITS:** este turno, un commit en `lib/`, `test/` y `docs/`.
- **ABIERTO / RIESGOS:** **R20** el núcleo no tiene getter de ReplayGain on/off
  (se recuerda en Dart; si molesta, entra en un pedido de núcleo); **R21**
  exportar y detectar BPM decodifican en el isolate sin barra de progreso.
  Pendientes los pedidos 3–10 (UI de audio, letras y etiquetas, listas y
  descargas, temas y gestos, Android nativo, Linux, radio/nube y CI).

## 2026-11-21 · turno 14 · FASE 3, pedido 1 de 10: paisajes, BPM y exportador WAV

- **PEDIDO:** Fase 3 completa en diez pedidos atómicos y reversibles, en orden
  estricto. Este turno abre el **pedido 1 (núcleo)**: `dsp_ambient.zig`,
  `bpm.zig`, CUE en memoria, paisaje en la cadena del motor y exportador WAV.
  PROHIBIDO tocar `lib/`, `android/`, `linux/`; no romper la ABI 3. RIESGO NO
  ACEPTABLE (solo `core/`).
- **HECHO:**
  - `core/src/dsp_ambient.zig` (nuevo): `Soundscape` con lluvia (paso alto 400 Hz
    + paso bajo 6 kHz con ráfagas), ruido marrón (integrador con fuga 0.012 ≈ 90 Hz
    y compensación ×4.8) y vinilo (mezcla blanco/filtrado + chasquidos). Un
    xorshift32 por canal, semilla fija, sin `malloc` ni candados; `set()`
    normaliza presets desconocidos a OFF y recorta el nivel; `isIdle()` corta el
    camino a coste cero. El marrón se recalibró en este turno: con la fuga
    anterior (420 Hz) sonaba a 0.53 de RMS (recortaba) y su delta espectral se
    parecía al de la lluvia; ahora 0.063 de RMS, pico 0.24 y delta 7.5× menor que
    la lluvia.
  - `core/src/bpm.zig` (nuevo): envolvente de energía en tramas de 10 ms, flujo
    (solo subidas), suavizado [0.25 0.5 0.25], centrado/normalizado,
    autocorrelación 60..200 BPM con prior logarítmico en 120, desempate por el
    desfase más corto y refinado parabólico. 5 tests: 120 exacto, 90/150, sin
    pulso → 0, barrido 62..198 (error ≤ 0.3 %), y entradas cortas o tasas raras.
    El suavizado fue lo que arregló 164 BPM (se leía 82 por el compás).
  - `core/src/cue.c`: el parser se parte en `parse_text()` (trabaja sobre un
    buffer) + `ch_cue_read()` (lee el fichero y resuelve `FILE` contra su carpeta)
    + **`ch_cue_parse(const char* text)`** (nuevo; `.cue` que llega de un zip, de
    la red o de compartir). Probado aparte con `gcc -fsanitize=address,undefined`:
    2 pistas, `INDEX 01 03:21:37` = 201.4933 s, `ch_cue_end` encadenado, fuera de
    rango → -1/"" y textos vacíos o nulos seguros, sin fugas.
  - `core/src/root.zig`: campo `soundscape` en `Engine` y mezcla **antes del
    limitador**; `ch_engine_set_soundscape` / `ch_engine_soundscape`;
    `ch_engine_detect_bpm(path)` (30 s, 5.7 MB, fuera del hilo de audio);
    `ExportChain` (EQ de 36 bandas con preamp → DSP → paisaje → balance →
    limitador) y `ch_engine_render_wav(src,dst,ini,fin)` +
    `ch_engine_render_wav_ex(engine,...)`: 48 kHz estéreo S16, ReplayGain de las
    etiquetas, techo −1 dBFS, dither TPDF por canal y cabecera RIFF escrita
    primero (sin `fseek`; si el decodificador no sabe la duración, dos pasadas).
  - `core/src/dsp_spatial.zig`: `Dsp.Settings` + `settings()`/`applySettings()` y
    un test, para clonar la cadena en el exportador sin arrastrar estado.
  - `core/include/cyberhex_core.h` y `core/API.md`: 6 símbolos documentados
    (paisaje ×2, BPM, exportador ×2, `ch_cue_parse`); `tests/smoke.c` amplía la
    prueba de humo con el camino completo por el ABI público.
- **VERIFICADO:** `zig build test -Ddecoder=miniaudio` → **48/48** (31 previos + 5
  de paisaje + 5 de BPM + 1 de `Dsp.Settings` + 6 nuevos de root, incluidos 4 de
  extremo a extremo que no se saltan). `zig build smoke -Dsmoke-dir=/tmp` →
  **0 fallos**, con `export: 576044 y 192044 bytes` (3 s y recorte de 1 s).
  `nm -D` → **199** símbolos `ch_*` (antes 193; +6). `zig fmt --check` limpio en
  lo tocado; `gcc -fsyntax-only -std=c2x -Wall -Wextra` limpio en `cue.c`,
  `smoke.c` y la cabecera, y un `abicheck.c` con punteros a los 6 símbolos nuevos
  compila. `zig build` instala el `.so` sin avisos.
- **NO VERIFICABLE AQUÍ:** sin dispositivo de audio real ni Android (el smoke usa
  el decodificador de miniaudio); nada de Dart en este pedido, así que tampoco
  `flutter analyze`/`flutter test`.
- **COMMITS:** este turno, un solo commit en `core/` + `docs/`.
- **ABIERTO / RIESGOS:** **R18** el paisaje aún no tiene mando en la UI (llega en
  el pedido 3); **R19** un tema de 5 min ocupa 57 MB como WAV S16 y tarda unos
  segundos. La ABI sigue en 3: los 6 símbolos son adiciones y la app los bindea
  con `providesSymbol` en el pedido 2. Nota de taller: el snapshot perdió los
  commits de la fase 2 en el índice local (seguían en `origin`); se recuperó
  `1d2344f` con `fetch` + `reset --hard` tras respaldar los ficheros en curso.

---

## 2026-11-21 · turno 13 · FASE 2: núcleo DSP audiófilo, 9D espacial y R14

- **PEDIDO:** Fase 2 en cuatro commits atómicos y reversibles: (1) fix R14
  (directorio persistente real); (2) 9D espacial + potenciador estéreo +
  karaoke en el núcleo; (3) crossfeed Bauer + modo noche + dither TPDF;
  (4) bindings y estado Dart de todo lo anterior. `RIESGO ACEPTABLE`: **no**
  en los cuatro.
- **HECHO (1, `84532c9`):** canal `cyberhex/storage` con `getAppDataDir` →
  `context.filesDir.absolutePath`, enganchado en `ensureEngine` (el motor nace
  antes que cualquier actividad) y, idempotente, en `configureFlutterEngine`.
  Dart: `StorageDirectory.prepare()` en `main()` resuelve
  `CYBERHEX_DATA_DIR` → canal Android → `$XDG_DATA_HOME/cyberhex` →
  `~/.local/share/cyberhex` → `%APPDATA%\CyberHex` → temporal, y crea el
  directorio. `SessionStore` y `FavoritesStore` lo usan por defecto, así que la
  pantalla de biblioteca también acierta sin tocarla. 7 tests nuevos.
- **HECHO (2, `1aca4cf`):** `core/src/dsp_spatial.zig` con `Spatial9D`
  (ITD ≤ 0.75 ms por línea de retardo, ILD de potencia constante y sombra
  craneal de 3 kHz en el oído que se aleja), `StereoEnhancer` (Mid/Side +
  punch por residuo armónico de `tanh` sobre < 120 Hz) y `VocalCut` (dos polos
  a 130 Hz con compensación del grave). 8 exports nuevos. De paso se arregla
  `sleepMs`, que llamaba a `poll` con una lista vacía y hacía imposible correr
  `zig build smoke` en Zig 0.17.
- **HECHO (3, `f857b78`):** `Crossfeed` Bauer (retardo de 12 muestras = 250 µs
  + paso bajo de 700 Hz) sustituyendo el inline; `NightMode` (RMS con ataque
  2 ms y relajación 300 ms, umbral -12 dBFS, hasta 4:1 y compensación);
  `ch_audio_quantize_s16` con dither TPDF (±1 LSB, dos uniformes de un
  xorshift32 por canal) y `ch_audio_set_s16` que reabre el dispositivo y
  reanuda. 6 exports nuevos.
- **HECHO (4, este commit):** 18 miembros nuevos en `PlayerApi` (63), todos
  con `providesSymbol`; `PlayerSnapshot` con los once campos DSP dentro de
  `copyWith`/`==`/`hashCode` (`Object.hashAll`); setters y alternancias en
  `PlayerController` con `_refresh()`; `FakePlayer` recortando igual que el
  motor. 8 tests nuevos.
- **VERIFICADO:** `zig build test -Ddecoder=miniaudio` **31/31**;
  `zig build smoke` **0 fallos**; `gcc -fsyntax-only -std=c2x -Wall -Wextra`
  limpio en `audio.c` y en la cabecera; `nm -D` del `.so`: 193 `ch_*` y los 12
  símbolos nuevos; tree-sitter-dart **22/22**; `PlayerApi` **63/63** en
  `NativePlayer` y `FakePlayer`; `lib` 5 100 líneas, `test` 1 970, 80 casos.
- **NO VERIFICABLE AQUÍ:** `flutter analyze`/`flutter test` y `kotlinc` (sin
  SDK): los 80 casos Dart están escritos, no ejecutados. Tampoco hay
  `/dev/snd` en este contenedor: la prueba de humo mide niveles porque el
  motor funciona sin dispositivo, pero un oído humano no ha escuchado el 9D.
- **COMMITS:** `84532c9` (1), `1aca4cf` (2), `f857b78` (3) y el de este turno.
- **ABIERTO / RIESGOS:** **R16** el DSP no tiene todavía interfaz (fase
  siguiente); **R17** coste de la cadena (despreciable y saltada con
  `isIdle()`); sigue **R15** (duración en la biblioteca). Pendiente de
  decisión del arquitecto: si el estado DSP debe viajar en
  `ch_engine_save_state` (hoy no) o quedarse solo en la sesión de Dart.

---

## 2026-11-21 · turno 12 · FASE 1B: cola, biblioteca y sesión

- **PEDIDO:** Fase 1B en tres commits atómicos y reversibles: (1) bindings FFI
  y estado de cola y biblioteca; (2) pantalla de cola + guardado automático de
  sesión; (3) pantalla de biblioteca con favoritos. `RIESGO ACEPTABLE`: **no**
  en los tres.
- **HECHO (1, `27b567f`):** `QueueItem` (path/title/artist) y `LibraryTrack`
  (path/title/extension/directory) inmutables con `==`/`hashCode`;
  `PlayerSnapshot` gana `queue`, `queueIndex` y `queueProtected`. 19 símbolos
  nuevos con `providesSymbol` (`play_index`, `load_add`, los nueve
  `queue_*`, los seis `ch_library_*`) que quedan en `null` con una `.so`
  vieja. Cola espejada en `_queuePaths` porque el contrato no exporta
  `queue_path`; `load_add` y el escaneo corren en `Isolate.run`. Controlador:
  `playAt`, `enqueue`, `playNext`, `loadAndPlay`, `moveQueueItem`,
  `removeQueueItem`, `clearQueue`, `scanDirectory` y el flag
  `queueProtected`, que hace que `openFile` use `load_add` en vez de `load`.
  `_refreshQueue()` solo relee ante `EV_QUEUE`/`EV_TRACK` o tras una mutación
  nuestra (el tick es de 80 ms y construir `QueueItem` cuesta). 11 tests
  nuevos.
- **HECHO (2, `ed2d444`):** `lib/ui/queue_sheet.dart` (hoja modal con
  `ReorderableListView`, `Dismissible`, salto al tocar, vaciar con
  confirmación y el interruptor «cola protegida») y botón de cola en la
  cabecera. `lib/core/session_store.dart`: `SessionSnapshot` +
  `SessionStore` (JSON con `.tmp`→rename, `fromJson` defensivo, nunca lanza) +
  `SessionKeeper`, que restaura al arrancar sin bloquear (ajustes, cola,
  `playAt`+`pause`+`seek` para no soltar audio) y guarda con 600 ms de
  antirrebote al pausar o cambiar de pista. `main.dart` solo lo monta con el
  motor real: con controlador inyectado no se toca el disco. 14 tests nuevos.
- **HECHO (3, este commit):** `lib/ui/library_page.dart` (pestañas
  Canciones/Álbumes/Artistas/Carpetas/Favoritos, búsqueda instantánea sin
  tildes, orden por título/artista/álbum/duración, filtro «ocultar < 30 s»,
  menú contextual con reproducir ahora / siguiente / añadir a la cola /
  favorito / ficha técnica) y `lib/core/favorites_store.dart` (JSON atómico,
  `ChangeNotifier`, `FavoritesStore.memory()` para pruebas). Artista y álbum
  salen de la jerarquía de carpetas porque el núcleo solo entrega rutas.
  Botón de biblioteca en la cabecera del reproductor. 11 tests de widget.
- **VERIFICADO:** tree-sitter-dart 22/22 sin errores; `PlayerApi` 45/45
  miembros implementados en `NativePlayer` **y** `FakePlayer`; cifras: `lib`
  4 602 líneas, `test` 1 632, 66 casos; sin dependencias nuevas; `core/`,
  `android/` y `pubspec.yaml` intactos.
- **NO VERIFICABLE AQUÍ:** `flutter analyze`/`flutter test` (sin SDK): los 66
  casos están escritos, no ejecutados. Los tres commits tocan solo
  `lib/`, `test/` y `docs/`.
- **COMMITS:** `27b567f` (1), `ed2d444` (2), y el de este turno (3).
- **ABIERTO / RIESGOS:** **R14** la sesión y los favoritos no llegan a un
  directorio privado en Android sin un canal nativo (15 líneas en `android/`,
  pedido aparte); **R15** sin consulta de duración por ruta, la ordenación por
  duración y el filtro de cortas solo ven lo ya reproducido. Pendiente de
  decisión: si la biblioteca debe recordar la última carpeta escaneada.

---

## 2026-11-21 · turno 11 · FASE 1A: Recientes, apertura desde el sistema y repeat/shuffle

- **PEDIDO:** Plan Maestro, fase 1A en tres commits atómicos: (1) P0.4 motor
  cacheado en la `Application` + R12 icono hexagonal; (2) P0.3 abrir audios con
  `ACTION_VIEW` y `%U`; (3) repetir/aleatorio desde el núcleo hasta la UI.
  `RIESGO ACEPTABLE`: sí, sí, **no**.
- **HECHO (1, `bff248c`):** `CyberHexApplication` (nueva) crea el
  `FlutterEngine` en `onCreate`, ejecuta `DartEntrypoint.createDefault()`, lo
  cachea como `"cyberhex_engine"` y engancha `MediaBridge` **antes** de que
  exista ventana. `MainActivity.provideFlutterEngine()` devuelve ese motor y
  `shouldDestroyEngineWithHost()` responde `false`. `MediaBridge.connect()`
  pasó a ser idempotente. Manifest: `android:name=".CyberHexApplication"`.
  `MediaSessionService` usa `R.drawable.ic_launcher_foreground` como `smallIcon`.
- **HECHO (2, `df02fef`):** manifest con `<intent-filter>` de `ACTION_VIEW`
  (`DEFAULT`+`BROWSABLE`, `content`/`file`, `audio/*`); `MainActivity` captura el
  `Uri` en `onCreate` (solo si `savedInstanceState == null`) y en `onNewIntent`,
  copia los `content://` a `cacheDir/shared_audio/shared_<hash>.<ext>`
  (extensión por MIME y luego por `DISPLAY_NAME`) y los entrega por el canal
  `cyberhex/intent` (`getInitialFile` / `onOpenFile`, con el primer archivo
  pendiente hasta que Dart pregunte). `packaging/linux/cyberhex.desktop`:
  `Exec=cyberhex %U` + `MimeType` de audio. Dart: `ExternalFileChannel`
  (carga y reproduce, ignora `MissingPluginException`), enganchado en
  `main.dart` y liberado en `dispose()`. 8 tests nuevos con
  `TestDefaultBinaryMessengerBinding`.
- **HECHO (3, este commit):** `PlayerSnapshot` gana `repeatMode` (0/1/2) y
  `shuffle`; `NativePlayer` bindea `ch_engine_set_repeat`, `ch_engine_repeat`,
  `ch_engine_set_shuffle` y `ch_engine_shuffle` con `providesSymbol`;
  `PlayerApi`/`PlayerController` exponen `cycleRepeat()` (0→1→2→0, leyendo del
  motor para no desincronizarse) y `toggleShuffle()`; `FakePlayer` los
  implementa; `player_page.dart` añade una fila con dos píldoras que **escriben
  el estado** ("Aleatorio: sí/no", "Repetir: no/todo/una") y cambian de color,
  icono (`repeat` ↔ `repeat_one`) y tooltip. 3 tests nuevos del controlador.
- **VERIFICADO:** tree-sitter-dart 16/16 limpio; comprobador de firmas 31/31 en
  `NativePlayer` y `FakePlayer`; canales cruzados `cyberhex/intent`
  (`getInitialFile` y `onOpenFile` con el mismo nombre a ambos lados) y el de
  medios intacto; manifest con dos `intent-filter` y XML válido; escáner de
  llaves/paréntesis en los 4 `.kt` balanceado. Sin tocar `core/`.
- **NO VERIFICABLE AQUÍ:** `flutter analyze`, `flutter test`, `kotlinc`, Gradle y
  toda prueba en el teléfono (no hay SDK ni JDK).
- **COMMITS:** `bff248c`, `df02fef`, este.
- **ABIERTO / RIESGOS:** el `.desktop` ya pasa `%U` pero el runner de Linux no
  entrega argv a Dart (P0.6); en escritorio el canal de intents no existe y todo
  pasa por `MissingPluginException`; falta el primer `flutter build apk` real.

---

## 2026-11-21 · turno 10 · Fusión de `main` y primer merge a `main`

- **PEDIDO:** "mergea todo". Antes hubo que integrar los dos commits que `main`
  ganó mientras trabajábamos (`core: A-B loop, crossfeed, mono/balance,
  medidores, estado persistente y hojas CUE; Android portable ARMv8-A` y
  `core: sonoridad EBU R128, picos, ganancia manual y guardar carátula`).
- **CONFLICTOS (3) y resolución:**
  - `core/build.zig`: la versión de `main` duplicaba la selección de
    decodificador ya refactorizada aquí. Se conserva la de la rama
    (`-Ddecoder=auto|ffmpeg|miniaudio`, `haveFfmpeg*`, mensajes claros) y se
    añaden las tres fuentes C nuevas de `main` (`cue.c`, `fileio.c`,
    `analysis.c`).
  - `core/src/root.zig`: fusión automática dejó **duplicados** que Zig no
    acepta (`balance_bits`, `ab_start`, `ab_end`, `ch_engine_set_balance`,
    `ch_engine_balance`) y un bucle `render` con dos versiones del mismo tramo.
    Se unificó: un solo `balance_bits`, un solo par A-B, un solo export de
    balance; `mono` desaparece como campo y **`ch_engine_set_mono` ahora escribe
    `chan_mode`** (0 estéreo, 1 mono, 2 intercambiados), así que la API vieja
    sigue funcionando y hay un solo mando de canales. El bucle quedó:
    fade con `fade_coeff` (respeta el fundido de pausa de ~50 ms) → modo de
    canales → **crossfeed Bauer** de `main` → balance por canal → limitador →
    medidores.
  - `core/API.md`: una sola cabecera
    `### Android: arm64-v8a portable (objetivo: Redmi Note 13, Snapdragon 685)`,
    conservando la sección de `-Ddecoder` y `zig build smoke`.
- **VERIFICADO AQUÍ:** `zig build test -Ddecoder=miniaudio` → *test success*
  (13 tests, ahora compilando también `cue.c`, `fileio.c` y `analysis.c`);
  `zig build -Drelease=true` → `.so` de 4,3 MB con **173 exports `ch_*`**;
  `gcc -fsyntax-only -std=c2x -Wall -Wextra` limpio en las 9 fuentes C;
  comprobador de símbolos: los **40** que pide `native_player.dart` están en la
  `.so` (ninguno queda sin `providesSymbol`); ABI sigue en **3**.
- **NO VERIFICABLE AQUÍ:** nada nuevo; sigue sin haber SDK de Flutter ni JDK.
- **COMMITS:** merge `main` → `arena/3351fdb0-cyberhex`, y el merge de la rama a
  `main` por PR.
- **ABIERTO / RIESGOS:** R11 (Recientes mata el motor), R12 (icono de
  notificación), R13 (FGS desde background). La nueva API de `main` (R128, CUE,
  picos) **no está bindeada en Dart todavía**: es P0.5.

---

## 2026-11-21 · turno 9 · P0.1: next/previous, canal de medios y servicio Kotlin

- **PEDIDO:** tres pedidos estrictos, un commit reversible cada uno: (1) exponer
  `next()`/`previous()` desde el FFI hasta `PlayerApi`; (2) puente Dart del canal
  `cyberhex/media` enganchado en `main.dart` solo en Android; (3) servicio en
  primer plano con `MediaSession` en Kotlin. `RIESGO ACEPTABLE`: no, no, **sí**.
- **HECHO (P1, commit `f43f040`):** `_Bindings` enlaza `ch_engine_next` y
  `ch_engine_previous` con `providesSymbol` (si la `.so` no los exporta quedan en
  `null` y son no-op); `PlayerApi` declara `next()`/`previous()`; `NativePlayer`,
  `PlayerController` (con `_refresh()`) y `FakePlayer` los implementan; 2 tests
  nuevos (llegan al motor / se ignoran tras `dispose`). No toca `core/`,
  `android/`, `pubspec.yaml` ni `lib/ui/`.
- **HECHO (P2, commit `fdf07ed`):** `lib/platform/media_session_channel.dart`
  (247 líneas): escucha el controlador y su `position`; `updateMetadata` al
  cambiar pista/etiquetas/duración/carátula; `updateState` con throttle por
  **segundo entero** de posición; comandos entrantes `play`, `pause`, `toggle`,
  `next`, `previous`, `seek` (recortado a `[0, duración]`), `setVolume`, `duck`
  (25 % del volumen guardado, restaurado exacto; `duck(true)` repetido no pierde
  el original); `MissingPluginException` ignorado; `main.dart` lo engancha bajo
  `Platform.isAndroid` y lo suelta en `dispose()` antes del controlador. 7 tests
  con `TestDefaultBinaryMessengerBinding`. Sin paquetes nuevos.
- **HECHO (P3, este commit):** `MediaSessionService.kt` (566 líneas) y
  `MediaBridge.kt` (205), `MainActivity.kt` (52), `AndroidManifest.xml`.
  FGS `mediaPlayback` (`START_NOT_STICKY`, `stopWithTask="false"`); pausa →
  `STOP_FOREGROUND_DETACH` (`stopForeground(false)` < API 24) con
  `setOngoing(false)` + `deleteIntent` para cerrar deslizando; `MediaMetadata`
  con duración y carátula (≤1024 px); `PlaybackState` con play/pause/play-pause/
  skip next/skip previous/seek/stop; receptor dinámico de
  `ACTION_AUDIO_BECOMING_NOISY`; audio focus completo (LOSS→pausa,
  LOSS_TRANSIENT→pausa+reanuda en GAIN, CAN_DUCK→`duck(true)`/`duck(false)`);
  `FLAG_IMMUTABLE` desde API 23; ramas por SDK en 26/29/33; `POST_NOTIFICATIONS`
  en runtime desde `onPostResume`. `MediaBridge` encola hasta 16 comandos si el
  canal no está adjunto y los drena en `configureFlutterEngine`.
- **VERIFICADO:** tree-sitter-dart 14/14 sin errores; comprobador de firmas
  (25/25 miembros en `NativePlayer` y `FakePlayer`); grep cruzado del canal
  (Dart acepta los 7 comandos que Kotlin emite; Kotlin acepta los 2 métodos que
  Dart envía; mismo nombre de canal); `ElementTree` valida el manifest (6
  permisos, servicio `mediaPlayback`); escáner de llaves/paréntesis en los 3
  `.kt` (balanceados). Sin `core/`, `build.gradle.kts`, `settings.gradle.kts` ni
  `libs.versions.toml` en el diff.
- **NO VERIFICABLE AQUÍ:** `flutter analyze`, `flutter test`, `kotlinc`, Gradle y
  cualquier prueba en el teléfono (no hay SDK ni JDK). El Kotlin se entrega
  "escrito, no compilado".
- **COMMITS:** `f43f040` (P1), `fdf07ed` (P2), este (P3).
- **ABIERTO / RIESGOS:** R11 (quitar la tarea de Recientes destruye el
  `FlutterEngine` y con él el audio → P0.4), R12 (falta un *small icon*
  monocromo propio), R13 (Android 12+ prohíbe arrancar el FGS desde background:
  hoy se arranca al pulsar play con la app delante).

---

## 2026-11-21 · turno 8 · Informe para el arquitecto

- **PEDIDO:** resumen del trabajo y traspaso a un arquitecto externo; todo lo
  que se haga debe quedar documentado en `.md` para control y visión.
- **HECHO:** creado `docs/INFORME.md` (estado real, contratos, riesgos, backlog
  P0–P3, entorno del agente, protocolo de pedidos) y esta bitácora. Sin cambios
  de código.
- **VERIFICADO:** datos del informe medidos, no estimados: 26 commits, 5 691
  líneas de núcleo, 1 762 de app, 327 de tests, 97 exports FFI, ABI 3, 13 tests
  Zig, 11 Dart.
- **NO VERIFICABLE AQUÍ:** —
- **COMMITS:** `docs: informe maestro y bitácora para el arquitecto`
- **ABIERTO:** ningún pedido del arquitecto todavía. Siguiente candidato P0:
  MediaSession + servicio en primer plano (Android) o biblioteca/cola (Dart).

---

## 2026-11-21 · turno 7 · Escritorio Arch + icono y permisos en Android

- **PEDIDO:** "app de escritorio para Arch y app completa para Android", sin web.
- **HECHO:**
  - `linux/CMakeLists.txt`: vigila `include/`, `vendor/`, `build.zig.zon`;
    `-DCYBERHEX_DECODER`; `touch` tras compilar para que el `--prefix` de Zig no
    dispare recompilaciones.
  - `packaging/linux/`: `PKGBUILD`, `cyberhex.desktop`, `cyberhex.svg`.
  - Ventana `CyberHex` 1000×780.
  - Android: icono adaptativo propio (hexágono), permisos `READ_MEDIA_AUDIO`,
    `READ_EXTERNAL_STORAGE` ≤12 y `WAKE_LOCK`; los de servicio en primer plano
    quedan comentados hasta que exista el servicio.
- **VERIFICADO:** harness de CMake 4.4 + Zig 0.17.1 sobre el bloque real
  (compila, 2ª pasada no-op, `touch build.zig` recompila). XMLs del icono
  válidos. `.so` con los símbolos nuevos.
- **NO VERIFICABLE AQUÍ:** `flutter build linux`, `flutter build apk`, `makepkg`.
- **COMMITS:** `276868c`, `c1ff6af`, `a9767fd`, `a3e5f31`, `c2755c3`
- **ABIERTO:** R10 (la música se corta al salir de la app), R2 (sin FFmpeg en
  Android no hay `.m4a`), abrir archivos desde el gestor.

---

## 2026-11-21 · turno 6 · Núcleo multiplataforma: decoder auto y prueba de humo

- **PEDIDO:** "enfoquémonos al 100 % en el core, funciones y todo" con dos
  versiones (PC y Android).
- **HECHO:**
  - `build.zig`: `-Ddecoder=auto|ffmpeg|miniaudio`; en PC detecta FFmpeg con
    `pkg-config`, en Android comprueba `third_party/ffmpeg-android/<abi>/lib`;
    si falta, avisa y compila con miniaudio. `-Ddecoder=ffmpeg` falla con
    mensaje claro (paso `addFail`, sin traza de pila).
  - `core/tests/smoke.c` + `zig build smoke`: sintetiza un WAV, reproduce y
    comprueba niveles, pausa, loop A-B, eventos, preamp, ReplayGain, balance y
    modo de canales. Portable a Android (`nanosleep`, sin libm).
  - Núcleo: `ch_engine_set_balance`, `ch_engine_set_channel_mode`,
    `ch_engine_abi_version` (ABI 3), versión 0.8.0.
  - `native_player.dart`: bindings de las cinco funciones nuevas.
- **VERIFICADO:** `zig build test` 13/13; `zig build smoke` **0 fallos**;
  build nativo y cruzado aarch64; `-Ddecoder=ffmpeg` falla como debe.
- **NO VERIFICABLE AQUÍ:** nada nuevo de Dart.
- **COMMITS:** `6a5e44a`, `77dc231`, `f5f5f46`, `1bfe206`
- **ABIERTO:** latencia/búfer configurable, crossfeed, dither, CUE.

---

## 2026-11-21 · turno 5 · Verificación real y corrección de banderas

- **PEDIDO:** "¿no podés hacer esto?" (`flutter analyze && flutter test`,
  `zig build`).
- **HECHO:** intento de instalar Dart/Flutter (imposible: solo hay salida a
  github/npm/pypi y el SDK vive en `storage.googleapis.com`). Sustitutos:
  tree-sitter-dart sobre los 12 archivos, verificación del layout de `ch_event`
  contra el header, revisión de imports y constantes de tema, cross-compile
  aarch64, y corrección de la documentación de banderas de Zig 0.17.
- **VERIFICADO:** 12/12 archivos Dart sin errores de sintaxis; `sizeof(ch_event)`
  = 24 B con offsets 0/4/8/16 = `_ChEvent`; `--release=*` y `-Drelease=*`
  válidos, `-Doptimize=*` **no**.
- **NO VERIFICABLE AQUÍ:** tipos de Dart (necesita el analizador real).
- **COMMITS:** `1dc1399` (y correcciones de docs en turnos siguientes)
- **ABIERTO:** R1 (nadie ha pasado `flutter analyze`).

---

## 2026-11-21 · turno 4 · Motor de audio: vúmetro, preamp, fade, A-B

- **PEDIDO:** "añadir al motor de audio" (segunda mitad de la tanda elegida).
- **HECHO:** `ch_engine_levels` (RMS/pico por canal, caída 200 ms, a cero al
  pausar), `ch_engine_set_eq_preamp`, `ch_engine_set_replaygain_mode` (+R128),
  `ch_engine_set_pause_fade`, `ch_engine_set_loop/loop_start/loop_end`,
  `ch_engine_skipped_tracks`; `openNextAuto` salta pistas ilegibles. La posición
  cuenta el audio del fundido (**arregla B6**).
- **VERIFICADO:** `zig test` 13/13; `.so` con los 11 símbolos; humo en C: RMS
  0,3514 y pico 0,4984 para un tono de 0,5, pausa con delta `0,00000`, 10/10
  muestras dentro del tramo A-B.
- **NO VERIFICABLE AQUÍ:** la UI del vúmetro (no existe).
- **COMMITS:** `d82e41b`, `1aa636d`, `e2b8308`
- **ABIERTO:** que A-B se cancele al cambiar de pista (documentado), R4.

---

## 2026-11-21 · turno 3 · Motor de estado en Dart

- **PEDIDO:** "añadir al motor de estado" (primera mitad de la tanda elegida).
- **HECHO:** `PlayerApi`, `PlayerSnapshot`, `PlayerEvent`; `PlayerController`
  (bombeo 80 ms, `ValueNotifier` de posición, snapshot con `==`); `NativePlayer`
  implementa el contrato y por fin consume `ch_engine_poll_event`; `main.dart`
  crea el motor; `PlayerPage` pasa a `ListenableBuilder`; `FakePlayer` + 10
  tests Dart sin la `.so`.
- **VERIFICADO:** sintaxis (tree-sitter) y revisión manual; el resto queda del
  lado del usuario.
- **NO VERIFICABLE AQUÍ:** `flutter test`, `flutter analyze`.
- **COMMITS:** `46772ef`, `e0767b3`, `1dc1399`
- **ABIERTO:** R1.

---

## 2026-11-21 · turnos 1–2 · Auditoría y dos tandas de correcciones

- **PEDIDO:** "analiza esto", "¿qué podés mejorar?", ejecutar fases 1 y 2.
- **HECHO:** `ANALISIS.md` con hallazgos A/B/C; EQ de 36 bandas real (antes 10
  con etiquetas inventadas) y `set_band_gain` que conserva el resto; metadatos y
  carátula en la UI; carga en isolate con spinner; tarea de Gradle incremental;
  cola sin vaciar (`play_index`/`load_add`); fuera los spinlocks del callback;
  reinicio del EQ por banda; biblioteca a prueba de ciclos y O(n²); la pantalla
  deja de reconstruirse cada 250 ms; README real y LICENSE MIT.
- **VERIFICADO:** `gcc -fsyntax-only` de los 5 `.c`; `zig test` 6→12 tests; humo
  C con WAV; ASan/UBSan sobre la biblioteca.
- **NO VERIFICABLE AQUÍ:** nada de Flutter.
- **COMMITS:** `2a330cd`, `cb70420`, `db40214`, `2f55173`, `b519832`, `cf08ef1`,
  `3db1560`, `ba04bf0`, `ced0785`, `0962ae3`, `6e19f24`
- **ABIERTO:** A4 (FFmpeg en git), B8 (Android en segundo plano), B9 ampliado.
