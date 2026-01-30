FROM node:24-bookworm-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install moltbot globally
RUN npm install -g moltbot@latest

# Create data directories
RUN mkdir -p /data/.clawdbot /data/clawd

# Set environment
ENV NODE_ENV=production
ENV HOME=/data
ENV CLAWDBOT_STATE_DIR=/data/.clawdbot
ENV PATH=/usr/local/bin:/usr/bin:/bin

WORKDIR /data

# Expose gateway port
EXPOSE 18789

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
    CMD node -e "fetch('http://localhost:18789/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

# Default command
CMD ["moltbot", "gateway", "--verbose"]
