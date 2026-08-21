#!/usr/bin/env bash
# =============================================================================
# ubuntu-post-install.sh
# Script automatizado de pós-instalação do Ubuntu / Xubuntu Desktop
# Foco: Brasil (São Paulo - SP), Teclado ABNT2, Sincronização NTP.br e ferramentas essenciais.
# Alvo: Ubuntu 26.04 LTS (Resolute Raccoon) e versões recentes.
# Versão: 1.1
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

# Modo não interativo (silencioso)
UNATTENDED=false

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
        warn "Este script foi projetado para Ubuntu/Xubuntu. SO detectado: $PRETTY_NAME"
        if [[ "$UNATTENDED" == false ]]; then
            read -r -p "Deseja continuar mesmo assim? [s/N] " resp
            [[ "$resp" =~ ^[sS]$ ]] || die "Instalação cancelada pelo usuário."
        fi
    else
        info "Sistema detectado: $PRETTY_NAME ($VERSION_CODENAME)"
    fi
}

# -----------------------------------------------------------------------------
# 1. Localização, Timezone (SP/Brasil) e Teclado ABNT2
# -----------------------------------------------------------------------------
configure_localization() {
    step "Configurando localização, Timezone (América/São Paulo) e Teclado ABNT2"

    # 1.1 Fuso Horário
    info "Definindo fuso horário para America/Sao_Paulo..."
    timedatectl set-timezone America/Sao_Paulo || warn "Falha ao definir timezone via timedatectl"
    success "Timezone definido: $(timedatectl | grep "Time zone" | awk '{print $3}')"

    # 1.2 Idioma e Locale pt_BR.UTF-8
    info "Configurando locale pt_BR.UTF-8..."
    apt-get install -y locales >/dev/null 2>&1 || true
    locale-gen pt_BR.UTF-8
    update-locale LANG=pt_BR.UTF-8 LC_ALL=pt_BR.UTF-8 LANGUAGE=pt_BR:pt
    export LANG=pt_BR.UTF-8
    export LC_ALL=pt_BR.UTF-8
    success "Locale pt_BR.UTF-8 gerado e configurado."

    # 1.3 Teclado ABNT2 (br)
    info "Configurando layout de teclado para Português (Brasil) ABNT2..."

    # Garantir pacotes de teclado e console instalados
    DEBIAN_FRONTEND=noninteractive apt-get install -y keyboard-configuration console-setup kbd xkb-data >/dev/null 2>&1 || true

    # Atualizar arquivo /etc/default/keyboard
    cp /etc/default/keyboard /etc/default/keyboard.bak 2>/dev/null || true
    cat > /etc/default/keyboard << 'KEYBOARD_EOF'
# Configuração de Teclado ABNT2 (Brasil)
XKBMODEL="abnt2"
XKBLAYOUT="br"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
KEYBOARD_EOF

    # Aplicar via localectl (se disponível em ambiente com systemd/X11)
    if command -v localectl &>/dev/null; then
        localectl set-keymap br-abnt2 2>/dev/null || localectl set-keymap br 2>/dev/null || true
        localectl set-x11-keymap br abnt2 2>/dev/null || localectl set-x11-keymap br 2>/dev/null || true
    fi

    # Aplicar reconfiguração não-interativa e console
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure keyboard-configuration >/dev/null 2>&1 || true
    if command -v setupcon &>/dev/null; then
        setupcon --force >/dev/null 2>&1 || true
    fi

    success "Teclado ABNT2 configurado."
}

