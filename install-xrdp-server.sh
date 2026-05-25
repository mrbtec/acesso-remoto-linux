#!/usr/bin/env bash
# =============================================================================
# install-xrdp-server.sh
# Instalação automatizada do servidor XRDP com TLS no Ubuntu
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
XRDP_PORT=3389
CERT_DIR="/etc/xrdp"
CERT_FILE="$CERT_DIR/cert.pem"
KEY_FILE="$CERT_DIR/key.pem"
CERT_DAYS=1095   # 3 anos
CERT_COUNTRY="BR"
CERT_STATE="SaoPaulo"
CERT_CITY="SaoPaulo"
CERT_ORG="MinhaOrg"
CERT_CN=""       # preenchido automaticamente com o hostname

# -----------------------------------------------------------------------------
# Detectar o ambiente de desktop disponível
# -----------------------------------------------------------------------------
detect_desktop() {
    if command -v startxfce4 &>/dev/null; then
        echo "xfce"
    elif command -v gnome-session &>/dev/null; then
        echo "gnome"
    elif command -v startplasma-x11 &>/dev/null || command -v startkde &>/dev/null; then
        echo "kde"
    elif command -v startlxde &>/dev/null; then
        echo "lxde"
    elif command -v startlxqt &>/dev/null; then
        echo "lxqt"
    else
        echo "none"
    fi
}

# -----------------------------------------------------------------------------
# Solicitar ambiente de desktop ao usuário
# -----------------------------------------------------------------------------
choose_desktop() {
    local detected
    detected=$(detect_desktop)

    echo ""
    echo -e "${BOLD}Ambientes de desktop disponíveis:${NC}"
    echo "  1) XFCE        (leve, recomendado para servidores)"
    echo "  2) GNOME       (completo, padrão Ubuntu Desktop)"
    echo "  3) KDE Plasma  (completo, compatível com XRDP)"
    echo "  4) LXDE        (muito leve)"
    echo "  5) Nenhum      (já possuo um desktop instalado)"

    if [[ "$detected" != "none" ]]; then
        info "Ambiente detectado no sistema: $detected"
    fi

    read -r -p "Escolha o ambiente [1-5] (padrão: 1): " choice
    choice="${choice:-1}"

    case "$choice" in
        1) DESKTOP_CHOICE="xfce"  ;;
        2) DESKTOP_CHOICE="gnome" ;;
        3) DESKTOP_CHOICE="kde"   ;;
        4) DESKTOP_CHOICE="lxde"  ;;
        5) DESKTOP_CHOICE="none"  ;;
        *) warn "Opção inválida. Usando XFCE."; DESKTOP_CHOICE="xfce" ;;
    esac
}

# -----------------------------------------------------------------------------
# Instalar o ambiente de desktop escolhido
# -----------------------------------------------------------------------------
install_desktop() {
    case "$DESKTOP_CHOICE" in
        xfce)
            if ! command -v startxfce4 &>/dev/null; then
                step "Instalando XFCE"
                apt-get install -y xfce4 xfce4-goodies
                success "XFCE instalado."
            else
                info "XFCE já está instalado."
            fi
            ;;
        gnome)
            if ! command -v gnome-session &>/dev/null; then
                step "Instalando GNOME"
                apt-get install -y ubuntu-desktop
                success "GNOME instalado."
            else
                info "GNOME já está instalado."
            fi
            ;;
        kde)
            if ! command -v startplasma-x11 &>/dev/null && ! command -v startkde &>/dev/null; then
                step "Instalando KDE Plasma"
                apt-get install -y kde-plasma-desktop
                success "KDE Plasma instalado."
            else
                info "KDE Plasma já está instalado."
            fi
            ;;
        lxde)
            if ! command -v startlxde &>/dev/null; then
                step "Instalando LXDE"
                apt-get install -y lxde
                success "LXDE instalado."
            else
                info "LXDE já está instalado."
            fi
            ;;
        none)
            info "Nenhum ambiente de desktop será instalado."
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Configurar ~/.xsession para o usuário que invocou o sudo
# -----------------------------------------------------------------------------
configure_xsession() {
    local real_user="${SUDO_USER:-$USER}"
    local home_dir
    home_dir=$(getent passwd "$real_user" | cut -d: -f6)

    [[ -z "$home_dir" || ! -d "$home_dir" ]] && return

    local session_cmd=""
    case "$DESKTOP_CHOICE" in
        xfce)  session_cmd="xfce4-session"    ;;
        gnome) session_cmd="gnome-session"    ;;
        kde)   session_cmd="startplasma-x11"  ;;
        lxde)  session_cmd="startlxde"        ;;
        none)  return ;;
    esac

    info "Configurando ~/.xsession para o usuário '$real_user'..."
    echo "$session_cmd" > "$home_dir/.xsession"
    chmod +x "$home_dir/.xsession"
    chown "$real_user":"$real_user" "$home_dir/.xsession"
    success "~/.xsession configurado: $session_cmd"
}

