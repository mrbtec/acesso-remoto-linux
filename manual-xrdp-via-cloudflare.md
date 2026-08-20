# Manual de Acesso Remoto ao XRDP via Cloudflare Zero Trust

Este manual descreve como disponibilizar o acesso remoto ao servidor **XRDP (Ubuntu)** com segurança através da internet utilizando o **Cloudflare Zero Trust (Cloudflare Tunnel)**.

Com esta arquitetura, **não é necessário abrir portas no roteador (Port Forwarding)** nem expor o endereço IP público da sua rede, prevenindo ataques de força bruta e varreduras de portas.

---

## Índice

1. [Visão geral e Arquitetura](#visão-geral-e-arquitetura)
2. [Pré-requisitos](#pré-requisitos)
3. [Instalação do cloudflared no Servidor Ubuntu](#instalação-do-cloudflared-no-servidor-ubuntu)
4. [Configuração do Cloudflare Tunnel](#configuração-do-cloudflare-tunnel)
   - [Opção A: Configuração via Linha de Comando (CLI)](#opção-a-configuração-via-linha-de-comando-cli)
   - [Opção B: Configuração via Painel Cloudflare Zero Trust (Managed Tunnel)](#opção-b-configuração-via-painel-cloudflare-zero-trust-managed-tunnel)
5. [Configuração das Políticas no Cloudflare Access](#configuração-das-políticas-no-cloudflare-access)
   - [Habilitando o RDP via Navegador (Browser-based RDP)](#habilitando-o-rdp-via-navegador-browser-based-rdp)
6. [Formas de Conexão pelos Clientes Remotos](#formas-de-conexão-pelos-clientes-remotos)
   - [Método 1: Acesso Direto via Navegador Web (Sem instalar nada)](#método-1-acesso-direto-via-navegador-web-sem-instalar-nada)
   - [Método 2: Acesso via Cliente RDP Nativo (cloudflared client)](#método-2-acesso-via-cliente-rdp-nativo-cloudflared-client)
   - [Método 3: Acesso via Rede Privada com Cloudflare WARP](#método-3-acesso-via-rede-privada-com-cloudflare-warp)
7. [Automação via API da Cloudflare](#automação-via-api-da-cloudflare)
8. [Comandos Úteis de Diagnóstico](#comandos-úteis-de-diagnóstico)
9. [Solução de Problemas](#solução-de-problemas)
10. [Boas Práticas de Segurança](#boas-práticas-de-segurança)

---

## Visão geral e Arquitetura

O **Cloudflare Tunnel** (através do daemon `cloudflared`) estabelece uma conexão de saída (*outbound*) criptografada via TLS/QUIC entre o servidor Ubuntu local e a rede global da Cloudflare.

### Fluxo de Conexão:

```
[ Cliente Remoto ]
       │
       ▼
 [ Cloudflare Access ] ── (Autenticação SSO / OTP / MFA)
       │
       ▼
 [ Cloudflare Edge ]
       │  (Túnel seguro de saída / QUIC / TLS)
       ▼
 [ Servidor Ubuntu ] ── (cloudflared) ──► [ XRDP local: 127.0.0.1:3389 ]
```

### Principais Benefícios:
- **Zero Inbound Ports:** Nenhuma porta de entrada aberta no firewall/roteador.
- **Proteção DDoS e WAF:** Proteção contra varreduras de portas e ataques de força bruta na porta 3389.
- **Autenticação Centralizada (MFA/SSO):** Exige autenticação (Google, Azure AD, E-mail OTP, etc.) antes de permitir o tráfego até o servidor.
- **RDP via Navegador:** Permite acessar a interface gráfica do Ubuntu diretamente no navegador sem instalar clientes RDP.

---

## Pré-requisitos

1. **Servidor Ubuntu com XRDP funcionando localmente:**
   - Verifique a instalação do XRDP seguindo o [manual-xrdp-tls-ubuntu.md](manual-xrdp-tls-ubuntu.md) ou usando o script `install-xrdp-server.sh`.
   - O serviço XRDP deve estar ativo e ouvindo na porta 3389 (`ss -tlnp | grep 3389`).

2. **Conta no Cloudflare (Plano Gratuito é suficiente):**
   - Um domínio próprio adicionado e ativo na Cloudflare (ex: `seudominio.com`).
   - Acesso ativado ao painel **Cloudflare Zero Trust** (Cloudflare One).

3. **Permissão de Administrador no Ubuntu (`sudo`).**

---

## Instalação do cloudflared no Servidor Ubuntu

Execute os comandos no terminal do servidor Ubuntu para instalar o agente oficial da Cloudflare (`cloudflared`).

### Opção 1: Via Repositório APT da Cloudflare (Recomendado)

#### 1. Criar o diretório de chaves e adicionar a chave GPG:
```bash
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
```

#### 2. Adicionar o repositório APT:

- **Canal Estável (Stable):**
```bash
# Para Ubuntu 24.04 (noble):
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared noble main' | sudo tee /etc/apt/sources.list.d/cloudflared.list

# Para compatibilidade genérica com qualquer versão Ubuntu/Debian (recomendado se 'noble' falhar):
# echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
```

- **Canal de Testes/Desenvolvimento (Nightly):**
```bash
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://next.pkg.cloudflare.com/cloudflared noble main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
```

#### 3. Instalar o `cloudflared`:
```bash
sudo apt-get update && sudo apt-get install -y cloudflared
```

---

### Opção 2: Download Direto do Pacote `.deb` (Caso o APT retorne erro de Release)

Se o seu sistema indicar que o repositório não possui ficheiro/arquivo Release, faça o download direto do pacote compilado:

```bash
# Para arquitetura 64-bit (x86_64 / amd64):
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb
rm cloudflared.deb
```

> **Para servidores ARM64 (ex: Raspberry Pi):**
> ```bash
> curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
> sudo dpkg -i cloudflared.deb
> rm cloudflared.deb
> ```

---

Verifique se o `cloudflared` foi instalado com sucesso:

```bash
cloudflared --version
```

---

## Configuração do Cloudflare Tunnel

Você pode configurar o túnel de duas formas: por **Linha de Comando (CLI)** ou pelo **Painel Zero Trust (Managed Tunnel)**.

---

### Opção A: Configuração via Linha de Comando (CLI)

#### 1. Autenticar o `cloudflared` na sua conta Cloudflare:

```bash
cloudflared tunnel login
```

O comando exibirá uma URL no terminal. Abra o link no navegador, faça login na sua conta Cloudflare e autorize o domínio desejado. Após a autorização, um arquivo de certificado `cert.pem` será salvo em `~/.cloudflared/cert.pem`.

#### 2. Criar o Túnel:

```bash
cloudflared tunnel create xrdp-tunnel
```

Será gerado um **UUID de Túnel** (ex: `a1b2c3d4-e5f6-7890-abcd-1234567890ab`) e o arquivo de credenciais correspondente em `~/.cloudflared/<UUID>.json`.

#### 3. Criar o arquivo de configuração `/etc/cloudflared/config.yml`:

```bash
sudo mkdir -p /etc/cloudflared
sudo nano /etc/cloudflared/config.yml
```

Insira o conteúdo abaixo (substitua `<UUID_DO_TUNEL>` pelo ID gerado e `rdp.seudominio.com` pelo seu subdomínio):

```yaml
tunnel: <UUID_DO_TUNEL>
credentials-file: /etc/cloudflared/<UUID_DO_TUNEL>.json

ingress:
  - hostname: rdp.seudominio.com
    service: rdp://localhost:3389
  - service: http_status:404
```

Mova o arquivo de credenciais para o diretório `/etc/cloudflared/`:

```bash
sudo cp ~/.cloudflared/<UUID_DO_TUNEL>.json /etc/cloudflared/
```

#### 4. Criar o registro DNS na Cloudflare:

```bash
cloudflared tunnel route dns xrdp-tunnel rdp.seudominio.com
```

Este comando cria automaticamente um registro `CNAME` na Cloudflare apontando `rdp.seudominio.com` para `<UUID_DO_TUNEL>.cfargotunnel.com`.

#### 5. Instalar e Iniciar o Serviço no Ubuntu:

```bash
# Instalar o serviço systemd
sudo cloudflared service install

# Iniciar o serviço
sudo systemctl start cloudflared

# Habilitar inicialização automática no boot
sudo systemctl enable cloudflared

# Verificar status do serviço
sudo systemctl status cloudflared
```

---

### Opção B: Configuração via Painel Cloudflare Zero Trust (Managed Tunnel)

Esta é a opção mais simples se preferir gerenciar tudo pela interface gráfica web.

1. Acesse o [Painel Cloudflare Zero Trust](https://one.dash.cloudflare.com/).
2. No menu lateral, navegue até **Networks** > **Tunnels**.
3. Clique em **Add a tunnel**.
4. Selecione a opção **Cloudflared** e clique em **Next**.
5. Dê um nome para o túnel (ex: `ubuntu-xrdp-server`) e clique em **Save tunnel**.
6. Selecione o ambiente **Debian 64-bit** / **Ubuntu** e **copie o comando de instalação** fornecido na tela (o comando contém o token de autenticação exclusivo do túnel):
   ```bash
   sudo cloudflared service install <TOKEN_FORNECIDO_PELO_PAINEL>
   ```
7. Execute esse comando no terminal do seu servidor Ubuntu.
8. No painel, clique em **Next**.
9. Na aba **Public Hostnames**, adicione uma regra:
   - **Subdomain:** `rdp`
   - **Domain:** `seudominio.com`
   - **Type:** `RDP`
   - **URL:** `localhost:3389` ou `127.0.0.1:3389`
10. Clique em **Save hostname**.

---

## Configuração das Políticas no Cloudflare Access

Para proteger a conexão e evitar que qualquer pessoa na internet tente acessar a tela de login do XRDP, configure uma aplicação no **Cloudflare Access**.

1. No painel **Cloudflare Zero Trust**, acesse **Access** > **Applications**.
2. Clique em **Add an application** e selecione **Self-hosted**.
3. Preencha os dados básicos:
   - **Application name:** `Acesso XRDP Ubuntu`
   - **Session Duration:** Selecione o tempo de sessão desejado (ex: `24 hours`).
   - **Application domain:** Subdomínio `rdp` e domínio `seudominio.com`.
4. Clique em **Next**.
5. Configure as **Políticas de Acesso (Access Policies)**:
   - **Policy name:** `Usuarios Autorizados`
   - **Action:** `Allow`
   - **Assign to people:** Adicione uma regra **Include**:
     - *Selector:* `Emails` ou `Email domains`
     - *Value:* Digite seu e-mail pessoal ou o domínio da sua empresa.
6. Clique em **Next**.

---

### Habilitando o RDP via Navegador (Browser-based RDP)

Para permitir acesso à área de trabalho gráfica diretamente pelo navegador web sem precisar de programa cliente:

1. Na edição da aplicação criada em **Access** > **Applications**, clique na aba **Additional settings** ou **Advanced settings**.
2. Localize a seção **Browser rendering** / **Browser-based RDP**.
3. Alterne a opção para **Enabled** (Ativado).
4. Clique em **Save application**.

---

## Formas de Conexão pelos Clientes Remotos

Existem 3 formas de conectar ao XRDP remotamente usando o Cloudflare Zero Trust:

---

### Método 1: Acesso Direto via Navegador Web (Sem instalar nada)

Se você ativou a opção **Browser-based RDP**:

1. No computador ou dispositivo remoto, abra qualquer navegador web modern.
2. Acesse a URL: `https://rdp.seudominio.com`
3. O portal de autenticação do **Cloudflare Access** será exibido. Informe seu e-mail e digite o código de validação enviado por e-mail (ou faça login via SSO/Google).
4. Após autenticado, a sessão **RDP HTML5** abrirá diretamente dentro da janela do navegador.
5. Digite o **Usuário** e **Senha** do seu sistema Ubuntu para iniciar a área de trabalho gráfica.

---

### Método 2: Acesso via Cliente RDP Nativo (cloudflared client)

Se preferir utilizar clientes RDP nativos como **Microsoft Remote Desktop (`mstsc.exe`)**, **Remmina** ou **FreeRDP**:

#### 1. Instalar o `cloudflared` na máquina cliente (Windows, Linux ou macOS):
- **Windows:** Baixe o executável `.exe` ou instale via winget: `winget install Cloudflare.cloudflared`
- **Linux:** Instale via pacote `.deb` / `.rpm` ou repositório.
- **macOS:** Instale via Homebrew: `brew install cloudflared`

#### 2. Iniciar o proxy local na máquina cliente:

Execute o comando abaixo no terminal ou prompt de comando da máquina cliente:

```bash
cloudflared access rdp --hostname rdp.seudominio.com --url localhost:3389
```

> **Dica:** Se a porta 3389 já estiver em uso na sua máquina cliente local, altere para outra porta como `33389`:
> `cloudflared access rdp --hostname rdp.seudominio.com --url localhost:33389`

#### 3. Conectar usando seu cliente RDP preferido:

- **No Windows (`mstsc.exe`):**
  - Conectar em: `127.0.0.1:3389` (ou `127.0.0.1:33389`).
- **No Linux (Remmina / FreeRDP):**
  - Servidor: `127.0.0.1:3389`
  - Protocolo: `RDP`
- **Autenticação:** Quando o cliente tentar conectar, uma aba no navegador abrirá automaticamente para você fazer o login no Cloudflare Access (caso não esteja logado).

---

### Método 3: Acesso via Rede Privada com Cloudflare WARP

Se você utiliza a arquitetura de **Private Network Routing** do Cloudflare Zero Trust:

#### 1. Roteamento no Servidor Ubuntu:
No servidor Ubuntu, roteie o bloco IP da sua rede local (ex: `192.168.1.0/24`):
```bash
cloudflared tunnel route ip add 192.168.1.0/24 xrdp-tunnel
```

#### 2. Instalação do Cliente Cloudflare WARP no Ubuntu/Debian:
Nos computadores ou dispositivos dos usuários:

```bash
# 1. Adicionar a chave GPG do Cloudflare WARP
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

# 2. Adicionar o repositório APT do Cloudflare WARP
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list

# 3. Atualizar a lista de pacotes e instalar o cliente
sudo apt-get update && sudo apt-get install -y cloudflare-warp
```

#### 3. Conexão:
1. Conecte o cliente **Cloudflare WARP** à sua organização do Cloudflare Zero Trust (`warp-cli register` ou via interface gráfica do WARP).
2. Conecte diretamente ao IP privado do servidor Ubuntu (ex: `192.168.1.50:3389`) utilizando qualquer cliente RDP padrão, como se estivesse na mesma rede local.

---

## Automação via API da Cloudflare

Você pode criar, visualizar e gerenciar seus Tunnels e Aplicações Access através da API REST da Cloudflare.

### 1. Obter o ID da Conta (Account ID):
Obtenha o `account_id` no canto inferior direito do painel da Cloudflare ou listando as zonas.

### 2. Listar Tunnels existentes via API:

```bash
curl -X GET "https://api.cloudflare.com/client/v4/accounts/{account_id}/cfd_tunnel" \
     -H "Authorization: Bearer <SEU_API_TOKEN>" \
     -H "Content-Type: application/json"
```

### 3. Criar uma Aplicação Access via API:

```bash
curl -X POST "https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps" \
     -H "Authorization: Bearer <SEU_API_TOKEN>" \
     -H "Content-Type: application/json" \
     --data '{
       "name": "Acesso XRDP Ubuntu API",
       "domain": "rdp.seudominio.com",
       "type": "self_hosted",
       "session_duration": "24h",
       "options": {
         "allow_authenticator_webauthn": true
       }
     }'
```

### 4. Criar Política Access via API:

```bash
curl -X POST "https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps/{app_id}/policies" \
     -H "Authorization: Bearer <SEU_API_TOKEN>" \
     -H "Content-Type: application/json" \
     --data '{
       "name": "Permitir Admin",
       "decision": "allow",
       "include": [
         {
           "email": {
             "email": "admin@seudominio.com"
           }
         }
       ]
     }'
```

---

## Comandos Úteis de Diagnóstico

### Ver status do serviço `cloudflared`:
```bash
sudo systemctl status cloudflared
```

### Acompanhar logs em tempo real:
```bash
sudo journalctl -u cloudflared -f
```

### Listar túneis ativos e conexões:
```bash
cloudflared tunnel list
cloudflared tunnel info <UUID_OU_NOME_DO_TUNEL>
```

### Validar se o backend XRDP responde localmente:
```bash
nc -zvw3 127.0.0.1 3389
```

### Atualizar o `cloudflared` para a versão mais recente:
```bash
sudo cloudflared update
```

---

## Solução de Problemas

### 1. Erro "Unable to reach backend" ou tela preta no Browser RDP
- **Causa:** O `cloudflared` não consegue se conectar à porta 3389 local do servidor ou o XRDP não está rodando.
- **Solução:**
  1. Verifique se o XRDP está ativo: `sudo systemctl status xrdp`
  2. Verifique se a porta 3389 responde localmente: `ss -tlnp | grep 3389`
  3. No `config.yml` ou no Painel Cloudflare, certifique-se de que a URL de destino é `rdp://localhost:3389` ou `rdp://127.0.0.1:3389`.

### 2. Conexão recusada ao usar `cloudflared access rdp` no cliente
- **Causa:** A porta local definida no cliente (ex: `3389`) já está em uso por outro serviço.
- **Solução:** Mude a porta no comando cliente:
  ```bash
  cloudflared access rdp --hostname rdp.seudominio.com --url localhost:33389
  ```
  Conecte seu cliente RDP em `127.0.0.1:33389`.

### 3. Falha de Autenticação no XRDP (Authentication Failed)
- **Causa:** Usuário ou senha do Ubuntu incorretos, ou o usuário já possui uma sessão aberta na máquina física (console local).
- **Solução:**
  1. Deslogue o usuário da sessão física local do Ubuntu.
  2. Verifique se o usuário pertence aos grupos corretos (`sudo adduser <usuario> xrdp`).

### 4. WebSocket error no Acesso via Navegador
- **Causa:** A opção **Browser-based RDP** não foi ativada nas configurações da aplicação no Cloudflare Access.
- **Solução:** Acesse o painel **Cloudflare Zero Trust** > **Access** > **Applications** > edite a aplicação do XRDP > **Advanced Settings** > ative **Browser-based RDP**.

### 5. Erro no APT: "O repositório '... Release' não tem um ficheiro Release"
- **Causa:** O comando `$(lsb_release -cs)` retornou o codinome de uma versão do Ubuntu/Debian que não tem diretório dedicado no servidor APT da Cloudflare.
- **Solução:**
  1. Remova o repositório incorreto: `sudo rm /etc/apt/sources.list.d/cloudflared.list`
  2. Use o repositório genérico (`any main`):
     ```bash
     echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
     sudo apt update && sudo apt install cloudflared
     ```
  3. Ou instale via pacote `.deb` direto:
     ```bash
     curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
     sudo dpkg -i cloudflared.deb
     ```

---

## Boas Práticas de Segurança

1. **Remova o Port Forwarding do Roteador:**
   - Garanta que a porta **3389** **NÃO** esteja aberta no seu roteador para a internet. O tráfego deve trafegar exclusivamente pelo túnel da Cloudflare.

2. **Ative Autenticação de Dois Fatores (MFA/2FA):**
   - Configure o Cloudflare Access para utilizar login com 2FA ou integração SSO com Google/Microsoft Azure AD.

3. **Restrinja os Usuários Autorizados:**
   - Utilize a política do Cloudflare Access para permitir exclusivamente os endereços de e-mail ou domínios necessários.

4. **Mantenha os Serviços Atualizados:**
   - Atualize regularmente o Ubuntu (`sudo apt update && sudo apt upgrade`) e o pacote `cloudflared` (`sudo cloudflared update`).

---

## Referências

- [Documentação Oficial do Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/)
- [Cloudflare RDP Use Cases & Browser RDP](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/use-cases/rdp/)
- [Cloudflare Zero Trust API Documentation](https://developers.cloudflare.com/api/resources/zero_trust/)
- [Manual de Instalação do XRDP com TLS](manual-xrdp-tls-ubuntu.md)
