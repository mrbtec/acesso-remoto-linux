#!/usr/bin/env bash
# =============================================================================
# install-snort-ids.sh
# Instalação automatizada do Snort 3 IDS/IPS no Ubuntu
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
NC='\033[0m'

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
# Configurações
# -----------------------------------------------------------------------------
SNORT_PREFIX="/usr/local/snort"
SNORT_CONF_DIR="/etc/snort"
SNORT_LOG_DIR="/var/log/snort"
SNORT_RULES_DIR="${SNORT_CONF_DIR}/rules"
SNORT_USER="snort"
SNORT_GROUP="snort"
BUILD_DIR="/tmp/snort-build-$$"
NETWORK_VAR=""

# Interface de rede para monitoramento
SNORT_IFACE=""

# -----------------------------------------------------------------------------
# Detectar interface de rede principal
# -----------------------------------------------------------------------------
detect_interface() {
    local iface
    iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -1)
    echo "${iface:-eth0}"
}

# -----------------------------------------------------------------------------
# Solicitar configuração ao usuário
# -----------------------------------------------------------------------------
choose_config() {
    local detected_iface
    detected_iface=$(detect_interface)

    echo ""
    echo -e "${BOLD}Configuração do Snort 3 IDS:${NC}"
    echo ""

    # Interface de rede
    read -r -p "Interface de rede para monitorar [padrão: ${detected_iface}]: " custom_iface
    SNORT_IFACE="${custom_iface:-$detected_iface}"

    if ! ip link show "$SNORT_IFACE" &>/dev/null; then
        warn "Interface '$SNORT_IFACE' não encontrada."
        read -r -p "Deseja continuar mesmo assim? [s/N] " resp
        [[ "$resp" =~ ^[sS]$ ]] || die "Instalação cancelada."
    else
        info "Interface de monitoramento: $SNORT_IFACE"
    fi

    # Rede local (HOME_NET)
    local detected_net
    detected_net=$(ip -4 addr show "$SNORT_IFACE" 2>/dev/null | grep -oP 'inet \K[\d.]+/[\d]+' | head -1)
    detected_net="${detected_net:-192.168.1.0/24}"

    echo ""
    echo -e "${BOLD}Rede local (HOME_NET):${NC}"
    echo "  Detectada: $detected_net"
    read -r -p "HOME_NET [padrão: ${detected_net}]: " custom_net
    NETWORK_VAR="${custom_net:-$detected_net}"
    info "HOME_NET configurado: $NETWORK_VAR"

    # Modo de operação
    echo ""
    echo -e "${BOLD}Modo de operação:${NC}"
    echo "  1) IDS  — Detecção apenas (modo passivo, recomendado)"
    echo "  2) IPS  — Prevenção ativa (inline, bloqueia tráfego malicioso)"
    echo ""
    read -r -p "Escolha o modo [1-2] (padrão: 1): " mode_choice
    mode_choice="${mode_choice:-1}"

    case "$mode_choice" in
        1) SNORT_MODE="ids" ;;
        2) SNORT_MODE="ips" ;;
        *) warn "Opção inválida. Usando IDS."; SNORT_MODE="ids" ;;
    esac
    info "Modo de operação: ${SNORT_MODE^^}"
}

# -----------------------------------------------------------------------------
# Instalar dependências de compilação
# -----------------------------------------------------------------------------
install_dependencies() {
    step "Instalando dependências de compilação"

    apt-get install -y \
        build-essential cmake flex bison \
        libhwloc-dev libluajit-5.1-dev libssl-dev \
        libpcap-dev libpcre2-dev pkg-config \
        zlib1g-dev libdumbnet-dev liblzma-dev \
        uuid-dev libnghttp2-dev git autoconf \
        automake libtool libsafec-dev \
        libunwind-dev libflatbuffers-dev \
        wget curl

    success "Dependências instaladas."
}

# -----------------------------------------------------------------------------
# Compilar e instalar libdaq
# -----------------------------------------------------------------------------
install_daq() {
    step "Compilando libdaq (Data Acquisition Library)"

    mkdir -p "$BUILD_DIR"

    if [[ -f /usr/local/lib/libdaq.so ]]; then
        info "libdaq já está instalada."
        return
    fi

    cd "$BUILD_DIR"

    if [[ ! -d libdaq ]]; then
        git clone https://github.com/snort3/libdaq.git
    fi

    cd libdaq
    ./bootstrap
    ./configure
    make -j"$(nproc)"
    make install
    ldconfig

    success "libdaq compilada e instalada."
}

