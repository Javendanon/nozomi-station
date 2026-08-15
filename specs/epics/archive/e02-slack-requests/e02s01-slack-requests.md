# e02s01 — Solicitar canciones desde Slack

**type:** feat
**risk:** P0
**context:** infra

## 1. Business narrative

La comunidad decide la programación mediante enlaces enviados en el canal configurado de Slack.

## 2. Actor

Miembro del canal de Slack configurado.

## 3. Need

Solicitar música sin salir de Slack.

## 4. Outcome

Cada enlace válido queda confirmado, preparado y disponible en una cola FIFO persistente.

## 5. Main flow

Slack entrega un evento firmado. Phoenix lo registra una sola vez, responde de inmediato y delega el trabajo a Oban. El trabajo resuelve, valida, prepara, deduplica y confirma cada enlace en orden.

## 6. Alternative flows

Un enlace de Spotify se empareja con el primer resultado disponible de YouTube. Los enlaces inválidos, directos, largos o duplicados reciben una respuesta de rechazo en el hilo.

## 7. Requirements

### ADDED: recepción autenticada e idempotente

El endpoint acepta únicamente eventos con firma Slack válida y antigüedad máxima de cinco minutos. Cada `event_id` se registra una sola vez y recibe una respuesta HTTP antes del trabajo externo.

### ADDED: resolución limitada a proveedores

Solo se admiten URLs HTTPS de Spotify y YouTube. Spotify aporta metadatos; YouTube aporta el medio reproducible. Ningún host controlado por el usuario llega directamente al cliente HTTP.

### ADDED: preparación y cola

Las pistas de máximo 15 minutos que no sean directos se preparan como archivos temporales y entran en orden FIFO. Se rechazan duplicados pendientes, listos o presentes entre las últimas diez reproducidas.

### ADDED: confirmación en Slack

Cada enlace produce una respuesta en el hilo con título, estado de aceptación o rechazo y posición cuando corresponda.

## 8. Data

Evento Slack, solicitante, URL, proveedor, identificador YouTube, metadatos, estado, ruta temporal y posición.

## 9. Interfaces

Slack Events API, Slack Web API, Spotify Web API, YouTube Data API, `yt-dlp`, PostgreSQL y la futura fuente de solicitudes de Liquidsoap.

## 10. Dependencies

La emisión e01s01 sigue aislada. e03s01 consumirá la cola de archivos preparados. PostgreSQL y `yt-dlp` son nuevos requisitos operativos.

## 11. Security

Aplican `specs/security/epics/e02/THREAT_MODEL.md`: firma sobre cuerpo crudo, comparación constante, protección contra replay, hosts fijos, argumentos sin shell y rutas generadas internamente.

## 12. Failure handling

El endpoint confirma rápido. Oban reintenta fallos transitorios con límites. Errores permanentes de validación se notifican y no se reintentan.

## 13. Observability

Registrar identificadores de evento y solicitud, proveedor, transición de estado y posición. No registrar cuerpos completos, firmas, tokens ni rutas internas en respuestas públicas.

## 14. Performance

Responder a Slack en menos de tres segundos. Toda llamada externa y preparación ocurre fuera de la petición.

## 15. Accessibility

No aplica a la interfaz de Slack.

## 16. Test approach

Pruebas de firma, replay, idempotencia concurrente, allowlist de proveedores, duración, directos, deduplicación, rutas seguras y flujo completo con límites externos falsos.

La prueba no requiere credenciales reales. Un smoke test real queda disponible cuando se configuren Slack, Spotify, YouTube y `yt-dlp`.

## 17. Acceptance criteria

```gherkin
Scenario: Solicitud válida
  Given un mensaje firmado del canal con enlaces admitidos
  When Slack entrega el evento
  Then el endpoint responde antes del procesamiento
  And cada canción no duplicada se prepara y confirma en el hilo

Scenario: Evento repetido
  Given un event_id ya registrado
  When Slack vuelve a entregarlo
  Then responde correctamente sin crear otro trabajo

Scenario: Enlace no reproducible
  Given un enlace directo o mayor de 15 minutos
  When se procesa el mensaje
  Then el bot informa el rechazo y no lo encola
```

## 18. Out of scope

Solicitudes web, moderación, cuotas por usuario, conexión de la cola a Liquidsoap y recuperación operativa completa de archivos.

## 19. Open questions

Las credenciales reales y el identificador del canal se aportarán antes del smoke test contra Slack. La implementación falla de forma controlada cuando no están configurados.

## 20. Definition of done

Un evento firmado de prueba produce una pista preparada y visible en la cola; los límites externos están probados sin red y los comandos de verificación son reproducibles.

## Implementation steps

1. Añadir PostgreSQL, Ecto y Oban `[OK]`; registrar eventos con restricción única y verificar la firma Slack sobre el cuerpo crudo (ref: ADR-0002) → verify: `mix test test/nozomi/slack/events_test.exs`
2. Añadir Req `[OK]` y resolver únicamente identificadores Spotify/YouTube mediante hosts API fijos; parsear duración ISO-8601 sin otra dependencia → verify: `mix test test/nozomi/media/resolver_test.exs`
3. Ejecutar `yt-dlp` `[OK]` sin shell, con tiempo límite y rutas internas; deduplicar y persistir solicitudes FIFO → verify: `mix test test/nozomi/requests/request_flow_test.exs`
4. Procesar el evento con Oban, responder en hilo y demostrar el flujo completo con límites falsos (ref: ADR-0002) → verify: `mix test test/nozomi/slack/request_worker_test.exs`
5. Documentar variables, PostgreSQL y `yt-dlp`; mantener intactas la radio y la integración HLS → verify: `mix precommit && npm --prefix assets test -- js/radio_player.test.mjs`

## Reason for depth

PostgreSQL y Oban evitan implementar de nuevo persistencia, exclusión idempotente y reintentos; cada módulo restante representa un límite externo o una regla de dominio que necesita pruebas aisladas.

## Slopcheck

- Ecto SQL, Postgrex y Oban: `[OK]`, mantenidos y necesarios para la decisión ADR-0002.
- Req: `[OK]`, cliente HTTP recomendado por las convenciones Phoenix del repositorio.
- yt-dlp: `[OK]`, proceso externo adoptado en el alcance; no se reimplementa extracción multimedia.
