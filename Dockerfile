FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    openssh-server \
    git \
    tmux \
    curl \
    jq \
    ca-certificates \
    iptables \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20 (required for Claude CLI)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Claude CLI
RUN npm install -g @anthropic-ai/claude-code

# Create git user with git-shell
RUN useradd -m -s /usr/bin/git-shell git \
    && passwd -u git \
    && mkdir -p /home/git/.ssh \
    && mkdir -p /home/git/repos \
    && mkdir -p /home/git/hooks \
    && mkdir -p /home/git/work \
    && chown -R git:git /home/git

# SSH setup
RUN mkdir -p /run/sshd /etc/ssh/ssh_host_keys

COPY sshd_config /etc/ssh/sshd_config
COPY git-shell-wrapper /usr/local/bin/git-shell-wrapper
COPY authorized-keys-command.sh /usr/local/bin/authorized-keys-command.sh
RUN chmod 755 /usr/local/bin/git-shell-wrapper /usr/local/bin/authorized-keys-command.sh

# Default hooks
COPY hooks/ /home/git/hooks/
RUN chmod +x /home/git/hooks/* && chown -R git:git /home/git/hooks

COPY firewall.sh /usr/local/bin/firewall.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/firewall.sh /usr/local/bin/entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
