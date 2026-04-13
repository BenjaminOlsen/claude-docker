#!/bin/bash
# Docker entrypoint: sets up SSH host keys, fixes permissions, starts sshd.

set -euo pipefail

HOST_KEYS_DIR="/etc/ssh/ssh_host_keys"

# Match container git user UID/GID to host values (if provided)
if [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
    groupmod -o -g "$HOST_GID" git 2>/dev/null || true
    usermod -o -u "$HOST_UID" -g "$HOST_GID" git 2>/dev/null || true
    chown -R git:git /home/git
fi

# Generate SSH host keys if they don't exist
if [ ! -f "$HOST_KEYS_DIR/ssh_host_ed25519_key" ]; then
    echo "Generating SSH host keys..."
    ssh-keygen -t ed25519 -f "$HOST_KEYS_DIR/ssh_host_ed25519_key" -N "" -q
    ssh-keygen -t rsa -b 4096 -f "$HOST_KEYS_DIR/ssh_host_rsa_key" -N "" -q
fi

# Ensure authorized_keys exists and has correct permissions
AUTH_KEYS="/home/git/.ssh/authorized_keys"
if [ ! -f "$AUTH_KEYS" ]; then
    echo "WARNING: No authorized_keys found at $AUTH_KEYS" >&2
    echo "Mount your public key: -v ~/.ssh/id_ed25519.pub:/home/git/.ssh/authorized_keys:ro" >&2
    # Create an empty file so sshd doesn't complain
    touch "$AUTH_KEYS"
fi

chmod 700 /home/git/.ssh
chmod 600 "$AUTH_KEYS" 2>/dev/null || true
chown -R git:git /home/git/.ssh

# Ensure Claude credentials directory exists and is owned by git
mkdir -p /home/git/.claude
chown -R git:git /home/git/.claude

# Verify Claude credentials
if [ -f "/home/git/.claude/.credentials.json" ]; then
    echo "  Claude OAuth credentials found."
else
    echo "WARNING: No Claude credentials found." >&2
    echo "  Mount your credentials: -v ~/.claude/.credentials.json:/home/git/.claude/.credentials.json" >&2
    echo "  Or set ANTHROPIC_API_KEY in the environment." >&2
fi

# Ensure work and log dirs exist
mkdir -p /home/git/work /home/git/logs /home/git/repos
chown -R git:git /home/git/work /home/git/logs /home/git/repos

echo "========================================"
echo "  Claude Docker - Git + Claude Server"
echo "========================================"
echo "  SSH port: 22 (map to host with -p)"
echo "  Repos:    /home/git/repos/"
echo "  Work:     /home/git/work/"
echo "  Logs:     /home/git/logs/"

# Apply outbound firewall rules
source /usr/local/bin/firewall.sh

echo "========================================"

# Trap signals for graceful shutdown
trap 'echo "Shutting down..."; kill $(cat /run/sshd.pid 2>/dev/null) 2>/dev/null; exit 0' SIGTERM SIGINT

# Start sshd in foreground
exec /usr/sbin/sshd -D -e
