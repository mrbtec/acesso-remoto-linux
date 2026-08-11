#!/usr/bin/env bash
# =============================================================================
# install-ssh-server.sh
# Instalação automatizada do servidor SSH (OpenSSH) com hardening no Ubuntu
# Versão: 1.0
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
    if [[ "$ID" != "ubuntu" ]]; then
        warn "Este script foi projetado para Ubuntu. SO detectado: $PRETTY_NAME"
        read -r -p "Deseja continuar mesmo assim? [s/N] " resp
        [[ "$resp" =~ ^[sS]$ ]] || die "Instalação cancelada."
    else
        info "Sistema detectado: $PRETTY_NAME"
    fi
}

# -----------------------------------------------------------------------------
# Configurações — altere conforme necessário
# -----------------------------------------------------------------------------
SSH_PORT=22
SSH_CONFIG="/etc/ssh/sshd_config"
SSH_CONFIG_DIR="/etc/ssh/sshd_config.d"
CUSTOM_CONFIG="${SSH_CONFIG_DIR}/99-hardening.conf"
BANNER_FILE="/etc/ssh/banner.txt"

# Opções de hardening
MAX_AUTH_TRIES=3
LOGIN_GRACE_TIME=60
MAX_SESSIONS=10
CLIENT_ALIVE_INTERVAL=300
CLIENT_ALIVE_COUNT_MAX=3

# -----------------------------------------------------------------------------
# Solicitar porta SSH ao usuário
# -----------------------------------------------------------------------------
choose_ssh_port() {
    echo ""
    echo -e "${BOLD}Configuração da porta SSH:${NC}"
    echo "  Porta padrão: 22"
    echo "  (Usar uma porta não-padrão adiciona segurança por obscuridade)"
    echo ""
    read -r -p "Porta SSH [padrão: 22]: " custom_port
    custom_port="${custom_port:-22}"

    if [[ "$custom_port" =~ ^[0-9]+$ ]] && (( custom_port >= 1 && custom_port <= 65535 )); then
        SSH_PORT="$custom_port"
        info "Porta SSH configurada: $SSH_PORT"
    else
        warn "Porta inválida. Usando porta padrão 22."
        SSH_PORT=22
    fi
}

# -----------------------------------------------------------------------------
# Solicitar método de autenticação
# -----------------------------------------------------------------------------
choose_auth_method() {
    echo ""
    echo -e "${BOLD}Método de autenticação:${NC}"
    echo "  1) Chave SSH + Senha     (recomendado para começar)"
    echo "  2) Somente chave SSH     (mais seguro, requer chave configurada)"
    echo "  3) Somente senha         (menos seguro, não recomendado)"
    echo ""
    read -r -p "Escolha o método [1-3] (padrão: 1): " auth_choice
    auth_choice="${auth_choice:-1}"

    case "$auth_choice" in
        1) AUTH_METHOD="both"     ;;
        2) AUTH_METHOD="key_only" ;;
        3) AUTH_METHOD="password" ;;
        *) warn "Opção inválida. Usando chave + senha."; AUTH_METHOD="both" ;;
    esac
}

# -----------------------------------------------------------------------------
# Instalar OpenSSH Server
# -----------------------------------------------------------------------------
install_ssh() {
    step "Instalando OpenSSH Server"

    if dpkg -l | grep -q openssh-server 2>/dev/null; then
        info "OpenSSH Server já está instalado."
    else
        apt-get install -y openssh-server
        success "OpenSSH Server instalado."
    fi
}

# -----------------------------------------------------------------------------
# Backup da configuração original
# -----------------------------------------------------------------------------
backup_config() {
    step "Criando backup da configuração SSH"

    if [[ ! -f "${SSH_CONFIG}.bak" ]]; then
        cp "$SSH_CONFIG" "${SSH_CONFIG}.bak"
        success "Backup criado: ${SSH_CONFIG}.bak"
    else
        info "Backup já existe: ${SSH_CONFIG}.bak"
    fi
}

