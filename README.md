# 🦞 Moltbot (Clawdbot) Self-Hosted VM Setup

This package replicates the **exe.dev** installation approach for Moltbot, allowing you to run it on any VM or server with network access.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Your VM / Server                          │
│                                                                  │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │                    Nginx Reverse Proxy                    │  │
│   │                                                          │  │
│   │   Port 80  ────┐                                         │  │
│   │   Port 8000 ───┴──► http://127.0.0.1:18789              │  │
│   │                     (Moltbot Gateway)                    │  │
│   │                                                          │  │
│   │   Features:                                              │  │
│   │   • WebSocket support                                    │  │
│   │   • X-Forwarded-For headers                             │  │
│   │   • 24hr timeout for long connections                   │  │
│   └──────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              ▼                                   │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │                  Moltbot Gateway                          │  │
│   │                  ws://127.0.0.1:18789                    │  │
│   │                                                          │  │
│   │   • Control UI (web dashboard)                          │  │
│   │   • Agent sessions                                       │  │
│   │   • Channel connections (WhatsApp, Telegram, etc.)      │  │
│   │   • Tool execution                                       │  │
│   └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Network Access
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│   External Access Options:                                       │
│                                                                  │
│   • LAN: http://192.168.x.x/ or http://192.168.x.x:8000/       │
│   • Your external reverse proxy handles SSL/HTTPS              │
└─────────────────────────────────────────────────────────────────┘
```

## Installation Options

### Option 1: Automated Script (Recommended for VMs)

Best for: Ubuntu/Debian VMs, VPS servers

```bash
# Download and run the installer
chmod +x install.sh
./install.sh
```

The script will:
1. Install Node.js 22 and prerequisites
2. Install Moltbot via npm
3. Configure Nginx reverse proxy (ports 80, 8000 → 18789)
4. Generate a secure gateway token
5. Set up firewall rules (UFW)
6. Create systemd service
7. (Optional) Set up Docker for sandboxing

### Option 2: Docker Compose

Best for: Existing Docker environments, containerized deployments

```bash
cd docker/

# Copy and configure environment
cp .env.example .env
nano .env  # Add your ANTHROPIC_API_KEY

# Start services
./start.sh
```

Or manually:

```bash
docker compose up -d
docker compose logs -f
```

## Configuration

### Gateway Token Authentication

The gateway uses token-based authentication. Your token is generated during installation and saved to:

- Script install: `~/.moltbot_gateway_token`
- Docker: `.env` file (GATEWAY_TOKEN)

Access the Control UI with your token:
```
http://YOUR_SERVER_IP/?token=YOUR_GATEWAY_TOKEN
```

### Trusted Proxies (CRITICAL for Security)

When running behind Nginx, you MUST configure `trustedProxies` to prevent authentication bypass:

```json
{
  "gateway": {
    "trustedProxies": ["127.0.0.1", "::1"],
    "auth": {
      "mode": "token",
      "token": "your-token-here"
    }
  }
}
```

**Security Note:** Without proper `trustedProxies` configuration, an attacker could spoof the `X-Forwarded-For` header and bypass authentication.

### Nginx Configuration

The Nginx config proxies these ports to the gateway:

| External Port | Protocol | Notes |
|--------------|----------|-------|
| 80 | HTTP | Standard web access |
| 8000 | HTTP | Alternative port (like exe.dev) |

Key features:
- WebSocket support for real-time communication
- 24-hour timeout for long-lived agent sessions
- Proper header forwarding for IP detection
- No buffering for streaming responses

## Usage

### Starting/Stopping the Gateway

**Script installation (systemd):**
```bash
# Start
systemctl --user start moltbot-gateway

# Stop
systemctl --user stop moltbot-gateway

# Restart
systemctl --user restart moltbot-gateway

# View logs
journalctl --user -u moltbot-gateway -f
```

**Docker:**
```bash
# Start
docker compose up -d

# Stop
docker compose down

# Restart
docker compose restart

# View logs
docker compose logs -f
```

### Moltbot CLI Commands

```bash
# Check status
moltbot status
moltbot health

# View devices/pairing
moltbot devices list

# Approve a device
moltbot device approve <request-id>

# Run doctor (troubleshooting)
moltbot doctor

# Start agent conversation
moltbot agent --message "Hello"
```

### Channel Setup

**WhatsApp:**
```bash
moltbot channels login
# Scan QR code with your phone
```

**Telegram:**
1. Create a bot via @BotFather
2. Add token to config or .env:
```json
{
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "YOUR_BOT_TOKEN",
      "allowFrom": ["your_username"]
    }
  }
}
```

## Network Access

### Local Network (LAN)

Access from any device on your network:
```
http://192.168.x.x/
http://192.168.x.x:8000/
```

### Remote Access Options

**1. External Reverse Proxy**
- Your external proxy handles SSL termination
- Forward to this server on port 80 or 8000

**2. VPN/WireGuard**
- Set up WireGuard on your VM
- Connect from remote devices via VPN
- Gateway stays on localhost, maximum security

**3. Tailscale**
```bash
# Install Tailscale on VM
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Access via Tailscale IP
http://100.x.x.x/
```

**4. SSH Tunnel**
```bash
# From your local machine
ssh -L 8000:localhost:18789 user@your-server

# Then access locally
http://localhost:8000/
```

## Security Best Practices

1. **Never expose port 18789 directly** - Always use Nginx reverse proxy
2. **Use strong gateway tokens** - At least 32 random hex characters
3. **Configure trustedProxies** - Prevents authentication bypass
4. **Enable sandboxing** - Run agent commands in Docker containers
5. **Prefer VPN/Tailscale** - For remote access instead of public exposure
6. **Regular updates** - Keep Moltbot and dependencies updated

## Troubleshooting

### Gateway not accessible

```bash
# Check if gateway is running
moltbot status

# Check port binding
ss -tlnp | grep 18789

# Check nginx
sudo nginx -t
sudo systemctl status nginx
```

### WebSocket connection fails

Ensure Nginx has WebSocket headers:
```nginx
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

### Authentication bypass warning

Update `clawdbot.json`:
```json
{
  "gateway": {
    "trustedProxies": ["127.0.0.1"]
  }
}
```

### Docker networking issues

```bash
# Check network
docker network inspect moltbot-internal

# Check if gateway is listening
docker compose exec moltbot-gateway curl http://localhost:18789/health
```

## File Locations

### Script Installation
- Config: `~/.clawdbot/clawdbot.json`
- State: `~/.clawdbot/`
- Workspace: `~/clawd/`
- Token: `~/.moltbot_gateway_token`
- Nginx: `/etc/nginx/sites-available/moltbot.conf`
- Service: `~/.config/systemd/user/moltbot-gateway.service`

### Docker Installation
- Config: `./config/clawdbot.json`
- Environment: `./.env`
- Nginx: `./config/moltbot-site.conf`
- Data volume: `moltbot-data`
- Workspace volume: `moltbot-workspace`

## Updating

**Script installation:**
```bash
npm update -g moltbot
moltbot doctor
systemctl --user restart moltbot-gateway
```

**Docker:**
```bash
docker compose down
docker compose pull
docker compose up -d
```

## References

- [Moltbot Documentation](https://docs.molt.bot/)
- [exe.dev Installation Guide](https://docs.molt.bot/platforms/exe-dev)
- [Security Guide](https://docs.molt.bot/gateway/security)
- [Docker Installation](https://docs.molt.bot/install/docker)
