# e05s01 — Subir al tren y ver la canción actual

## 1. Business narrative

La emisión ya funciona, pero el oyente necesita una identidad visual y saber qué pista está oyendo.

## 2. Actor

Oyente público en escritorio o móvil.

## 3. Need

Entrar en vivo y recibir el estado real de la pista sin afectar la continuidad del audio.

## 4. Outcome

El reproductor muestra una experiencia Neo-Tokyo, la pista actual y datos opcionales de Last.fm.

## 5. Main flow

El oyente abre la web, pulsa **Subir al tren**, escucha HLS y ve la pista detectada desde la cola activa de Liquidsoap. Un único proceso del servidor consulta el estado y distribuye cambios con Phoenix PubSub.

## 6. Alternative flows

- Sin pista activa, la interfaz conserva el reproductor y oculta la ficha musical.
- Si Last.fm falla o devuelve datos incompletos, se muestran al menos título y artista almacenados.
- Sin portada, álbum, reseña o etiquetas, la sección correspondiente no se renderiza.
- Si Liquidsoap no responde, el audio continúa y la última ficha válida no se reemplaza por un error.

## 7. Requirements

### MODIFIED: Reproductor público

**Before:** El botón inicia HLS y solo muestra el estado de conexión.

**After:** El mismo botón inicia HLS sin reconexiones y la página recibe la pista actual mediante PubSub.

### ADDED: Estado real de reproducción

La pista actual se obtiene como la solicitud activa de Liquidsoap que ya no está en ninguna cola pendiente. Los comandos son constantes y los IDs deben ser numéricos.

### ADDED: Metadatos Last.fm

`track.getInfo` usa la API key existente para obtener álbum, portada, etiquetas y reseña. La URL de API permanece fija y las imágenes se aceptan solo desde el CDN HTTPS permitido.

### ADDED: Visual provisional

Una escena CSS Neo-Tokyo y una onda animada indican reproducción. Ambas respetan `prefers-reduced-motion`; el video final sustituirá la escena cuando exista el recurso.

### ADDED: Mensaje del oyente

El texto libre que acompaña uno o más enlaces en Slack se normaliza, limita a 280 caracteres y se conserva con cada solicitud. La estación lo muestra solo mientras suena esa solicitud; mensajes formados únicamente por enlaces o puntuación se omiten.

### ADDED: Control de volumen

Un control nativo de rango, diseñado como el mando maestro de un Shinkansen, ajusta el volumen local del elemento de audio sin reconectar ni modificar la emisión compartida.

## 8. Data

Título, artista, duración, álbum, portada, etiquetas, reseña y mensaje opcional del oyente. Solo el mensaje se persiste con la solicitud; la ficha enriquecida vive en el proceso singleton durante la pista.

## 9. Interfaces

