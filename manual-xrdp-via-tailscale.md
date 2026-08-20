# Manual de Acesso Remoto ao XRDP via Tailscale

Este manual descreve como instalar, configurar e disponibilizar o acesso remoto ao servidor **XRDP (Ubuntu)** utilizando a rede mesh VPN privada do **Tailscale** (baseada em WireGuard).

Com esta solução, você obtém **acesso remoto seguro de qualquer lugar do mundo**, sem expor portas públicas no roteador (sem Port Forwarding / NAT) e com tráfego 100% criptografado ponta a ponta.

---

## Índice

1. [Visão geral e Arquitetura](#visão-geral-e-arquitetura)
2. [Pré-requisitos](#pré-requisitos)
3. [Instalação e Configuração do XRDP no Ubuntu](#instalação-e-configuração-do-xrdp-no-ubuntu)
4. [Instalação do Tailscale no Servidor Ubuntu](#instalação-do-tailscale-no-servidor-ubuntu)
   - [Opção A: Script Oficial de Instalação (Recomendado)](#opção-a-script-oficial-de-instalação-recomendado)
   - [Opção B: Via Repositório APT Oficial (Ubuntu 24.04 / Noble)](#opção-b-via-repositório-apt-oficial-ubuntu-2404--noble)
5. [Conectando o Servidor à Rede Tailscale (Tailnet)](#conectando-o-servidor-à-rede-tailscale-tailnet)
6. [Configuração do Firewall (UFW / Tailscale)](#configuração-do-firewall-ufw--tailscale)
7. [Formas de Conexão pelos Clientes Remotos](#formas-de-conexão-pelos-clientes-remotos)
   - [Windows (mstsc.exe)](#windows-mstscexe)
   - [Linux (Remmina / FreeRDP)](#linux-remmina--freerdp)
   - [macOS, Android e iOS](#macos-android-e-ios)
8. [Recursos Avançados do Tailscale](#recursos-avançados-do-tailscale)
   - [Uso do MagicDNS (Acesso por nome de host)](#uso-do-magicdns-acesso-por-nome-de-host)
   - [Subnet Router (Roteamento de Sub-rede local)](#subnet-router-roteamento-de-sub-rede-local)
   - [Restrição de Acesso por ACLs (Tailscale Admin Console)](#restrição-de-acesso-por-acls-tailscale-admin-console)
9. [Comandos Úteis de Diagnóstico](#comandos-úteis-de-diagnóstico)
10. [Solução de Problemas](#solução-de-problemas)
11. [Boas Práticas de Segurança](#boas-práticas-de-segurança)

---

## Visão geral e Arquitetura

O **Tailscale** cria uma rede virtual privada (*Tailnet*) baseada no protocolo **WireGuard**. Cada dispositivo (servidor, computador pessoal, smartphone) conectado à sua conta recebe um endereço IP privado exclusivo dentro da faixa `100.x.y.z`.

### Fluxo de Conexão:

```
[ Cliente Remoto ] ── (Tailscale / IP: 100.x.y.z)
       │
       ▼  (Túnel criptografado WireGuard P2P)
       │
 [ Servidor Ubuntu ] ── (Interface tailscale0) ──► [ XRDP local: 127.0.0.1:3389 ]
```

### Principais Vantagens do Tailscale com XRDP:
- **Zero Port Forwarding:** Não exige abertura de portas 3389 no roteador.
- **Criptografia Nativa WireGuard:** Conexão direta peer-to-peer (P2P) ultra rápida e segura.
- **Autenticação SSO / 2FA:** Acesso controlado via provedores de identidade (Google, Microsoft, GitHub, Okta).
- **MagicDNS:** Conecte usando o nome da máquina (`ubuntu-servidor.tailnet.ts.net`) em vez de memorizar IPs.

---

## Pré-requisitos

1. **Servidor Ubuntu** (20.04, 22.04 ou 24.04 LTS) com privilégios `sudo`.
2. **Conta Gratuita no Tailscale** (acesse [tailscale.com](https://tailscale.com) para criar uma conta).
3. **Dispositivo Cliente** (Windows, Linux, macOS, Android ou iOS) com o aplicativo Tailscale instalado.

---

## Instalação e Configuração do XRDP no Ubuntu

Se você ainda não instalou o servidor XRDP, execute os passos abaixo (ou utilize o script `install-xrdp-server.sh` do repositório):

```bash
# 1. Atualizar o sistema e instalar o XRDP e um ambiente leve (XFCE)
sudo apt update
sudo apt install -y xrdp xfce4 xfce4-goodies

# 2. Configurar a sessão gráfica padrão para o usuário
echo "startxfce4" > ~/.xsession
chmod +x ~/.xsession

# 3. Adicionar o usuário xrdp ao grupo ssl-cert
sudo adduser xrdp ssl-cert

# 4. Habilitar e iniciar o serviço XRDP
sudo systemctl enable --now xrdp

# 5. Verifique se o serviço está ativo
sudo systemctl status xrdp
```

---

## Instalação do Tailscale no Servidor Ubuntu

### Opção A: Script Oficial de Instalação (Recomendado)

O script oficial detecta automaticamente a distribuição Linux e adiciona a chave GPG e o repositório correto:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

---

### Opção B: Via Repositório APT Oficial (Ubuntu 24.04 / Noble)

Caso prefira instalar manualmente adicionando o repositório da Tailscale:

```bash
# 1. Criar o diretório de chaves e adicionar a chave GPG do Tailscale
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null

# 2. Adicionar a lista de repositórios do Tailscale
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list

# 3. Atualizar e instalar o pacote tailscale
sudo apt-get update
sudo apt-get install -y tailscale
```

> **Para Ubuntu 22.04 (Jammy):** Substitua `noble` por `jammy` nos links acima.

---

## Conectando o Servidor à Rede Tailscale (Tailnet)

Após instalar o pacote `tailscale`, inicie o serviço e autentique a máquina:

```bash
sudo tailscale up
```

O terminal exibirá uma URL de autenticação:

```text
To authenticate, visit:
  https://login.tailscale.com/a/a1b2c3d4e5f6
```

1. Copie o link e abra-o no seu navegador.
2. Faça login com a sua conta do Tailscale (Google, Microsoft, GitHub, etc.).
3. Clique em **Authorize** para aprovar a conexão do servidor Ubuntu.

Após a autorização, consulte o endereço IP do seu servidor na rede Tailscale:

```bash
tailscale ip -4
```

> **Exemplo de saída:** `100.85.120.45`

---

## Configuração do Firewall (UFW / Tailscale)

Por padrão, quando você se conecta via Tailscale, o tráfego que entra pela interface `tailscale0` é seguro. No entanto, é boa prática configurar o firewall **UFW** no Ubuntu para aceitar conexões RDP **exclusivamente através da interface do Tailscale**.

### 1. Permitir tráfego na porta 3389 somente vindo do Tailscale:

```bash
# Permitir conexões RDP na interface do Tailscale (tailscale0)
sudo ufw allow in on tailscale0 to any port 3389 proto tcp

# Ativar o UFW caso não esteja ativo
sudo ufw enable

# Verificar o status das regras
sudo ufw status verbose
```

### 2. (Opcional) Bloquear acesso direto à porta 3389 na rede local física:
Se quiser impedir conexões na porta 3389 via IP local tradicional (ex: `192.168.1.X`), remova a regra antiga:

```bash
sudo ufw delete allow 3389/tcp
```

---

## Formas de Conexão pelos Clientes Remotos

### Passo Prévio: Instalar o Tailscale no Dispositivo Cliente
Instale o aplicativo Tailscale na máquina cliente (Windows, Linux, Mac, iPhone ou Android) a partir de [tailscale.com/download](https://tailscale.com/download) e faça login na **mesma conta Tailscale**.

---

### Windows (mstsc.exe)

1. Abra o aplicativo **Conexão de Área de Trabalho Remota** (`mstsc.exe`).
2. No campo **Computador**, informe o **IP do Tailscale** (ex: `100.85.120.45`) ou o nome MagicDNS (ex: `ubuntu-servidor.tailnet-name.ts.net`).
3. Clique em **Conectar**.
4. Aceite o aviso de certificado TLS (se autoassinado).
5. Digite o usuário e a senha do seu sistema Ubuntu.

---

### Linux (Remmina / FreeRDP)

#### Usando o Remmina:
1. Abra o **Remmina**.
2. Crie uma nova conexão do tipo **RDP**.
3. No campo **Servidor**, digite o IP do Tailscale: `100.85.120.45:3389`.
4. Informe Usuário e Senha e clique em **Conectar**.

#### Usando FreeRDP via terminal:
```bash
xfreerdp /v:100.85.120.45 /u:SEU_USUARIO /p:SUA_SENHA /cert:ignore
```

---

### macOS, Android e iOS

1. Instale o app **Tailscale** na App Store ou Google Play Store e conecte-o à sua conta.
2. Instale um cliente RDP oficial como o **Microsoft Remote Desktop** (disponível na App Store / Play Store).
3. Adicione um novo PC informando o IP Tailscale (`100.85.120.45`).
4. Inicie a conexão normalmente.

---

## Recursos Avançados do Tailscale

### Uso do MagicDNS (Acesso por nome de host)

O **MagicDNS** atribui automaticamente um nome amigável a cada dispositivo da sua rede Tailscale.

1. No [Painel Admin do Tailscale](https://login.tailscale.com/admin/dns), certifique-se de que o **MagicDNS** está ativado.
2. Verifique o nome completo FQDN da sua máquina:
   ```bash
   tailscale status
   ```
3. Em vez de usar `100.85.120.45`, você pode se conectar no cliente RDP digitando:
   `ubuntu-servidor.seu-tailnet.ts.net`

---

### Subnet Router (Roteamento de Sub-rede local)

Se você tem outros dispositivos na rede local do Ubuntu que não possuem o Tailscale instalado, pode transformar este servidor Ubuntu em um **Subnet Router**:

1. No servidor Ubuntu, habilite o encaminhamento de pacotes IPv4 no kernel:
   ```bash
   echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
   echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
   sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
   ```

2. Inicie o Tailscale anunciando a sua rede local (ex: `192.168.1.0/24`):
   ```bash
   sudo tailscale up --advertise-routes=192.168.1.0/24
   ```

3. Acesse o [Painel Admin do Tailscale](https://login.tailscale.com/admin/machines) > clique nos três pontos ao lado do servidor > **Edit route settings** > Aprove a rota `192.168.1.0/24`.

---

### Restrição de Acesso por ACLs (Tailscale Admin Console)

Por padrão, todos os dispositivos da sua conta Tailscale podem se comunicar entre si. Você pode restringir o acesso à porta RDP (3389) editando o arquivo de ACL no painel do Tailscale:

Acesse **Access Controls** no painel do Tailscale e defina regras como:

```json
"acls": [
  // Permitir que apenas o usuário admin acesse a porta 3389 (RDP) no servidor Ubuntu
  {
    "action": "accept",
    "src": ["admin@exemplo.com"],
    "dst": ["tag:server:3389"]
  }
]
```

---

## Comandos Úteis de Diagnóstico

### Ver status da conexão Tailscale:
```bash
tailscale status
```

### Consultar IPs atribuídos ao Tailscale:
```bash
tailscale ip
```

### Testar conectividade (ping via rede Tailscale):
```bash
tailscale ping <IP_OU_NOME_DO_OUTRO_DISPOSITIVO>
```

### Ver logs em tempo real do serviço:
```bash
sudo journalctl -u tailscaled -f
```

### Reiniciar o serviço Tailscale:
```bash
sudo systemctl restart tailscaled
```

---

## Solução de Problemas

### 1. Cliente não consegue conectar ao IP `100.x.y.z`
- **Causa:** O cliente ou o servidor não estão ativos no Tailscale.
- **Solução:**
  1. Verifique se o app Tailscale está rodando e conectado no cliente.
  2. No servidor, rode `tailscale status` e certifique-se de que a máquina consta como online.
  3. Teste a conexão via `tailscale ping 100.x.y.z`.

### 2. Conexão recusada na porta 3389
- **Causa:** O serviço `xrdp` não está ouvindo na interface ou o UFW está bloqueando.
- **Solução:**
  1. Verifique o XRDP: `sudo systemctl status xrdp`
  2. Verifique se a porta responde localmente: `ss -tlnp | grep 3389`
  3. Verifique as regras do UFW: `sudo ufw status`

### 3. Conexão lenta ou caindo (Relay DERP)
- **Causa:** Se uma conexão direta P2P entre o cliente e o servidor não puder ser estabelecida por causa de NAT estrito/firewall corporativo, o Tailscale usa servidores de Relay (DERP).
- **Solução:**
  1. Execute `tailscale status` para verificar se a conexão aparece como `direct` ou `relay`.
  2. Se estiver em `relay`, verifique se portas UDP de saída (porta 41641/udp) estão liberadas na rede física.

---

## Boas Práticas de Segurança

1. **Evite expor a porta 3389 publicamente:** Mantenha a porta 3389 bloqueada na interface de rede pública (`eth0` / `wlan0`) e permita apenas pela interface `tailscale0`.
2. **Ative 2FA/MFA no Provedor de Identidade:** Como o login no Tailscale usa sua conta Google/Microsoft/GitHub, proteja essa conta com autenticação de dois fatores.
3. **Ative a Expiração de Chave (Key Expiry):** Mantenha a expiração ativada para garantir re-autenticação periódica de dispositivos.

---

## Referências

- [Documentação Oficial do Tailscale](https://tailscale.com/kb)
- [Como conectar ao RDP via Tailscale](https://tailscale.com/kb/1095/remote-desktop)
- [Manual de Instalação do XRDP com TLS](manual-xrdp-tls-ubuntu.md)
