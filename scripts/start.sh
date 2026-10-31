#!/usr/bin/env bash
# Run Planly entirely on this machine: PostgreSQL, Ollama (your CPU/GPU), the API and the web app.
#
#   make start                          # or: scripts/start.sh
#   PLANLY_MODEL=qwen2.5:7b make start  # lighter model for slower machines (3b for 8 GB)
#
# First run installs dependencies, sets up the database and downloads the model; later runs
# start in seconds. Ctrl-C stops everything this script started.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/backend/.env"
API_PORT="${PLANLY_API_PORT:-8000}"
WEB_PORT="${PLANLY_PORT:-5173}"

say()  { printf '\033[1m▸ %s\033[0m\n' "$*"; }
warn() { printf '\033[33m! %s\033[0m\n' "$*"; }
die()  { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
env_value() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2- || true; }

# write KEY=value into backend/.env, replacing an existing line (sed -i.bak works on macOS and Linux)
set_env() {
  [ -f "$ENV_FILE" ] || cp "$ROOT/backend/.env.example" "$ENV_FILE"
  if grep -q "^$1=" "$ENV_FILE"; then
    sed -i.bak "s|^$1=.*|$1=$2|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
  else
    echo "$1=$2" >> "$ENV_FILE"
  fi
}

# one-time: older .env.example copies pinned the previous default, which would hide the new one
CHOSEN="# model chosen with PLANLY_MODEL"
if [ -z "${PLANLY_MODEL:-}" ] && [ "$(env_value OLLAMA_MODEL)" = "qwen2.5:7b" ] && ! grep -qx "$CHOSEN" "$ENV_FILE"; then
  sed -i.bak 's|^OLLAMA_MODEL=qwen2.5:7b$|# OLLAMA_MODEL=qwen2.5:7b   (old default, unpinned by start.sh)|' "$ENV_FILE" && rm -f "$ENV_FILE.bak"
  say "Switched to the new default model qwen2.5:14b (PLANLY_MODEL=qwen2.5:7b make start to go back)"
fi
# a model picked with PLANLY_MODEL is remembered for later runs
if [ -n "${PLANLY_MODEL:-}" ]; then
  set_env OLLAMA_MODEL "$PLANLY_MODEL"
  grep -qx "$CHOSEN" "$ENV_FILE" || echo "$CHOSEN" >> "$ENV_FILE"
fi

MODEL="${PLANLY_MODEL:-$(env_value OLLAMA_MODEL)}"
MODEL="${MODEL:-qwen2.5:14b}"
OLLAMA_URL="${OLLAMA_BASE_URL:-$(env_value OLLAMA_BASE_URL)}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"

have curl || die "curl is required."
have node || die "Node.js 20+ is required: https://nodejs.org (macOS: brew install node)."

# ---------- Python environment ----------
cd "$ROOT/backend"
if [ ! -f .venv/.installed ] || [ pyproject.toml -nt .venv/.installed ]; then
  say "Installing the Python backend (one time)"
  if have uv; then
    [ -x .venv/bin/python ] || uv venv -q -p 3.12 .venv
    uv pip install -q -p .venv -e .
  else
    PY=""
    for candidate in python3.13 python3.12 python3; do
      if have "$candidate" && "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 12))'; then
        PY="$candidate"; break
      fi
    done
    [ -n "$PY" ] || die "Python 3.12+ is required (macOS: brew install python@3.12), or install uv: https://docs.astral.sh/uv/"
    [ -x .venv/bin/python ] || "$PY" -m venv .venv
    .venv/bin/pip install -q -e .
  fi
  touch .venv/.installed
fi

# ---------- web app dependencies ----------
cd "$ROOT/frontend"
if [ ! -f node_modules/.package-lock.json ] || [ package-lock.json -nt node_modules/.package-lock.json ]; then
  say "Installing the web app (one time)"
  npm ci --no-audit --no-fund --loglevel=error
fi

# ---------- PostgreSQL ----------
# Homebrew's versioned PostgreSQL formulas are keg-only, so their tools aren't on PATH
if ! have pg_isready && have brew; then
  for version in 18 17 16 15; do
    if [ -x "$(brew --prefix)/opt/postgresql@$version/bin/pg_isready" ]; then
      PATH="$(brew --prefix)/opt/postgresql@$version/bin:$PATH"; break
    fi
  done
