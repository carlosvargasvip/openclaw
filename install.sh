#!/bin/bash
#===============================================================================
# Moltbot (Clawdbot) VM Installation Script
# Replicates exe.dev setup for self-hosted environments
# 
# Gateway: ws://127.0.0.1:18789
# Nginx Proxy: Listens on 80, 443, and 8000 → proxies to gateway
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MOLTBOT_PORT=18789
NGINX_HTTP_PORT=80
NGINX_HTTPS_PORT=443
NGINX_ALT_PORT=8000
INSTALL_DIR="$HOME/.clawdbot"
WORKSPACE_DIR="$HOME/clawd"

print_banner() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║     🦞 Moltbot (Clawdbot) VM Installation                     ║"
    echo "║     Self-hosted AI Assistant with Nginx Reverse Proxy         ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    echo -e "\n${GREEN}[STEP]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "Don't run this script as root. It will use sudo when needed."
        exit 1
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        print_error "Cannot detect OS. This script supports Ubuntu/Debian."
        exit 1
    fi
    print_info "Detected OS: $OS $VERSION"
}

install_prerequisites() {
    print_step "Installing prerequisites..."
    
    sudo apt-get update
    sudo apt-get install -y \
        curl \
        git \
        jq \
        ca-certificates \
        openssl \
        gnupg \
        nginx \
        certbot \
        python3-certbot-nginx \
        ufw
    
    print_info "Prerequisites installed"
}

install_nodejs() {
    print_step "Installing Node.js 22..."
    
    # Check if already installed
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
        if [[ $NODE_VERSION -ge 22 ]]; then
            print_info "Node.js $(node -v) already installed"
            return
        fi
    fi
    
    # Install NodeSource repo for Node 22
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
    
    print_info "Node.js $(node -v) installed"
    print_info "npm $(npm -v) installed"
}

install_docker() {
    print_step "Installing Docker (optional, for sandboxing)..."
    
    if command -v docker &> /dev/null; then
        print_info "Docker already installed"
        return
    fi
    
    # Install Docker
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker $USER
    
    print_info "Docker installed. You may need to log out and back in for group changes."
}

setup_swap() {
    print_step "Setting up swap file (2GB)..."
    
    if [[ -f /swapfile ]]; then
        print_info "Swap file already exists"
        return
    fi
    
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    
    # Make persistent
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    fi
    
    sudo sysctl vm.swappiness=10
    
    print_info "Swap configured"
}

install_moltbot() {
    print_step "Installing Moltbot..."
    
    # Install via npm
    sudo npm install -g moltbot@latest
    
    print_info "Moltbot installed: $(moltbot --version 2>/dev/null || echo 'version check pending')"
}

generate_gateway_token() {
    print_step "Generating gateway authentication token..."
    
    GATEWAY_TOKEN=$(openssl rand -hex 32)
    echo "$GATEWAY_TOKEN" > "$HOME/.moltbot_gateway_token"
    chmod 600 "$HOME/.moltbot_gateway_token"
    
    export CLAWDBOT_GATEWAY_TOKEN="$GATEWAY_TOKEN"
    
    print_info "Gateway token generated and saved to ~/.moltbot_gateway_token"
    echo -e "${YELLOW}IMPORTANT: Save this token securely!${NC}"
    echo -e "Token: ${GREEN}$GATEWAY_TOKEN${NC}"
}