- Liquidsoap TCP loopback: `request.all`, `requested.queue`, `complementary.queue`, `request.metadata <id>`.
- Last.fm HTTPS: `track.getInfo` con `artist`, `track`, `api_key` y `format=json` ([documentación oficial](https://www.last.fm/api/show/track.getInfo)).
- Phoenix PubSub: tema interno de now-playing.
- LiveView y hook HLS existentes.

## 10. Dependencies

Requiere e01s01 y e03s01. Usa Req, Ecto, Phoenix PubSub y CSS nativos ya instalados; no añade paquetes.

## 11. Security

HEEx escapa texto externo, no se renderiza HTML del proveedor, la imagen requiere host HTTPS permitido y el API key nunca llega al cliente o logs. Ver `specs/security/epics/e05/THREAT_MODEL.md`.

## 12. Failure handling

El poller conserva la última pista ante fallos transitorios y registra el motivo sin datos secretos. Un fallo visual o de metadatos nunca modifica el elemento `<audio>`.

## 13. Observability

Registrar cambios de pista y fallos de consulta con eventos concisos `now_playing_changed` y `now_playing_poll_failed`.

## 14. Performance

Un solo proceso consulta Liquidsoap cada dos segundos y hace como máximo una consulta Last.fm por cambio de pista. Los LiveViews reciben PubSub; no consultan proveedores individualmente.

## 15. Accessibility

Control por teclado, estado con `role=status`, texto visible, contraste suficiente y animaciones desactivadas con movimiento reducido.

## 16. Test approach

Pruebas unitarias con funciones inyectadas para Liquidsoap y Last.fm, prueba del proceso con mensajes deterministas, pruebas LiveView por selectores y prueba Node del hook. Cero red en tests.

## 17. Acceptance criteria

```gherkin
Scenario: Subir al tren
  Given que existe una emisión activa
  When el oyente pulsa el botón principal
  Then escucha en vivo y ve la canción actual

Scenario: Dos oyentes reciben el mismo estado
  Given dos LiveViews conectados
  When cambia la pista publicada
  Then ambos muestran el mismo título y artista

Scenario: Faltan datos opcionales
  Given que Last.fm no devuelve portada ni reseña
  When se actualiza el reproductor
  Then esas secciones permanecen ocultas y el audio continúa

Scenario: Dedicatoria alrededor del enlace
  Given un mensaje Slack con texto antes o después del enlace
  When la solicitud llega a reproducirse
  Then la estación muestra el texto sin el enlace

Scenario: Volumen local
  Given que el oyente está conectado
  When mueve el mando de volumen
  Then cambia solo el volumen de su reproductor sin reconectar HLS

Scenario: Movimiento reducido
  Given que el sistema solicita movimiento reducido
  When se muestra la escena
  Then la escena y la onda no se animan
```

## 18. Out of scope

Letras, aplicación nativa, escenas 3D, extracción de colores de portada y video definitivo aún no proporcionado.

## 19. Open questions

Ninguna bloqueante. El video final se incorporará cuando el recurso esté disponible.

## 20. Definition of done

Los flujos funcionan en navegadores modernos de escritorio y móvil; 57 pruebas existentes no regresan; nuevos límites externos están simulados; cobertura de módulos de producto permanece sobre 90%; integración HLS local pasa antes del PR.

### Story e05s01 — Implementation Steps

**type:** feat

**risk:** P0
**context:** domain + UI

1. Detectar la ruta que Liquidsoap reproduce y distribuir una ficha singleton por PubSub → verify: `mix test test/nozomi/programming/liquidsoap_client_test.exs test/nozomi/programming/now_playing_test.exs`
2. Enriquecer la ficha con `track.getInfo`, tolerar JSON incompleto y filtrar portadas remotas → verify: `mix test test/nozomi/programming/lastfm_test.exs`
3. Renderizar la ficha, escena y onda accesibles sin cambiar el contrato HLS → verify: `mix test test/nozomi_station_web/live/radio_live_test.exs && npm --prefix assets test -- js/radio_player.test.mjs`
4. Ejecutar regresión y cobertura del producto → verify: `mix precommit && mix test --cover`

## Verification Script (Step-by-Step)

1. Levantar PostgreSQL, Liquidsoap y Phoenix con `LASTFM_API_KEY` cargada desde `.env`.
2. Encolar una pista local y abrir `http://localhost:4000` en dos ventanas.
3. Pulsar **Subir al tren** en ambas y confirmar audio continuo y ficha idéntica.
4. Cambiar de pista y confirmar que ambas fichas se actualizan sin recargar.
5. Activar movimiento reducido en el navegador y confirmar que escena y onda quedan estáticas.

## Risks

- El protocolo Liquidsoap puede cambiar el formato de IDs; una prueba de respuesta real fija el contrato observado.
- Last.fm puede omitir campos; todos los datos salvo título y artista son opcionales.
- La portada remota puede fallar; nunca bloquea la ficha ni el audio.

## Slopcheck

- `[OK]` Req, Phoenix PubSub, Ecto y Tailwind ya están instalados y cubren todo el alcance.
- No se proponen dependencias nuevas.

## Reason for Depth

El único módulo nuevo con estado es un poller singleton porque consultar Liquidsoap y Last.fm desde cada LiveView multiplicaría el trabajo por los 50 oyentes objetivo.
