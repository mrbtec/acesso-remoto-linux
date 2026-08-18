Guia Completo de Otimização do XRDP no Ubuntu
Este guia aborda todas as otimizações necessárias para obter o máximo de desempenho e fluidez ao usar o XRDP no Ubuntu, desde a instalação até ajustes finos de rede e renderização gráfica.

📋 Índice
Instalação Correta do XRDP

Otimizações de Rede e Buffer

Configurações de Sessão e Cores

Backend Xorg vs VNC

Desativando Efeitos Visuais

Otimizações por Ambiente Gráfico

Configurações do Cliente

Monitoramento e Diagnóstico

Solução de Problemas Comuns

1. Instalação Correta do XRDP
1.1 Instalação dos Pacotes Essenciais
bash
# Atualize o sistema
sudo apt update && sudo apt upgrade -y

# Instale o XRDP e o backend Xorg
sudo apt install xrdp xorgxrdp -y

# Instale um ambiente gráfico leve (recomendado)
sudo apt install xfce4 xfce4-goodies -y
1.2 Configuração Inicial do Ambiente
bash
# Defina o XFCE como ambiente padrão
echo "xfce4-session" > ~/.xsession

# Reinicie o serviço
sudo systemctl restart xrdp
sudo systemctl enable xrdp
1.3 Verificação da Instalação
bash
# Verifique se o serviço está rodando
sudo systemctl status xrdp

# Verifique as portas em uso
sudo netstat -tlnp | grep xrdp
2. Otimizações de Rede e Buffer
2.1 Arquivo de Configuração Principal (/etc/xrdp/xrdp.ini)
bash
sudo nano /etc/xrdp/xrdp.ini
Configurações otimizadas:

ini
[Globals]
ini_version=1
fork=true
port=3389
use_vsock=false
tcp_nodelay=true
tcp_send_buffer_bytes=4194304      # 4MB - REDUZ DRAMATICAMENTE LAG
tcp_recv_buffer_bytes=4194304      # 4MB - MELHORA RECEPÇÃO DE DADOS
use_compression=yes
crypt_level=low                     # Menos CPU com criptografia
bitmap_cache=yes
bitmap_compression=yes
bulk_compression=true
max_bpp=16                          # Força 16 bits para menos dados
xserverbpp=16
enable_token_login=false
2.2 Configurações de Sessão (/etc/xrdp/sesman.ini)
bash
sudo nano /etc/xrdp/sesman.ini
Configurações otimizadas:

ini
[Xorg]
param=Xorg
param=-config
param=xrdp/xorg.conf
param=-noreset
param=-nolisten
param=tcp
param=-logfile
param=.xorgxrdp.%s.log

[SessionVariables]
X11DisplayOffset=10
MaxDisplayNumber=20
AllowRootLogin=false
FuseMountName=thinclient_drives
EnableUserWindowManager=true
UserWindowManager=startxfce4
DefaultWindowManager=startxfce4
MaxSessions=10
KillDisconnected=true
IdleTimeLimit=0
DisconnectedTimeLimit=0
3. Configurações de Sessão e Cores
3.1 Redução de Profundidade de Cor
Crie ou edite o arquivo de configuração do Xorg:

bash
sudo nano /etc/X11/xrdp/xorg.conf
Adicione ou modifique:

conf
Section "Screen"
    Identifier "Default Screen"
    Monitor "Configured Monitor"
    Device "Configured Video Device"
    DefaultDepth 16
    SubSection "Display"
        Depth 16
        Modes "1920x1080" "1600x900" "1366x768" "1280x720"
    EndSubSection
EndSection
3.2 Otimização do Cache de Bitmap
No arquivo /etc/xrdp/xrdp.ini, adicione:

ini
bitmap_cache_quality=50             # Equilíbrio entre qualidade e performance
bitmap_cache_size_mb=64             # Aumenta cache para 64MB
desktop_dpi=96
4. Backend Xorg vs VNC
4.1 Forçando Uso do Xorg
Certifique-se de que a sessão padrão seja Xorg no arquivo /etc/xrdp/xrdp.ini:

ini
[Xorg]
name=Xorg
lib=libxup.so
username=ask
password=ask
ip=127.0.0.1
port=-1
code=20
4.2 Removendo Dependências Desnecessárias
bash
# Desabilite serviços VNC desnecessários
sudo systemctl stop vncserver-x11-serviced
sudo systemctl disable vncserver-x11-serviced