# -----------------------------------------------------------------------------
# Aplicar hardening no sshd_config
# -----------------------------------------------------------------------------
configure_sshd() {
    step "Aplicando hardening no SSH"

    mkdir -p "$SSH_CONFIG_DIR"

    # Garantir que Include está habilitado no sshd_config principal
    if ! grep -q "^Include ${SSH_CONFIG_DIR}/\*.conf" "$SSH_CONFIG" 2>/dev/null; then
        # Adicionar Include no início do arquivo (após comentários iniciais)
        if grep -q "^Include" "$SSH_CONFIG"; then
            info "Include já configurado em $SSH_CONFIG"
        else
            sed -i "1s|^|Include ${SSH_CONFIG_DIR}/*.conf\n|" "$SSH_CONFIG"
            info "Include adicionado em $SSH_CONFIG"
        fi
    fi

    # Construir arquivo de configuração de hardening
    cat > "$CUSTOM_CONFIG" << SSHD_EOF
# =============================================================================
# Configuração de hardening SSH
# Gerado por install-ssh-server.sh — NÃO EDITAR MANUALMENTE
# Data: $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================================

# --- Porta e protocolo ---
Port ${SSH_PORT}

# --- Autenticação ---
PermitRootLogin no
MaxAuthTries ${MAX_AUTH_TRIES}
LoginGraceTime ${LOGIN_GRACE_TIME}
MaxSessions ${MAX_SESSIONS}
SSHD_EOF

    # Método de autenticação
    case "$AUTH_METHOD" in
        both)
            cat >> "$CUSTOM_CONFIG" << 'AUTH_EOF'

# Autenticação: chave SSH + senha
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
AUTH_EOF
            ;;
        key_only)
            cat >> "$CUSTOM_CONFIG" << 'AUTH_EOF'

# Autenticação: somente chave SSH
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
AUTH_EOF
            ;;
        password)
            cat >> "$CUSTOM_CONFIG" << 'AUTH_EOF'

# Autenticação: somente senha
PubkeyAuthentication no
PasswordAuthentication yes
PermitEmptyPasswords no
AUTH_EOF
            ;;
    esac

    # Hardening adicional
    cat >> "$CUSTOM_CONFIG" << SSHD2_EOF

# --- Hardening geral ---
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitTunnel no
GatewayPorts no
PrintMotd no
PrintLastLog yes

# --- Sessões ociosas ---
ClientAliveInterval ${CLIENT_ALIVE_INTERVAL}
ClientAliveCountMax ${CLIENT_ALIVE_COUNT_MAX}

# --- Logging ---
SyslogFacility AUTH
LogLevel VERBOSE

# --- Criptografia forte ---
# KexAlgorithms (troca de chaves)
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

# Ciphers (cifragem)
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr

# MACs (integridade)
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com

# Host key algorithms
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256

# --- Banner ---
Banner ${BANNER_FILE}

# --- Desabilitar recursos desnecessários ---
PermitUserEnvironment no
DebianBanner no
SSHD2_EOF

    chmod 600 "$CUSTOM_CONFIG"
    success "Configuração de hardening salva: $CUSTOM_CONFIG"
}

# -----------------------------------------------------------------------------
# Gerar chaves do host (Ed25519 + RSA)
# -----------------------------------------------------------------------------
generate_host_keys() {
    step "Verificando chaves do host SSH"

    # Remover chaves fracas (DSA, ECDSA) se existirem
    for keytype in dsa ecdsa; do
        if [[ -f "/etc/ssh/ssh_host_${keytype}_key" ]]; then
            rm -f "/etc/ssh/ssh_host_${keytype}_key" "/etc/ssh/ssh_host_${keytype}_key.pub"
            info "Chave ${keytype} removida (considerada fraca)."
        fi
    done

    # Gerar Ed25519 se não existir
    if [[ ! -f /etc/ssh/ssh_host_ed25519_key ]]; then
        ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" -q
        success "Chave Ed25519 do host gerada."
    else
        info "Chave Ed25519 do host já existe."
    fi

    # Gerar RSA 4096 se não existir
    if [[ ! -f /etc/ssh/ssh_host_rsa_key ]]; then
        ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N "" -q
        success "Chave RSA 4096 do host gerada."
    else
        info "Chave RSA do host já existe."
    fi
}

