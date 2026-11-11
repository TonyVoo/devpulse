# DevPulse developer commands. Run `make help`.
SHELL := /bin/bash
COMPOSE := docker compose --env-file .env -f infra/compose/docker-compose.yml
API := services/api
PY := $(API)/.venv/bin

.PHONY: help env up down logs ps migrate api-venv api-test api-lint api-typecheck api-check openapi web-install web-dev web-check

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-16s %s\n", $$1, $$2}'

env: ## Create .env files from .env.example (does not overwrite)
	@test -f .env || cp .env.example .env
	@test -f $(API)/.env || cp .env $(API)/.env
	@test -f apps/web/.env.local || cp .env apps/web/.env.local

up: env ## Build and start the stack, wait until healthy
	$(COMPOSE) up -d --build --wait

down: ## Stop the stack (keeps volumes)
	$(COMPOSE) down

logs: ## Follow logs
	$(COMPOSE) logs -f --tail=100

ps: ## Service status
	$(COMPOSE) ps -a

migrate: ## Apply migrations inside the stack
	$(COMPOSE) run --rm migrate

api-venv: ## Create backend virtualenv with dev deps
	test -d $(API)/.venv || python3.12 -m venv $(API)/.venv
	$(PY)/pip install -q -e "$(API)[dev]"

api-test: ## Backend tests (needs `make up` for postgres/redis)
	cd $(API) && .venv/bin/pytest -q

api-lint: ## Ruff lint + format check
	cd $(API) && .venv/bin/ruff check . && .venv/bin/ruff format --check .

api-typecheck: ## mypy strict
	cd $(API) && .venv/bin/mypy app

api-check: api-lint api-typecheck api-test ## All backend checks

openapi: ## Export OpenAPI schema to packages/api-contract
	cd $(API) && .venv/bin/python -m app.scripts.export_openapi ../../packages/api-contract/openapi.json

web-install: ## Install web dependencies
	cd apps/web && pnpm install

web-dev: ## Run the web dashboard on :3000
	cd apps/web && pnpm dev

web-check: ## Web lint, typecheck, tests, build
	cd apps/web && pnpm lint && pnpm typecheck && pnpm test && pnpm build
