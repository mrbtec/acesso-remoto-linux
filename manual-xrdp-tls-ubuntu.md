# Manual de Instalação do Servidor XRDP com TLS no Ubuntu

## Índice

1. [Pré-requisitos](#pré-requisitos)
2. [Instalação do XRDP](#instalação-do-xrdp)
3. [Instalação de um ambiente de desktop](#instalação-de-um-ambiente-de-desktop)
4. [Configuração do TLS](#configuração-do-tls)
   - [Opção A: Certificado autoassinado](#opção-a-certificado-autoassinado)
   - [Opção B: Certificado Let's Encrypt](#opção-b-certificado-lets-encrypt)
5. [Configuração do xrdp.ini](#configuração-do-xrdpini)
6. [Configurando o ambiente de desktop para o XRDP](#configurando-o-ambiente-de-desktop-para-o-xrdp)
7. [Configurando o firewall](#configurando-o-firewall)
8. [Habilitando e iniciando o serviço](#habilitando-e-iniciando-o-serviço)
9. [Conectando ao servidor XRDP](#conectando-ao-servidor-xrdp)
10. [Comandos úteis](#comandos-úteis)
11. [Solução de problemas](#solução-de-problemas)

---

## Pré-requisitos

- Ubuntu 20.04, 22.04 ou 24.04 (LTS recomendado)
- Acesso com privilégios `sudo`
- OpenSSL instalado (`openssl version` para verificar)
- Um ambiente de desktop instalado (XFCE, GNOME, etc.)
- Porta **3389/tcp** acessível no firewall (padrão RDP)

---

## Instalação do XRDP

Atualize os repositórios e instale o XRDP:

```bash
sudo apt update
sudo apt install -y xrdp
```

Verifique a versão instalada:

```bash
xrdp --version
```

O XRDP instala automaticamente os seguintes arquivos de configuração em `/etc/xrdp/`:

| Arquivo | Descrição |
|---------|-----------|
| `xrdp.ini` | Configuração principal do servidor |
| `sesman.ini` | Configuração do gerenciador de sessões |
| `cert.pem` | Certificado TLS padrão (autoassinado) |
| `key.pem` | Chave privada TLS padrão |
| `startwm.sh` | Script de inicialização do gerenciador de janelas |

---

## Instalação de um ambiente de desktop

Se o servidor não possuir interface gráfica, instale um ambiente leve:

### XFCE (recomendado para servidores):

```bash
sudo apt install -y xfce4 xfce4-goodies
```

### GNOME (padrão do Ubuntu Desktop):

```bash
sudo apt install -y ubuntu-desktop
```

### LXDE (muito leve):

```bash
sudo apt install -y lxde
```

---

## Configuração do TLS

O XRDP suporta criptografia TLS nativamente. Por padrão, já cria um certificado autoassinado em `/etc/xrdp/cert.pem`. Esta seção descreve como usar seus próprios certificados para maior segurança.

### Opção A: Certificado autoassinado

Gere um certificado autoassinado com validade de 3 anos:

```bash
sudo openssl req -x509 -newkey rsa:4096 \
  -keyout /etc/xrdp/key.pem \
  -out /etc/xrdp/cert.pem \
  -days 1095 -nodes \
  -subj "/C=BR/ST=SaoPaulo/L=SaoPaulo/O=MinhaOrg/CN=$(hostname -f)"
```

Ajuste as permissões:

```bash
sudo chmod 640 /etc/xrdp/key.pem
sudo chmod 644 /etc/xrdp/cert.pem
sudo chown root:xrdp /etc/xrdp/key.pem /etc/xrdp/cert.pem
```

> **Atenção:** Certificados autoassinados geram um aviso de segurança no cliente RDP. Aceite o certificado para continuar. Use a **Opção B** para evitar esse aviso em produção.

---

### Opção B: Certificado Let's Encrypt

Requer um domínio público apontando para o servidor e a porta 80 aberta temporariamente.

#### 1. Instalar o Certbot:

```bash
sudo apt install -y certbot
```

#### 2. Obter o certificado (substitua `seudominio.com` pelo domínio real):

```bash
sudo certbot certonly --standalone -d seudominio.com
```

Os certificados ficam em `/etc/letsencrypt/live/seudominio.com/`.

#### 3. Copiar os certificados para o diretório do XRDP:

```bash
sudo cp /etc/letsencrypt/live/seudominio.com/fullchain.pem /etc/xrdp/cert.pem
sudo cp /etc/letsencrypt/live/seudominio.com/privkey.pem /etc/xrdp/key.pem
sudo chmod 640 /etc/xrdp/key.pem
sudo chmod 644 /etc/xrdp/cert.pem
sudo chown root:xrdp /etc/xrdp/key.pem /etc/xrdp/cert.pem
```

#### 4. Renovação automática com hook de cópia:

Crie o script de renovação:

```bash
sudo nano /etc/letsencrypt/renewal-hooks/deploy/xrdp-cert.sh
```

Conteúdo:

```bash
#!/bin/bash
DOMAIN="seudominio.com"
cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/xrdp/cert.pem
cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /etc/xrdp/key.pem
chmod 640 /etc/xrdp/key.pem
chmod 644 /etc/xrdp/cert.pem
chown root:xrdp /etc/xrdp/key.pem /etc/xrdp/cert.pem
systemctl restart xrdp
```

Torne o script executável:

```bash
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/xrdp-cert.sh
```

---

## Configuração do xrdp.ini

Edite o arquivo de configuração principal:

```bash
sudo nano /etc/xrdp/xrdp.ini
```

Localize e ajuste as seguintes diretivas na seção `[Globals]`:

```ini
[Globals]
; Porta de escuta (padrão RDP)
port=3389

; Camada de segurança:
;   negotiate  - negocia automaticamente entre RDP e TLS (recomendado)
;   tls        - força TLS obrigatório
;   rdp        - apenas RDP clássico (sem criptografia — não recomendado)
security_layer=tls

; Nível de criptografia:
;   low    - criptografia de 56 bits
;   medium - criptografia de 128 bits
;   high   - criptografia máxima (recomendado)
;   fips   - modo FIPS
crypt_level=high

; Caminho do certificado TLS
certificate=/etc/xrdp/cert.pem

; Caminho da chave privada TLS
key_file=/etc/xrdp/key.pem

; Versões de TLS permitidas (desabilita TLS 1.0 e 1.1 por segurança)
ssl_protocols=TLSv1.2, TLSv1.3

; Suítes de cifra TLS (opcional — configuração forte)
tls_ciphers=HIGH:!aNULL:!MD5:!RC4
```

> **Nota:** Com `security_layer=tls`, clientes mais antigos do Windows (antes do Windows 7) podem não conseguir conectar. Use `security_layer=negotiate` para maior compatibilidade.

Salve e feche o arquivo (`Ctrl+X`, `Y`, `Enter`).

---

## Configurando o ambiente de desktop para o XRDP

O XRDP utiliza o arquivo `~/.xsession` ou `~/.Xclients` para determinar qual desktop iniciar para o usuário.

### Para XFCE:

```bash
echo "xfce4-session" > ~/.xsession
chmod +x ~/.xsession
```

### Para GNOME:

```bash
echo "gnome-session" > ~/.xsession
chmod +x ~/.xsession
```

### Configuração global (para todos os usuários)

Edite o script de inicialização do XRDP:

```bash
sudo nano /etc/xrdp/startwm.sh
```

Localize as últimas linhas e substitua por:

```bash
# Para XFCE
exec startxfce4

# OU para GNOME
# exec gnome-session
```

> **Atenção:** Comente as linhas originais antes de adicionar as novas.

---

## Configurando o firewall

### Com UFW:

```bash
# Liberar a porta RDP padrão
sudo ufw allow 3389/tcp

# Verificar as regras
sudo ufw status
```

### Restringir acesso por IP (mais seguro):

```bash
# Permitir apenas de um IP específico
sudo ufw allow from 192.168.1.0/24 to any port 3389 proto tcp

# Verificar
sudo ufw status numbered
```

---

## Habilitando e iniciando o serviço

```bash
# Habilitar para iniciar com o sistema
sudo systemctl enable xrdp

# Iniciar o serviço
sudo systemctl start xrdp

# Verificar o status
sudo systemctl status xrdp
```

Adicionar o usuário `xrdp` ao grupo `ssl-cert` (necessário para leitura do certificado):

```bash
sudo adduser xrdp ssl-cert
sudo systemctl restart xrdp
```

Verificar se o servidor está ouvindo na porta 3389:

```bash
ss -tlnp | grep 3389
```

---

## Conectando ao servidor XRDP

### Windows

1. Abra o **Conexão de Área de Trabalho Remota** (`mstsc.exe`)
2. Informe o IP do servidor e clique em **Conectar**
3. Aceite o certificado (se autoassinado)
4. Faça login com usuário e senha do Ubuntu

### Linux (Remmina)

```bash
sudo apt install remmina remmina-plugin-rdp
```

1. Abra o Remmina
2. Crie uma nova conexão RDP
3. Informe IP, usuário e senha
4. Em **Avançado**, selecione **TLS** como protocolo de segurança

### Linux (FreeRDP via terminal)

```bash
sudo apt install freerdp2-x11

# Conectar com TLS
xfreerdp /v:IP_DO_SERVIDOR:3389 /u:SEU_USUARIO /p:SUA_SENHA /tls-seclevel:1 /cert:ignore
```

---

## Comandos úteis

```bash
# Iniciar o serviço xrdp
sudo systemctl start xrdp

# Parar o serviço xrdp
sudo systemctl stop xrdp

# Reiniciar o serviço xrdp
sudo systemctl restart xrdp

# Ver status detalhado
sudo systemctl status xrdp

# Ver logs em tempo real
sudo journalctl -u xrdp -f

# Ver logs de sessão
sudo journalctl -u xrdp-sesman -f

# Verificar certificado TLS em uso
openssl x509 -in /etc/xrdp/cert.pem -noout -text | grep -E "Subject:|Issuer:|Not After"

# Testar a conexão TLS manualmente
openssl s_client -connect localhost:3389 -starttls rdp 2>/dev/null | openssl x509 -noout -text | grep -E "Subject:|Not After"

# Verificar porta em uso
ss -tlnp | grep 3389
```

---

## Solução de problemas

### Tela preta após login

O ambiente de desktop não foi configurado corretamente. Verifique:

```bash
# Verificar se o arquivo ~/.xsession existe e está correto
cat ~/.xsession

# Verificar logs da sessão
cat /var/log/xrdp-sesman.log

# Alternativa: configurar globalmente
sudo nano /etc/xrdp/startwm.sh
```

### Erro de certificado TLS

```bash
# Verificar validade do certificado
openssl x509 -in /etc/xrdp/cert.pem -noout -dates

# Regenerar certificado autoassinado
sudo openssl req -x509 -newkey rsa:4096 \
  -keyout /etc/xrdp/key.pem \
  -out /etc/xrdp/cert.pem \
  -days 1095 -nodes \
  -subj "/CN=$(hostname -f)"
sudo chown root:xrdp /etc/xrdp/key.pem /etc/xrdp/cert.pem
sudo chmod 640 /etc/xrdp/key.pem
sudo systemctl restart xrdp
```

### Conexão recusada

```bash
# Verificar se o serviço está rodando
sudo systemctl status xrdp

# Verificar se a porta está aberta
ss -tlnp | grep 3389

# Verificar o firewall
sudo ufw status

# Ver logs de erro
sudo journalctl -u xrdp --no-pager | tail -30
```

### Erro "Authentication failed"

- Certifique-se de que o usuário existe no sistema Ubuntu
- Verifique se a senha está correta
- O usuário **não deve** estar logado graficamente no console local simultaneamente

```bash
# Verificar se o usuário existe
id SEU_USUARIO

# Verificar status do sesman (gerenciador de autenticação)
sudo systemctl status xrdp-sesman
sudo journalctl -u xrdp-sesman --no-pager | tail -20
```

### Desempenho lento

- Use o ambiente XFCE em vez de GNOME
- Reduza a profundidade de cor na conexão RDP (16 bits)
- No cliente Windows, desabilite efeitos visuais em **Experiência**
- Verifique a largura de banda disponível

### Múltiplas sessões para o mesmo usuário

Por padrão, o XRDP cria uma nova sessão a cada conexão. Para reconectar à sessão existente, configure o XRDP para usar sessões persistentes via `~/.xsession` e habilite no `sesman.ini`:

```bash
sudo nano /etc/xrdp/sesman.ini
```

Certifique-se de que a opção `KillDisconnected` está como `false`:

```ini
KillDisconnected=false
DisconnectedTimeLimit=0
```

---

## Referências

- [Site oficial do XRDP](http://xrdp.org)
- [Repositório GitHub do XRDP](https://github.com/neutrinolabs/xrdp)
- [Wiki do XRDP](https://github.com/neutrinolabs/xrdp/wiki)
- [Documentação Ubuntu Server](https://ubuntu.com/server/docs)