# -----------------------------------------------------------------------------
# Gerar par de chaves SSH para o usuário (se solicitado)
# -----------------------------------------------------------------------------
generate_user_key() {
    local real_user="${SUDO_USER:-$USER}"
    local home_dir
    home_dir=$(getent passwd "$real_user" | cut -d: -f6)

    [[ -z "$home_dir" || ! -d "$home_dir" ]] && return

    local ssh_dir="$home_dir/.ssh"

    if [[ -f "$ssh_dir/id_ed25519" ]]; then
        info "Chave SSH do usuário '$real_user' já existe: $ssh_dir/id_ed25519"
        return
    fi

    echo ""
    read -r -p "Deseja gerar um par de chaves SSH para o usuário '$real_user'? [S/n] " resp
    resp="${resp:-s}"

    if [[ "$resp" =~ ^[sS]$ ]]; then
        step "Gerando chave SSH Ed25519 para '$real_user'"

        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"

        ssh-keygen -t ed25519 -f "$ssh_dir/id_ed25519" -N "" -C "${real_user}@$(hostname)" -q
        chmod 600 "$ssh_dir/id_ed25519"
        chmod 644 "$ssh_dir/id_ed25519.pub"
        chown -R "$real_user":"$real_user" "$ssh_dir"

        success "Chave gerada: $ssh_dir/id_ed25519"
        info "Chave pública:"
        echo ""
        cat "$ssh_dir/id_ed25519.pub"
        echo ""

        # Adicionar ao authorized_keys
        touch "$ssh_dir/authorized_keys"
        chmod 600 "$ssh_dir/authorized_keys"
        if ! grep -qf "$ssh_dir/id_ed25519.pub" "$ssh_dir/authorized_keys" 2>/dev/null; then
            cat "$ssh_dir/id_ed25519.pub" >> "$ssh_dir/authorized_keys"
            info "Chave adicionada ao authorized_keys."
        fi
        chown "$real_user":"$real_user" "$ssh_dir/authorized_keys"
    fi
}

# -----------------------------------------------------------------------------
# Criar banner de login
# -----------------------------------------------------------------------------
configure_banner() {
    step "Configurando banner de login SSH"

    cat > "$BANNER_FILE" << 'BANNER_EOF'
╔══════════════════════════════════════════════════════════════╗
║                    ACESSO RESTRITO                          ║
║                                                              ║
║  Este sistema é de uso exclusivo para usuários autorizados.  ║
║  Todas as atividades são monitoradas e registradas.          ║
║  O acesso não autorizado é proibido e sujeito a              ║
║  penalidades legais.                                         ║
╚══════════════════════════════════════════════════════════════╝
BANNER_EOF

    chmod 644 "$BANNER_FILE"
    success "Banner configurado: $BANNER_FILE"
}

# -----------------------------------------------------------------------------
# Remover módulos Diffie-Hellman pequenos
# -----------------------------------------------------------------------------
harden_moduli() {
    step "Removendo parâmetros Diffie-Hellman fracos"

    local moduli="/etc/ssh/moduli"

    if [[ -f "$moduli" ]]; then
        local count_before
        count_before=$(wc -l < "$moduli")

        # Manter apenas módulos >= 3072 bits
        awk '$5 >= 3071' "$moduli" > "${moduli}.safe"

        local count_after
        count_after=$(wc -l < "${moduli}.safe")

        if (( count_after > 0 )); then
            mv "${moduli}.safe" "$moduli"
            info "Módulos removidos: $((count_before - count_after)) (< 3072 bits)"
            success "Apenas módulos DH >= 3072 bits mantidos."
        else
            rm -f "${moduli}.safe"
            warn "Nenhum módulo >= 3072 bits encontrado. Arquivo moduli mantido sem alteração."
        fi
    fi
}

