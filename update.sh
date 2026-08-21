#!/bin/bash
# =============================================================
#  Ubuntu Full Update Script
#  Atualização completa do sistema com limpeza automática
# =============================================================

set -e

echo "============================================="
echo "  🔄 Atualização Completa do Ubuntu"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================="
echo ""

# 1. Atualizar lista de pacotes
echo "📦 [1/6] Atualizando lista de pacotes..."
sudo apt update

# 2. Upgrade padrão (pacotes existentes)
echo ""
echo "⬆️  [2/6] Atualizando pacotes instalados..."
sudo apt upgrade -y

# 3. Dist-upgrade (resolve dependências, adiciona/remove conforme necessário)
echo ""
echo "🔧 [3/6] Dist-upgrade (resolução de dependências)..."
sudo apt dist-upgrade -y

# 4. Full-upgrade (equivalente ao dist-upgrade no apt moderno)
echo ""
echo "🚀 [4/6] Full-upgrade..."
sudo apt full-upgrade -y

# 5. Remover pacotes órfãos e desnecessários
echo ""
echo "🧹 [5/6] Removendo pacotes desnecessários..."
sudo apt autoremove -y
sudo apt autoclean -y

# 6. Verificar se reboot é necessário
echo ""
echo "✅ [6/6] Verificando estado do sistema..."
if [ -f /var/run/reboot-required ]; then
    echo ""
    echo "⚠️  REINICIALIZAÇÃO NECESSÁRIA!"
    echo "   Pacotes que requerem reboot:"
    [ -f /var/run/reboot-required.pkgs ] && cat /var/run/reboot-required.pkgs
    echo ""
    read -p "   Deseja reiniciar agora? (s/N): " resposta
    if [[ "$resposta" =~ ^[Ss]$ ]]; then
        echo "   Reiniciando em 5 segundos..."
        sleep 5
        sudo reboot
    else
        echo "   Reboot adiado. Lembre-se de reiniciar manualmente."
    fi
else
    echo "   ✅ Nenhuma reinicialização necessária."
fi

echo ""
echo "============================================="
echo "  ✅ Atualização concluída!"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================="