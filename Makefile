# Atlas PMF — common tasks. Run `make` for the list.
#
#   make up        Docker: build and start everything (only Docker needed)
#   make install   No Docker: install asdf, Erlang, Elixir and the app
#   make server    No Docker: start the app at http://localhost:4000

SHELL := /bin/bash
ASDF_SHIMS := $(or $(ASDF_DATA_DIR),$(HOME)/.asdf)/shims
export PATH := $(ASDF_SHIMS):$(PATH)

PORT ?= $(or $(ATLAS_PORT),4000)
COMPOSE := ATLAS_PORT=$(PORT) docker compose

.DEFAULT_GOAL := help
.PHONY: help up down logs restart rebuild docker-login docker-shell docker-doctor docker-reset \
        install setup server test test-live doctor clis env clean

help: ## Show this help
	@echo "Atlas PMF"
	@echo
	@echo "With Docker (nothing else to install):"
	@grep -E '^(up|down|logs|restart|rebuild|docker-[a-z-]+):.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-14s %s\n", $$1, $$2}'
	@echo
	@echo "Without Docker:"
	@grep -E '^(install|setup|server|test|test-live|doctor|clis|env|clean):.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-14s %s\n", $$1, $$2}'

## ---------------------------------------------------------------- Docker

up: env ## Build and start Atlas in Docker (another port: make up PORT=4001)
	@command -v docker >/dev/null || { echo "Docker is not installed: https://docs.docker.com/get-docker/"; exit 1; }
	@docker info >/dev/null 2>&1 || { echo "Docker is not running. Start Docker Desktop (or the docker service) and retry."; exit 1; }
	@if ! docker ps --filter name=^atlas$$ --format '{{.Names}}' | grep -q atlas && \
	   (lsof -nP -iTCP:$(PORT) -sTCP:LISTEN >/dev/null 2>&1 || nc -z 127.0.0.1 $(PORT) >/dev/null 2>&1); then \
	  echo "Port $(PORT) is already in use. Pick another: make up PORT=4001"; exit 1; fi
	$(COMPOSE) up --build -d
	@echo
	@echo "Atlas is starting at http://localhost:$(PORT)"
	@echo "Log in to an AI CLI inside the container with:  make docker-login"

down: ## Stop the container (data is kept)
	$(COMPOSE) down

logs: ## Follow the app's logs
	$(COMPOSE) logs -f atlas

restart: ## Restart the container
	$(COMPOSE) restart atlas

rebuild: ## Rebuild the image from scratch and restart
	$(COMPOSE) build --no-cache
	$(COMPOSE) up -d

docker-login: ## Log in to Claude Code / Codex / Gemini / Cursor inside the container
	@echo "Pick the CLI to log in to. Logins persist in the atlas-home volume."
	@echo "  1) Claude Code   2) Codex   3) Gemini   4) Cursor"
	@read -p "> " choice; \
	case $$choice in \
	  1) $(COMPOSE) exec -it atlas claude ;; \
	  2) $(COMPOSE) exec -it atlas sh -c 'codex login --device-auth || codex login' ;; \
	  3) $(COMPOSE) exec -it atlas gemini ;; \
	  4) $(COMPOSE) exec -it atlas sh -c 'cursor-agent login 2>/dev/null || agent login' ;; \
	  *) echo "Nothing selected." ;; \
	esac

docker-shell: ## Open a shell inside the container
	$(COMPOSE) exec -it atlas bash

docker-doctor: ## Check which AI backends work inside the container
	@$(COMPOSE) exec atlas /app/bin/atlas rpc 'for {n, r} <- Atlas.LLM.doctor(), do: IO.puts("#{String.pad_trailing(n, 14)} #{elem(r, 0)}  #{elem(r, 1)}")'

docker-reset: ## Delete the container AND its data volumes (asks first)
	@read -p "This deletes all studies, uploads and CLI logins. Type yes: " ok; \
	[ "$$ok" = "yes" ] && $(COMPOSE) down -v || echo "Cancelled."

## ---------------------------------------------------------------- Local

install: ## Install asdf + Erlang + Elixir (from .tool-versions) and set up the app
	@./scripts/install.sh

setup: ## Fetch deps, create the database, build assets (Elixir already installed)
	mix setup

server: ## Start Atlas at http://localhost:4000
	mix phx.server

test: ## Run the test suite (offline, no model calls)
	mix test

test-live: ## Run tests against the AI CLIs installed here (uses your plan's quota)
	mix test --only live

doctor: ## Check which AI backends are ready on this machine
	mix atlas.doctor

clis: ## Install the Claude Code, Codex and Gemini CLIs with npm (Cursor: see output)
	@command -v npm >/dev/null || { echo "npm is required: install Node.js 20+ first."; exit 1; }
	npm install -g @anthropic-ai/claude-code @openai/codex @google/gemini-cli
	@echo
	@echo "Cursor CLI:  curl https://cursor.com/install -fsS | bash"
	@echo "Then log in once: claude  |  codex login  |  gemini  |  cursor-agent login"

env: ## Create .env from .env.example if missing
	@[ -f .env ] || { cp .env.example .env && echo "Created .env (edit it to add tokens)"; }

clean: ## Remove build output (keeps your database and uploads)
	rm -rf _build deps priv/static/assets tmp
