# Nozomi Station

[![CI](https://github.com/Javendanon/nozomi-station/actions/workflows/test-build-release.yml/badge.svg)](https://github.com/Javendanon/nozomi-station/actions/workflows/test-build-release.yml)

Radio comunitaria inspirada en el Shinkansen. Todos los oyentes comparten una emisión HLS continua y sincronizada, servida mediante Phoenix LiveView y producida por Liquidsoap.

## Estado

El primer recorrido funcional está listo: Liquidsoap emite audio AAC a 192 kbps, Phoenix publica el manifiesto HLS y el navegador se conecta mediante HLS nativo o `hls.js`.

La fuente actual es un tono de prueba de 440 Hz. La programación musical, las solicitudes desde Slack, el chat y las herramientas de operación se incorporarán en los siguientes epics.

## Arquitectura

```text
Liquidsoap ──escribe──> priv/static/hls ──sirve──> Phoenix ──HLS──> navegador
```

- **Phoenix LiveView** presenta la radio y su estado.
- **Liquidsoap** controla la emisión continua y genera segmentos HLS.
- **hls.js** cubre los navegadores sin soporte HLS nativo.
- **Docker Compose** ejecuta Liquidsoap sin publicar puertos y sin privilegios de root.

## Requisitos

- Elixir 1.15 o posterior y Erlang/OTP compatible
- Node.js 22
- Docker con Compose
- FFmpeg, solo para ejecutar la verificación completa de HLS

## Inicio local

```bash
git clone git@github.com:Javendanon/nozomi-station.git
cd nozomi-station
npm ci --prefix assets
mix setup
mkdir -p priv/static/hls
LIQUIDSOAP_UID="$(id -u)" LIQUIDSOAP_GID="$(id -g)" docker compose up -d liquidsoap
mix phx.server
```

Abre [http://localhost:4000](http://localhost:4000) y pulsa **Subir al tren**. El navegador requiere una acción explícita antes de reproducir audio.

Para detener Liquidsoap:

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
lib/nozomi_station_web/live/       interfaz LiveView
scripts/                            verificaciones ejecutables
specs/                              alcance, epics, ADR y evidencias
```

## Próximos recorridos

1. Solicitudes de canciones desde Slack.
2. Programación complementaria y transiciones ferroviarias.
3. Reproductor público, chat y votación comunitaria.
4. Operación, recuperación y despliegue en VPS.
