#!/bin/bash
# Launcher script for Claude Docker.
#
# Usage:
#   ./run.sh                        # Start default instance (port 2222)
#   ./run.sh --build                # Rebuild and start
#   ./run.sh -n worker2 -p 2223     # Start a named instance on a different port
#   ./run.sh -n worker2 --stop      # Stop a specific instance
#   ./run.sh -n worker2 --destroy   # Stop and delete all data (repos, work, logs)
#   ./run.sh --attach <session>     # Attach to a Claude tmux session
#   ./run.sh --shell                # Get a root shell in the container

set -euo pipefail

# Parse instance name and port from flags
INSTANCE="default"
PORT="2222"
ACTION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--name)
            INSTANCE="$2"
            shift 2
            ;;
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        --build|--stop|--destroy|--logs|--status|--shell)
            ACTION="$1"
            shift
            ;;
        --attach)
            ACTION="--attach"
            ATTACH_SESSION="${2:-}"
            shift
            [ -n "$ATTACH_SESSION" ] && shift
            ;;
        *)
            ACTION="$1"
            shift
            ;;
    esac
done

export CLAUDE_INSTANCE="$INSTANCE"
export SSH_PORT="$PORT"
CONTAINER_NAME="claude-${INSTANCE}"
COMPOSE="docker compose -p claude-${INSTANCE}"

case "${ACTION:-start}" in
    --build)
        echo "Building and starting Claude Docker [${INSTANCE}] on port ${PORT}..."
        HOST_UID="$(id -u)" HOST_GID="$(id -g)" $COMPOSE up --build -d
        echo ""
        echo "Ready! Add as a git remote in your project:"
        echo "  git remote add ${INSTANCE} ssh://git@localhost:${PORT}/repos/<your-repo>"
        echo "  git push ${INSTANCE} <branch>"
        ;;
    --stop)
        echo "Stopping Claude Docker [${INSTANCE}]..."
        $COMPOSE down
        ;;
    --destroy)
        echo "Destroying Claude Docker [${INSTANCE}] and all its data (repos, work, logs)..."
        read -rp "Are you sure? [y/N] " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            $COMPOSE down -v
            echo "Destroyed. Run '$0 -n ${INSTANCE} --build' to start fresh."
        else
            echo "Cancelled."
        fi
        ;;
    --logs)
        $COMPOSE logs -f
        ;;
    --attach)
        if [ -z "${ATTACH_SESSION:-}" ]; then
            echo "Available tmux sessions in [${INSTANCE}]:"
            docker exec -it -u git "$CONTAINER_NAME" tmux list-sessions 2>/dev/null || echo "  (none)"
            echo ""
            echo "Usage: $0 -n ${INSTANCE} --attach <session-name>"
            exit 1
        fi
        docker exec -it -u git "$CONTAINER_NAME" tmux attach -t "$ATTACH_SESSION"
        ;;
    --shell)
        docker exec -it "$CONTAINER_NAME" bash
        ;;
    --status)
        echo "=== Claude Docker [${INSTANCE}] ==="
        echo ""
        echo "Container:"
        docker ps --filter "name=$CONTAINER_NAME" --format "  {{.Status}} (port ${PORT})" 2>/dev/null || echo "  not running"
        echo ""
        echo "Tmux sessions (Claude workers):"
        docker exec -u git "$CONTAINER_NAME" tmux list-sessions 2>/dev/null || echo "  (none)"
        echo ""
        echo "Repos:"
        docker exec "$CONTAINER_NAME" ls /home/git/repos/ 2>/dev/null || echo "  (none)"
        ;;
    --list)
        echo "Running Claude Docker instances:"
        docker ps --filter "name=claude-" --format "  {{.Names}}\t{{.Status}}\t{{.Ports}}"
        ;;
    start|"")
        echo "Starting Claude Docker [${INSTANCE}] on port ${PORT}..."
        HOST_UID="$(id -u)" HOST_GID="$(id -g)" $COMPOSE up -d
        echo ""
        echo "Ready! Add as a git remote in your project:"
        echo "  git remote add ${INSTANCE} ssh://git@localhost:${PORT}/repos/<your-repo>"
        echo "  git push ${INSTANCE} <branch>"
        echo ""
        echo "Other commands:"
        echo "  $0 -n ${INSTANCE} --status    Show status and active Claude sessions"
        echo "  $0 -n ${INSTANCE} --attach    Attach to a Claude tmux session"
        echo "  $0 -n ${INSTANCE} --logs      Follow container logs"
        echo "  $0 -n ${INSTANCE} --shell     Root shell in the container"
        echo "  $0 -n ${INSTANCE} --stop       Stop the container"
        echo "  $0 -n ${INSTANCE} --destroy    Stop and wipe all data"
        echo "  $0 --list                      List all running instances"
        ;;
esac
