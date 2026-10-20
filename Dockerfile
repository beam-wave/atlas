# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the builder image
#     E.g.: docker.io/hexpm/elixir:1.17.2-erlang-27.1-debian-trixie-20260610-slim
#   - https://hub.docker.com/_/debian/tags?name=trixie-20260610-slim - for the runner image
#     E.g.: docker.io/debian:trixie-20260610-slim
#
# Find builder and runner images on Docker Hub or on Hex's Build Server (Bob).
# We recommend using Bob's Web UI to find recent tags:
#
#   - https://bob.hex.pm/docker?repo=hexpm/elixir&os=debian&sort=elixir_version,erlang_version,os_version
#
# We suggest using the same Debian version for both the builder and runner images.
#
# We suggest Debian/Ubuntu instead of Alpine to avoid production compatibility issues
# (such as DNS resolution failures, and dynamically linked NIFs/precompiled binaries).
#
# For finding packages in Debian, search on https://packages.debian.org/.

ARG ELIXIR_VERSION=1.17.2
ARG OTP_VERSION=27.1
ARG DEBIAN_VERSION=trixie-20260610-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git curl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# prepare build dir
WORKDIR /app

# Network steps retry: a dropped download should not fail a first install.
# install hex + rebar
RUN for i in 1 2 3 4 5; do mix local.hex --force && mix local.rebar --force && break; \
      echo "retrying in 5s ($i)"; sleep 5; done; mix hex.info >/dev/null

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN for i in 1 2 3 4 5; do mix deps.get --only $MIX_ENV && break; echo "retrying in 5s ($i)"; sleep 5; done; \
    mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Fetch the Tailwind binary with curl (retries survive flaky connections; the
# Erlang downloader gives up on a dropped 100 MB transfer). The version comes
# from config/config.exs so the two never drift.
RUN set -eu; \
  version="$(sed -n '/config :tailwind/,/]/p' config/config.exs | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"; \
  case "$(dpkg --print-architecture)" in amd64) target=linux-x64 ;; arm64) target=linux-arm64 ;; *) exit 0 ;; esac; \
  mkdir -p _build; \
  curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
    -o "_build/tailwind-${target}-${version}" \
    "https://github.com/tailwindlabs/tailwindcss/releases/download/v${version}/tailwindcss-${target}"; \
  chmod +x "_build/tailwind-${target}-${version}"

RUN for i in 1 2 3; do mix assets.setup && break; echo "retrying in 5s ($i)"; sleep 5; done; \
    mix assets.setup

COPY priv priv

COPY lib lib

# Compile the release
RUN mix compile

COPY assets assets

# compile assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS final

# Subscription CLIs Atlas can drive. Set to "false" to build a smaller image
# (then use the mock backend or ANTHROPIC_API_KEY).
ARG INSTALL_AGENT_CLIS=true

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
     tini curl git \
  && if [ "$INSTALL_AGENT_CLIS" = "true" ]; then \
       apt-get install -y --no-install-recommends nodejs npm ; \
     fi \
  && rm -rf /var/lib/apt/lists/*

# Claude Code, OpenAI Codex and Gemini CLIs (npm).
RUN if [ "$INSTALL_AGENT_CLIS" = "true" ]; then \
      npm install -g --no-fund --no-audit @anthropic-ai/claude-code @openai/codex @google/gemini-cli \
      && npm cache clean --force ; \
    fi

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# A real user with a home directory: the CLIs keep their logins in $HOME,
# which docker-compose persists in a volume.
RUN useradd --create-home --home-dir /home/atlas --shell /bin/bash atlas \
  && mkdir -p /data /app \
  && chown atlas:atlas /data /app

USER atlas
ENV HOME=/home/atlas
ENV PATH="/home/atlas/.local/bin:${PATH}"

# Cursor's CLI installs per user. Best effort: the build continues without it.
RUN if [ "$INSTALL_AGENT_CLIS" = "true" ]; then \
      (curl -fsS https://cursor.com/install | bash) || echo "cursor-agent install skipped" ; \
    fi

WORKDIR "/app"

# set runner ENV
ENV MIX_ENV="prod"
ENV PHX_HOST=localhost
ENV PORT=4000

# Only copy the final release from the build stage
COPY --from=builder --chown=atlas:atlas /app/_build/${MIX_ENV}/rel/atlas ./
COPY --chown=atlas:atlas rel/docker-entrypoint.sh /app/docker-entrypoint.sh

VOLUME ["/data"]
EXPOSE 4000

ENTRYPOINT ["/usr/bin/tini", "--", "/app/docker-entrypoint.sh"]
CMD ["/app/bin/server"]
