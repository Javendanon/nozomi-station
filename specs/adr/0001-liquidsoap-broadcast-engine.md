# ADR-0001: Liquidsoap controla la emisión

## Estado

Aceptado.

## Razón de existir

Fijar el límite entre la aplicación Elixir y el motor de audio antes de dividir el trabajo.

## Contexto

Nozomi Station necesita colas dinámicas, respaldo continuo, crossfade, interludios y salida HLS. Construir estas funciones directamente con procesos FFmpeg añadiría coordinación, recuperación y continuidad de segmentos propias.

## Decisión

- **Phoenix/LiveView** controla solicitudes, catálogo, chat, votos y estado público.
- **Liquidsoap 2.4.5** controla reproducción, fallback, crossfade, mezcla de interludios y salida HLS AAC.
- **Oban** ejecuta preparación persistente de medios y reintentos.
- **yt-dlp** descarga audio como proceso externo; Liquidsoap no descarga fuentes públicas.
- Phoenix entrega a Liquidsoap solo archivos locales validados y metadatos de reproducción.

## Límites

- Nunca implementar un segundo planificador de audio dentro de Phoenix.
- Nunca permitir que una descarga bloquee la emisión.
- Nunca exponer la interfaz de control de Liquidsoap a internet.
- El estado durable de solicitudes vive en PostgreSQL; los archivos de audio son temporales.

## Consecuencias

- Se elimina la mayor parte de la orquestación FFmpeg propia.
- Liquidsoap se convierte en un proceso obligatorio del despliegue.
- La recuperación debe reconciliar PostgreSQL con el estado activo de Liquidsoap.
- Las pruebas del límite Phoenix–Liquidsoap requieren un proceso real en integración.

## Alternativa rechazada

**Elixir + FFmpeg directo:** ofrece control total, pero obliga a construir colas, fallback, mezcla y continuidad HLS que Liquidsoap ya resuelve.

## Verificación

```bash
test -f specs/adr/0001-liquidsoap-broadcast-engine.md && \
  grep -q 'Nunca implementar un segundo planificador' specs/adr/0001-liquidsoap-broadcast-engine.md
```

## Siguiente paso

Crear primero un tracer bullet: una canción local entra a Liquidsoap y dos navegadores reciben el mismo HLS.
