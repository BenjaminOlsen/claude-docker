#!/bin/bash
# AuthorizedKeysCommand for sshd.
# For the git user: wraps each key with a forced command to go through git-shell-wrapper.
# For root: passes keys through as-is (debug access).

set -euo pipefail

USER="$1"
KEYS_FILE="/home/git/.ssh/authorized_keys"

if [ ! -f "$KEYS_FILE" ]; then
    exit 0
fi

if [ "$USER" = "git" ]; then
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        echo "command=\"/usr/local/bin/git-shell-wrapper\",no-port-forwarding,no-agent-forwarding,no-X11-forwarding $line"
    done < "$KEYS_FILE"
elif [ "$USER" = "root" ]; then
    cat "$KEYS_FILE"
fi