# Desinstale servidores VNC adicionais
sudo apt remove tightvncserver tigervnc-standalone-server -y
5. Desativando Efeitos Visuais
5.1 Para XFCE (Recomendado)
bash
# Desative a composição via linha de comando
xfconf-query -c xfwm4 -p /general/use_compositing -s false
OU via interface gráfica:

Configurações → Gerenciador de Janelas → Compositor

Desmarque "Habilitar composição de tela"

5.2 Para GNOME (Ubuntu Padrão)
bash
# Desative animações
gsettings set org.gnome.desktop.interface enable-animations false

# Desative efeitos visuais
gsettings set org.gnome.desktop.interface gtk-enable-animations false

# Desative transparência
gsettings set org.gnome.desktop.interface enable-alpha false
5.3 Para KDE Plasma
bash
# Desative efeitos do compositor
kwriteconfig5 --file kwinrc --group Compositing --key Enabled false
kwriteconfig5 --file kwinrc --group Compositing --key OpenGLIsUnsafe true

# Reinicie o KWin
kwin_x11 --replace &
5.4 Otimizações Adicionais de Interface
Desative fundos de tela:

bash
# Para GNOME
gsettings set org.gnome.desktop.background picture-uri ''

# Para XFCE
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-path -s ''
Reduza o tempo de espera do cursor:

bash
# Reduza o tempo de resposta do cursor
xset m 1 1                    # Aceleração e threshold mínimos
xset r rate 200 20           # Velocidade de repetição de teclas
6. Otimizações por Ambiente Gráfico
6.1 XFCE (Mais Leve)
bash
# Instale o XFCE completo
sudo apt install xfce4 xfce4-goodies xfce4-terminal -y

# Configure o XFCE como padrão
echo "xfce4-session" > ~/.xsession

# Otimizações adicionais
xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-trash -s false
xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-home -s false
xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-removable -s false
6.2 LXDE (Ultra Leve)
bash
# Instale o LXDE
sudo apt install lxde lxde-common -y

# Configure como padrão
echo "startlxde" > ~/.xsession
6.3 MATE (Balanço Entre Leveza e Recursos)
bash
# Instale o MATE
sudo apt install mate-desktop-environment mate-desktop-environment-extra -y

# Configure como padrão
echo "mate-session" > ~/.xsession

# Desative composição
dconf write /org/mate/marco/general/compositing-manager false
6.4 GNOME com Otimizações
bash
# Instale extensões para otimização
sudo apt install gnome-shell-extensions -y

# Desative animações
gsettings set org.gnome.desktop.interface enable-animations false
gsettings set org.gnome.shell.extensions.dash-to-dock animate-show-apps false
gsettings set org.gnome.shell.extensions.dash-to-dock animate-window-launch false
7. Configurações do Cliente
7.1 Windows (Remote Desktop Connection)
Abra o Remote Desktop Connection

Clique em "Mostrar Opções"

Vá para a aba Experiência

Configure:

Performance: Selecione "Modem (56 kbps)"

Desmarque todas as opções visuais:

☐ Fundo da área de trabalho

☐ Menu iniciar

☐ Composição da área de trabalho

☐ Estilos visuais

☐ Fontes suaves

7.2 Linux (Remmina)
bash
# Instale o Remmina
sudo apt install remmina remmina-plugin-rdp -y
Configurações otimizadas no Remmina:

Protocolo: RDP

Qualidade: "Média" ou "Baixa"

Profundidade de cor: 16 bpp

Desative "Animações de janela"

Desative "Sombreamento de janela"

7.3 Android (Microsoft Remote Desktop)
Configurações → Experience

Selecionar "Low bandwidth"

Desativar "Background wallpaper"

8. Monitoramento e Diagnóstico
8.1 Script de Monitoramento
Crie um script para monitorar o desempenho:

bash
#!/bin/bash
# monitor_xrdp.sh

echo "=== MONITORAMENTO XRDP ==="
echo ""

echo "📊 Uso de CPU:"
top -bn1 | grep -E "xrdp|Xorg" | head -3

echo ""
echo "📊 Uso de Memória:"
free -h

echo ""
echo "📊 Conexões Ativas:"
sudo netstat -an | grep 3389 | grep ESTABLISHED

