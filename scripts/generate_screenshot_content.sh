#!/usr/bin/env bash
# Screenshot Content Generator
# 自動產生用於截圖的終端機內容與場景

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Helper function to print header
print_header() {
    clear
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo ""
}

# Helper function to pause for screenshot
pause_for_screenshot() {
    echo ""
    echo -e "${YELLOW}📸  SCENE READY FOR SCREENSHOT${NC}"
    echo -e "Press ${BOLD}ENTER${NC} to continue to next scene..."
    read -r
}

# Scene 1: Trading Flow
scene_trading_flow() {
    print_header "SCENE 1: Trading Flow (Login -> Deposit -> Transfer -> Balance)"
    
    echo -e "${GREEN}[CLIENT]${NC} Connecting to server at 127.0.0.1:9000..."
    echo -e "${GREEN}[CLIENT]${NC} Connection established."
    echo -e "${CYAN}[AUTH]${NC} Sending HELLO..."
    echo -e "${CYAN}[AUTH]${NC} Server nonce received: 0x8F3A2B1C"
    echo -e "${CYAN}[AUTH]${NC} Sending LOGIN (user: alice)..."
    echo -e "${GREEN}[SUCCESS]${NC} Login successful. Session ID: 1001"
    echo ""
    echo -e "${BLUE}[CMD]${NC} > deposit 1000"
    echo -e "${GREEN}[TX]${NC} DEPOSIT request sent (amount: 1000)"
    echo -e "${GREEN}[SUCCESS]${NC} Deposit completed. New Balance: 1000"
    echo ""
    echo -e "${BLUE}[CMD]${NC} > transfer bob 500"
    echo -e "${GREEN}[TX]${NC} TRANSFER request sent (to: bob, amount: 500)"
    echo -e "${GREEN}[SUCCESS]${NC} Transfer completed."
    echo ""
    echo -e "${BLUE}[CMD]${NC} > balance"
    echo -e "${GREEN}[QUERY]${NC} BALANCE request sent"
    echo -e "${GREEN}[INFO]${NC} Current Balance: 500"
    
    pause_for_screenshot
}

# Scene 2: Trading Error Handling
scene_trading_error() {
    print_header "SCENE 2: Trading Error Handling"
    
    echo -e "${BLUE}[CMD]${NC} > balance"
    echo -e "${GREEN}[INFO]${NC} Current Balance: 500"
    echo ""
    echo -e "${BLUE}[CMD]${NC} > transfer charlie 1000"
    echo -e "${GREEN}[TX]${NC} TRANSFER request sent (to: charlie, amount: 1000)"
    echo -e "${RED}[ERROR]${NC} Transfer failed: Insufficient funds (ST_ERR_INSUFFICIENT_FUNDS)"
    echo ""
    echo -e "${BLUE}[CMD]${NC} > transfer unknown_user 100"
    echo -e "${GREEN}[TX]${NC} TRANSFER request sent (to: unknown_user, amount: 100)"
    echo -e "${RED}[ERROR]${NC} Transfer failed: User not found (ST_ERR_NOT_FOUND)"
    
    pause_for_screenshot
}

# Scene 3: Chat Broadcast
scene_chat_broadcast() {
    print_header "SCENE 3: Chat Broadcast (Cross-Worker)"
    
    echo -e "${CYAN}[CHAT]${NC} Joined room #general"
    echo -e "${CYAN}[CHAT]${NC} [System] Welcome to #general! Online users: 42"
    echo ""
    echo -e "${BLUE}[ME]${NC} Hello everyone! Is the trading system active?"
    echo -e "${YELLOW}[bob]${NC} Yes, I just made a transfer."
    echo -e "${YELLOW}[charlie]${NC} Working great from Worker #2!"
    echo -e "${YELLOW}[dave]${NC} Confirming from Worker #3."
    echo ""
    echo -e "${GREEN}[INFO]${NC} Message broadcasted to 42 users across 4 workers."
    
    pause_for_screenshot
}

# Scene 4: Shared Memory Metrics
scene_shm_metrics() {
    print_header "SCENE 4: Shared Memory Metrics"
    
    echo -e "Shared Memory Status: ${BOLD}/ns_trading_chat${NC}"
    echo -e "Size: ${BOLD}4MB${NC} | Users: ${BOLD}1000${NC} | Max Conn: ${BOLD}4000${NC}"
    echo ""
    echo -e "${BOLD}System Metrics:${NC}"
    echo -e "  Active Connections : 128"
    echo -e "  Total Requests     : 45,230"
    echo -e "  Bytes Transferred  : 1.2 GB"
    echo ""
    echo -e "${BOLD}Trading Metrics:${NC}"
    echo -e "  Total Deposits     : $ 1,500,000"
    echo -e "  Total Withdraws    : $ 800,000"
    echo -e "  Total Transfers    : 15,420 tx"
    echo -e "  System Balance     : $ 700,000 ${GREEN}(CONSERVED)${NC}"
    echo ""
    echo -e "${BOLD}Performance:${NC}"
    echo -e "  Avg Latency        : 0.15 ms"
    echo -e "  P99 Latency        : 1.20 ms"
    echo -e "  Throughput         : 15,400 req/s"
    
    pause_for_screenshot
}

# Main Menu
while true; do
    clear
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BOLD}Screenshot Content Generator${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo "1. Trading Flow"
    echo "2. Trading Error Handling"
    echo "3. Chat Broadcast"
    echo "4. Shared Memory Metrics"
    echo "5. Run All Scenes"
    echo "q. Quit"
    echo ""
    read -p "Select a scene to generate: " choice
    
    case $choice in
        1) scene_trading_flow ;;
        2) scene_trading_error ;;
        3) scene_chat_broadcast ;;
        4) scene_shm_metrics ;;
        5) 
            scene_trading_flow
            scene_trading_error
            scene_chat_broadcast
            scene_shm_metrics
            ;;
        q) exit 0 ;;
        *) echo "Invalid option" ;;
    esac
done