fi
DB_URL="${DATABASE_URL:-$(env_value DATABASE_URL)}"
if [ -z "$DB_URL" ]; then
  if have pg_isready && pg_isready -h localhost -q; then
    say "Using your local PostgreSQL"
    run_psql() {
      psql -h localhost -d postgres -qtAc "$1" 2>/dev/null && return
      have sudo && sudo -u postgres psql -d postgres -qtAc "$1" && return
      die "Couldn't connect to PostgreSQL as a superuser. Create the database yourself:
  CREATE ROLE planly LOGIN PASSWORD 'planly' CREATEDB; CREATE DATABASE planly OWNER planly;
then run this again."
    }
    [ "$(run_psql "SELECT 1 FROM pg_roles WHERE rolname = 'planly'")" = 1 ] \
      || run_psql "CREATE ROLE planly LOGIN PASSWORD 'planly' CREATEDB" >/dev/null
    [ "$(run_psql "SELECT 1 FROM pg_database WHERE datname = 'planly'")" = 1 ] \
      || run_psql "CREATE DATABASE planly OWNER planly" >/dev/null
    DB_URL="postgresql://planly:planly@localhost:5432/planly"
  elif have docker && docker info >/dev/null 2>&1; then
    say "Starting PostgreSQL in Docker (container planly-postgres on port 5433)"
    docker start planly-postgres >/dev/null 2>&1 || docker run -d --name planly-postgres \
      -e POSTGRES_USER=planly -e POSTGRES_PASSWORD=planly -e POSTGRES_DB=planly \
      -p 127.0.0.1:5433:5432 -v planly-pgdata:/var/lib/postgresql/data postgres:16-alpine >/dev/null
    for _ in $(seq 1 30); do docker exec planly-postgres pg_isready -U planly -q && break; sleep 1; done
    DB_URL="postgresql://planly:planly@localhost:5433/planly"
  else
    die "PostgreSQL is needed. Install and start it (macOS: brew install postgresql@16 && brew services start postgresql@16;
Ubuntu: sudo apt install postgresql) or start Docker, then run this again."
  fi
  set_env DATABASE_URL "$DB_URL"
fi

# ---------- Ollama on this machine ----------
PIDS=""  # a string, not an array: macOS ships bash 3.2, where empty arrays trip `set -u`
cleanup() { [ -z "$PIDS" ] || kill $PIDS 2>/dev/null || true; }
trap cleanup EXIT
trap 'exit 130' INT TERM

ollama_up() { curl -sf -m 2 "$OLLAMA_URL/api/tags" >/dev/null; }
if ! ollama_up; then
  have ollama || die "Ollama runs the agent's model on your own hardware. Install it from https://ollama.com/download, then run this again."
  say "Starting Ollama"
  ollama serve >/dev/null 2>&1 &
  PIDS="$PIDS $!"
  for _ in $(seq 1 30); do ollama_up && break; sleep 1; done
  ollama_up || die "Ollama didn't start. Try running 'ollama serve' yourself to see why."
fi
if ! curl -sf "$OLLAMA_URL/api/tags" | grep -q "\"name\":\"$MODEL\""; then
  if have ollama; then
    say "Downloading $MODEL (one time)"
    ollama pull "$MODEL"
  else
    warn "Model $MODEL isn't on the Ollama server at $OLLAMA_URL; the agent will fail until it is pulled."
  fi
fi

# ---------- database schema, API and web app ----------
export DATABASE_URL="$DB_URL" OLLAMA_MODEL="$MODEL" OLLAMA_BASE_URL="$OLLAMA_URL"
cd "$ROOT/backend"
if ! migration=$(.venv/bin/alembic upgrade head 2>&1); then
  echo "$migration" >&2
  die "Database migration failed (DATABASE_URL=$DB_URL)."
fi

.venv/bin/uvicorn app.main:app --port "$API_PORT" --log-level warning &
PIDS="$PIDS $!"
for _ in $(seq 1 30); do curl -sf -m 2 "http://localhost:$API_PORT/api/health" >/dev/null && break; sleep 1; done
curl -sf -m 2 "http://localhost:$API_PORT/api/health" >/dev/null || die "The API didn't start (see the errors above)."

cd "$ROOT/frontend"
PLANLY_API="http://localhost:$API_PORT" node node_modules/vite/bin/vite.js --port "$WEB_PORT" --strictPort --logLevel warn &
PIDS="$PIDS $!"
for _ in $(seq 1 30); do curl -sf -m 2 "http://localhost:$WEB_PORT/" >/dev/null && break; sleep 1; done

URL="http://localhost:$WEB_PORT"
say "Planly is running at $URL (model: $MODEL). Press Ctrl-C to stop."
if [ -z "${PLANLY_NO_OPEN:-}" ]; then
  if have open; then open "$URL"; elif have xdg-open; then xdg-open "$URL" >/dev/null 2>&1 || true; fi
fi
wait