echo ""
echo "📊 Logs de Erro:"
sudo tail -n 20 /var/log/xrdp.log | grep -i error
Torne o script executável e execute periodicamente:

bash
chmod +x monitor_xrdp.sh
./monitor_xrdp.sh
8.2 Logs Úteis
bash
# Log principal do XRDP
sudo tail -f /var/log/xrdp.log

# Log de sessão
sudo tail -f /var/log/xrdp-sesman.log

# Log de erros do Xorg
sudo tail -f /var/log/xorg.*.log
8.3 Comandos de Diagnóstico
bash
# Verifique a profundidade de cor atual
xdpyinfo | grep "depth"

# Verifique o gerenciador de janelas em uso
echo $XDG_CURRENT_DESKTOP

# Verifique a resolução atual
xrandr --current | grep "*"

# Teste de latência de rede
ping -c 10 SEU_SERVIDOR
9. Solução de Problemas Comuns
9.1 Tela Preta na Conexão
Solução 1: Reinicie o serviço

bash
sudo systemctl restart xrdp
sudo systemctl restart xrdp-sesman
Solução 2: Verifique o arquivo .xsession

bash
# Certifique-se de que o arquivo existe e está configurado
cat ~/.xsession
# Deve conter: xfce4-session ou outro ambiente

# Se não existir, crie:
echo "xfce4-session" > ~/.xsession
Solução 3: Force um display diferente

bash
sudo pkill Xorg
sudo systemctl restart xrdp
9.2 Conexão Lenta ou Lag
Verifique a qualidade da rede:

bash
# Teste de velocidade entre cliente e servidor
iperf3 -c IP_DO_SERVIDOR -p 5201
Ajustes adicionais:

bash
# Aumente ainda mais os buffers
echo "net.core.rmem_max = 16777216" >> /etc/sysctl.conf
echo "net.core.wmem_max = 16777216" >> /etc/sysctl.conf
sudo sysctl -p
9.3 Problemas de Teclado
Configure o layout de teclado:

bash
# No arquivo /etc/xrdp/xrdp.ini
# Adicione:
keyboard_layout=pt-br    # Para português do Brasil
# Ou
keyboard_layout=us       # Para inglês

# Reinicie o serviço
sudo systemctl restart xrdp
9.4 Sessão Não Finaliza
bash
# Liste as sessões ativas
sudo xrdp-sesadmin list

# Finalize uma sessão específica
sudo xrdp-sesadmin kill SESSION_ID

# Ou finalize todas
sudo pkill -u $USER
sudo systemctl restart xrdp
9.5 Permissões de Áudio
bash
# Adicione o usuário ao grupo de áudio
sudo usermod -a -G audio $USER

# Configure o áudio no XRDP
echo "pulseaudio -D" >> ~/.xinitrc
📝 Lista de Verificação de Otimização
□ XRDP instalado com backend Xorg (xorgxrdp)
□ Ambiente gráfico leve instalado (XFCE recomendado)
□ Buffers de rede aumentados para 4MB
□ tcp_nodelay=true configurado
□ Compressão ativada (use_compression=yes)
□ Profundidade de cor reduzida para 16 bits
□ Efeitos visuais desativados
□ Fundos de tela e animações desligados
□ Cliente configurado para baixa largura de banda
□ Firewall configurado para porta 3389
🚀 Conclusão
Com estas otimizações, o XRDP no Ubuntu deve oferecer uma experiência de uso muito mais fluida e responsiva. A chave principal está em:

Buffers de rede aumentados (melhoria mais significativa)

Uso do backend Xorg (em vez do VNC)

Desativação de efeitos visuais (redução de carga gráfica)

Redução da profundidade de cor (menos dados transmitidos)

Se você ainda tiver problemas de desempenho mesmo após todas as otimizações, considere:

Usar uma conexão cabeada em vez de Wi-Fi

Verificar se o servidor tem recursos de hardware suficientes

Considerar um ambiente gráfico ainda mais leve (LXDE)

Dica Bônus: Para maior segurança, sempre utilize o XRDP em conjunto com uma VPN ou SSH tunneling, já que a criptografia nativa do RDP é limitada.

bash
# Exemplo de tunneling SSH para o XRDP
ssh -L 3389:localhost:3389 usuario@servidor_remoto
# Depois conecte-se a localhost:3389 no cliente RDP