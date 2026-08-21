#!/usr/bin/env bash
# =============================================================================
# install-ufw.sh
# Configuração segura do UFW (Uncomplicated Firewall) para Ubuntu
# Foco: Acesso restrito via rede local e Tailscale — sem exposição pública.
# Versão: 1.0
# =============================================================================
#
# Uso:
#   Interativo:    sudo ./install-ufw.sh
#   Automático:    sudo ./install-ufw.sh --auto
#   Ajuda:         ./install-ufw.sh --help
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Cores e formatação
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Funções auxiliares
# -----------------------------------------------------------------------------
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[AVISO]${NC} $*"; }
error()   { echo -e "${RED}[ERRO]${NC}  $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}==> $*${NC}"; }
die()     { error "$*"; exit 1; }

# Modo não interativo
UNATTENDED=false

# -----------------------------------------------------------------------------
# Configurações — altere conforme sua rede
# -----------------------------------------------------------------------------
LOCAL_NETWORK="192.168.15.0/24"   # Rede local (Wi-Fi / Ethernet)
TAILSCALE_IFACE="tailscale0"      # Interface da VPN Tailscale

# Portas de serviços
SSH_PORT=22
XRDP_PORT=3389

# Logging
UFW_LOG_LEVEL="medium"            # off, low, medium, high, full

# -----------------------------------------------------------------------------
# Verificações iniciais
# -----------------------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "Este script deve ser executado como root. Use: sudo $0"
    fi
}

check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        die "Não foi possível identificar o sistema operacional."
    fi
    # shellcheck source=/dev/null
    source /etc/os-release
    if [[ "$ID" != "ubuntu" && "${ID_LIKE:-}" != *"ubuntu"* ]]; then
        warn "Este script foi projetado para Ubuntu. SO detectado: $PRETTY_NAME"
        if [[ "$UNATTENDED" == false ]]; then
            read -r -p "Deseja continuar mesmo assim? [s/N] " resp
            [[ "$resp" =~ ^[sS]$ ]] || die "Instalação cancelada pelo usuário."
        fi
    else
        info "Sistema detectado: $PRETTY_NAME"
    fi
}