# -----------------------------------------------------------------------------
# Gerar certificado TLS autoassinado
# -----------------------------------------------------------------------------
generate_certificate() {
    step "Gerando certificado TLS autoassinado (RSA 4096, $CERT_DAYS dias)"

    CERT_CN=$(hostname -f 2>/dev/null || hostname)

    # Remover symlinks (ex: para ssl-cert-snakeoil) antes de criar os arquivos,
    # evitando sobrescrever certificados usados por outros serviços (Apache, Nginx)
    if [[ -L "$CERT_FILE" ]]; then
        info "Removendo symlink existente: $CERT_FILE"
        rm -f "$CERT_FILE"
    fi
    if [[ -L "$KEY_FILE" ]]; then
        info "Removendo symlink existente: $KEY_FILE"
        rm -f "$KEY_FILE"
    fi

    openssl req -x509 -newkey rsa:4096 \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE" \
        -days "$CERT_DAYS" \
        -nodes \
        -subj "/C=${CERT_COUNTRY}/ST=${CERT_STATE}/L=${CERT_CITY}/O=${CERT_ORG}/CN=${CERT_CN}" \
        2>/dev/null

    chmod 640 "$KEY_FILE"
    chmod 644 "$CERT_FILE"
    chown root:xrdp "$KEY_FILE" "$CERT_FILE"

    success "Certificado gerado: $CERT_FILE"
    info "  CN: $CERT_CN"
    info "  Validade: $CERT_DAYS dias"
}

# -----------------------------------------------------------------------------
# Aplicar configurações de TLS no xrdp.ini via sed
# -----------------------------------------------------------------------------
configure_xrdp_ini() {
    step "Configurando /etc/xrdp/xrdp.ini"

    local ini="/etc/xrdp/xrdp.ini"

    # Backup do arquivo original
    if [[ ! -f "${ini}.bak" ]]; then
        cp "$ini" "${ini}.bak"
        info "Backup criado: ${ini}.bak"
    fi

    # Forçar TLS como camada de segurança
    sed -i "s|^security_layer=.*|security_layer=tls|" "$ini"

    # Criptografia máxima
    sed -i "s|^crypt_level=.*|crypt_level=high|" "$ini"

    # Caminho do certificado
    sed -i "s|^certificate=.*|certificate=${CERT_FILE}|" "$ini"

    # Caminho da chave privada
    sed -i "s|^key_file=.*|key_file=${KEY_FILE}|" "$ini"

    # Versões de TLS (somente 1.2 e 1.3)
    sed -i "s|^ssl_protocols=.*|ssl_protocols=TLSv1.2, TLSv1.3|" "$ini"

    # Adicionar tls_ciphers se não existir
    if ! grep -q "^tls_ciphers=" "$ini"; then
        sed -i "/^ssl_protocols=/a tls_ciphers=HIGH:!aNULL:!MD5:!RC4" "$ini"
    else
        sed -i "s|^tls_ciphers=.*|tls_ciphers=HIGH:!aNULL:!MD5:!RC4|" "$ini"
    fi

    success "xrdp.ini atualizado com configurações TLS."
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

    ufw allow "${XRDP_PORT}/tcp" comment "XRDP" > /dev/null 2>&1
    success "Porta ${XRDP_PORT}/tcp liberada no UFW."
}

# -----------------------------------------------------------------------------
# Adicionar xrdp ao grupo ssl-cert
# -----------------------------------------------------------------------------
configure_ssl_cert_group() {
    if getent group ssl-cert &>/dev/null; then
        if ! id -nG xrdp | grep -qw ssl-cert; then
            adduser xrdp ssl-cert > /dev/null 2>&1
            success "Usuário 'xrdp' adicionado ao grupo 'ssl-cert'."
        else
            info "Usuário 'xrdp' já pertence ao grupo 'ssl-cert'."
        fi
    fi
}

# -----------------------------------------------------------------------------
# Habilitar e iniciar serviços
# -----------------------------------------------------------------------------
enable_services() {
    step "Habilitando e iniciando os serviços XRDP"

    systemctl daemon-reload
    systemctl enable xrdp > /dev/null 2>&1
    systemctl restart xrdp

    # Aguardar o serviço iniciar
    sleep 2

    if systemctl is-active --quiet xrdp; then
        success "Serviço xrdp está ativo e em execução."
    else
        error "Falha ao iniciar o serviço xrdp."
        systemctl status xrdp --no-pager | tail -15
        die "Verifique os logs: journalctl -u xrdp -n 50"
    fi
}

