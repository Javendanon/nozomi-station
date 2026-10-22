# Nozomi Station

[![CI](https://github.com/Javendanon/nozomi-station/actions/workflows/test-build-release.yml/badge.svg)](https://github.com/Javendanon/nozomi-station/actions/workflows/test-build-release.yml)

Radio comunitaria inspirada en el Shinkansen. Todos los oyentes comparten una emisión HLS continua y sincronizada, servida mediante Phoenix LiveView y producida por Liquidsoap.

## Estado

El primer recorrido funcional está listo: Liquidsoap emite audio AAC a 192 kbps, Phoenix publica el manifiesto HLS y el navegador se conecta mediante HLS nativo o `hls.js`.

Slack acepta, valida y prepara solicitudes. La programación complementaria mantiene diez pistas listas desde Last.fm y YouTube; Liquidsoap prioriza solicitudes en límites de canción y conserva el tono de 440 Hz como último respaldo.

## Arquitectura

```text
Slack ──evento firmado──> Phoenix ──Oban/PostgreSQL──> resolución y preparación
Last.fm/yt-dlp ──candidatas──> programación ──control local──> Liquidsoap
Liquidsoap ──escribe──> priv/static/hls ──sirve──> Phoenix ──HLS──> navegador
```

- **Phoenix LiveView** presenta la radio y su estado.
- **Liquidsoap** controla la emisión continua y genera segmentos HLS.
- **hls.js** cubre los navegadores sin soporte HLS nativo.
- **PostgreSQL y Oban** conservan eventos idempotentes y trabajos fuera del webhook.
- **Docker Compose** ejecuta PostgreSQL y Liquidsoap; Liquidsoap no publica puertos ni usa root.

## Requisitos

- Elixir 1.15 o posterior y Erlang/OTP compatible
- Node.js 22
- Docker con Compose
- FFmpeg, solo para ejecutar la verificación completa de HLS
- `yt-dlp`, para preparar solicitudes reales de música

## Inicio local

```bash
git clone git@github.com:Javendanon/nozomi-station.git
cd nozomi-station
docker compose up -d --wait postgres
npm ci --prefix assets
mix setup
mkdir -p priv/static/hls tmp/media
LIQUIDSOAP_UID="$(id -u)" LIQUIDSOAP_GID="$(id -g)" docker compose up -d liquidsoap
mix phx.server
```

Abre [http://localhost:4000](http://localhost:4000) y pulsa **Subir al tren**. El navegador requiere una acción explícita antes de reproducir audio.

## Configuración de Slack

La integración necesita una app de Slack suscrita al endpoint `POST /slack/events`, credenciales de Spotify y Last.fm, y `yt-dlp` disponible:

```bash
export SLACK_SIGNING_SECRET="..."
export SLACK_BOT_TOKEN="xoxb-..."
export SLACK_CHANNEL_ID="C..."
export SPOTIFY_CLIENT_ID="..."
export SPOTIFY_CLIENT_SECRET="..."
export LASTFM_API_KEY="..."

# Opcional en producción: sesión para bloqueos anti-bot de yt-dlp.
export YTDLP_COOKIES_FILE="/ruta/privada/cookies.txt"
# El cliente mweb funciona por defecto; permite cambiarlo si YouTube vuelve a bloquearlo.
export YTDLP_EXTRACTOR_ARGS="youtube:player_client=mweb"
```

Nozomi usa `yt-dlp` directamente para búsqueda, metadatos y descarga; no necesita una API key de YouTube. En desarrollo detecta automáticamente `cookies/cookies.txt`, que está ignorado por Git. No guardes estas variables ni las cookies en el repositorio. En producción también son obligatorios `DATABASE_URL` y `SECRET_KEY_BASE`.

Para detener los servicios:

```bash
docker compose down
```

## Verificación

Pruebas rápidas:

```bash
mix precommit
mix test --cover
npm --prefix assets test -- js/radio_player.test.mjs
```

Integración HLS:

```bash
bash scripts/verify-liquidsoap-hls.sh
bash scripts/verify-hls-sync.sh
bash scripts/verify-programming-priority.sh
```

### Player browser evidence

Run the offline regression checks:

```bash
npm --prefix assets test
```

Collect local browser evidence:

```bash
bash scripts/verify-player-manual.sh
```

The script requires Docker, Chrome, Node with built-in WebSocket support, and `ffmpeg`.
It uses a disposable Compose project, tmpfs PostgreSQL storage, private ports, and a separate Liquidsoap instance.
The application uses the `player_manual` database with Oban queues and plugins disabled.
Existing development services, databases, queues, and HLS output remain unchanged.
The script does not load `.env`.

Results go to `specs/verifications/e05s01-manual.json` and `specs/verifications/evidence/`.
Chrome checks desktop and mobile viewports, two consistent cards, reduced motion, and playback clocks for 15 seconds after metadata changes.
Mobile emulation is not a physical-device test.
A suspended playback clock produces an inconclusive result, not a pass.
Exit codes are `0` for complete, `1` for failure, and `2` for incomplete evidence.
The recorder always leaves auditory confirmation pending because it cannot establish what a human hears.

For real Last.fm rendering, export `LASTFM_API_KEY` and explicitly enable provider access:

```bash
PLAYER_HEADED=1 PLAYER_REAL_LASTFM=1 bash scripts/verify-player-manual.sh
```

This manual integration can access Last.fm and its cover CDN. Automated tests never use real providers.
The generated tones use metadata for New Order's `Blue Monday` and `Bizarre Love Triangle`.
Override metadata with `PLAYER_FIRST_TITLE`, `PLAYER_FIRST_ARTIST`, `PLAYER_SECOND_TITLE`, and `PLAYER_SECOND_ARTIST` when necessary.
The browser receives the matching expected titles.
An album, tags, summary, and a fully loaded allowlisted cover are required.
The generated audio is not the named commercial recording.

Listen across the natural boundary in the audible windows without reloading.
Record the browser, date, device, and listening result in `specs/verifications/e05s01-verify.yaml`.
Retain `manual.passed: false` and `gaps.closed: false` until all required checks have evidence.
Do not treat historical API responses or screenshots as proof of uninterrupted audio.

El CI automático ejecuta las pruebas rápidas en cada PR. Las integraciones Docker de HLS y prioridad se ejecutan localmente antes de abrir o actualizar el PR; GitHub Actions las conserva como un workflow manual para la verificación final de una release.

## Estructura

```text
assets/js/                         reproductor HLS y pruebas
config/liquidsoap/radio.liq        emisión Liquidsoap
lib/nozomi_station/slack/           webhook y procesamiento asíncrono
lib/nozomi_station/media/           resolución y preparación de medios
lib/nozomi_station/requests/        cola persistente de solicitudes
lib/nozomi_station/programming/     mood, margen y despacho a Liquidsoap
lib/nozomi_station_web/live/        interfaz LiveView
scripts/                            verificaciones ejecutables
specs/                              alcance, epics, ADR y evidencias
```

## Próximos recorridos

1. Transiciones e interludios ferroviarios.
2. Reproductor público, chat y votación comunitaria.
3. Operación, recuperación y despliegue en VPS.
