#!/usr/bin/env bash
# =============================================================================
# auto-update.sh
# Atualização automática do Ubuntu com suporte a cron, systemd timer e
# execução interativa.
# Versão: 1.0
# =============================================================================
#
# Uso:
#   Interativo:    sudo ./auto-update.sh
#   Automático:    sudo ./auto-update.sh --auto
#   Com reboot:    sudo ./auto-update.sh --auto --reboot
#   Ajuda:         ./auto-update.sh --help
#
# Instalação do agendamento:
#   Cron:          sudo ./auto-update.sh --install-cron
#   Systemd:       sudo ./auto-update.sh --install-timer
#   Remover:       sudo ./auto-update.sh --uninstall
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Ambiente — cron/systemd herdam ambiente mínimo, precisamos garantir estes
# -----------------------------------------------------------------------------
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LANG="${LANG:-pt_BR.UTF-8}"
export LC_ALL="${LC_ALL:-pt_BR.UTF-8}"
export DEBIAN_FRONTEND="noninteractive"

# -----------------------------------------------------------------------------
# Constantes
# -----------------------------------------------------------------------------
SCRIPT_NAME="$(basename "$0")"
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/${SCRIPT_NAME}"
LOG_FILE="/var/log/ubuntu-update.log"
LOCK_FILE="/var/lock/ubuntu-update.lock"
APT_LOCK="/var/lib/dpkg/lock-frontend"

# Configurações padrão
AUTO_MODE=false
AUTO_REBOOT=false
REBOOT_WINDOW_START=2   # hora início da janela de reboot (02:00)
REBOOT_WINDOW_END=5     # hora fim da janela de reboot (05:00)

# Cron/Systemd
CRON_FILE="/etc/cron.d/ubuntu-update"
SYSTEMD_SERVICE="/etc/systemd/system/ubuntu-update.service"
SYSTEMD_TIMER="/etc/systemd/system/ubuntu-update.timer"
LOGROTATE_CONF="/etc/logrotate.d/ubuntu-update"

# -----------------------------------------------------------------------------
# Cores (desabilitadas em modo automático)
# -----------------------------------------------------------------------------
setup_colors() {
    if [[ "$AUTO_MODE" == true ]] || [[ ! -t 1 ]]; then
        RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
    else
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        CYAN='\033[0;36m'
        BOLD='\033[1m'
        NC='\033[0m'
    fi
}

# -----------------------------------------------------------------------------
# Funções auxiliares
# -----------------------------------------------------------------------------
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
info()      { echo -e "${BLUE}[INFO]${NC}  $(timestamp) $*"; }
success()   { echo -e "${GREEN}[OK]${NC}    $(timestamp) $*"; }
warn()      { echo -e "${YELLOW}[AVISO]${NC} $(timestamp) $*"; }
error()     { echo -e "${RED}[ERRO]${NC}  $(timestamp) $*" >&2; }
step()      { echo -e "\n${BOLD}${CYAN}==> $*${NC}"; }
die()       { error "$*"; cleanup_lock; exit 1; }

# -----------------------------------------------------------------------------
# Lock — evita execuções simultâneas
# -----------------------------------------------------------------------------
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            die "Outra instância já está em execução (PID: $lock_pid). Abortando."
        else
            warn "Lock file obsoleto encontrado. Removendo..."
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
}

cleanup_lock() {
    rm -f "$LOCK_FILE" 2>/dev/null || true
}

trap cleanup_lock EXIT INT TERM

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
    fi
}

# Aguardar liberação do lock do APT (outro processo pode estar atualizando)
wait_for_apt() {
    local max_wait=300  # 5 minutos
    local waited=0

    while fuser "$APT_LOCK" >/dev/null 2>&1; do
        if [[ $waited -ge $max_wait ]]; then
            die "Timeout aguardando liberação do APT lock ($APT_LOCK). Outro processo está usando o APT há mais de 5 minutos."
        fi
        info "APT em uso por outro processo. Aguardando... (${waited}s/${max_wait}s)"
        sleep 10
        waited=$((waited + 10))
    done
}

