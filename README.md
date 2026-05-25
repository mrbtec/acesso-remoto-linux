# Acesso Remoto ao Desktop Ubuntu — TigerVNC e XRDP com TLS

Documentação e scripts para configurar acesso remoto gráfico seguro em servidores Ubuntu, cobrindo dois protocolos distintos: **VNC** (via TigerVNC) e **RDP** (via XRDP com TLS).

---

## Conteúdo do repositório

| Arquivo | Idioma | Descrição |
|---------|--------|-----------|
| [manual-tigervnc-ubuntu.md](manual-tigervnc-ubuntu.md) | 🇧🇷 Português | Manual completo de instalação do TigerVNC |
| [manual-tigervnc-ubuntu-en.md](manual-tigervnc-ubuntu-en.md) | 🇺🇸 English | TigerVNC installation manual |
| [manual-xrdp-tls-ubuntu.md](manual-xrdp-tls-ubuntu.md) | 🇧🇷 Português | Manual completo de instalação do XRDP com TLS |
| [manual-xrdp-tls-ubuntu-en.md](manual-xrdp-tls-ubuntu-en.md) | 🇺🇸 English | XRDP with TLS installation manual |
| [install-xrdp-server.sh](install-xrdp-server.sh) | — | Script de instalação automatizada do XRDP |

---

## Visão geral

### TigerVNC
Servidor VNC de alto desempenho. Ideal para uso em rede local com túnel SSH.

- Protocolo: **VNC** (porta 5900+)
- Segurança: **túnel SSH** (recomendado) ou certificado X509
- Compatível com clientes: TigerVNC Viewer, RealVNC, Remmina

### XRDP
Servidor de área de trabalho remota compatível com o protocolo RDP da Microsoft.

- Protocolo: **RDP** (porta 3389)
- Segurança: **TLS nativo** (TLSv1.2 / TLSv1.3), autenticação PAM
- Compatível com clientes: Windows (`mstsc.exe`), Remmina, FreeRDP

---

## Comparativo rápido

| Característica | TigerVNC | XRDP |
|----------------|----------|------|
| Protocolo | VNC | RDP |
| Criptografia nativa | ⚠️ Requer SSH tunnel | ✅ TLS obrigatório |
| Autenticação | Senha VNC | PAM (usuários do sistema) |
| Cliente Windows nativo | ❌ | ✅ (`mstsc.exe`) |
| Desempenho em WAN | ⚠️ Moderado | ✅ Bom |
| Facilidade de configuração | ✅ Simples | ✅ Simples com o script |

---

## Instalação rápida (XRDP)

Use o script automatizado para instalar e configurar o XRDP com TLS em um único comando:

```bash
sudo bash install-xrdp-server.sh
```

O script realiza automaticamente:
- Instalação do XRDP e OpenSSL
- Geração de certificado TLS autoassinado (RSA 4096)
- Configuração de TLS obrigatório (TLSv1.2/1.3) no `xrdp.ini`
- Instalação opcional de ambiente de desktop (XFCE, GNOME, KDE Plasma, LXDE)
- Configuração do `~/.xsession`
- Liberação da porta 3389 no UFW
- Integração com Fail2Ban (proteção contra força bruta)
- Habilitação e inicialização dos serviços

---

## Pré-requisitos

- Ubuntu 20.04, 22.04 ou 24.04 LTS
- Acesso com privilégios `sudo`
- Conexão com a internet

---

## Desktops suportados

| Desktop | TigerVNC | XRDP | Observação |
|---------|----------|------|------------|
| XFCE | ✅ | ✅ | **Recomendado** — leve e estável |
| KDE Plasma | ✅ | ✅ | Completo, usa `startplasma-x11` |
| GNOME | ✅ | ⚠️ | Requer forçar sessão X11 |
| LXDE | ✅ | ✅ | Muito leve |

> **GNOME + XRDP:** crie `~/.xsessionrc` com `export XDG_SESSION_TYPE=x11` para evitar que o GNOME inicie uma sessão Wayland (incompatível com XRDP).

---

## Segurança

- O script gera certificado RSA 4096 bits com validade de 3 anos
- TLS 1.0 e 1.1 são desabilitados por padrão
- O Fail2Ban bloqueia IPs após 5 tentativas falhas em 10 minutos
- Recomenda-se restringir a porta 3389 por IP no UFW em ambientes de produção:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 3389 proto tcp
```

---

## Referências

- [XRDP — Site oficial](http://xrdp.org)
- [TigerVNC — Site oficial](https://tigervnc.org)
- [Documentação Ubuntu Server](https://ubuntu.com/server/docs)
- [Fail2Ban — Documentação](https://www.fail2ban.org/wiki/index.php/Main_Page)
