---
type: feat
risk: P0
context: infra
story_id: e03s01
epic_id: e03
delta: ADDED
adrs:
  - specs/adr/0001-liquidsoap-broadcast-engine.md
  - specs/adr/0003-liquidsoap-local-control.md
---

# e03s01 — Mantener música sin solicitudes

## Outcome

La emisión mantiene diez pistas complementarias preparadas. Las solicitudes listas toman prioridad únicamente al terminar la pista musical actual.

## Scope

### Included

- Persistir pistas complementarias y sus estados de preparación, cola, reproducción, fallo y salto.
- Usar `rock` y `80s` como semillas cuando no exista historial.
- Derivar recomendaciones únicamente de las últimas veinte solicitudes reproducibles y no saltadas.
- Consultar Last.fm en un host HTTPS fijo y validar cada candidata mediante YouTube antes de descargarla.
- Mantener diez pistas complementarias preparadas o encoladas durante operación normal.
- Entregar archivos locales a dos `request.queue` de Liquidsoap mediante su puerto de control ligado a loopback.
- Reconciliar elementos ya reproducidos para que el margen pueda rellenarse.
- Mantener el tono de prueba como último respaldo, sin convertir Phoenix en un segundo planificador de audio.

### Excluded

- Tempo, energía, tonalidad, aprendizaje automático o perfiles por usuario.
- Recuperación completa del estado interno de Liquidsoap después de una caída; pertenece a e08.
- Crossfade e interludios ferroviarios; pertenecen a e04.
- Marcar una pista como saltada desde votos; e07 usará el estado que esta historia define.

## Rules

1. `rock` y `80s` son las únicas semillas sin historial.
2. El mood usa como máximo veinte solicitudes con estado `ready`, `queued` o `played`; omite `failed` y `skipped`.
3. Una pista complementaria con estado `skipped` nunca vuelve a seleccionarse.
4. Una candidata debe resolver a YouTube, no ser un directo y durar como máximo quince minutos.
5. El margen cuenta pistas `preparing`, `ready` y `queued`.
6. La cola solicitada precede a la complementaria en Liquidsoap; el cambio es sensible al final de pista.
7. El control de Liquidsoap nunca se publica fuera de `127.0.0.1`.
8. Una candidata fallida no impide probar la siguiente.

## Data

`complementary_tracks` conserva `youtube_id`, título, artista, duración, archivo local, origen (`seed` o `mood`) y estado. `requests` amplía sus estados activos con `queued`.

## Interfaces

- Last.fm `tag.gettoptracks` para semilla y `track.getsimilar` para mood.
- YouTube Data API y `yt-dlp` existentes.
- Servidor de control de Liquidsoap por TCP local.
- Oban Cron para reposición y despacho periódicos.

## Failure handling

- Last.fm, YouTube o yt-dlp fallidos dejan evidencia y continúan con otras candidatas.
- Un control Liquidsoap no disponible conserva la pista como `ready` para el siguiente intento.
- Una respuesta de control malformada falla cerrada y no cambia el estado durable.

## Observability

Registrar margen disponible, pistas preparadas, candidatas descartadas, despachos por cola y fallos de control. Nunca registrar tokens ni cuerpos completos de proveedores.

## Performance

- Objetivo: diez pistas complementarias preparadas o encoladas.
- Last.fm, YouTube y Liquidsoap tienen timeout explícito.
- La reposición se ejecuta fuera de peticiones web.

## Acceptance criteria

```gherkin
Scenario: Arranque vacío
  Given que no existe historial ni solicitudes
  When se ejecuta la reposición
  Then usa únicamente las semillas rock y 80s
  And deja al menos diez pistas complementarias preparadas o encoladas

Scenario: Mood reciente
  Given más de veinte solicitudes y algunas saltadas
  When se deriva el mood
  Then usa solo las veinte solicitudes reproducibles más recientes no saltadas

Scenario: Llega una solicitud
  Given que suena una canción complementaria
  When una solicitud queda lista
  Then Liquidsoap termina la canción actual
  And reproduce la solicitud antes de otra canción complementaria

Scenario: Proveedor falla
  Given una candidata no resoluble
  When se rellena el margen
  Then descarta esa candidata
  And continúa con las siguientes
```

## Test approach

- Pruebas SQL Sandbox para margen, deduplicación, fallos y mood de veinte elementos.
- Pruebas deterministas del cliente Last.fm con funciones Req simuladas.
- Pruebas del planificador con un cliente Liquidsoap simulado.
- Verificación real de sintaxis Liquidsoap, control ligado a loopback y no regresión HLS.

## Supply chain

- `[OK]` Last.fm API: HTTP directo mediante Req ya instalado; no se añade SDK.
- `[OK]` Oban Cron: plugin incluido en Oban ya instalado.
- `[OK]` Liquidsoap `request.queue`: capacidad nativa de la versión fijada 2.4.5.
- `[OK]` Erlang `:gen_tcp`: biblioteca estándar para el control local.

## Definition of done

Las pruebas, cobertura, auditoría de seguridad, verificación HLS y una prueba de prioridad de colas pasan. La configuración real no expone el control fuera del host.