# -----------------------------------------------------------------------------
# Atualização do sistema
# -----------------------------------------------------------------------------
run_update() {
    step "[1/4] Atualizando lista de pacotes"
    apt-get update -qq
    success "Lista de pacotes atualizada."

    step "[2/4] Atualizando pacotes instalados (dist-upgrade)"
    apt-get dist-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    success "Pacotes atualizados."

    step "[3/4] Removendo pacotes desnecessários"
    apt-get autoremove --purge -y >/dev/null 2>&1 || true
    apt-get autoclean -y >/dev/null 2>&1 || true
    success "Limpeza concluída."

    step "[4/4] Verificando estado do sistema"

    # Atualizar snaps se disponível
    if command -v snap &>/dev/null; then
        info "Atualizando pacotes Snap..."
        snap refresh 2>/dev/null || warn "Snap refresh falhou (pode estar em uso)."
    fi
}

# -----------------------------------------------------------------------------
# Verificação e tratamento de reboot
# -----------------------------------------------------------------------------
handle_reboot() {
    if [[ ! -f /var/run/reboot-required ]]; then
        success "Nenhuma reinicialização necessária."
        return
    fi

    warn "REINICIALIZAÇÃO NECESSÁRIA!"
    if [[ -f /var/run/reboot-required.pkgs ]]; then
        info "Pacotes que requerem reboot:"
        cat /var/run/reboot-required.pkgs
    fi

    if [[ "$AUTO_MODE" == true ]]; then
        if [[ "$AUTO_REBOOT" == true ]]; then
            local current_hour
            current_hour=$(date +%H)
            current_hour=$((10#$current_hour))  # remover zero à esquerda

            if (( current_hour >= REBOOT_WINDOW_START && current_hour < REBOOT_WINDOW_END )); then
                warn "Reiniciando automaticamente (dentro da janela ${REBOOT_WINDOW_START}h-${REBOOT_WINDOW_END}h)..."
                sync
                sleep 5
                /sbin/reboot
            else
                info "Reboot necessário, mas fora da janela permitida (${REBOOT_WINDOW_START}h-${REBOOT_WINDOW_END}h). Hora atual: ${current_hour}h."
                info "O reboot será realizado na próxima execução dentro da janela."
            fi
        else
            info "Reboot necessário. Execute manualmente: sudo reboot"
        fi
    else
        echo ""
        read -r -p "   Deseja reiniciar agora? (s/N): " resposta
        if [[ "$resposta" =~ ^[sS]$ ]]; then
            warn "Reiniciando em 5 segundos..."
            sleep 5
            /sbin/reboot
        else
            info "Reboot adiado. Lembre-se de reiniciar manualmente."
        fi
    fi
}

# -----------------------------------------------------------------------------
# Instalação do agendamento via Cron
# -----------------------------------------------------------------------------
install_cron() {
    check_root
    info "Instalando cron job para atualização automática diária às 03:00..."

    cat > "$CRON_FILE" << CRON_EOF
# Atualização automática do Ubuntu — diária às 03:00
# Gerado por auto-update.sh em $(timestamp)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
LANG=pt_BR.UTF-8

0 3 * * * root ${SCRIPT_PATH} --auto >> ${LOG_FILE} 2>&1
CRON_EOF

    chmod 644 "$CRON_FILE"
    install_logrotate

    success "Cron job instalado: $CRON_FILE"
    info "Atualização agendada para todos os dias às 03:00."
    info "Log de execução: $LOG_FILE"
    info "Para remover: sudo $SCRIPT_PATH --uninstall"
}

# -----------------------------------------------------------------------------
# Instalação do agendamento via Systemd Timer
# -----------------------------------------------------------------------------
install_timer() {
    check_root
    info "Instalando systemd timer para atualização automática..."

    # Service unit
    cat > "$SYSTEMD_SERVICE" << SERVICE_EOF
[Unit]
Description=Atualização automática do Ubuntu
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/mrbtec/acesso-remoto-linux

[Service]
Type=oneshot
ExecStart=${SCRIPT_PATH} --auto
Environment="DEBIAN_FRONTEND=noninteractive"
Environment="LANG=pt_BR.UTF-8"
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}
Nice=10
IOSchedulingClass=idle
SERVICE_EOF

    # Timer unit
    cat > "$SYSTEMD_TIMER" << TIMER_EOF
[Unit]
Description=Timer para atualização automática do Ubuntu

[Timer]
# Executar 15 minutos após o boot
OnBootSec=15min
# Executar diariamente às 03:00
OnCalendar=*-*-* 03:00:00
# Randomizar até 30 min para evitar pico nos espelhos
RandomizedDelaySec=1800
# Manter agendamento mesmo se o sistema esteve desligado
Persistent=true

[Install]
WantedBy=timers.target
TIMER_EOF

    install_logrotate

    systemctl daemon-reload
    systemctl enable ubuntu-update.timer
    systemctl start ubuntu-update.timer

    success "Systemd timer instalado e ativado."
    info "Agendamento: diário às 03:00 + 15 min após cada boot."
    info "Log de execução: $LOG_FILE"
    info "Verificar timer:  systemctl list-timers ubuntu-update.timer"
    info "Status:           systemctl status ubuntu-update.timer"
    info "Executar agora:   sudo systemctl start ubuntu-update.service"
    info "Para remover:     sudo $SCRIPT_PATH --uninstall"
}

# -----------------------------------------------------------------------------
# Instalar logrotate
# -----------------------------------------------------------------------------
install_logrotate() {
    cat > "$LOGROTATE_CONF" << 'LOGROTATE_EOF'
/var/log/ubuntu-update.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 640 root adm
}
LOGROTATE_EOF
    info "Logrotate configurado: $LOGROTATE_CONF"
}