# -----------------------------------------------------------------------------
# Compilar e instalar Snort 3
# -----------------------------------------------------------------------------
install_snort() {
    step "Compilando Snort 3"

    if [[ -x "${SNORT_PREFIX}/bin/snort" ]]; then
        local installed_ver
        installed_ver=$("${SNORT_PREFIX}/bin/snort" -V 2>&1 | grep -oP 'Version \K[\d.]+' || echo "desconhecida")
        info "Snort já instalado (versão: $installed_ver)"
        read -r -p "Deseja recompilar? [s/N] " resp
        if [[ ! "$resp" =~ ^[sS]$ ]]; then
            return
        fi
    fi

    cd "$BUILD_DIR"

    if [[ ! -d snort3 ]]; then
        git clone https://github.com/snort3/snort3.git
    fi

    cd snort3
    ./configure_cmake.sh --prefix="$SNORT_PREFIX"
    cd build
    make -j"$(nproc)"
    make install

    # Atualizar cache de bibliotecas
    if ! grep -q "$SNORT_PREFIX/lib" /etc/ld.so.conf.d/snort.conf 2>/dev/null; then
        echo "${SNORT_PREFIX}/lib" > /etc/ld.so.conf.d/snort.conf
        ldconfig
    fi

    # Symlink para facilitar uso
    if [[ ! -L /usr/local/bin/snort ]]; then
        ln -sf "${SNORT_PREFIX}/bin/snort" /usr/local/bin/snort
    fi

    success "Snort 3 compilado e instalado em ${SNORT_PREFIX}"

    # Verificar instalação
    "${SNORT_PREFIX}/bin/snort" -V 2>&1 | head -5
}

# -----------------------------------------------------------------------------
# Criar usuário e grupo para o Snort
# -----------------------------------------------------------------------------
create_snort_user() {
    step "Criando usuário de serviço para o Snort"

    if ! getent group "$SNORT_GROUP" &>/dev/null; then
        groupadd -r "$SNORT_GROUP"
        success "Grupo '$SNORT_GROUP' criado."
    else
        info "Grupo '$SNORT_GROUP' já existe."
    fi

    if ! id "$SNORT_USER" &>/dev/null; then
        useradd -r -g "$SNORT_GROUP" -s /usr/sbin/nologin \
            -d /nonexistent -c "Snort IDS" "$SNORT_USER"
        success "Usuário '$SNORT_USER' criado."
    else
        info "Usuário '$SNORT_USER' já existe."
    fi
}

# -----------------------------------------------------------------------------
# Criar estrutura de diretórios
# -----------------------------------------------------------------------------
create_directories() {
    step "Criando estrutura de diretórios"

    mkdir -p "$SNORT_CONF_DIR"
    mkdir -p "$SNORT_RULES_DIR"
    mkdir -p "$SNORT_LOG_DIR"
    mkdir -p "${SNORT_CONF_DIR}/appid"
    mkdir -p "${SNORT_CONF_DIR}/lists"

    chown -R "$SNORT_USER":"$SNORT_GROUP" "$SNORT_LOG_DIR"
    chmod 750 "$SNORT_LOG_DIR"

    success "Diretórios criados."
}

