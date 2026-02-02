#!/bin/bash
#===============================================================================
# OpenClaw Docker Quick Start Script
#===============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

print_banner() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║     🦞 OpenClaw Docker Quick Start                            ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker is not installed. Please install Docker first:${NC}"
        echo "  curl -fsSL https://get.docker.com | sh"
        exit 1
    fi
    
    if ! docker compose version &> /dev/null; then
        echo -e "${RED}Docker Compose is not available.${NC}"
        exit 1
    fi
}

setup_env() {
    if [[ ! -f .env ]]; then
        echo -e "${YELLOW}Creating .env file from template...${NC}"
        cp .env.example .env
        
        # Generate gateway token
        TOKEN=$(openssl rand -hex 32)
        sed -i "s/GATEWAY_TOKEN=.*/GATEWAY_TOKEN=$TOKEN/" .env
        
        echo -e "${GREEN}Generated gateway token: $TOKEN${NC}"
        echo ""
        echo -e "${YELLOW}Please edit .env and add your API keys:${NC}"
        echo "  nano .env"
        echo ""
        echo "Required: ANTHROPIC_API_KEY or OPENAI_API_KEY"
        exit 0
    fi
}

check_api_key() {
    source .env
    
    if [[ -z "$ANTHROPIC_API_KEY" && -z "$OPENAI_API_KEY" ]]; then
        echo -e "${RED}No API key configured!${NC}"
        echo "Please add ANTHROPIC_API_KEY or OPENAI_API_KEY to .env"
        exit 1
    fi
}

start_services() {
    echo -e "${GREEN}Pulling and starting OpenClaw services...${NC}"
    docker compose pull
    docker compose up -d
    
    echo ""
    echo -e "${GREEN}Waiting for services to start...${NC}"
    sleep 10
    
    docker compose ps
}

show_info() {
    source .env
    SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    OpenClaw is Running!                        ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${GREEN}Access URLs:${NC}"
    echo "  • Control UI: http://$SERVER_IP/"
    echo "  • Alt Port:   http://$SERVER_IP:8000/"
    echo ""
    
    echo -e "${GREEN}Gateway Token:${NC}"
    echo "  $GATEWAY_TOKEN"
    echo ""
    
    echo -e "${GREEN}Access with token:${NC}"
    echo "  http://$SERVER_IP/?token=$GATEWAY_TOKEN"
    echo ""
    
    echo -e "${GREEN}Useful Commands:${NC}"
    echo "  View logs:        docker compose logs -f"
    echo "  Stop services:    docker compose down"
    echo "  Restart:          docker compose restart"
    echo "  CLI access:       docker compose run --rm openclaw-cli"
    echo "  Shell access:     docker compose exec openclaw-gateway bash"
    echo "  Dashboard URL:    docker compose run --rm openclaw-cli node dist/index.js dashboard --no-open"
    echo ""
}

# Main
case "${1:-start}" in
    start)
        print_banner
        check_docker
        setup_env
        check_api_key
        start_services
        show_info
        ;;
    stop)
        docker compose down
        echo "OpenClaw stopped"
        ;;
    restart)
        docker compose restart
        echo "OpenClaw restarted"
        ;;
    logs)
        docker compose logs -f
        ;;
    status)
        docker compose ps
        ;;
    cli)
        docker compose run --rm openclaw-cli
        ;;
    build)
        echo "Pulling latest OpenClaw image..."
        docker compose pull
        ;;
    onboard)
        echo "Running OpenClaw onboarding..."
        docker compose run --rm openclaw-cli onboard
        ;;
    dashboard)
        docker compose run --rm openclaw-cli dashboard --no-open
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|logs|status|cli|build|onboard|dashboard}"
        exit 1
        ;;
esac