# -----------------------------------------------------------------------------
# Desinstalar agendamento
# -----------------------------------------------------------------------------
uninstall_schedule() {
    check_root
    info "Removendo agendamentos de atualização automática..."

    # Remover cron
    if [[ -f "$CRON_FILE" ]]; then
        rm -f "$CRON_FILE"
        success "Cron job removido: $CRON_FILE"
    fi

    # Remover systemd timer
    if [[ -f "$SYSTEMD_TIMER" ]]; then
        systemctl stop ubuntu-update.timer 2>/dev/null || true
        systemctl disable ubuntu-update.timer 2>/dev/null || true
        rm -f "$SYSTEMD_SERVICE" "$SYSTEMD_TIMER"
        systemctl daemon-reload
        success "Systemd timer removido."
    fi

    # Remover logrotate
    if [[ -f "$LOGROTATE_CONF" ]]; then
        rm -f "$LOGROTATE_CONF"
        success "Logrotate removido: $LOGROTATE_CONF"
    fi

    success "Agendamentos removidos com sucesso."
    info "O log existente foi preservado: $LOG_FILE"
}

# -----------------------------------------------------------------------------
# Ajuda
# -----------------------------------------------------------------------------
usage() {
    cat << USAGE_EOF
Uso: sudo $SCRIPT_NAME [OPÇÕES]

Script de atualização completa do Ubuntu com suporte a execução interativa
e automática via cron ou systemd timer.

Opções de Execução:
  (sem opção)         Execução interativa (com prompts visuais)
  --auto, -y          Execução automática (sem prompts, ideal para cron)
  --reboot            Permite reboot automático (apenas com --auto, entre 02h-05h)

Opções de Agendamento:
  --install-cron      Instala cron job (diário às 03:00)
  --install-timer     Instala systemd timer (diário às 03:00 + 15min pós-boot)
  --uninstall         Remove cron job e/ou systemd timer

Outras:
  --status            Exibe estado do agendamento e último log
  -h, --help          Exibe esta ajuda

Exemplos:
  sudo ./auto-update.sh                    # Interativo
  sudo ./auto-update.sh --auto             # Automático (log em $LOG_FILE)
  sudo ./auto-update.sh --auto --reboot    # Automático com reboot permitido
  sudo ./auto-update.sh --install-timer    # Instala timer systemd
  sudo ./auto-update.sh --install-cron     # Instala cron job

USAGE_EOF
    exit 0
}