# -----------------------------------------------------------------------------
# Configurar snort.lua principal
# -----------------------------------------------------------------------------
configure_snort() {
    step "Gerando configuração principal (snort.lua)"

    local snort_lua="${SNORT_CONF_DIR}/snort.lua"

    if [[ -f "$snort_lua" && ! -f "${snort_lua}.bak" ]]; then
        cp "$snort_lua" "${snort_lua}.bak"
        info "Backup criado: ${snort_lua}.bak"
    fi

    cat > "$snort_lua" << SNORT_LUA_EOF
---------------------------------------------------------------------------
-- Snort 3 — Configuração principal
-- Gerado por install-snort-ids.sh — $(date '+%Y-%m-%d %H:%M:%S')
---------------------------------------------------------------------------

-- Variáveis de rede
HOME_NET = '${NETWORK_VAR}'
EXTERNAL_NET = '!\$HOME_NET'

-- Caminhos
RULE_PATH = '${SNORT_RULES_DIR}'
BUILTIN_RULE_PATH = '${SNORT_PREFIX}/etc/snort/builtin_rules'
PLUGIN_RULE_PATH = '${SNORT_PREFIX}/etc/snort/so_rules'

-- Decodificadores
wizard = default_wizard

---------------------------------------------------------------------------
-- Configuração de rede
---------------------------------------------------------------------------
default_bindings =
{
    {
        when = { nets = HOME_NET },
        use  = { inspection_policy = 'balanced' }
    }
}

---------------------------------------------------------------------------
-- Módulo de inspeção
---------------------------------------------------------------------------
stream = { }
stream_tcp = { }
stream_udp = { }
stream_icmp = { }

---------------------------------------------------------------------------
-- Normalização
---------------------------------------------------------------------------
normalizer =
{
    tcp = { ips = true },
    ip4 = { df = true }
}

---------------------------------------------------------------------------
-- Detecção
---------------------------------------------------------------------------
search_engine = { search_method = 'ac_bnfa' }

detection =
{
    hyperscan_literals = false,
    pcre_match_limit = 3500,
    pcre_match_limit_recursion = 1500
}

---------------------------------------------------------------------------
-- Alertas e logging
---------------------------------------------------------------------------
alert_fast =
{
    file = true
}

alert_full =
{
    file = true
}

-- Log unificado para integração com ferramentas externas
unified2 = { }

---------------------------------------------------------------------------
-- Reputação de IP (listas de bloqueio/permissão)
---------------------------------------------------------------------------
reputation =
{
    -- blacklist = '${SNORT_CONF_DIR}/lists/blocklist.txt',
    -- whitelist = '${SNORT_CONF_DIR}/lists/allowlist.txt',
}

---------------------------------------------------------------------------
-- Regras
---------------------------------------------------------------------------
ips =
{
    enable_builtin_rules = true,
    include = RULE_PATH .. '/local.rules',
    variables = default_variables
}

---------------------------------------------------------------------------
-- Inspetores de protocolo
---------------------------------------------------------------------------
http_inspect = { }
http2_inspect = { }
ssl_inspect = { }
dns_inspect = { }
smtp_inspect = { }
imap_inspect = { }
pop_inspect = { }
ftp_server = { }
ftp_client = { }
ftp_data = { }
telnet = { }
ssh_inspect = { }
sip_inspect = { }
SNORT_LUA_EOF

    chmod 640 "$snort_lua"
    chown root:"$SNORT_GROUP" "$snort_lua"
    success "Configuração salva: $snort_lua"
}

# -----------------------------------------------------------------------------
# Criar regras locais de exemplo
# -----------------------------------------------------------------------------
create_local_rules() {
    step "Criando regras locais de exemplo"

    local rules_file="${SNORT_RULES_DIR}/local.rules"

    cat > "$rules_file" << 'RULES_EOF'
# =============================================================================
# Regras locais do Snort 3
# Adicione suas regras personalizadas aqui
# =============================================================================

# --- Teste: ping ICMP (descomente para validar) ---
# alert icmp any any -> $HOME_NET any (msg:"ICMP Echo Request detectado"; itype:8; sid:1000001; rev:1;)

# --- Detecção de scan de portas ---
alert tcp any any -> $HOME_NET any (msg:"Possível scan SYN detectado"; flags:S,12; threshold:type both, track by_src, count 20, seconds 10; sid:1000002; rev:1;)

# --- SSH brute force ---
alert tcp any any -> $HOME_NET 22 (msg:"Tentativas excessivas de SSH"; flow:to_server,established; threshold:type both, track by_src, count 5, seconds 60; sid:1000003; rev:1;)

# --- Detecção de tráfego DNS suspeito (tunneling) ---
alert udp any any -> any 53 (msg:"Consulta DNS com payload grande - possível tunneling"; dsize:>512; sid:1000004; rev:1;)

# --- SQL Injection básico ---
alert tcp any any -> $HOME_NET any (msg:"Possível SQL Injection detectado"; flow:to_server,established; content:"' OR '1'='1"; nocase; sid:1000005; rev:1;)
alert tcp any any -> $HOME_NET any (msg:"Possível SQL Injection - UNION SELECT"; flow:to_server,established; content:"UNION SELECT"; nocase; sid:1000006; rev:1;)

# --- XSS básico ---
alert tcp any any -> $HOME_NET any (msg:"Possível XSS detectado"; flow:to_server,established; content:"<script>"; nocase; sid:1000007; rev:1;)

# --- Shellshock ---
alert tcp any any -> $HOME_NET any (msg:"Possível Shellshock exploit"; flow:to_server,established; content:"() {"; sid:1000008; rev:1;)
RULES_EOF

    chmod 640 "$rules_file"
    chown root:"$SNORT_GROUP" "$rules_file"
    success "Regras locais criadas: $rules_file"
}