configure_nginx() {
    print_step "Configuring Nginx reverse proxy..."
    
    # Get server IP or hostname
    if [[ -n "$MOLTBOT_DOMAIN" ]]; then
        SERVER_NAME="$MOLTBOT_DOMAIN"
    else
        SERVER_NAME=$(hostname -I | awk '{print $1}')
        print_warn "No domain set. Using IP: $SERVER_NAME"
        print_info "Set MOLTBOT_DOMAIN environment variable for a custom domain"
    fi
    
    # Create nginx config
    sudo tee /etc/nginx/sites-available/moltbot.conf > /dev/null << 'NGINX_CONF'
# Moltbot Reverse Proxy Configuration
# Replicates exe.dev setup for self-hosted environments

# Upstream for the Moltbot gateway
upstream moltbot_gateway {
    server 127.0.0.1:18789;
    keepalive 32;
}

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 8000;
    listen [::]:8000;
    
    server_name _;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    location / {
        proxy_pass http://moltbot_gateway;
        proxy_http_version 1.1;
        
        # WebSocket support (critical for Moltbot)
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Standard proxy headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        
        # Timeout settings for long-lived connections
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_connect_timeout 60s;
        
        # Buffer settings
        proxy_buffering off;
        proxy_buffer_size 4k;
        
        # Keep connection alive
        proxy_socket_keepalive on;
    }
    
    # Health check endpoint
    location /nginx-health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
NGINX_CONF

    # Remove default site if exists
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # Enable moltbot site
    sudo ln -sf /etc/nginx/sites-available/moltbot.conf /etc/nginx/sites-enabled/
    
    # Test and reload nginx
    sudo nginx -t
    sudo systemctl reload nginx
    sudo systemctl enable nginx
    
    print_info "Nginx configured and reloaded"
}

configure_firewall() {
    print_step "Configuring firewall..."
    
    sudo ufw allow OpenSSH
    sudo ufw allow 'Nginx Full'  # Allows 80 and 443
    sudo ufw allow 8000/tcp      # Alternative port like exe.dev
    
    # Enable firewall if not already
    sudo ufw --force enable
    
    print_info "Firewall configured"
    sudo ufw status verbose
}

create_moltbot_config() {
    print_step "Creating Moltbot configuration..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$WORKSPACE_DIR"
    
    # Read token if exists
    if [[ -f "$HOME/.moltbot_gateway_token" ]]; then
        GATEWAY_TOKEN=$(cat "$HOME/.moltbot_gateway_token")
    fi
    
    cat > "$INSTALL_DIR/clawdbot.json" << MOLTBOT_CONFIG
{
  "gateway": {
    "bind": "127.0.0.1",
    "port": 18789,
    "trustedProxies": ["127.0.0.1", "::1"],
    "auth": {
      "mode": "token",
      "token": "${GATEWAY_TOKEN:-REPLACE_WITH_YOUR_TOKEN}"
    },
    "controlUi": {
      "enabled": true,
      "allowInsecureAuth": false
    }
  },
  "agents": {
    "defaults": {
      "sandbox": {
        "mode": "non-main",
        "scope": "session",
        "workspaceAccess": "ro"
      }
    }
  },
  "channels": {
    "whatsapp": {
      "enabled": false,
      "allowFrom": []
    },
    "telegram": {
      "enabled": false
    },
    "discord": {
      "enabled": false
    }
  }
}
MOLTBOT_CONFIG

    chmod 600 "$INSTALL_DIR/clawdbot.json"
    
    print_info "Moltbot config created at $INSTALL_DIR/clawdbot.json"
}

create_systemd_service() {
    print_step "Creating systemd service for Moltbot gateway..."
    
    # User service (no sudo needed to manage)
    mkdir -p "$HOME/.config/systemd/user"
    
    cat > "$HOME/.config/systemd/user/moltbot-gateway.service" << SERVICE
[Unit]
Description=Moltbot Gateway Service
After=network.target

[Service]
Type=simple
Environment="NODE_ENV=production"
Environment="CLAWDBOT_GATEWAY_TOKEN=$(cat $HOME/.moltbot_gateway_token 2>/dev/null || echo '')"
ExecStart=$(which moltbot) gateway
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
SERVICE

    # Enable lingering for user services to run without login
    sudo loginctl enable-linger $USER
    
    # Reload and enable
    systemctl --user daemon-reload
    systemctl --user enable moltbot-gateway
    
    print_info "Systemd user service created"
}

setup_ssl() {
    print_step "Setting up SSL (optional)..."
    
    if [[ -z "$MOLTBOT_DOMAIN" ]]; then
        print_warn "No domain set. Skipping SSL setup."
        print_info "To enable SSL later, run:"
        echo "  sudo certbot --nginx -d yourdomain.com"
        return
    fi
    
    # Update nginx server_name
    sudo sed -i "s/server_name _;/server_name $MOLTBOT_DOMAIN;/" /etc/nginx/sites-available/moltbot.conf
    sudo nginx -t && sudo systemctl reload nginx
    
    # Get SSL certificate
    sudo certbot --nginx -d "$MOLTBOT_DOMAIN" --non-interactive --agree-tos --email "${SSL_EMAIL:-admin@$MOLTBOT_DOMAIN}"
    
    print_info "SSL certificate installed for $MOLTBOT_DOMAIN"
}