# -----------------------------------------------------------------------------
# Status do agendamento
# -----------------------------------------------------------------------------
show_status() {
    echo ""
    echo -e "${BOLD}Estado do agendamento de atualização:${NC}"
    echo ""

    # Cron
    if [[ -f "$CRON_FILE" ]]; then
        echo -e "  ${GREEN}●${NC} Cron:    ${GREEN}Ativo${NC} ($CRON_FILE)"
        grep -v '^#' "$CRON_FILE" | grep -v '^$' | grep -v '^[A-Z]' | head -1 | sed 's/^/           /'
    else
        echo -e "  ${RED}○${NC} Cron:    ${RED}Não instalado${NC}"
    fi

    # Systemd Timer
    if [[ -f "$SYSTEMD_TIMER" ]]; then
        echo -e "  ${GREEN}●${NC} Systemd: ${GREEN}Ativo${NC}"
        systemctl status ubuntu-update.timer --no-pager 2>/dev/null | grep -E "Active:|Trigger:" | sed 's/^/           /'
    else
        echo -e "  ${RED}○${NC} Systemd: ${RED}Não instalado${NC}"
    fi

    # Log
    echo ""
    if [[ -f "$LOG_FILE" ]]; then
        local log_size
        log_size=$(du -h "$LOG_FILE" | awk '{print $1}')
        echo -e "  ${BOLD}Log:${NC} $LOG_FILE ($log_size)"
        echo -e "  ${BOLD}Última execução:${NC}"
        tail -5 "$LOG_FILE" 2>/dev/null | sed 's/^/    /'
    else
        echo -e "  ${BOLD}Log:${NC} Nenhum log encontrado."
    fi
    echo ""
}

# -----------------------------------------------------------------------------
# Processamento de argumentos
# -----------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --auto|-y)
                AUTO_MODE=true
                shift
                ;;
            --reboot)
                AUTO_REBOOT=true
                shift
                ;;
            --install-cron)
                setup_colors
                install_cron
                exit 0
                ;;
            --install-timer)
                setup_colors
                install_timer
                exit 0
                ;;
            --uninstall)
                setup_colors
                uninstall_schedule
                exit 0
                ;;
            --status)
                setup_colors
                show_status
                exit 0
                ;;
            -h|--help)
                setup_colors
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
    setup_colors

    # Cabeçalho
    echo ""
    echo -e "${BOLD}${CYAN}=============================================${NC}"
    echo -e "${BOLD}${CYAN}  Atualização Completa do Ubuntu${NC}"
    echo -e "${BOLD}${CYAN}  $(timestamp)${NC}"
    if [[ "$AUTO_MODE" == true ]]; then
        echo -e "${BOLD}${CYAN}  Modo: AUTOMÁTICO${NC}"
    else
        echo -e "${BOLD}${CYAN}  Modo: INTERATIVO${NC}"
    fi
    echo -e "${BOLD}${CYAN}=============================================${NC}"
    echo ""

    check_root
    check_ubuntu
    acquire_lock
    wait_for_apt

    local start_time
    start_time=$(date +%s)

    run_update
    handle_reboot

    local end_time elapsed
    end_time=$(date +%s)
    elapsed=$(( end_time - start_time ))
    local minutes=$(( elapsed / 60 ))
    local seconds=$(( elapsed % 60 ))

    echo ""
    echo -e "${BOLD}${GREEN}=============================================${NC}"
    echo -e "${BOLD}${GREEN}  Atualização concluída!${NC}"
    echo -e "${BOLD}${GREEN}  $(timestamp)${NC}"
    echo -e "${BOLD}${GREEN}  Duração: ${minutes}m ${seconds}s${NC}"
    echo -e "${BOLD}${GREEN}=============================================${NC}"
    echo ""
}

main "$@"
