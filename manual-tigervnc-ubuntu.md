# Manual de Instalação do Servidor TigerVNC no Ubuntu

## Índice

1. [Pré-requisitos](#pré-requisitos)
2. [Instalação do TigerVNC](#instalação-do-tigervnc)
3. [Configuração inicial](#configuração-inicial)
4. [Configurando o ambiente de desktop](#configurando-o-ambiente-de-desktop)
5. [Iniciando o servidor VNC](#iniciando-o-servidor-vnc)
6. [Configurando como serviço systemd](#configurando-como-serviço-systemd)
7. [Configurando o firewall](#configurando-o-firewall)
8. [Conexão via túnel SSH (recomendado)](#conexão-via-túnel-ssh-recomendado)
9. [Conectando ao servidor VNC](#conectando-ao-servidor-vnc)
10. [Comandos úteis](#comandos-úteis)
11. [Solução de problemas](#solução-de-problemas)

---

## Pré-requisitos

- Ubuntu 20.04, 22.04 ou 24.04 (LTS recomendado)
- Acesso à conta com privilégios `sudo`
- Conexão com a internet
- Um ambiente de desktop instalado (GNOME, XFCE, KDE, etc.)

### Instalar um ambiente de desktop (se necessário)

Caso o servidor Ubuntu não possua interface gráfica, instale um ambiente leve como o **XFCE**:

```bash
sudo apt update
sudo apt install -y xfce4 xfce4-goodies
```

Ou o **GNOME** (mais pesado):

```bash
sudo apt update
sudo apt install -y ubuntu-desktop
```

---

## Instalação do TigerVNC

Atualize os pacotes e instale o TigerVNC:

```bash
sudo apt update
sudo apt install -y tigervnc-standalone-server tigervnc-common
```

Verifique a versão instalada:

```bash
vncserver --version
```

---

## Configuração inicial

### 1. Definir a senha do VNC

Execute o comando abaixo com o usuário que irá usar o VNC (**não use sudo**):

```bash
vncpasswd
```

Você será solicitado a:
- Informar uma senha (mínimo 6 caracteres, máximo 8)
- Confirmar a senha
- Optionally configurar uma senha somente leitura (view-only)

As senhas ficam armazenadas em `~/.vnc/passwd`.

---

## Configurando o ambiente de desktop

O TigerVNC moderno usa o arquivo `~/.vnc/tigervnc.conf` para definir a sessão de desktop e outras opções do servidor.

### Método recomendado: arquivo tigervnc.conf

Crie o arquivo de configuração:

```bash
mkdir -p ~/.vnc
nano ~/.vnc/tigervnc.conf
```

Escolha o ambiente desejado e adicione ao arquivo:

```perl
# Ambiente de desktop (deve corresponder a um arquivo em /usr/share/xsessions)
$session = "xfce";      # para XFCE
# $session = "gnome";   # para GNOME
# $session = "lxde";    # para LXDE

# Resolução e profundidade de cor
$geometry = "1920x1080";
$depth = 24;

# Aceitar apenas conexões locais (usar com túnel SSH)
$localhost = "yes";
```

Para listar as sessões disponíveis no sistema:

```bash
ls /usr/share/xsessions/
```

### Método alternativo: arquivo xstartup

Se preferir controle manual, crie o arquivo `~/.vnc/xstartup`:

```bash
nano ~/.vnc/xstartup
```

#### Para XFCE (recomendado para servidores):

```bash
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
```

#### Para GNOME:

```bash
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XKL_XMODMAP_DISABLE=1
dbus-launch --exit-with-session gnome-session
```

Torne o arquivo executável:

```bash
chmod +x ~/.vnc/xstartup
```

---

## Iniciando o servidor VNC

### Iniciar na porta padrão (display :1 → porta 5901)

```bash
vncserver :1
```

### Iniciar com opções personalizadas

```bash
vncserver :1 -geometry 1920x1080 -depth 24 -localhost no
```

| Opção | Descrição |
|-------|-----------|
| `:1` | Número do display (porta = 5900 + número) |
| `-geometry` | Resolução da tela (largura x altura) |
| `-depth` | Profundidade de cor (24 bits recomendado) |
| `-localhost no` | Permite conexões externas (sem túnel SSH) |
| `-localhost yes` | Aceita apenas conexões locais (padrão, usar com SSH) |

### Parar o servidor VNC

```bash
vncserver -kill :1
```

### Listar sessões ativas

```bash
vncserver -list
```

---

## Configurando como serviço systemd

O TigerVNC já inclui o unit file `/lib/systemd/system/tigervncserver@.service`. Não é necessário criar um novo arquivo de serviço.

### 1. Mapear o display ao usuário

Edite o arquivo `/etc/tigervnc/vncserver.users` para associar um número de display a um usuário do sistema:

```bash
sudo nano /etc/tigervnc/vncserver.users
```

Adicione a linha no formato `:<display>=<usuario>`. Substitua `SEU_USUARIO` pelo nome real do usuário:

```
:1=SEU_USUARIO
```

Salve e feche o arquivo (`Ctrl+X`, `Y`, `Enter`).

### 2. (Opcional) Configurar opções globais do servidor

Para definir opções padrão para todos os usuários, edite:

```bash
sudo nano /etc/tigervnc/vncserver-config-defaults
```

Exemplo de conteúdo:

```perl
$geometry = "1920x1080";
$depth = 24;
$localhost = "yes";
```

### 3. Habilitar e iniciar o serviço

```bash
sudo systemctl enable tigervncserver@:1.service
sudo systemctl start tigervncserver@:1.service
```

### 4. Verificar o status do serviço

```bash
sudo systemctl status tigervncserver@:1.service
```

---

## Configurando o firewall

### Usando UFW

Se estiver usando túnel SSH (recomendado), **não é necessário** liberar a porta VNC no firewall.

Caso precise liberar acesso direto (menos seguro):

```bash
# Liberar porta do display :1
sudo ufw allow 5901/tcp

# Liberar porta do display :2
sudo ufw allow 5902/tcp

# Verificar regras
sudo ufw status
```

---

## Conexão via túnel SSH (recomendado)

O túnel SSH criptografa o tráfego VNC, tornando a conexão segura.

### No cliente (sua máquina local), execute:

```bash
ssh -L 5901:localhost:5901 -N -f usuario@IP_DO_SERVIDOR
```

| Parâmetro | Descrição |
|-----------|-----------|
| `-L 5901:localhost:5901` | Redireciona porta local 5901 para a porta 5901 do servidor |
| `-N` | Não executa comandos remotos |
| `-f` | Roda em segundo plano |
| `usuario@IP_DO_SERVIDOR` | Usuário e IP do servidor Ubuntu |

Após estabelecer o túnel, conecte o cliente VNC em `localhost:5901`.

---

## Conectando ao servidor VNC

### Clientes VNC recomendados

| Cliente | Plataforma | Download |
|---------|-----------|----------|
| **TigerVNC Viewer** | Windows, Linux, macOS | https://tigervnc.org |
| **RealVNC Viewer** | Windows, Linux, macOS, Mobile | https://www.realvnc.com |
| **Remmina** | Linux | `sudo apt install remmina` |

### Instalando o TigerVNC Viewer no cliente Linux

```bash
sudo apt install tigervnc-viewer
```

### Conectando

```bash
# Sem túnel SSH (conexão direta)
vncviewer IP_DO_SERVIDOR:5901

# Com túnel SSH ativo
vncviewer localhost:5901
```

---

## Comandos úteis

```bash
# Iniciar servidor VNC no display :1
vncserver :1

# Iniciar com resolução personalizada
vncserver :1 -geometry 1280x720 -depth 24

# Parar o servidor VNC no display :1
vncserver -kill :1

# Listar todas as sessões VNC ativas
vncserver -list

# Alterar a senha do VNC
vncpasswd

# Verificar logs do VNC
cat ~/.vnc/*.log

# Iniciar serviço systemd (display :1)
sudo systemctl start tigervncserver@:1.service

# Reiniciar o serviço systemd
sudo systemctl restart tigervncserver@:1.service

# Parar o serviço systemd
sudo systemctl stop tigervncserver@:1.service

# Ver logs do serviço
sudo journalctl -u tigervncserver@:1.service -f
```

---

## Solução de problemas

### Tela cinza ou preta ao conectar

O arquivo `~/.vnc/xstartup` pode estar incorreto. Verifique se:
- O arquivo tem permissão de execução (`chmod +x ~/.vnc/xstartup`)
- O ambiente de desktop indicado está instalado
- O comando no arquivo está correto para seu desktop

```bash
# Verificar se o XFCE está instalado
which startxfce4

# Verificar logs de erro
cat ~/.vnc/*.log
```

### Erro "A VNC server is already running"

```bash
# Listar e matar todas as sessões
vncserver -kill :1
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
```

### Conexão recusada

1. Verifique se o servidor está em execução: `vncserver -list`
2. Verifique se a porta está aberta: `ss -tlnp | grep 590`
3. Verifique o firewall: `sudo ufw status`
4. Confirme o IP do servidor: `ip addr show`

### Serviço systemd não inicia

```bash
# Ver erro detalhado
sudo journalctl -u tigervncserver@:1.service --no-pager

# Verificar se o mapeamento de usuário está correto
cat /etc/tigervnc/vncserver.users

# Verificar se a senha VNC do usuário foi definida
ls ~/.vnc/passwd
```

### Desempenho lento

- Use o ambiente XFCE em vez de GNOME
- Reduza a resolução: `-geometry 1280x720`
- Use conexão via LAN em vez de WAN
- Ative compressão no cliente VNC

---

## Referências

- [Site oficial do TigerVNC](https://tigervnc.org)
- [Repositório GitHub do TigerVNC](https://github.com/TigerVNC/tigervnc)
- [Documentação Ubuntu Server](https://ubuntu.com/server/docs)
