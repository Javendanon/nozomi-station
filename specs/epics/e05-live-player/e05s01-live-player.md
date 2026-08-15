# e05s01 — Subir al tren y ver la canción actual

## 1. Business narrative
La emisión necesita una experiencia visual reconocible y útil.
## 2. Actor
Oyente público en escritorio o móvil.
## 3. Need
Entrar en vivo y entender qué está sonando.
## 4. Outcome
Reproductor LiveView con viaje Neo-Tokyo, onda e información musical.
## 5. Main flow
El oyente abre la web, pulsa el botón y ve la canción sincronizada con la emisión.
## 6. Alternative flows
Las secciones sin datos o letras se ocultan.
## 7. Rules
Un video en bucle; colores derivados de portada; HLS nativo o hls.js.
## 8. Data
Canción, artista, álbum, portada, año, géneros, reseña, relacionados y letras.
## 9. Interfaces
LiveView, HLS y proveedores de metadatos.
## 10. Dependencies
Requiere e01s01.
## 11. Security
Escapar contenido externo y restringir recursos remotos admitidos.
## 12. Failure handling
Un fallo visual o de metadatos nunca detiene el audio.
## 13. Observability
Registrar errores de reproducción y actualización de estado.
## 14. Performance
Evitar descargar el video repetidamente y limitar trabajo visual.
## 15. Accessibility
Controles por teclado, texto visible y respeto a movimiento reducido.
## 16. Test approach
Pruebas LiveView y verificación del hook del reproductor.
## 17. Acceptance criteria
```gherkin
Scenario: Subir al tren
  Given que existe una emisión activa
  When el oyente pulsa el botón principal
  Then escucha en vivo y ve la canción actual

Scenario: Faltan letras
  Given que la canción no tiene letras disponibles
  When se actualiza el reproductor
  Then la sección de letras permanece oculta y el audio continúa
```
## 18. Out of scope
Aplicación nativa, más fondos y escena 3D.
## 19. Open questions
El video final se aportará antes del cierre visual.
## 20. Definition of done
Los flujos funcionan en navegadores modernos de escritorio y móvil.