# -----------------------------------------------------------------------------
# Configurar UFW
# -----------------------------------------------------------------------------
configure_firewall() {
    step "Configurando firewall (UFW)"

    if ! command -v ufw &>/dev/null; then
        warn "UFW não encontrado. Pulando configuração de firewall."
        return
    fi

    if ufw status | grep -q "Status: inactive"; then
        warn "UFW está inativo. A regra será adicionada mas não ativada."
    fi

    ufw allow "${SSH_PORT}/tcp" comment "SSH" > /dev/null 2>&1
    success "Porta ${SSH_PORT}/tcp liberada no UFW."

    # Se a porta não é 22, avisar sobre a regra da porta padrão
    if [[ "$SSH_PORT" -ne 22 ]]; then
        warn "Considere remover a regra da porta 22 se não for mais necessária:"
        info "  sudo ufw delete allow 22/tcp"
    fi
}

# -----------------------------------------------------------------------------
# Integração com Fail2Ban
# -----------------------------------------------------------------------------
configure_fail2ban() {
    step "Configurando Fail2Ban para SSH"

    if ! command -v fail2ban-server &>/dev/null; then
        info "Instalando fail2ban..."
        apt-get install -y fail2ban
        success "Fail2ban instalado."
    else
        info "Fail2ban já está instalado."
    fi

    # Jail: adiciona/atualiza bloco [sshd] em jail.local
    local jail_local="/etc/fail2ban/jail.local"
    touch "$jail_local"

    if grep -q "^\[sshd\]" "$jail_local" 2>/dev/null; then
        info "Jail SSH já presente em $jail_local — mantido sem alteração."
    else
        cat >> "$jail_local" << JAIL_EOF

[sshd]
enabled   = true
port      = ${SSH_PORT}
filter    = sshd
logpath   = /var/log/auth.log
backend   = systemd
maxretry  = 5
findtime  = 600
bantime   = 3600
banaction = ufw
JAIL_EOF
        success "Jail SSH adicionado em $jail_local."
        info "  Máx. tentativas:   5 em 10 min"
        info "  Tempo de bloqueio: 1 hora"
    fi

    systemctl enable fail2ban > /dev/null 2>&1
    systemctl restart fail2ban

    sleep 2
    if systemctl is-active --quiet fail2ban; then
        success "Fail2ban ativo com proteção SSH habilitada."
    else
        warn "Fail2ban iniciado mas status incerto. Verifique: systemctl status fail2ban"
    fi
}

# -----------------------------------------------------------------------------
# Tuning de kernel/rede (sysctl)
# -----------------------------------------------------------------------------
configure_sysctl() {
    step "Configurando parâmetros de kernel para SSH"

    local sysctl_file="/etc/sysctl.d/60-ssh.conf"

    cat > "$sysctl_file" << 'SYSCTL_EOF'
# Otimizações de segurança para SSH
# Gerado por install-ssh-server.sh

# Proteção contra SYN flood
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2

# Ignorar redirecionamentos ICMP
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Não enviar redirecionamentos ICMP
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Proteção contra IP spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignorar ICMP broadcast
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Log de pacotes marcianos
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# TCP keepalive
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 3
SYSCTL_EOF

    sysctl -p "$sysctl_file" > /dev/null 2>&1
    success "Parâmetros sysctl de segurança aplicados."
}

# -----------------------------------------------------------------------------
# Validar configuração do sshd
# -----------------------------------------------------------------------------
validate_config() {
    step "Validando configuração SSH"

    if sshd -t 2>/dev/null; then
        success "Configuração SSH válida (sshd -t)."
    else
        error "Configuração SSH inválida!"
        sshd -t 2>&1 | tail -10
        die "Corrija os erros acima antes de reiniciar o serviço."
    fi
}

# -----------------------------------------------------------------------------
# Habilitar e iniciar serviço SSH
# -----------------------------------------------------------------------------
enable_services() {
    step "Habilitando e reiniciando o serviço SSH"

    systemctl daemon-reload
    systemctl enable ssh > /dev/null 2>&1
    systemctl restart ssh

    # Aguardar o serviço iniciar
    sleep 2

    if systemctl is-active --quiet ssh; then
        success "Serviço SSH está ativo e em execução."
    else
        error "Falha ao iniciar o serviço SSH."
        systemctl status ssh --no-pager | tail -15
        die "Verifique os logs: journalctl -u ssh -n 50"
    fi
}

