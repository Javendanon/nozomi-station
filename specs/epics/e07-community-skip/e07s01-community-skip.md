# e07s01 — Saltar una canción por mayoría

## 1. Business narrative
La comunidad necesita corregir una canción no deseada sin administrador.
## 2. Actor
Oyente activo con audio iniciado.
## 3. Need
Votar una vez para avanzar la emisión.
## 4. Outcome
La mayoría estable salta la canción actual.
## 5. Main flow
El primer voto congela oyentes activos y calcula floor(n/2)+1; al alcanzarlo se avanza.
## 6. Alternative flows
Los votos insuficientes caducan al cambiar de canción.
## 7. Rules
Un voto por identidad local; solo oyentes activos cuentan.
## 8. Data
Pista, identidad, base congelada, umbral y votos.
## 9. Interfaces
Reproductor LiveView y planificador.
## 10. Dependencies
Requiere e01s01 y presencia pública.
## 11. Security
No confiar en conteos enviados por el cliente; aceptar la limitación de identidades locales.
## 12. Failure handling
Procesar el salto una sola vez aunque lleguen votos concurrentes.
## 13. Observability
Registrar base, umbral y resultado sin identificar personas.
## 14. Performance
Actualizar el conteo en tiempo real para 50 oyentes.
## 15. Accessibility
Botón y estado de votación anunciables.
## 16. Test approach
Pruebas de concurrencia, umbral y cambio de canción.
## 17. Acceptance criteria
```gherkin
Scenario: Se alcanza la mayoría
  Given una base congelada de 4 oyentes activos
  When llega el tercer voto único
  Then la radio salta la canción una sola vez

Scenario: Cambia la canción sin mayoría
  Given una votación incompleta
  When comienza otra canción
  Then los votos anteriores se eliminan
```
## 18. Out of scope
Protección fuerte contra múltiples navegadores.
## 19. Open questions
Ninguna.
## 20. Definition of done
El voto controla la emisión y una canción saltada queda fuera del mood automático.