run_onboarding() {
    print_step "Running Moltbot onboarding..."
    
    echo ""
    echo -e "${YELLOW}Interactive onboarding is starting...${NC}"
    echo "When prompted:"
    echo "  - Gateway bind: ${GREEN}lan${NC} (to allow reverse proxy)"
    echo "  - Gateway auth: ${GREEN}token${NC}"
    echo "  - Gateway token: ${GREEN}$(cat $HOME/.moltbot_gateway_token)${NC}"
    echo "  - Install Gateway daemon: ${GREEN}No${NC} (we use our own systemd service)"
    echo ""
    
    read -p "Press Enter to start onboarding (or Ctrl+C to skip)..."
    
    moltbot onboard --no-install-daemon || true
}

print_summary() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    Installation Complete!                      ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    echo -e "${GREEN}Access URLs:${NC}"
    echo "  • HTTP:  http://$SERVER_IP/"
    echo "  • Alt:   http://$SERVER_IP:8000/"
    if [[ -n "$MOLTBOT_DOMAIN" ]]; then
        echo "  • HTTPS: https://$MOLTBOT_DOMAIN/"
    fi
    echo ""
    
    echo -e "${GREEN}Gateway Token:${NC}"
    echo "  $(cat $HOME/.moltbot_gateway_token)"
    echo ""
    
    echo -e "${GREEN}Useful Commands:${NC}"
    echo "  Start gateway:    systemctl --user start moltbot-gateway"
    echo "  Stop gateway:     systemctl --user stop moltbot-gateway"
    echo "  View logs:        journalctl --user -u moltbot-gateway -f"
    echo "  Check status:     moltbot status"
    echo "  Health check:     moltbot health"
    echo "  Device pairing:   moltbot devices list"
    echo "  Approve device:   moltbot device approve <id>"
    echo ""
    
    echo -e "${GREEN}Configuration Files:${NC}"
    echo "  Moltbot config:   $INSTALL_DIR/clawdbot.json"
    echo "  Nginx config:     /etc/nginx/sites-available/moltbot.conf"
    echo "  Systemd service:  ~/.config/systemd/user/moltbot-gateway.service"
    echo ""
    
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Start the gateway: systemctl --user start moltbot-gateway"
    echo "  2. Access the Control UI: http://$SERVER_IP/?token=YOUR_TOKEN"
    echo "  3. Configure your model provider (Anthropic API key)"
    echo "  4. Set up messaging channels (WhatsApp, Telegram, etc.)"
    echo ""
    
    echo -e "${RED}Security Reminder:${NC}"
    echo "  • Keep your gateway token secret!"
    echo "  • Configure trustedProxies properly in clawdbot.json"
    echo "  • Consider VPN/Tailscale for remote access instead of public exposure"
    echo ""
}

# Main installation flow
main() {
    print_banner
    check_root
    detect_os
    
    echo ""
    echo "This script will install:"
    echo "  • Node.js 22"
    echo "  • Moltbot (Clawdbot) AI Assistant"
    echo "  • Nginx reverse proxy (ports 80, 443, 8000 → 18789)"
    echo "  • Docker (optional, for sandboxing)"
    echo "  • Firewall rules"
    echo "  • Systemd service"
    echo ""
    
    read -p "Continue with installation? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        exit 0
    fi
    
    install_prerequisites
    install_nodejs
    setup_swap
    install_moltbot
    generate_gateway_token
    configure_nginx
    configure_firewall
    create_moltbot_config
    create_systemd_service
    
    # Optional: Docker for sandboxing
    read -p "Install Docker for sandboxing? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_docker
    fi
    
    # Optional: SSL
    if [[ -n "$MOLTBOT_DOMAIN" ]]; then
        read -p "Set up SSL certificate for $MOLTBOT_DOMAIN? [Y/n] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            setup_ssl
        fi
    fi
    
    # Optional: Run onboarding
    read -p "Run Moltbot onboarding wizard? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        run_onboarding
    fi
    
    print_summary
}

# Run main
main "$@"
