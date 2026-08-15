# e06s01 — Conversar con una identidad ferroviaria

## 1. Business narrative
La radio comunitaria necesita presencia compartida además de música.
## 2. Actor
Oyente público sin cuenta.
## 3. Need
Conversar con un alias estable sin registrarse.
## 4. Outcome
Chat LiveView con alias ferroviario y últimos 50 mensajes.
## 5. Main flow
El navegador obtiene un alias local, entra al chat y publica mensajes visibles para todos.
## 6. Alternative flows
El oyente puede regenerar su alias.
## 7. Rules
Máximo 50 mensajes; límites de longitud, frecuencia y repetición.
## 8. Data
Alias, texto, fecha y relación opcional con canción actual.
## 9. Interfaces
LiveView y almacenamiento local del navegador.
## 10. Dependencies
Phoenix PubSub y persistencia del proyecto.
## 11. Security
Escapar texto; no aceptar HTML; aplicar límites en servidor.
## 12. Failure handling
Reconectar sin duplicar mensajes enviados.
## 13. Observability
Registrar rechazos sin almacenar contenido adicional.
## 14. Performance
Difundir mensajes sin consultar historiales mayores a 50.
## 15. Accessibility
Región anunciable, etiquetas y navegación por teclado.
## 16. Test approach
Pruebas LiveView de historial, publicación, alias y límites.
## 17. Acceptance criteria
```gherkin
Scenario: Enviar un mensaje
  Given un oyente con alias local
  When envía texto válido
  Then todos ven el mensaje con ese alias

Scenario: Exceso de frecuencia
  Given un oyente que supera el límite
  When intenta enviar otro mensaje
  Then el servidor lo rechaza sin afectar el chat
```
## 18. Out of scope
Cuentas, moderación manual y bloqueos persistentes.
## 19. Open questions
Los valores exactos de límites se calibrarán durante implementación.
## 20. Definition of done
El chat persiste solo 50 mensajes y aplica las tres protecciones acordadas.