# -----------------------------------------------------------------------------
# Baixar regras da comunidade Snort
# -----------------------------------------------------------------------------
download_community_rules() {
    step "Baixando regras da comunidade Snort"

    local rules_url="https://www.snort.org/downloads/community/snort3-community-rules.tar.gz"
    local rules_tar="${BUILD_DIR}/snort3-community-rules.tar.gz"

    if wget -q -O "$rules_tar" "$rules_url" 2>/dev/null; then
        tar -xzf "$rules_tar" -C "$BUILD_DIR"

        if [[ -d "${BUILD_DIR}/snort3-community-rules" ]]; then
            cp "${BUILD_DIR}/snort3-community-rules/"*.rules "$SNORT_RULES_DIR/" 2>/dev/null || true
            cp "${BUILD_DIR}/snort3-community-rules/sid-msg.map" "$SNORT_CONF_DIR/" 2>/dev/null || true
            chown -R root:"$SNORT_GROUP" "$SNORT_RULES_DIR"
            success "Regras da comunidade instaladas em $SNORT_RULES_DIR"
        fi
    else
        warn "Não foi possível baixar regras da comunidade."
        info "Baixe manualmente de: https://www.snort.org/downloads"
    fi
}

# -----------------------------------------------------------------------------
# Configurar interface em modo promíscuo
# -----------------------------------------------------------------------------
configure_promiscuous() {
    step "Configurando interface $SNORT_IFACE em modo promíscuo"

    # Ativar modo promíscuo agora
    ip link set "$SNORT_IFACE" promisc on 2>/dev/null || true

    # Desativar offloading para captura precisa de pacotes
    if command -v ethtool &>/dev/null; then
        ethtool -K "$SNORT_IFACE" gro off lro off 2>/dev/null || true
        info "Offloading (GRO/LRO) desativado na interface."
    else
        apt-get install -y ethtool > /dev/null 2>&1
        ethtool -K "$SNORT_IFACE" gro off lro off 2>/dev/null || true
    fi

    # Criar serviço systemd para persistir modo promíscuo
    cat > /etc/systemd/system/snort-promisc@.service << 'PROMISC_EOF'
[Unit]
Description=Modo promíscuo para interface %i (Snort)
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ip link set %i promisc on
ExecStart=/usr/sbin/ethtool -K %i gro off lro off
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
PROMISC_EOF

    systemctl daemon-reload
    systemctl enable "snort-promisc@${SNORT_IFACE}" > /dev/null 2>&1
    success "Interface $SNORT_IFACE configurada em modo promíscuo (persistente)."
}

# -----------------------------------------------------------------------------
# Criar serviço systemd para o Snort
# -----------------------------------------------------------------------------
create_systemd_service() {
    step "Criando serviço systemd para o Snort"

    local snort_args=""
    if [[ "$SNORT_MODE" == "ips" ]]; then
        snort_args="-Q --daq afpacket --daq-var buffer_size_mb=256"
    else
        snort_args="--daq afpacket --daq-var buffer_size_mb=128"
    fi

    cat > /etc/systemd/system/snort3.service << SERVICE_EOF
[Unit]
Description=Snort 3 ${SNORT_MODE^^} Service
Documentation=https://snort.org/documents
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SNORT_USER}
Group=${SNORT_GROUP}
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN CAP_SYS_NICE
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN CAP_SYS_NICE
NoNewPrivileges=true

ExecStart=${SNORT_PREFIX}/bin/snort -c ${SNORT_CONF_DIR}/snort.lua \\
    -i ${SNORT_IFACE} \\
    -l ${SNORT_LOG_DIR} \\
    -s 65535 \\
    --create-pidfile \\
    ${snort_args}

ExecReload=/bin/kill -SIGHUP \$MAINPID

Restart=on-failure
RestartSec=10

