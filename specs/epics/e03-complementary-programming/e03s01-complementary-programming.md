# e03s01 — Mantener música sin solicitudes

## 1. Business narrative
La radio no puede depender de que Slack tenga solicitudes en todo momento.
## 2. Actor
Oyente público.
## 3. Need
Recibir música continua cuando la cola solicitada está vacía.
## 4. Outcome
Existe una cola complementaria de al menos 10 pistas listas.
## 5. Main flow
La radio usa rock/años 80 al inicio y luego deriva selecciones de las últimas 20 solicitudes.
## 6. Alternative flows
Una solicitud lista toma prioridad al terminar la canción actual.
## 7. Rules
Solo solicitudes alimentan el mood; una pista saltada nunca vuelve a la selección automática.
## 8. Data
Historial solicitado, tags, artistas relacionados, candidatas y estado de preparación.
## 9. Interfaces
Last.fm, YouTube y cola de emisión.
## 10. Dependencies
Requiere e01s01; aprovecha historial de e02s01 cuando existe.
## 11. Security
Validar respuestas externas y URLs antes de preparar contenido.
## 12. Failure handling
Descartar candidatas fallidas y continuar rellenando el margen.
## 13. Observability
Medir pistas listas, tiempo de preparación y fallos por fuente.
## 14. Performance
Mantener 10 pistas durante operación normal.
## 15. Accessibility
No aplica.
## 16. Test approach
Pruebas deterministas con proveedores simulados y flujo de prioridad.
## 17. Acceptance criteria
```gherkin
Scenario: Arranque vacío
  Given que no existe historial ni solicitudes
  When inicia la radio
  Then prepara al menos 10 canciones de rock o años 80

Scenario: Llega una solicitud
  Given que suena una canción complementaria
  When una solicitud queda lista
  Then termina la canción actual y reproduce la solicitud después
```
## 18. Out of scope
Análisis de tempo, energía o tonalidad.
## 19. Open questions
Ninguna.
## 20. Definition of done
La radio alterna entre ambas colas sin silencio y conserva el margen acordado.