# -----------------------------------------------------------------------------
# Integração com Fail2Ban
# -----------------------------------------------------------------------------
configure_fail2ban() {
    step "Configurando Fail2Ban para XRDP"

    if ! command -v fail2ban-server &>/dev/null; then
        info "Instalando fail2ban..."
        apt-get install -y fail2ban
        success "Fail2ban instalado."
    else
        info "Fail2ban já está instalado."
    fi

    # Filtro: detecta falhas de autenticação XRDP via PAM em auth.log
    cat > /etc/fail2ban/filter.d/xrdp.conf << 'EOF'
[Definition]
failregex = ^.*xrdp-sesman\[\d+\]: PAM Error: Authentication failure for \S+ at <HOST>$
            ^.*xrdp-sesman\[\d+\]: pam_unix\(.*\): authentication failure;.*rhost=<HOST>.*$
ignoreregex =
EOF

    success "Filtro /etc/fail2ban/filter.d/xrdp.conf criado."

    # Jail: adiciona bloco [xrdp] em jail.local apenas se ainda não existir
    local jail_local="/etc/fail2ban/jail.local"
    touch "$jail_local"

    if grep -q "^\[xrdp\]" "$jail_local" 2>/dev/null; then
        info "Jail XRDP já presente em $jail_local — mantido sem alteração."
    else
        cat >> "$jail_local" << 'EOF'

[xrdp]
enabled   = true
port      = 3389
filter    = xrdp
logpath   = /var/log/auth.log
maxretry  = 5
findtime  = 600
bantime   = 3600
EOF
        success "Jail XRDP adicionado em $jail_local."
        info "  Máx. tentativas:   5 em 10 min"
        info "  Tempo de bloqueio: 1 hora"
    fi

    systemctl enable fail2ban > /dev/null 2>&1
    systemctl restart fail2ban

    sleep 2
    if systemctl is-active --quiet fail2ban; then
        success "Fail2ban ativo com proteção XRDP habilitada."
    else
        warn "Fail2ban iniciado mas status incerto. Verifique: systemctl status fail2ban"
    fi
}

# -----------------------------------------------------------------------------
# Exibir resumo final
# -----------------------------------------------------------------------------
show_summary() {
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')
    local cert_expiry
    cert_expiry=$(openssl x509 -in "$CERT_FILE" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "N/A")

    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║         XRDP com TLS instalado com sucesso!          ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Servidor:${NC}       $server_ip:${XRDP_PORT}"
    echo -e "  ${BOLD}Segurança:${NC}      TLS obrigatório (TLSv1.2 / TLSv1.3)"
    echo -e "  ${BOLD}Certificado:${NC}    $CERT_FILE"
    echo -e "  ${BOLD}Expira em:${NC}      $cert_expiry"
    echo -e "  ${BOLD}Desktop:${NC}        ${DESKTOP_CHOICE:-detectado pelo sistema}"
    echo -e "  ${BOLD}Fail2Ban:${NC}       Ativo — jail xrdp (5 tentativas / ban 1h)"
    echo ""
    echo -e "  ${BOLD}${CYAN}Como conectar:${NC}"
    echo -e "  - Windows: mstsc.exe → ${server_ip}"
    echo -e "  - Linux:   xfreerdp /v:${server_ip} /u:SEU_USUARIO /tls-seclevel:1 /cert:ignore"
    echo -e "  - Remmina: Nova conexão RDP → ${server_ip}:${XRDP_PORT}"
    echo ""
    echo -e "  ${BOLD}Logs:${NC}"
    echo -e "  - sudo journalctl -u xrdp -f"
    echo -e "  - sudo journalctl -u xrdp-sesman -f"
    echo ""
    warn "Se usar certificado autoassinado, aceite o aviso de segurança no cliente RDP."
    echo ""
}

# -----------------------------------------------------------------------------
# Fluxo principal
# -----------------------------------------------------------------------------
main() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║   Instalador XRDP + TLS para Ubuntu       ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${NC}"

    check_root
    check_ubuntu
    choose_desktop

    step "Atualizando lista de pacotes"
    apt-get update -qq
    success "Lista de pacotes atualizada."

    step "Instalando XRDP"
    apt-get install -y xrdp openssl
    success "XRDP instalado."

    install_desktop
    configure_xsession
    generate_certificate
    configure_xrdp_ini
    configure_ssl_cert_group
    configure_firewall
    enable_services
    configure_fail2ban
    show_summary
}

main "$@"
