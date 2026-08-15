# Nozomi Station

[![CI](https://github.com/Javendanon/nozomi-station/actions/workflows/test-build-release.yml/badge.svg)](https://github.com/Javendanon/nozomi-station/actions/workflows/test-build-release.yml)

Radio comunitaria inspirada en el Shinkansen. Todos los oyentes comparten una emisión HLS continua y sincronizada, servida mediante Phoenix LiveView y producida por Liquidsoap.

## Estado

El primer recorrido funcional está listo: Liquidsoap emite audio AAC a 192 kbps, Phoenix publica el manifiesto HLS y el navegador se conecta mediante HLS nativo o `hls.js`.

La fuente actual es un tono de prueba de 440 Hz. Slack ya acepta, valida, prepara y encola solicitudes; su conexión con Liquidsoap, la programación musical, el chat y las herramientas de operación pertenecen a los siguientes recorridos.

## Arquitectura

```text
Slack ──evento firmado──> Phoenix ──Oban/PostgreSQL──> resolución y preparación
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
mkdir -p priv/static/hls
LIQUIDSOAP_UID="$(id -u)" LIQUIDSOAP_GID="$(id -g)" docker compose up -d liquidsoap
mix phx.server
```

Abre [http://localhost:4000](http://localhost:4000) y pulsa **Subir al tren**. El navegador requiere una acción explícita antes de reproducir audio.

## Configuración de Slack

La integración necesita una app de Slack suscrita al endpoint `POST /slack/events` y credenciales de Spotify y YouTube:

```bash
export SLACK_SIGNING_SECRET="..."
export SLACK_BOT_TOKEN="xoxb-..."
export SLACK_CHANNEL_ID="C..."
export SPOTIFY_CLIENT_ID="..."
export SPOTIFY_CLIENT_SECRET="..."
export YOUTUBE_API_KEY="..."
```

No guardes estas variables en el repositorio. En producción también son obligatorios `DATABASE_URL` y `SECRET_KEY_BASE`.

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
```

La integración HLS comprueba el códec, la continuidad del manifiesto y que dos clientes simultáneos compartan la misma ventana de emisión.

En CI, estas comprobaciones solo se ejecutan cuando un PR modifica Liquidsoap, HLS o el reproductor. También pueden lanzarse manualmente desde GitHub Actions.

## Estructura

```text
assets/js/                         reproductor HLS y pruebas
config/liquidsoap/radio.liq        emisión Liquidsoap
lib/nozomi_station/slack/           webhook y procesamiento asíncrono
lib/nozomi_station/media/           resolución y preparación de medios
lib/nozomi_station/requests/        cola persistente de solicitudes
lib/nozomi_station_web/live/        interfaz LiveView
scripts/                            verificaciones ejecutables
specs/                              alcance, epics, ADR y evidencias
```

## Próximos recorridos

1. Solicitudes de canciones desde Slack.
2. Programación complementaria y transiciones ferroviarias.
3. Reproductor público, chat y votación comunitaria.
4. Operación, recuperación y despliegue en VPS.
