# e01s01 — Escuchar una emisión continua compartida

**type:** feat  
**risk:** P0  
**context:** infra

## 1. Business narrative
La radio necesita una señal común antes de añadir solicitudes o comunidad.

## 2. Actor
Oyente público en un navegador moderno.

## 3. Need
Entrar en una emisión compartida sin cuenta ni configuración previa.

## 4. Outcome
Una aplicación Phoenix sirve una emisión HLS continua producida por Liquidsoap.

## 5. Main flow
El oyente abre la página, pulsa «Subir al tren» y el reproductor se une al punto en vivo.

## 6. Alternative flows
Safari usa HLS nativo; los demás navegadores usan hls.js. Al finalizar una pista, Liquidsoap mantiene la señal sin silencio evitable.

## 7. Requirements
### ADDED: Emisión pública compartida
Todos los oyentes deben consumir el mismo manifiesto HLS AAC a 192 kbps, con 5–15 segundos de latencia y una diferencia máxima de 2 segundos entre clientes activos.

### ADDED: Inicio explícito
La reproducción debe comenzar solo después de activar el botón accesible «Subir al tren».

### ADDED: Motor privado
Liquidsoap debe ejecutarse sin root y su interfaz de control no debe publicarse fuera de la red interna.

## 8. Data
Estado efímero de emisión: activa/inactiva, título de fuente y URL pública del manifiesto. No se persiste catálogo en esta historia.

## 9. Interfaces
- `GET /`: LiveView público de radio.
- `GET /hls/live.m3u8`: manifiesto público.
- Volumen compartido: Liquidsoap escribe segmentos que Phoenix sirve como estáticos.

## 10. Dependencies
- `[OK]` Phoenix 1.8 / LiveView: interfaz y estado público.
- `[OK]` Liquidsoap 2.4.5: fuente, codificación y HLS.
- `[OK]` hls.js: reproducción en navegadores sin HLS nativo.
- `[OK]` Docker Compose: límite reproducible entre servicios.

No se introduce una abstracción de motor de audio: Phoenix conoce una URL HLS y Liquidsoap conoce un directorio de salida.

## 11. Security
Aplicar T1–T5 de `specs/security/epics/e01/THREAT_MODEL.md`: ningún puerto de control público, procesos sin shell, rutas locales acotadas, texto escapado y contenedor sin root.

## 12. Failure handling
Si el manifiesto aún no existe, la página muestra que la emisión está conectando y permite reintentar sin recargar.

## 13. Observability
Liquidsoap registra inicio y errores; Phoenix registra solicitudes del manifiesto sin incluir secretos.

## 14. Performance
El objetivo de 50 oyentes se valida en e08s01. Esta historia valida duración de segmento suficiente para mantener una deriva máxima de 2 segundos.

## 15. Accessibility
El CTA es operable con teclado, tiene nombre accesible y no se sustituye por reproducción automática.

## 16. Test approach
Un tracer bullet real atraviesa LiveView → HLS → Liquidsoap. Las pruebas unitarias cubren estado y hook; scripts sin fixtures con copyright cubren manifiesto y sincronización.

## 17. Acceptance criteria
```gherkin
Scenario: Entrar a la emisión
  Given que Liquidsoap está publicando HLS
  When un oyente pulsa «Subir al tren»
  Then el reproductor se conecta al punto en vivo

Scenario: El manifiesto aún no existe
  Given que Liquidsoap todavía está iniciando
  When un oyente abre la radio
  Then ve el estado «Conectando» y puede reintentar sin recargar

Scenario: Dos oyentes escuchan en vivo
  Given dos clientes conectados al mismo manifiesto
  When ambos reproducen la emisión
  Then su diferencia temporal no supera 2 segundos
```

## 18. Out of scope
Solicitudes, catálogo musical, chat, diseño Neo-Tokyo, recuperación tras reinicio y carga de 50 oyentes.

## 19. Open questions
Ninguna bloqueante. La primera fuente será un tono o archivo generado localmente, no música de terceros.

## 20. Definition of done
Los cuatro comandos `verify` de `e01s01-tasks.yaml` pasan; Liquidsoap no publica controles y la demostración manual reproduce HLS en dos clientes.

### Implementation steps
1. Crear Phoenix/LiveView y el primer test de la página pública → verify: `mix test test/nozomi_station_web/live/radio_live_test.exs`
2. Añadir Liquidsoap y la verificación HLS segura (ref: ADR-0001) → verify: `bash scripts/verify-liquidsoap-hls.sh`
3. Conectar el reproductor HLS mediante un hook mínimo → verify: `mix test test/nozomi_station_web/live/radio_live_test.exs && npm test -- --run assets/js/radio_player.test.js`
4. Medir continuidad y sincronización → verify: `bash scripts/verify-hls-sync.sh`

### Manual verification
1. Iniciar los servicios con Docker Compose.
2. Abrir la radio en dos ventanas.
3. Pulsar «Subir al tren» en ambas.
4. Confirmar audio continuo y una diferencia máxima perceptible de dos segundos.
