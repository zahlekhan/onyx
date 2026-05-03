#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.runtime/local-ods"
PID_DIR="$RUNTIME_DIR/pids"
LOG_DIR="$RUNTIME_DIR/logs"

SERVICES=(api model_server background web)

usage() {
  cat <<'EOF'
Usage: tools/run-local-ods.sh [start|stop|restart|status]

Commands:
  start    Start docker infra + ODS services
  stop     Stop ODS services started by this script
  restart  Stop then start
  status   Show process and docker status
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

is_pid_running() {
  local pid="$1"
  kill -0 "$pid" >/dev/null 2>&1
}

start_one() {
  local name="$1"
  local cmd="$2"
  local pid_file="$PID_DIR/$name.pid"
  local log_file="$LOG_DIR/$name.log"

  if [[ -f "$pid_file" ]]; then
    local existing_pid
    existing_pid="$(cat "$pid_file")"
    if [[ -n "$existing_pid" ]] && is_pid_running "$existing_pid"; then
      echo "$name already running (pid $existing_pid)"
      return
    fi
    rm -f "$pid_file"
  fi

  echo "Starting $name ..."
  nohup bash -lc "$cmd" >"$log_file" 2>&1 &
  local new_pid=$!
  echo "$new_pid" >"$pid_file"
  echo "$name started (pid $new_pid, log: $log_file)"
}

stop_one() {
  local name="$1"
  local pid_file="$PID_DIR/$name.pid"

  if [[ ! -f "$pid_file" ]]; then
    echo "$name not running (no pid file)"
    return
  fi

  local pid
  pid="$(cat "$pid_file")"
  if [[ -n "$pid" ]] && is_pid_running "$pid"; then
    echo "Stopping $name (pid $pid) ..."
    kill "$pid" >/dev/null 2>&1 || true
    sleep 1
    if is_pid_running "$pid"; then
      kill -9 "$pid" >/dev/null 2>&1 || true
    fi
  else
    echo "$name already stopped"
  fi

  rm -f "$pid_file"
}

status_one() {
  local name="$1"
  local pid_file="$PID_DIR/$name.pid"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file")"
    if [[ -n "$pid" ]] && is_pid_running "$pid"; then
      echo "  - $name: running (pid $pid)"
      return
    fi
  fi
  echo "  - $name: stopped"
}

start_all() {
  require_cmd docker
  require_cmd ods
  require_cmd python

  mkdir -p "$PID_DIR" "$LOG_DIR"
  cd "$ROOT_DIR"

  if [[ ! -f ".env" ]]; then
    echo "Missing .env at repo root. Create it before running this script." >&2
    exit 1
  fi

  echo "Starting docker infra ..."
  docker compose -f deployment/docker_compose/docker-compose.yml -f deployment/docker_compose/docker-compose.dev.yml up -d index relational_db cache minio opensearch

  echo "Running database migrations ..."
  python -m dotenv -f .env run -- bash -lc "cd \"$ROOT_DIR/backend\" && source ../.venv/bin/activate && alembic upgrade head"

  # Use python-dotenv so placeholders in .env don't break shell parsing.
  start_one "model_server" "cd \"$ROOT_DIR\" && python -m dotenv -f .env run -- ods backend model_server"
  start_one "api" "cd \"$ROOT_DIR\" && python -m dotenv -f .env run -- ods backend api"
  start_one "background" "cd \"$ROOT_DIR\" && python -m dotenv -f .env run -- bash -lc 'cd backend && source ../.venv/bin/activate && python ./scripts/dev_run_background_jobs.py'"
  start_one "web" "cd \"$ROOT_DIR\" && python -m dotenv -f .env run -- ods web dev"

  echo
  echo "All start commands issued."
  echo "Logs: $LOG_DIR"
}

stop_all() {
  mkdir -p "$PID_DIR"
  for svc in "${SERVICES[@]}"; do
    stop_one "$svc"
  done
}

status_all() {
  mkdir -p "$PID_DIR"
  echo "Local ODS service status:"
  for svc in "${SERVICES[@]}"; do
    status_one "$svc"
  done
  echo
  echo "Docker infra:"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | rg "onyx-(index|relational_db|cache|minio|opensearch)-1|NAMES" || true
}

cmd="${1:-start}"
case "$cmd" in
  start) start_all ;;
  stop) stop_all ;;
  restart) stop_all; start_all ;;
  status) status_all ;;
  *) usage; exit 1 ;;
esac
