# e04s01 — Ambientar cambios y esperas con sonidos ferroviarios

## 1. Business narrative
La identidad ferroviaria debe formar parte de la escucha, no solo de la pantalla.
## 2. Actor
Oyente público.
## 3. Need
Escuchar transiciones coherentes y nunca un silencio técnico.
## 4. Outcome
Avisos, melodías y ambiente cubren cambios claros o esperas.
## 5. Main flow
Un cambio claro de género selecciona un clip y reduce la música durante la mezcla.
## 6. Alternative flows
Sin pista lista, se encadenan interludios distintos hasta recuperar música.
## 7. Rules
Máximo una transición temática cada cinco canciones; no repetir el mismo clip seguido.
## 8. Data
Catálogo de clips, género anterior, género siguiente y último uso.
## 9. Interfaces
Planificador y Liquidsoap.
## 10. Dependencies
Requiere e01s01 y clasificación de e03s01.
## 11. Security
Solo reproducir archivos locales preparados.
## 12. Failure handling
Un clip inválido se omite sin detener la emisión.
## 13. Observability
Registrar motivo, clip y duración de cada interludio.
## 14. Performance
La selección no bloquea el límite entre pistas.
## 15. Accessibility
No introducir picos de volumen; normalizar clips.
## 16. Test approach
Probar política de frecuencia y mezcla con catálogo fijo.
## 17. Acceptance criteria
```gherkin
Scenario: Cambio claro de género
  Given que no hubo interludio en las últimas cinco canciones
  When la programación cambia claramente de pop a rock
  Then mezcla un aviso ferroviario bajando temporalmente la música

Scenario: No hay pista lista
  Given que ninguna cola tiene audio reproducible
  When termina la pista actual
  Then encadena clips distintos hasta recuperar música
```
## 18. Out of scope
Resolver licencias de clips y crear múltiples paisajes visuales.
## 19. Open questions
El catálogo de clips se aportará antes de implementar esta historia.
## 20. Definition of done
Ambos escenarios se demuestran sin silencios ni repeticiones inmediatas.