# -----------------------------------------------------------------------------
# 2. Sincronização de Horário NTP (NTP.br via chrony)
#    Ubuntu 26.04 usa chrony como daemon NTP padrão.
#    O utilitário legado ntpdate foi descontinuado.
# -----------------------------------------------------------------------------
configure_ntp() {
    step "Configurando sincronização de horário (NTP.br via chrony)"

    # 2.1 Instalar chrony (padrão no Ubuntu 26.04, mas garantir presença)
    info "Instalando chrony (daemon NTP padrão do Ubuntu 26.04)..."
    apt-get install -y chrony >/dev/null 2>&1 || warn "Não foi possível instalar chrony"

    # 2.2 Configurar chrony com servidores brasileiros (NTP.br)
    if command -v chronyc &>/dev/null; then
        local chrony_conf="/etc/chrony/chrony.conf"
        if [[ -f "$chrony_conf" ]]; then
            cp "$chrony_conf" "${chrony_conf}.bak" 2>/dev/null || true

            # Adicionar servidores NTP.br antes de qualquer pool/server existente
            # Remover pools/servers padrão e inserir os brasileiros
            local chrony_custom="/etc/chrony/conf.d/ntp-brasil.conf"
            mkdir -p /etc/chrony/conf.d 2>/dev/null || true
            cat > "$chrony_custom" << 'CHRONY_EOF'
# Servidores NTP.br — Projeto NTP.br / NIC.br
# Gerado por ubuntu-post-install.sh
server a.ntp.br iburst nts
server b.ntp.br iburst nts
server c.ntp.br iburst nts
server gps.ntp.br iburst nts

# Pool brasileiro como fallback
pool 0.br.pool.ntp.org iburst
pool 1.br.pool.ntp.org iburst
pool 2.br.pool.ntp.org iburst
CHRONY_EOF
            success "Servidores NTP.br configurados em $chrony_custom"
        fi

        # Reiniciar e ativar chrony
        systemctl enable chrony >/dev/null 2>&1 || true
        systemctl restart chrony 2>/dev/null || true

        # Forçar sincronização imediata
        info "Forçando sincronização imediata de horário..."
        chronyc makestep >/dev/null 2>&1 || true

        success "Sincronização de horário ativada via chrony com NTP.br."
        info "Verificando fontes NTP:"
        chronyc sources 2>/dev/null || true
    fi

    # 2.3 Configurar também o systemd-timesyncd como fallback (caso chrony seja removido)
    local timesyncd_conf="/etc/systemd/timesyncd.conf"
    if [[ -f "$timesyncd_conf" ]]; then
        cp "$timesyncd_conf" "${timesyncd_conf}.bak" 2>/dev/null || true
        cat > "$timesyncd_conf" << 'TIMESYNCD_EOF'
[Time]
NTP=a.ntp.br b.ntp.br c.ntp.br 0.br.pool.ntp.org 1.br.pool.ntp.org 2.br.pool.ntp.org
FallbackNTP=pool.ntp.org
TIMESYNCD_EOF
    fi

    if command -v timedatectl &>/dev/null; then
        timedatectl set-ntp true || true
    fi
}

