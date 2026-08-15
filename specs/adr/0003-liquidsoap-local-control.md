# ADR-0003: Liquidsoap recibe colas por control TCP local

## Estado

Aceptado.

## Contexto

Phoenix conserva solicitudes y pistas preparadas, pero ADR-0001 exige que Liquidsoap sea el único planificador de audio. Los archivos locales deben entrar en colas dinámicas y las solicitudes deben tener prioridad en límites de pista.

Un socket UNIX sería privado, pero los sockets sobre bind mounts no son portables en Docker Desktop. Una lista M3U observada no ofrece semántica FIFO ni reconciliación fiable.

## Decisión

Liquidsoap expone su servidor de control sin autenticación dentro del contenedor y Docker publica el puerto únicamente en `127.0.0.1`. Phoenix usa Erlang `:gen_tcp` con timeout y una lista fija de comandos para alimentar dos `request.queue`:

1. `requested`
2. `complementary`

Liquidsoap aplica prioridad mediante un `fallback(track_sensitive=true, ...)`. Otro fallback no sensible a pista usa el tono de prueba solo cuando ambas colas están vacías.

PostgreSQL conserva el estado durable. El planificador consulta los request IDs activos de Liquidsoap y reconcilia pistas `queued` antes de rellenar el margen.

## Consecuencias

- El puerto de control no puede publicarse en una interfaz externa.
- Las rutas de Phoenix deben traducirse al montaje `/media` de Liquidsoap.
- Una caída de control deja elementos `ready` y permite reintento.
- La recuperación exacta después de reiniciar Liquidsoap permanece en e08.
- No se añade `socat`, SDK ni proceso planificador propio.

## Alternativas rechazadas

- **Socket UNIX en bind mount:** no funciona de forma portable en Docker Desktop.
- **M3U observada:** semántica de actualización y FIFO insuficiente.
- **Phoenix decide el audio actual:** viola ADR-0001 y duplica el planificador.
