# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Docker container that acts as a git remote server. Users push code over SSH, a post-receive hook fires, and Claude works on the code autonomously in a tmux session. Claude's commits are pushed back to the bare repo so users can `git pull` the results.

## Build and Run

```bash
./run.sh --build                          # build image and start container (port 2222)
./run.sh -n <name> -p <port> --build      # named instance on custom port
./run.sh --stop                           # stop container
./run.sh --destroy                        # stop and wipe all volumes
./run.sh --status                         # show repos and tmux sessions
./run.sh --attach <session>               # attach to Claude's tmux session
./run.sh --shell                          # root shell in container
```

There is no test suite. Validate changes by building the image and testing a push manually.

## Architecture

The push-to-Claude pipeline is a chain of scripts, each handing off to the next:

1. **`sshd`** receives the SSH connection on port 22 (mapped to 2222 on host)
2. **`authorized-keys-command.sh`** runs at auth time, wraps every git-user key with `command="/usr/local/bin/git-shell-wrapper"` so all sessions are forced through the wrapper
3. **`git-shell-wrapper`** parses `$SSH_ORIGINAL_COMMAND`, auto-creates bare repos on first push (via `git init --bare`), copies default hooks from `/home/git/hooks/` into new repos, then delegates to `git-shell`
4. **`hooks/post-receive`** fires after objects are written: clones to a timestamped work dir, reads instruction files (`AGENTS.md` > `CLAUDE.md` > `.claude-docker-hook`), builds a prompt, and launches `claude -p` in a detached tmux session
5. **`entrypoint.sh`** is the container init: UID/GID remapping, SSH host key generation, permission setup, firewall application, sshd start
6. **`firewall.sh`** locks outbound traffic to whitelisted domains via iptables (sourced by entrypoint)

### Key design decisions

- **All scripts are bash.** The project has no application-level language runtime beyond Node.js (needed only for the Claude CLI npm package).
- **Repos are bare git repos** at `/home/git/repos/`. Work happens in ephemeral timestamped clones under `/home/git/work/`. Logs go to `/home/git/logs/`.
- **`run.sh` wraps docker compose** with instance naming (`-n`). Instance name determines container name (`claude-<name>`), compose project, and volume namespace. All `run.sh` commands operate on one instance at a time.
- **UID/GID remapping** in entrypoint.sh ensures the container's `git` user matches the host user's IDs so mounted volumes have correct ownership.
- **The post-receive hook unsets git env vars** (`GIT_DIR`, `GIT_QUARANTINE_PATH`, etc.) at the top because they leak from `git-receive-pack` and break the clone/checkout operations inside the hook.
- **Loop prevention**: the hook checks `$SSH_CONNECTION` and exits early for local pushes, so Claude pushing back to the bare repo doesn't re-trigger the hook.
- **Auth bridging**: Docker env vars don't propagate through sshd, so `entrypoint.sh` writes them to `/home/git/.claude-env` which the hook sources.
- **Live logging**: `script -f` wraps the Claude invocation to allocate a PTY, so output streams unbuffered to both the tmux pane and the log file.
- **tmux sessions** are named `claude-<repo>-<branch>` with non-alphanumeric chars replaced by underscores. Existing sessions for the same repo/branch are killed before starting a new one.
- **Push options** (`git push -o prompt="..."`) are read via `GIT_PUSH_OPTION_*` env vars in the post-receive hook and appended to the prompt.

## Commit Style

- Small, atomic commits with short messages
- No Co-Authored-By lines