# Hardening
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${SNORT_LOG_DIR}
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    systemctl daemon-reload
    success "Serviço systemd criado: snort3.service"
}

# -----------------------------------------------------------------------------
# Configurar logrotate
# -----------------------------------------------------------------------------
configure_logrotate() {
    step "Configurando rotação de logs"

    cat > /etc/logrotate.d/snort << LOGROTATE_EOF
${SNORT_LOG_DIR}/*.log ${SNORT_LOG_DIR}/*.txt {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 640 ${SNORT_USER} ${SNORT_GROUP}
    postrotate
        systemctl reload snort3 2>/dev/null || true
    endscript
}
LOGROTATE_EOF

    success "Logrotate configurado: rotação diária, 14 dias de retenção."
}

# -----------------------------------------------------------------------------
# Validar configuração do Snort
# -----------------------------------------------------------------------------
validate_config() {
    step "Validando configuração do Snort"

    if "${SNORT_PREFIX}/bin/snort" -c "${SNORT_CONF_DIR}/snort.lua" --warn-all -T 2>&1 | tail -5; then
        success "Configuração do Snort válida."
    else
        warn "Validação retornou avisos. Verifique a configuração."
        info "Execute: snort -c ${SNORT_CONF_DIR}/snort.lua --warn-all -T"
    fi
}

# -----------------------------------------------------------------------------
# Habilitar e iniciar serviço
# -----------------------------------------------------------------------------
enable_services() {
    step "Habilitando e iniciando o serviço Snort"

    systemctl enable snort3 > /dev/null 2>&1
    systemctl start snort3

    sleep 3

    if systemctl is-active --quiet snort3; then
        success "Serviço Snort 3 está ativo e em execução."
    else
        warn "Snort pode não ter iniciado corretamente."
        systemctl status snort3 --no-pager | tail -15
        info "Verifique: journalctl -u snort3 -n 50"
    fi
}

# -----------------------------------------------------------------------------
# Limpeza dos arquivos de compilação
# -----------------------------------------------------------------------------
cleanup_build() {
    echo ""
    read -r -p "Deseja remover os arquivos de compilação ($BUILD_DIR)? [S/n] " resp
    resp="${resp:-s}"

    if [[ "$resp" =~ ^[sS]$ ]]; then
        rm -rf "$BUILD_DIR"
        success "Arquivos de compilação removidos."
    else
        info "Arquivos mantidos em: $BUILD_DIR"
    fi
}

# -----------------------------------------------------------------------------
# Integração com Fail2Ban — bloqueio automático de IPs detectados pelo Snort
# -----------------------------------------------------------------------------
configure_fail2ban() {
    step "Configurando Fail2Ban para bloqueio automático via Snort"

    if ! command -v fail2ban-server &>/dev/null; then
        info "Instalando fail2ban..."
        apt-get install -y fail2ban
        success "Fail2ban instalado."
    else
        info "Fail2ban já está instalado."
    fi

    # Filtro: extrai IPs dos alertas do Snort (alert_fast.txt)
    # Formato típico: 08/11-14:20:00.123456 [**] [1:1000002:1] "Possível scan..." [**] {TCP} 192.168.1.100:54321 -> 10.0.0.1:22
    cat > /etc/fail2ban/filter.d/snort.conf << 'FILTER_EOF'
[Definition]
# Captura o IP de origem nos alertas do Snort 3 (alert_fast)
failregex = ^.*\}\s+<HOST>[:\d]+ ->.*$
ignoreregex =
datepattern = ^%%m/%%d-%%H:%%M:%%S
FILTER_EOF

    success "Filtro /etc/fail2ban/filter.d/snort.conf criado."

    # Jail: bloqueia IPs que geraram alertas no Snort
    local jail_local="/etc/fail2ban/jail.local"
    touch "$jail_local"

    if grep -q "^\[snort\]" "$jail_local" 2>/dev/null; then
        info "Jail Snort já presente em $jail_local — mantido sem alteração."
    else
        cat >> "$jail_local" << JAIL_EOF

[snort]
enabled   = true
filter    = snort
logpath   = ${SNORT_LOG_DIR}/alert_fast.txt
maxretry  = 3
findtime  = 600
bantime   = 3600
banaction = ufw
action    = %(action_mwl)s
JAIL_EOF
        success "Jail Snort adicionado em $jail_local."
        info "  Máx. alertas:      3 em 10 min"
        info "  Tempo de bloqueio: 1 hora"
        info "  Ação: bloqueio UFW + notificação por email (se configurado)"
    fi

    # Garantir que o arquivo de log existe para o fail2ban monitorar
    touch "${SNORT_LOG_DIR}/alert_fast.txt"
    chown "${SNORT_USER}:${SNORT_GROUP}" "${SNORT_LOG_DIR}/alert_fast.txt"

    systemctl enable fail2ban > /dev/null 2>&1
    systemctl restart fail2ban

    sleep 2
    if systemctl is-active --quiet fail2ban; then
        success "Fail2ban ativo com bloqueio automático via Snort."
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

    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║       Snort 3 ${SNORT_MODE^^} instalado com sucesso!           ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Servidor:${NC}         $server_ip"
    echo -e "  ${BOLD}Modo:${NC}             ${SNORT_MODE^^} ($([ "$SNORT_MODE" = "ids" ] && echo "detecção passiva" || echo "prevenção ativa"))"
    echo -e "  ${BOLD}Interface:${NC}        $SNORT_IFACE (modo promíscuo)"
    echo -e "  ${BOLD}HOME_NET:${NC}         $NETWORK_VAR"
    echo -e "  ${BOLD}Usuário:${NC}          $SNORT_USER"
    echo -e "  ${BOLD}Fail2Ban:${NC}         Ativo — jail snort (3 alertas / ban 1h)"
    echo ""
    echo -e "  ${BOLD}${CYAN}Fluxo de detecção e bloqueio:${NC}"
    echo -e "  1. Snort monitora tráfego na interface $SNORT_IFACE"
    echo -e "  2. Alerta registrado em ${SNORT_LOG_DIR}/alert_fast.txt"
    echo -e "  3. Fail2Ban lê o log e extrai o IP do atacante"
    echo -e "  4. Após 3 alertas em 10 min → IP bloqueado no UFW por 1h"
    echo ""
    echo -e "  ${BOLD}${CYAN}Diretórios:${NC}"
    echo -e "  - Binário:       ${SNORT_PREFIX}/bin/snort"
    echo -e "  - Configuração:  ${SNORT_CONF_DIR}/snort.lua"
    echo -e "  - Regras:        ${SNORT_RULES_DIR}/"
    echo -e "  - Logs:          ${SNORT_LOG_DIR}/"
    echo ""
    echo -e "  ${BOLD}${CYAN}Comandos úteis:${NC}"
    echo -e "  - Status Snort:    sudo systemctl status snort3"
    echo -e "  - Status Fail2Ban: sudo fail2ban-client status snort"
    echo -e "  - IPs banidos:     sudo fail2ban-client status snort"
    echo -e "  - Desbanir IP:     sudo fail2ban-client set snort unbanip <IP>"
    echo -e "  - Alertas:         sudo tail -f ${SNORT_LOG_DIR}/alert_fast.txt"
    echo -e "  - Testar config:   sudo snort -c ${SNORT_CONF_DIR}/snort.lua -T"
    echo -e "  - Logs journal:    sudo journalctl -u snort3 -f"
    echo ""
    echo -e "  ${BOLD}${CYAN}Teste rápido:${NC}"
    echo -e "  1. Descomente a regra ICMP em ${SNORT_RULES_DIR}/local.rules"
    echo -e "  2. sudo systemctl reload snort3"
    echo -e "  3. Faça ping neste servidor de outra máquina"
    echo -e "  4. Verifique: tail -f ${SNORT_LOG_DIR}/alert_fast.txt"
    echo -e "  5. Verifique ban: sudo fail2ban-client status snort"
    echo ""
}

# -----------------------------------------------------------------------------
# Fluxo principal
# -----------------------------------------------------------------------------
main() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║   Instalador Snort 3 IDS/IPS             ║"
    echo "  ║   para Ubuntu                             ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${NC}"

    check_root
    check_ubuntu
    choose_config

    step "Atualizando lista de pacotes"
    apt-get update -qq
    success "Lista de pacotes atualizada."

    install_dependencies
    install_daq
    install_snort
    create_snort_user
    create_directories
    configure_snort
    create_local_rules
    download_community_rules
    configure_promiscuous
    create_systemd_service
    configure_logrotate
    configure_fail2ban
    validate_config
    enable_services
    cleanup_build

    show_summary
}

main "$@"
