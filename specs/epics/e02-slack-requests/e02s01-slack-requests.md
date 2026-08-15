# e02s01 — Solicitar canciones desde Slack

## 1. Business narrative
La comunidad decide la programación mediante enlaces enviados en Slack.
## 2. Actor
Miembro del canal configurado.
## 3. Need
Solicitar música sin salir de Slack.
## 4. Outcome
Cada enlace válido queda confirmado y listo para reproducirse.
## 5. Main flow
Slack entrega el evento, la radio confirma, resuelve, valida y encola los enlaces en orden.
## 6. Alternative flows
Spotify se empareja con YouTube; enlaces inválidos reciben error en hilo.
## 7. Rules
Sin cuotas; máximo 15 minutos; no directos; duplicados pendientes o en últimas 10 se descartan.
## 8. Data
Evento, solicitante, URL, metadatos, estado y posición.
## 9. Interfaces
Slack Events API, Spotify, YouTube y cola de radio.
## 10. Dependencies
La emisión e01s01 debe aceptar archivos preparados.
## 11. Security
Verificar firma y antigüedad de eventos; procesar cada event_id una vez.
## 12. Failure handling
Responder rápido y procesar fuera de la petición; reintentar fallos transitorios.
## 13. Observability
Registrar evento, resolución, descarga, rechazo y posición.
## 14. Performance
Responder a Slack en menos de tres segundos.
## 15. Accessibility
No aplica a la interfaz de Slack.
## 16. Test approach
Pruebas de firma, idempotencia, resolución y flujo completo.
## 17. Acceptance criteria
```gherkin
Scenario: Solicitud válida
  Given un mensaje del canal con enlaces admitidos
  When Slack entrega el evento
  Then el bot confirma cada canción no duplicada en el hilo

Scenario: Enlace no reproducible
  Given un enlace directo o mayor de 15 minutos
  When se procesa el mensaje
  Then el bot informa el rechazo y no lo encola
```
## 18. Out of scope
Solicitudes web, moderación y cuotas por usuario.
## 19. Open questions
Las credenciales se aportarán antes de la integración real.
## 20. Definition of done
Un evento firmado produce una pista preparada y visible en la cola.