# -----------------------------------------------------------------------------
# 3. Otimização de Repositórios APT (Mirrors BR)
#    Ubuntu 26.04 usa formato deb822 (.sources) como padrão.
#    O arquivo /etc/apt/sources.list legado pode não existir.
# -----------------------------------------------------------------------------
configure_apt_mirrors() {
    step "Otimizando repositórios APT para espelhos do Brasil (br.archive.ubuntu.com)"

    local sources_file="/etc/apt/sources.list"
    local ubuntu_sources="/etc/apt/sources.list.d/ubuntu.sources" # Ubuntu 24.04+ (DEB822)

    # Remover arquivos de backup antigos em /etc/apt/sources.list.d/ para evitar avisos do APT
    rm -f /etc/apt/sources.list.d/*.bak* /etc/apt/sources.list.d/*.save 2>/dev/null || true

    # Formato primário no Ubuntu 26.04: deb822 (/etc/apt/sources.list.d/ubuntu.sources)
    if [[ -f "$ubuntu_sources" ]]; then
        cp "$ubuntu_sources" "/var/backups/ubuntu.sources.bak" 2>/dev/null || true
        sed -i 's|http://archive.ubuntu.com/ubuntu|http://br.archive.ubuntu.com/ubuntu|g' "$ubuntu_sources"
        sed -i 's|http://us.archive.ubuntu.com/ubuntu|http://br.archive.ubuntu.com/ubuntu|g' "$ubuntu_sources"
        info "Espelhos atualizados no formato deb822 ($ubuntu_sources)"
    fi

    # Fallback: formato legado /etc/apt/sources.list (caso exista em instalações customizadas)
    if [[ -f "$sources_file" && -s "$sources_file" ]]; then
        cp "$sources_file" "/var/backups/sources.list.bak" 2>/dev/null || true
        sed -i 's|http://archive.ubuntu.com/ubuntu|http://br.archive.ubuntu.com/ubuntu|g' "$sources_file"
        sed -i 's|http://us.archive.ubuntu.com/ubuntu|http://br.archive.ubuntu.com/ubuntu|g' "$sources_file"
        info "Espelhos atualizados no formato legado ($sources_file)"
    fi

    info "Instalando software-properties-common..."
    apt-get install -y software-properties-common >/dev/null 2>&1 || true

    info "Habilitando repositórios universe, multiverse e restricted..."
    add-apt-repository -y universe >/dev/null 2>&1 || true
    add-apt-repository -y multiverse >/dev/null 2>&1 || true
    add-apt-repository -y restricted >/dev/null 2>&1 || true

    info "Atualizando índices de pacotes (apt update)..."
    apt-get update -qq
    success "Repositórios atualizados com sucesso."
}

# -----------------------------------------------------------------------------
# 4. Instalação da Interface Gráfica Xubuntu Desktop (XFCE)
# -----------------------------------------------------------------------------
install_xubuntu_desktop() {
    step "Instalando a interface gráfica Xubuntu Desktop (XFCE)"

    info "Iniciando a instalação do pacote xubuntu-desktop (pode levar alguns minutos)..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y xubuntu-desktop

    # Garantir que o LightDM é o gerenciador de exibição padrão se instalado
    if dpkg -l | grep -q lightdm; then
        info "Definindo LightDM como Display Manager padrão..."
        echo "set shared/default-xdisplay-manager lightdm" | debconf-communicate 2>/dev/null || true
    fi

    success "Interface Xubuntu Desktop instalada."
}

# -----------------------------------------------------------------------------
# 5. Instalação de Pacotes e Utilitários Essenciais
#    Pacotes modernizados para Ubuntu 26.04:
#    - 7zip substitui p7zip-full (descontinuado)
#    - net-tools removido (iproute2 é nativo e moderno)
#    - gnupg continua presente como gpg
# -----------------------------------------------------------------------------
install_essential_packages() {
    step "Instalando pacotes e ferramentas essenciais"

    local cli_tools=(
        build-essential
        curl
        wget
        git
        vim
        nano
        htop
        btop
        iproute2
        unzip
        7zip
        unrar
        ca-certificates
        gnupg
        ufw
        cifs-utils
        nfs-common
        dconf-cli
        jq
        rsync
        tree
        bash-completion
        openssh-client
    )

    local desktop_apps=(
        vlc
        ffmpeg
        gimp
        remmina
        remmina-plugin-rdp
        remmina-plugin-secret
    )

    info "Instalando utilitários de linha de comando..."
    for pkg in "${cli_tools[@]}"; do
        DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" >/dev/null 2>&1 || warn "Pacote não disponível nesta versão: $pkg"
    done

    info "Instalando aplicativos de desktop (VLC, GIMP, Remmina, FFmpeg)..."
    for pkg in "${desktop_apps[@]}"; do
        DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" >/dev/null 2>&1 || warn "Aplicativo não disponível nesta versão: $pkg"
    done

    success "Pacotes essenciais instalados com sucesso."
}

# -----------------------------------------------------------------------------
# 6. Atualização do Sistema
# -----------------------------------------------------------------------------
upgrade_system() {
    step "Executando atualização completa do sistema (dist-upgrade)"

    info "Atualizando pacotes existentes..."
    DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
    success "Sistema completamente atualizado."
}

# -----------------------------------------------------------------------------
# 7. Otimizações de Desempenho e Kernel
# -----------------------------------------------------------------------------
configure_sysctl_performance() {
    step "Aplicando otimizações de desempenho (Swappiness & Sysctl)"

    local perf_sysctl="/etc/sysctl.d/99-postinstall-performance.conf"

    cat > "$perf_sysctl" << 'SYSCTL_EOF'
# Otimizações de desempenho pós-instalação
# Gerado por ubuntu-post-install.sh

# Reduz uso agressivo do SWAP (recomendado para Desktops/Servidores com RAM suficiente)
vm.swappiness = 10
vm.vfs_cache_pressure = 50

# Aumenta limites de inotify para sincronizadores (VS Code, Dropbox, etc)
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
SYSCTL_EOF

    sysctl -p "$perf_sysctl" >/dev/null 2>&1 || true
    success "Otimizações de desempenho aplicadas em $perf_sysctl"
}

# -----------------------------------------------------------------------------
# 8. Firewall Básico (UFW)
# -----------------------------------------------------------------------------
configure_firewall() {
    step "Configurando firewall básico (UFW)"

    if command -v ufw &>/dev/null; then
        info "Configurando regras padrão do UFW..."
        ufw default deny incoming >/dev/null 2>&1
        ufw default allow outgoing >/dev/null 2>&1
        ufw allow from 127.0.0.1 to 127.0.0.1 >/dev/null 2>&1

        # Liberar SSH se o servidor OpenSSH estiver instalado
        if dpkg -l | grep -q openssh-server; then
            ufw allow 22/tcp comment 'SSH' >/dev/null 2>&1 || true
            info "Porta SSH (22/tcp) permitida no firewall."
        fi

        ufw --force enable >/dev/null 2>&1 || true
        success "Firewall UFW ativado."
    fi
}

# -----------------------------------------------------------------------------
# 9. Limpeza Final
# -----------------------------------------------------------------------------
cleanup_system() {
    step "Realizando limpeza de arquivos temporários e pacotes residuais"

    info "Removendo pacotes desnecessários (autoremove)..."
    apt-get autoremove --purge -y >/dev/null 2>&1
    apt-get clean >/dev/null 2>&1

    if command -v snap &>/dev/null; then
        info "Atualizando pacotes Snap instalados..."
        # snap refresh pode falhar se o snap store ainda estiver carregando
        snap refresh 2>/dev/null || warn "Snap refresh falhou (normal logo após instalação). Tente novamente manualmente com: sudo snap refresh"
    fi

    success "Limpeza do sistema concluída."
}

# -----------------------------------------------------------------------------
# Resumo Final
# -----------------------------------------------------------------------------
show_summary() {
    local host_ip
    host_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")

    local ntp_daemon="chrony"
    command -v chronyc &>/dev/null || ntp_daemon="systemd-timesyncd"

    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║      Pós-Instalação do Xubuntu Concluída com Sucesso!        ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Sistema:${NC}            $(uname -s -r -m)"
    echo -e "  ${BOLD}IP do Host:${NC}         ${host_ip}"
    echo -e "  ${BOLD}Interface Gráfica:${NC}  Xubuntu Desktop (XFCE)"
    echo -e "  ${BOLD}Fuso Horário:${NC}       America/Sao_Paulo (SP / Brasil)"
    echo -e "  ${BOLD}Locale:${NC}             pt_BR.UTF-8"
    echo -e "  ${BOLD}Teclado:${NC}            ABNT2 (br)"
    echo -e "  ${BOLD}Daemon NTP:${NC}         ${ntp_daemon} (NTP.br: a.ntp.br, b.ntp.br, c.ntp.br)"
    echo -e "  ${BOLD}Espelhos APT:${NC}       br.archive.ubuntu.com"
    echo -e "  ${BOLD}Softwares:${NC}          VLC, GIMP, Remmina, FFmpeg, Git, Vim, Htop, Btop"
    echo -e "  ${BOLD}Compactação:${NC}        7zip (substitui p7zip-full legado)"
    echo -e "  ${BOLD}Swappiness:${NC}         10 (Otimizado)"
    echo ""
    echo -e "  ${BOLD}${CYAN}Comandos úteis pós-instalação:${NC}"
    echo -e "  - Verificar NTP:    ${BOLD}chronyc tracking${NC}"
    echo -e "  - Fontes NTP:       ${BOLD}chronyc sources -v${NC}"
    echo -e "  - Status da hora:   ${BOLD}timedatectl status${NC}"
    echo -e "  - Layout teclado:   ${BOLD}localectl${NC}"
    echo -e "  - Rede (moderno):   ${BOLD}ip a${NC} / ${BOLD}ss -tlnp${NC}"
    echo ""
    echo -e "  ${BOLD}${YELLOW}Nota:${NC} É recomendável reiniciar o sistema para aplicar todas as"
    echo -e "        configurações de ambiente de trabalho e teclado."
    echo -e "        Comando: ${BOLD}sudo reboot${NC}"
    echo ""
}

# -----------------------------------------------------------------------------
# Menu / Processamento de Argumentos
# -----------------------------------------------------------------------------
usage() {
    echo "Uso: sudo $0 [OPÇÕES]"
    echo ""
    echo "Opções:"
    echo "  -y, --unattended    Executa a pós-instalação completa de forma não-interativa"
    echo "  -h, --help          Exibe esta ajuda"
    echo ""
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--unattended)
                UNATTENDED=true
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

main() {
    parse_args "$@"

    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═════════════════════════════════════════════════════════╗"
    echo "  ║   Pós-Instalação do Ubuntu / Xubuntu Desktop (SP/BR)    ║"
    echo "  ║   Localização, Teclado ABNT2, NTP.br & Pacotes          ║"
    echo "  ╚═════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_root
    check_ubuntu

    if [[ "$UNATTENDED" == false ]]; then
        echo ""
        echo "Este script irá realizar as seguintes ações:"
        echo "  1. Configurar Fuso Horário (SP), Locale pt_BR.UTF-8 e Teclado ABNT2"
        echo "  2. Configurar sincronização de horário com NTP.br via chrony"
        echo "  3. Otimizar repositórios APT para os espelhos do Brasil"
        echo "  4. Instalar o ambiente gráfico Xubuntu Desktop (XFCE)"
        echo "  5. Instalar pacotes essenciais CLI e Desktop (VLC, GIMP, Remmina, etc)"
        echo "  6. Atualizar o sistema completamente"
        echo "  7. Aplicar otimizações de kernel (Swappiness) e firewall (UFW)"
        echo ""
        read -r -p "Deseja iniciar o processo de pós-instalação? [S/n] " resp
        resp="${resp:-s}"
        if [[ ! "$resp" =~ ^[sS]$ ]]; then
            die "Operação cancelada pelo usuário."
        fi
    fi

    configure_localization
    configure_ntp
    configure_apt_mirrors
    install_xubuntu_desktop
    install_essential_packages
    upgrade_system
    configure_sysctl_performance
    configure_firewall
    cleanup_system

    show_summary
}

main "$@"

# Baseado em: https://gist.github.com/moisesbarreiros/32f2cd4cf9e4c6f5680901868a4216a8