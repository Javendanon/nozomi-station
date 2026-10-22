# Nozomi Station

[![CI](https://github.com/Javendanon/nozomi-station/actions/workflows/test-build-release.yml/badge.svg)](https://github.com/Javendanon/nozomi-station/actions/workflows/test-build-release.yml)

Radio comunitaria inspirada en el Shinkansen. Todos los oyentes comparten una emisión HLS continua y sincronizada, servida mediante Phoenix LiveView y producida por Liquidsoap.

## Status

Liquidsoap broadcasts continuous AAC audio at 192 kbps. Phoenix serves HLS, and browsers connect through native HLS or `hls.js`.

Slack accepts, validates, and prepares requests. Complementary programming keeps ten tracks ready from Last.fm and YouTube. Liquidsoap prioritizes requests at track boundaries and retains a 440 Hz fallback tone.

### e05 integrated

[PR #4](https://github.com/Javendanon/nozomi-station/pull/4) merged into `main` on October 22, 2026, at 16:47:32 UTC ([`de95fe6`](https://github.com/Javendanon/nozomi-station/commit/de95fe690e58413beb8721ad02d923d358c9fc2a)). [Post-merge CI passed](https://github.com/Javendanon/nozomi-station/actions/runs/39817023268).

The five completed tasks deliver synchronized current-track metadata, optional Last.fm details, the provisional Neo-Tokyo scene, Slack listener messages, and local volume control. The [e05 capsule](specs/epics/archive/e05-live-player/epic.yaml) is archived, like e01–e03.

Integration does not prove completion of the remaining manual checks. Desktop/mobile review, a natural track boundary, two windows, reduced motion, and real Last.fm browser rendering still lack recorded completion. See [verification evidence](specs/verifications/e05s01-verify.yaml).

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

La integración HLS comprueba el códec, la continuidad del manifiesto y que dos clientes simultáneos compartan la misma ventana de emisión.

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

## Resume point

Resume with [e08s01 — operations and recovery](specs/epics/e08-operations/e08s01-operations.md), next by WSJF in the [release plan](specs/release-plan.yaml). It remains `todo`. Do not reimplement e05.

The e08 recovery and load scripts (`scripts/verify-radio-recovery.sh` and `scripts/load-test-radio.sh`) do not exist yet. They are pending deliverables, not executable verification evidence. The same rule applies to future test/script files marked for creation.

After e08, the planned order is e07 community voting, e06 public chat, then e04 railway transitions.