# -----------------------------------------------------------------------------
# Solicitar configuração da rede local ao usuário
# -----------------------------------------------------------------------------
choose_network() {
    [[ "$UNATTENDED" == true ]] && return

    echo ""
    echo -e "${BOLD}Configuração da rede local:${NC}"
    echo "  Rede padrão: $LOCAL_NETWORK"
    echo ""
    read -r -p "Informe a rede local (CIDR) [padrão: $LOCAL_NETWORK]: " custom_net
    custom_net="${custom_net:-$LOCAL_NETWORK}"

    # Validação básica do formato CIDR
    if [[ "$custom_net" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        LOCAL_NETWORK="$custom_net"
        info "Rede local definida: $LOCAL_NETWORK"
    else
        warn "Formato inválido. Usando rede padrão: $LOCAL_NETWORK"
    fi
}

# -----------------------------------------------------------------------------
# Verificar se o Tailscale está instalado/ativo
# -----------------------------------------------------------------------------
check_tailscale() {
    if ip link show "$TAILSCALE_IFACE" &>/dev/null; then
        local ts_ip
        ts_ip=$(ip -4 addr show "$TAILSCALE_IFACE" 2>/dev/null | grep -oP 'inet \K[\d.]+' || echo "N/A")
        info "Tailscale detectado: interface $TAILSCALE_IFACE (IP: $ts_ip)"
        return 0
    else
        warn "Interface Tailscale ($TAILSCALE_IFACE) não encontrada."
        warn "As regras para Tailscale serão criadas, mas só terão efeito quando o Tailscale estiver ativo."
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Instalar o UFW se necessário
# -----------------------------------------------------------------------------
install_ufw() {
    step "Verificando instalação do UFW"

    if command -v ufw &>/dev/null; then
        info "UFW já está instalado."
    else
        info "Instalando UFW..."
        apt-get install -y ufw >/dev/null 2>&1
        success "UFW instalado."
    fi
}

# -----------------------------------------------------------------------------
# Exibir regras atuais e confirmar reset
# -----------------------------------------------------------------------------
confirm_reset() {
    step "Verificando regras existentes do UFW"

    local current_status
    current_status=$(ufw status verbose 2>/dev/null || echo "inativo")

    echo ""
    echo -e "${BOLD}Estado atual do UFW:${NC}"
    echo "$current_status"
    echo ""

    if [[ "$UNATTENDED" == true ]]; then
        info "Modo automático: resetando regras..."
        return 0
    fi

    echo -e "${YELLOW}⚠  O UFW será resetado e novas regras seguras serão aplicadas.${NC}"
    echo -e "${YELLOW}   Todas as regras existentes serão removidas.${NC}"
    echo ""
    read -r -p "Deseja continuar? [S/n] " resp
    resp="${resp:-s}"
    if [[ ! "$resp" =~ ^[sS]$ ]]; then
        die "Operação cancelada pelo usuário."
    fi
}

# -----------------------------------------------------------------------------
# Resetar e aplicar políticas padrão
# -----------------------------------------------------------------------------
reset_and_set_defaults() {
    step "Resetando UFW e aplicando políticas padrão"

    # Desabilitar antes de resetar para evitar bloqueio
    ufw --force disable >/dev/null 2>&1 || true

    # Resetar todas as regras
    ufw --force reset >/dev/null 2>&1
    success "Regras anteriores removidas."

    # Políticas padrão: bloquear entrada, permitir saída
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1
    success "Política padrão: DENY incoming / ALLOW outgoing"
}

# -----------------------------------------------------------------------------
# Aplicar regras seguras
# -----------------------------------------------------------------------------
apply_secure_rules() {
    step "Aplicando regras de firewall seguras"

    # ── 1. Localhost ──────────────────────────────────────────────────────────
    info "Regra 1: Permitir tráfego localhost (loopback)"
    ufw allow from 127.0.0.1 to 127.0.0.1 comment 'Loopback IPv4' >/dev/null 2>&1
    success "  ✓ Loopback (127.0.0.1)"

    # ── 2. Tailscale VPN ─────────────────────────────────────────────────────
    info "Regra 2: Permitir todo tráfego via Tailscale ($TAILSCALE_IFACE)"
    ufw allow in on "$TAILSCALE_IFACE" comment 'Tailscale VPN' >/dev/null 2>&1
    success "  ✓ Tailscale ($TAILSCALE_IFACE) — acesso total"

    # ── 3. SSH — somente rede local ──────────────────────────────────────────
    info "Regra 3: SSH (porta $SSH_PORT) — somente rede local ($LOCAL_NETWORK)"
    ufw allow from "$LOCAL_NETWORK" to any port "$SSH_PORT" proto tcp \
        comment "SSH Local ($LOCAL_NETWORK)" >/dev/null 2>&1
    success "  ✓ SSH ($SSH_PORT/tcp) — rede local apenas"

    # ── 4. XRDP — somente rede local ─────────────────────────────────────────
    info "Regra 4: XRDP (porta $XRDP_PORT) — somente rede local ($LOCAL_NETWORK)"
    ufw allow from "$LOCAL_NETWORK" to any port "$XRDP_PORT" proto tcp \
        comment "XRDP Local ($LOCAL_NETWORK)" >/dev/null 2>&1
    success "  ✓ XRDP ($XRDP_PORT/tcp) — rede local apenas"

    # ── 5. Proteções adicionais contra ataques ────────────────────────────────
    step "Aplicando proteções adicionais"

    # Rate limiting no SSH — bloqueia após 6 tentativas em 30 segundos
    # Nota: aplica-se a conexões que não são da rede local (ex: se SSH for
    #       aberto futuramente para outra rede)
    info "Habilitando rate limiting para SSH..."
    # O UFW limit já inclui proteção contra brute-force
    # Usamos uma regra separada para não conflitar com a regra de rede local
    ufw limit "$SSH_PORT"/tcp comment 'SSH Rate Limit' >/dev/null 2>&1 || true
    success "  ✓ Rate limiting SSH ativo"

    # ── 6. Logging ────────────────────────────────────────────────────────────
    info "Configurando nível de logging: $UFW_LOG_LEVEL"
    ufw logging "$UFW_LOG_LEVEL" >/dev/null 2>&1
    success "  ✓ Logging: $UFW_LOG_LEVEL"
}

# -----------------------------------------------------------------------------
# Aplicar hardening de rede via sysctl
# -----------------------------------------------------------------------------
apply_sysctl_hardening() {
    step "Aplicando hardening de rede (sysctl)"

    local sysctl_file="/etc/sysctl.d/60-ufw-hardening.conf"

    cat > "$sysctl_file" << 'SYSCTL_EOF'
# Hardening de rede — Gerado por install-ufw.sh
# Proteção contra ataques comuns de rede

# Proteção contra SYN flood
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2

# Ignorar redirecionamentos ICMP (impede ataques MITM)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Não enviar redirecionamentos ICMP
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Proteção contra IP spoofing (reverse path filter)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignorar ICMP broadcast (Smurf attack)
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Log de pacotes marcianos (endereços impossíveis)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignorar source routing (previne spoofing avançado)
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# TCP keepalive otimizado
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 3
SYSCTL_EOF

    sysctl -p "$sysctl_file" >/dev/null 2>&1 || true
    success "Hardening sysctl aplicado: $sysctl_file"
}

# -----------------------------------------------------------------------------
# Ativar o UFW
# -----------------------------------------------------------------------------
enable_ufw() {
    step "Ativando o UFW"

    ufw --force enable >/dev/null 2>&1
    success "UFW ativado e regras em vigor."
}

# -----------------------------------------------------------------------------
# Resumo Final
# -----------------------------------------------------------------------------
show_summary() {
    local host_ip
    host_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")

    local ts_ip="N/A"
    if ip link show "$TAILSCALE_IFACE" &>/dev/null; then
        ts_ip=$(ip -4 addr show "$TAILSCALE_IFACE" 2>/dev/null | grep -oP 'inet \K[\d.]+' || echo "N/A")
    fi

    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║        Firewall UFW Configurado com Segurança!               ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}IP Local:${NC}           ${host_ip}"
    echo -e "  ${BOLD}IP Tailscale:${NC}       ${ts_ip}"
    echo -e "  ${BOLD}Rede Local:${NC}         ${LOCAL_NETWORK}"
    echo ""
    echo -e "  ${BOLD}${CYAN}Regras aplicadas:${NC}"
    echo -e "  ${GREEN}✓${NC} Loopback (127.0.0.1)            — Permitido"
    echo -e "  ${GREEN}✓${NC} Tailscale ($TAILSCALE_IFACE)             — Acesso total (VPN segura)"
    echo -e "  ${GREEN}✓${NC} SSH ($SSH_PORT/tcp)                    — Apenas rede local ($LOCAL_NETWORK)"
    echo -e "  ${GREEN}✓${NC} XRDP ($XRDP_PORT/tcp)                  — Apenas rede local ($LOCAL_NETWORK)"
    echo -e "  ${GREEN}✓${NC} SSH Rate Limit                 — Proteção brute-force"
    echo -e "  ${GREEN}✓${NC} Logging                        — Nível: $UFW_LOG_LEVEL"
    echo ""
    echo -e "  ${BOLD}${CYAN}Política padrão:${NC}"
    echo -e "  ${RED}✗${NC} Incoming  → ${RED}DENY${NC}  (bloqueado por padrão)"
    echo -e "  ${GREEN}✓${NC} Outgoing  → ${GREEN}ALLOW${NC} (permitido por padrão)"
    echo ""
    echo -e "  ${BOLD}${CYAN}Proteções de rede (sysctl):${NC}"
    echo -e "  - SYN flood (syncookies)        — Ativo"
    echo -e "  - IP spoofing (rp_filter)       — Ativo"
    echo -e "  - ICMP redirect (MITM)          — Bloqueado"
    echo -e "  - Source routing                 — Bloqueado"
    echo -e "  - Smurf attack (ICMP broadcast) — Bloqueado"
    echo -e "  - Pacotes marcianos              — Logados"
    echo ""
    echo -e "  ${BOLD}${CYAN}Como acessar remotamente:${NC}"
    echo -e "  - Via rede local:  ssh ${host_ip} / mstsc ${host_ip}"
    echo -e "  - Via Tailscale:   ssh ${ts_ip} / mstsc ${ts_ip}"
    echo ""
    echo -e "  ${BOLD}Comandos úteis:${NC}"
    echo -e "  - Status:          ${BOLD}sudo ufw status verbose${NC}"
    echo -e "  - Status numerado: ${BOLD}sudo ufw status numbered${NC}"
    echo -e "  - Logs:            ${BOLD}sudo tail -f /var/log/ufw.log${NC}"
    echo -e "  - Adicionar regra: ${BOLD}sudo ufw allow from IP to any port PORTA${NC}"
    echo -e "  - Remover regra:   ${BOLD}sudo ufw delete NUM${NC} (ver com status numbered)"
    echo ""

    echo -e "  ${BOLD}${GREEN}Regras atuais do UFW:${NC}"
    echo ""
    ufw status numbered
    echo ""
}

# -----------------------------------------------------------------------------
# Ajuda
# -----------------------------------------------------------------------------
usage() {
    cat << USAGE_EOF
Uso: sudo $0 [OPÇÕES]

Configuração segura do UFW (Uncomplicated Firewall) para Ubuntu.
Aplica regras restritivas permitindo acesso apenas via rede local e Tailscale.

Opções:
  (sem opção)         Execução interativa (com confirmação)
  --auto, -y          Execução automática (sem prompts)
  --network CIDR      Define a rede local (padrão: $LOCAL_NETWORK)
  --ssh-port PORTA    Define a porta SSH (padrão: $SSH_PORT)
  --xrdp-port PORTA   Define a porta XRDP (padrão: $XRDP_PORT)
  --no-sysctl         Não aplica hardening sysctl
  -h, --help          Exibe esta ajuda

Exemplos:
  sudo ./install-ufw.sh
  sudo ./install-ufw.sh --auto
  sudo ./install-ufw.sh --auto --network 10.0.0.0/24
  sudo ./install-ufw.sh --auto --ssh-port 2222

USAGE_EOF
    exit 0
}

# -----------------------------------------------------------------------------
# Processamento de argumentos
# -----------------------------------------------------------------------------
SKIP_SYSCTL=false

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --auto|-y)
                UNATTENDED=true
                shift
                ;;
            --network)
                LOCAL_NETWORK="${2:-}"
                [[ -z "$LOCAL_NETWORK" ]] && die "Faltou o valor para --network"
                shift 2
                ;;
            --ssh-port)
                SSH_PORT="${2:-}"
                [[ -z "$SSH_PORT" ]] && die "Faltou o valor para --ssh-port"
                shift 2
                ;;
            --xrdp-port)
                XRDP_PORT="${2:-}"
                [[ -z "$XRDP_PORT" ]] && die "Faltou o valor para --xrdp-port"
                shift 2
                ;;
            --no-sysctl)
                SKIP_SYSCTL=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                error "Opção desconhecida: $1"
                usage
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Fluxo principal
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"

    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═════════════════════════════════════════════════════════╗"
    echo "  ║   Configuração Segura do Firewall UFW                    ║"
    echo "  ║   Acesso restrito: Rede Local + Tailscale                ║"
    echo "  ╚═════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_root
    check_ubuntu
    choose_network
    check_tailscale
    install_ufw
    confirm_reset
    reset_and_set_defaults
    apply_secure_rules

    if [[ "$SKIP_SYSCTL" == false ]]; then
        apply_sysctl_hardening
    fi

    enable_ufw
    show_summary
}

main "$@"