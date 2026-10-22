FROM node:22-bookworm-slim AS assets
WORKDIR /assets
COPY assets/package.json assets/package-lock.json ./
RUN npm ci --ignore-scripts

FROM elixir:1.18.4-otp-28-slim AS builder
RUN apt-get update && apt-get install -y --no-install-recommends build-essential git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
COPY config/config.exs config/prod.exs config/
RUN mix deps.get --only prod && mix deps.compile
COPY assets assets
COPY --from=assets /assets/node_modules assets/node_modules
COPY priv priv
COPY lib lib
RUN mix compile && mix assets.deploy
COPY config/runtime.exs config/runtime.exs
RUN mix release

FROM debian:trixie-slim AS runner
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl libstdc++6 libssl3t64 libncurses6 locales ffmpeg yt-dlp \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen \
    && groupadd --gid 1000 nozomi && useradd --uid 1000 --gid 1000 --create-home nozomi
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    PHX_SERVER=true PORT=4000 RELEASE_DISTRIBUTION=none RELEASE_TMP=/tmp/nozomi
WORKDIR /app
COPY --from=builder --chown=nozomi:nozomi /app/_build/prod/rel/nozomi_station ./
USER nozomi
EXPOSE 4000
CMD ["bin/nozomi_station", "start"]
