# e08s01 — Mantener y recuperar la radio pública

## 1. Business narrative
Una radio 24/7 no está terminada si requiere intervención después de cada fallo.
## 2. Actor
Oyente público y operador del VPS.
## 3. Need
Conservar la emisión y almacenamiento bajo control.
## 4. Outcome
Despliegue recuperable, observable y validado con 50 oyentes.
## 5. Main flow
Los servicios arrancan, restauran estado y publican la emisión detrás del proxy/CDN.
## 6. Alternative flows
Después de un reinicio se retoma cerca del punto persistido; los temporales usados se eliminan.
## 7. Rules
No exponer controles internos; no conservar biblioteca permanente.
## 8. Data
Estado de reproducción, salud, métricas y rutas temporales.
## 9. Interfaces
VPS, contenedores, proxy/CDN y endpoints de salud.
## 10. Dependencies
Requiere las historias necesarias para una emisión representativa.
## 11. Security
Secretos fuera del repositorio, TLS público y servicios internos aislados.
## 12. Failure handling
Reinicios automáticos, reintentos acotados y fallback audible.
## 13. Observability
Salud de Phoenix, Liquidsoap, colas, disco y emisión.
## 14. Performance
50 oyentes, diferencia máxima de 2 s y latencia de 5–15 s.
## 15. Accessibility
No aplica a operación; la página conserva requisitos de e05s01.
## 16. Test approach
Prueba de reinicio, limpieza, salud y carga.
## 17. Acceptance criteria
```gherkin
Scenario: Reinicio durante una canción
  Given una emisión activa
  When se reinician los servicios
  Then la radio vuelve cerca del punto anterior sin intervención

Scenario: Carga inicial
  Given 50 oyentes simulados
  When consumen la emisión simultáneamente
  Then permanecen dentro de 2 segundos sin degradar la aplicación
```
## 18. Out of scope
Alta disponibilidad multirregión y garantía superior a 50 oyentes.
## 19. Open questions
Proveedor de VPS, dominio y CDN se elegirán antes del despliegue.
## 20. Definition of done
Las verificaciones de recuperación, carga, seguridad básica y limpieza pasan en el VPS.
