# claude-docker

A Docker container that acts as a git remote. Push your code to it and Claude works on it autonomously.

Inspired by [aquanauts/legit](https://github.com/aquanauts/legit).

## How it works

```
┌─────────────┐     git push      ┌──────────────────────────────┐
│  Your local  │ ───────────────▶  │       claude-docker          │
│  working     │     ssh:2222      │                              │
│  copy        │                   │  post-receive hook fires:    │
│              │                   │    1. clone into /work/       │
│              │  git pull claude  │    2. read AGENTS.md          │
│              │ ◀──────────────── │    3. claude -p "..." --yolo  │
│              │                   │    4. claude commits & pushes │
└─────────────┘                   └──────────────────────────────┘
```

1. You `git push` to the container over SSH (port 2222)
2. A `post-receive` hook fires, cloning the repo into a timestamped work directory
3. Claude launches headlessly, reads your `AGENTS.md` (or `CLAUDE.md`), and goes to work
4. Claude commits its changes and pushes them back to the bare repo
5. You `git pull` to get claude's work. Do with it what you will - review, merge, modify, discard...

## Quick start

### Prerequisites

- Docker with compose
- An SSH keypair (`~/.ssh/id_ed25519` and `~/.ssh/id_ed25519.pub`)
- Claude credentials (`~/.claude/` directory or `ANTHROPIC_API_KEY` env var)

### 1. Build and start

```bash
./run.sh --build
```

Or with docker compose directly:

```bash
HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose up --build -d
```

### 2. Add the remote to your project

```bash
cd /path/to/your/project
git remote add claude ssh://git@localhost:2222/repos/myproject
```

Repos are auto-created in the container on first push.

### 3. Push and let Claude work

```bash
git push claude main

# Or with an initial prompt to tell Claude what to focus on
git push -o prompt="Fix the failing tests in src/auth" claude main
```

You'll see output like:

```
==> Claude Docker: received push to myproject/main
==> Found AGENTS.md - Claude will follow its instructions
==> Starting Claude in tmux session: claude-myproject-main
==> Claude is working autonomously on myproject/main
```

### 4. Watch Claude work (optional)

```bash
# Attach to the tmux session
./run.sh --attach claude-myproject-main

# Or tail the log
docker exec claude-docker tail -f /home/git/logs/myproject_main_*.log
```

Detach from tmux with `Ctrl-b d`.

### 5. Pull Claude's changes

```bash
git pull claude main
```

## Controlling Claude's behavior

Claude looks for instruction files in your repo (in order of priority):

| File | Purpose |
|------|---------|
| `AGENTS.md` | Primary instruction file. Claude reads and follows it. |
| `CLAUDE.md` | Fallback instruction file if no AGENTS.md exists. |
| `.claude-docker-hook` | Executable script that **replaces** the default Claude invocation entirely. Receives `$1=old_rev`, `$2=new_rev`, `$3=branch`. |

If none of these exist, Claude will analyze the codebase on its own and look for TODOs, bugs, and improvements.

### Push-time prompt

You can pass an initial prompt via git push options. This gets appended to whatever `AGENTS.md`/`CLAUDE.md` already provides, so you can give Claude specific focus for a particular push:

```bash
# Just a prompt, no instruction files needed
git push -o prompt="Refactor the database layer to use connection pooling" claude main

# Combines with AGENTS.md -- Claude reads the file AND your prompt
git push -o prompt="Focus on the auth module only" claude main
```

## Launcher script

```bash
./run.sh                            # Start default instance (port 2222)
./run.sh --build                    # Rebuild and start
./run.sh --stop                     # Stop the container
./run.sh --status                   # Show active repos and Claude sessions
./run.sh --attach claude-myproject-main   # Attach to a Claude tmux session
./run.sh --logs                     # Follow container logs
./run.sh --shell                    # Root shell in the container
./run.sh --list                     # List all running instances
```

## Multiple instances

You can run multiple containers in parallel, each on its own port with isolated volumes:

```bash
# Start three independent workers
./run.sh --build                            # "default" on port 2222
./run.sh -n worker2 -p 2223 --build         # "worker2" on port 2223
./run.sh -n worker3 -p 2224 --build         # "worker3" on port 2224

# Each gets its own git remote
git remote add claude   ssh://git@localhost:2222/repos/myproject
git remote add worker2  ssh://git@localhost:2223/repos/myproject
git remote add worker3  ssh://git@localhost:2224/repos/myproject

# Push the same repo to multiple workers with different AGENTS.md on different branches,
# or push entirely different repos to each
git push claude  main
git push worker2 main
git push worker3 experiment-branch

# Manage them independently
./run.sh -n worker2 --status
./run.sh -n worker2 --attach claude-myproject-main
./run.sh -n worker3 --stop

# List all running instances
./run.sh --list
```

Each instance gets its own container name (`claude-default`, `claude-worker2`, ...), port, and volumes (repos, work dirs, logs are all isolated).

## Configuration

### SSH key

By default, `docker-compose.yml` mounts `~/.ssh/id_ed25519.pub`. If you use a different key:

```yaml
volumes:
  - ~/.ssh/id_rsa.pub:/home/git/.ssh/authorized_keys:ro
```

### Claude authentication

**Pro/Max plan (OAuth):** The compose file mounts your `~/.claude/.credentials.json` into the container. The CLI uses the refresh token to stay authenticated headlessly -- no browser needed after your initial `claude login` on the host.

The credentials file is mounted read-write so the CLI can refresh expired tokens.

**API key (pay-as-you-go):** Alternatively, create a `.env` file next to `docker-compose.yml`:

```env
ANTHROPIC_API_KEY=sk-ant-...
```

### Port

The default port is 2222. Use the `-p` flag to change it:

```bash
./run.sh -p 3333 --build
```

Then use `ssh://git@localhost:3333/repos/myproject` as your remote.

### Outbound firewall

By default, the container restricts outbound network access to only what Claude needs:

| Allowed | Why |
|---|---|
| `api.anthropic.com`, `claude.ai` | Claude API (required) |
| DNS (port 53) | Domain resolution |
| `registry.npmjs.org` | npm packages |

Everything else is **dropped** via iptables. Claude cannot exfiltrate code or reach arbitrary endpoints.

```bash
# Disable the firewall entirely
FIREWALL_ENABLED=false ./run.sh --build

# Whitelist extra domains (comma-separated)
FIREWALL_ALLOW_EXTRA="github.com,pypi.org,files.pythonhosted.org" ./run.sh --build
```

To permanently enable additional registries (pypi, rubygems, crates.io, etc.), uncomment the relevant lines in `firewall.sh`.

Note: domains are resolved to IPs at container startup. If Anthropic's IPs rotate, restart the container to re-resolve.

## Architecture

```
Container filesystem:
/home/git/
├── .ssh/authorized_keys     # mounted from host (read-only)
├── .claude/                 # mounted from host (Claude credentials)
├── repos/                   # bare git repos (auto-created on push)
│   └── myproject.git/
│       └── hooks/post-receive
├── hooks/                   # default hooks (copied into new repos)
│   └── post-receive
├── work/                    # ephemeral clones where Claude works
│   └── myproject/
│       └── main/
│           └── 2025-01-15/
│               └── 14_30_00/   # timestamped clone
└── logs/                    # Claude session logs
    └── myproject_main_20250115_143000.log
```

Key components:

- **`git-shell-wrapper`** -- Intercepts all SSH git commands. Auto-initializes bare repos on first push and copies default hooks into them.
- **`authorized-keys-command.sh`** -- Forces all git-user SSH sessions through the wrapper. Root gets unrestricted access for debugging.
- **`post-receive` hook** -- Clones the repo, finds instruction files, launches Claude in a tmux session.
- **`entrypoint.sh`** -- Generates SSH host keys, fixes UID/GID mapping, starts sshd.

## Troubleshooting

### "Permission denied (publickey)"

Make sure your public key is mounted correctly:

```bash
# Check the key is there
docker exec claude-docker cat /home/git/.ssh/authorized_keys

# Test SSH connection
ssh -p 2222 -T git@localhost
```

### Claude isn't starting

```bash
# Check if tmux sessions exist
docker exec claude-docker tmux list-sessions

# Check logs
docker exec claude-docker ls /home/git/logs/

# Get a shell and debug
./run.sh --shell
```

### Want to wipe everything and start fresh

```bash
./run.sh --stop
docker compose down -v   # removes volumes too
./run.sh --build
```

# How it all works

Here's the full chain of what happens when you push:

### 1. You push

```bash
git push claude main
```

Your git client opens an SSH connection to `localhost:2222`, which Docker forwards to port 22 inside the container. SSH sends the command:

```
git-receive-pack '/repos/myproject'
```

### 2. SSH authenticates and forces the wrapper

sshd receives the connection and runs `authorized-keys-command.sh` to look up your key. That script **prepends a forced command**:

```
command="/usr/local/bin/git-shell-wrapper",no-port-forwarding ... ssh-ed25519 AAAA...
```

This means no matter what the SSH client asks to run, sshd runs `git-shell-wrapper` instead. The original command (`git-receive-pack '/repos/myproject'`) gets stashed in the `$SSH_ORIGINAL_COMMAND` environment variable.

### 3. git-shell-wrapper auto-creates the repo

The wrapper parses `$SSH_ORIGINAL_COMMAND` to extract the repo path. If `/home/git/repos/myproject.git` doesn't exist yet, it:

1. Runs `git init --bare` to create it
2. Copies the default hooks from `/home/git/hooks/` (including `post-receive`) into the new repo's `hooks/` directory

Then it hands off to the real `git-shell`, which runs `git-receive-pack` against the bare repo. This is the standard git protocol -- your commits get written into the bare repo.

### 4. post-receive fires

After git finishes writing the pushed objects, it automatically runs the `post-receive` hook. Git passes the push info on stdin:

```
<old-sha> <new-sha> refs/heads/main
```

The hook:

1. **Clones** the bare repo into a fresh timestamped directory: `/home/git/work/myproject/main/2026-04-13/14_30_00/`
2. **Checks out** the pushed branch
3. **Looks for instructions** -- `AGENTS.md`, then `CLAUDE.md`, then `.claude-docker-hook`
4. **Builds a prompt** from what it finds
5. **Launches Claude** inside a detached tmux session:

```bash
tmux new-session -d -s "claude-myproject-main" \
    "claude -p '<prompt>' --dangerously-skip-permissions 2>&1 | tee logfile"
```

At this point your `git push` returns -- the hook launched tmux in the background and didn't wait for Claude to finish.

### 5. Claude works autonomously

Claude is now running in that cloned working directory with full permissions. It reads your `AGENTS.md`, does whatever it says -- edits files, runs tests, etc. -- and commits its changes. The prompt tells it to:

```bash
git push origin/main
```

That `origin` points back to the bare repo inside the container (since the work directory was cloned from it). So Claude's commits land in `/home/git/repos/myproject.git`.

### 6. You pull Claude's work

```bash
git pull claude main
```

This fetches from the same bare repo that Claude pushed to.

### The whole flow visually

```
Your machine                        Docker container
───────────                         ────────────────
git push claude main
    │
    ▼
SSH to localhost:2222 ──────────▶  sshd
                                      │
                                      ▼
                                   authorized-keys-command.sh
                                   (forces git-shell-wrapper)
                                      │
                                      ▼
                                   git-shell-wrapper
                                   (auto-inits bare repo if new,
                                    copies hooks, delegates to git-shell)
                                      │
                                      ▼
                                   git-receive-pack
                                   (writes objects to bare repo)
                                      │
                                      ▼
                                   post-receive hook
                                   (clones repo → work dir, reads AGENTS.md)
                                      │
                                      ▼
                                   tmux session ──▶ claude -p "..." --dangerously-skip-permissions
                                                        │
                                                        ▼
                                                   (edits, tests, commits)
                                                        │
                                                        ▼
                                                   git push origin/main
                                                   (back to the bare repo)
    │
    ▼
git pull claude main ◀──────────  bare repo now has Claude's commits
```

The SSH plumbing (sshd_config → authorized-keys-command → git-shell-wrapper → git-shell) is all just to get a secure git server that auto-creates repos. The actual "Claude magic" is entirely in the post-receive hook.
