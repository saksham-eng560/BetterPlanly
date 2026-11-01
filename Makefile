# Local development. Needs Python 3.12+, Node 22, PostgreSQL 16 and (for the agent) Ollama.
PY := backend/.venv/bin/python

.PHONY: start phone setup db migrate backend frontend fake-ollama test e2e build up

start:  ## run everything on this machine (installs on first run) → http://localhost:5173
	scripts/start.sh

phone:  ## like start, but the API also listens on home Wi-Fi for the iPhone app
	PLANLY_HOST=0.0.0.0 scripts/start.sh

setup:  ## create the Python venv and install both apps
	python3 -m venv backend/.venv
	$(PY) -m pip install -e "backend[dev]"
	cd frontend && npm ci

db:  ## create the planly role and databases in a local Postgres (run once)
	psql -d postgres -c "CREATE ROLE planly LOGIN PASSWORD 'planly' CREATEDB" || true
	createdb -O planly planly || true
	createdb -O planly planly_test || true

migrate:
	cd backend && .venv/bin/alembic upgrade head

backend: migrate  ## API on :8000 (auto-reload)
	cd backend && .venv/bin/uvicorn app.main:app --reload --port 8000

frontend:  ## web app on :5173, proxying /api to :8000
	cd frontend && npm run dev

fake-ollama:  ## scripted stand-in for Ollama on :11434 (no model needed)
	python3 scripts/fake_ollama.py

test:  ## backend + frontend unit tests
	cd backend && .venv/bin/python -m pytest -q
	cd frontend && npm test

e2e:  ## browser smoke test; needs `make backend`, `make frontend`, `make fake-ollama` running and a fresh database
	cd frontend && npx playwright test

build:
	cd frontend && npm run build

up:  ## everything in Docker → http://localhost:8080
	docker compose up --build