# -----------------------------------------------------------------------------
# Exibir resumo final
# -----------------------------------------------------------------------------
show_summary() {
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')

    local auth_desc=""
    case "$AUTH_METHOD" in
        both)     auth_desc="Chave SSH + Senha" ;;
        key_only) auth_desc="Somente chave SSH" ;;
        password) auth_desc="Somente senha"     ;;
    esac

    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║       SSH Server com hardening instalado!            ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Servidor:${NC}         $server_ip:${SSH_PORT}"
    echo -e "  ${BOLD}Autenticação:${NC}     $auth_desc"
    echo -e "  ${BOLD}Root login:${NC}       Desabilitado"
    echo -e "  ${BOLD}Máx. tentativas:${NC}  ${MAX_AUTH_TRIES}"
    echo -e "  ${BOLD}Fail2Ban:${NC}         Ativo — jail sshd (5 tentativas / ban 1h)"
    echo ""
    echo -e "  ${BOLD}${CYAN}Hardening aplicado:${NC}"
    echo -e "  - Criptografia: ChaCha20, AES-256-GCM, AES-128-GCM"
    echo -e "  - KexAlgorithms: Curve25519, DH Group16/18"
    echo -e "  - MACs: HMAC-SHA2-512/256 (ETM)"
    echo -e "  - Host Keys: Ed25519, RSA-SHA2"
    echo -e "  - Moduli DH: apenas >= 3072 bits"
    echo -e "  - X11/Agent/TCP Forwarding: desabilitados"
    echo -e "  - Sessões ociosas: desconexão após $((CLIENT_ALIVE_INTERVAL * CLIENT_ALIVE_COUNT_MAX / 60)) min"
    echo -e "  - sysctl: SYN flood, spoofing, ICMP protegidos"
    echo ""
    echo -e "  ${BOLD}${CYAN}Como conectar:${NC}"
    if [[ "$SSH_PORT" -ne 22 ]]; then
        echo -e "  - ssh -p ${SSH_PORT} SEU_USUARIO@${server_ip}"
    else
        echo -e "  - ssh SEU_USUARIO@${server_ip}"
    fi
    echo ""
    echo -e "  ${BOLD}Logs:${NC}"
    echo -e "  - sudo journalctl -u ssh -f"
    echo -e "  - sudo tail -f /var/log/auth.log"
    echo -e "  - sudo fail2ban-client status sshd"
    echo ""
    echo -e "  ${BOLD}Arquivos de configuração:${NC}"
    echo -e "  - Principal:  $SSH_CONFIG"
    echo -e "  - Hardening:  $CUSTOM_CONFIG"
    echo -e "  - Banner:     $BANNER_FILE"
    echo -e "  - Backup:     ${SSH_CONFIG}.bak"
    echo ""

    if [[ "$AUTH_METHOD" == "key_only" ]]; then
        echo -e "  ${BOLD}${YELLOW}⚠  IMPORTANTE:${NC} Autenticação por senha está DESABILITADA."
        echo -e "     Certifique-se de ter sua chave SSH configurada antes de sair"
        echo -e "     desta sessão, ou você perderá acesso ao servidor!"
        echo ""
    fi
}

# -----------------------------------------------------------------------------
# Fluxo principal
# -----------------------------------------------------------------------------
main() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║   Instalador SSH Server + Hardening       ║"
    echo "  ║   para Ubuntu                             ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${NC}"

    check_root
    check_ubuntu
    choose_ssh_port
    choose_auth_method

    step "Atualizando lista de pacotes"
    apt-get update -qq
    success "Lista de pacotes atualizada."

    install_ssh
    backup_config
    generate_host_keys
    configure_sshd
    configure_banner
    harden_moduli
    generate_user_key
    configure_firewall
    configure_fail2ban
    configure_sysctl
    validate_config
    enable_services

    show_summary
}

main "$@"
