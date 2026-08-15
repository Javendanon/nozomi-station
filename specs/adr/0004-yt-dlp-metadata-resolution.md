# ADR-0004: yt-dlp resuelve búsqueda, metadatos y audio de YouTube

## Estado

Aceptado.

## Contexto

Nozomi usaba YouTube Data API para buscar y validar candidatos, y luego ejecutaba yt-dlp para preparar audio. Esto exigía una API key adicional, duplicaba integraciones y consumía cuota de búsqueda.

El proyecto local `deejai` ya demostró el uso operativo de yt-dlp con una cookie jar opcional para bloqueos anti-bot. El propietario pidió reutilizar ese enfoque y eliminar la API key.

## Decisión

- yt-dlp ejecuta `ytsearch1:` para buscar una candidata.
- yt-dlp entrega JSON para identificador, título, artista, duración y estado de directo.
- El Resolver conserva la validación de quince minutos y rechaza directos.
- El mismo `YTDLP_COOKIES_FILE` se aplica a metadatos y preparación.
- `youtube:player_client=mweb` es el cliente extractor predeterminado probado; `YTDLP_EXTRACTOR_ARGS` permite reemplazarlo sin cambiar código.
- Desarrollo detecta `cookies/cookies.txt`; el directorio completo está ignorado por Git.
- Spotify y Last.fm conservan sus APIs actuales.
- Nozomi no configura ni requiere `YOUTUBE_API_KEY`.

## Seguridad

- yt-dlp recibe vectores de argumentos, nunca una shell.
- IDs de YouTube se validan antes de construir URLs.
- Las búsquedas se prefijan con `ytsearch1:` y se limitan a 500 bytes.
- La cookie jar permanece fuera de Git y usa permisos `0600` localmente.
- JSON ausente o malformado falla cerrado.

## Consecuencias

- Se elimina cuota, credencial y cliente HTTP de YouTube Data API.
- Búsqueda y metadatos dependen de la compatibilidad de yt-dlp con YouTube.
- Una cookie expirada puede ser peor que acceso anónimo; quitar `YTDLP_COOKIES_FILE` permite el fallback anónimo.
- Las llamadas siguen fuera de peticiones web bajo Oban.

## Alternativa rechazada

Mantener YouTube Data API solo para metadatos: añade configuración y cuota sin aportar una capacidad que yt-dlp no entregue ya en este producto.
