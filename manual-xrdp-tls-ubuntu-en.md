# XRDP Server with TLS Installation Guide on Ubuntu

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installing XRDP](#installing-xrdp)
3. [Installing a Desktop Environment](#installing-a-desktop-environment)
4. [TLS Configuration](#tls-configuration)
   - [Option A: Self-signed Certificate](#option-a-self-signed-certificate)
   - [Option B: Let's Encrypt Certificate](#option-b-lets-encrypt-certificate)
5. [xrdp.ini Configuration](#xrdpini-configuration)
6. [Configuring the Desktop Environment for XRDP](#configuring-the-desktop-environment-for-xrdp)
7. [Configuring the Firewall](#configuring-the-firewall)
8. [Enabling and Starting the Service](#enabling-and-starting-the-service)
9. [Connecting to the XRDP Server](#connecting-to-the-xrdp-server)
10. [Useful Commands](#useful-commands)
11. [Troubleshooting](#troubleshooting)

---

## Prerequisites

- Ubuntu 20.04, 22.04, or 24.04 (LTS recommended)
- Access with `sudo` privileges
- OpenSSL installed (`openssl version` to verify)
- A desktop environment installed (XFCE, GNOME, etc.)
- Port **3389/tcp** accessible through the firewall (default RDP port)

---

## Installing XRDP

Update the repositories and install XRDP:

```bash
sudo apt update
sudo apt install -y xrdp
```

Verify the installed version:

```bash
xrdp --version
```

XRDP automatically installs the following configuration files under `/etc/xrdp/`:

| File | Description |
|------|-------------|
| `xrdp.ini` | Main server configuration |
| `sesman.ini` | Session manager configuration |
| `cert.pem` | Default TLS certificate (self-signed) |
| `key.pem` | Default TLS private key |
| `startwm.sh` | Window manager startup script |

---

## Installing a Desktop Environment

If the server has no graphical interface, install a lightweight environment:

### XFCE (recommended for servers):

```bash
sudo apt install -y xfce4 xfce4-goodies
```

### GNOME (Ubuntu Desktop default):

```bash
sudo apt install -y ubuntu-desktop
```

### KDE Plasma (full-featured, compatible with XRDP):

```bash
sudo apt install -y kde-plasma-desktop
```

### LXDE (very lightweight):

```bash
sudo apt install -y lxde
```

---

## TLS Configuration

XRDP natively supports TLS encryption. By default, it already creates a self-signed certificate at `/etc/xrdp/cert.pem`. This section describes how to use your own certificates for enhanced security.

### Option A: Self-signed Certificate

Generate a self-signed certificate valid for 3 years:

```bash
sudo openssl req -x509 -newkey rsa:4096 \
  -keyout /etc/xrdp/key.pem \
  -out /etc/xrdp/cert.pem \
  -days 1095 -nodes \
  -subj "/C=US/ST=YourState/L=YourCity/O=YourOrg/CN=$(hostname -f)"
```

Set the correct permissions:

```bash
sudo chmod 640 /etc/xrdp/key.pem
sudo chmod 644 /etc/xrdp/cert.pem
sudo chown root:xrdp /etc/xrdp/key.pem /etc/xrdp/cert.pem
```

> **Note:** Self-signed certificates trigger a security warning in the RDP client. Accept the certificate to proceed. Use **Option B** to avoid this warning in production environments.

---

### Option B: Let's Encrypt Certificate

Requires a public domain pointing to the server and port 80 temporarily open.

#### 1. Install Certbot:

```bash
sudo apt install -y certbot
```

#### 2. Obtain the certificate (replace `yourdomain.com` with your real domain):

```bash
sudo certbot certonly --standalone -d yourdomain.com
```

Certificates are stored in `/etc/letsencrypt/live/yourdomain.com/`.

#### 3. Copy the certificates to the XRDP directory:

```bash
sudo cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem /etc/xrdp/cert.pem
sudo cp /etc/letsencrypt/live/yourdomain.com/privkey.pem /etc/xrdp/key.pem
sudo chmod 640 /etc/xrdp/key.pem
sudo chmod 644 /etc/xrdp/cert.pem
sudo chown root:xrdp /etc/xrdp/key.pem /etc/xrdp/cert.pem
```

#### 4. Automatic renewal with a copy hook:

Create the renewal script:

```bash
sudo nano /etc/letsencrypt/renewal-hooks/deploy/xrdp-cert.sh
```

Content:

```bash
#!/bin/bash
DOMAIN="yourdomain.com"
cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/xrdp/cert.pem
cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /etc/xrdp/key.pem
chmod 640 /etc/xrdp/key.pem
chmod 644 /etc/xrdp/cert.pem
chown root:xrdp /etc/xrdp/key.pem /etc/xrdp/cert.pem
systemctl restart xrdp
```

Make the script executable:

```bash
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/xrdp-cert.sh
```

---

## xrdp.ini Configuration

Edit the main configuration file:

```bash
sudo nano /etc/xrdp/xrdp.ini
```

Locate and adjust the following directives in the `[Globals]` section:

```ini
[Globals]
; Listening port (default RDP)
port=3389

; Security layer:
;   negotiate  - automatically negotiates between RDP and TLS (recommended)
;   tls        - forces mandatory TLS
;   rdp        - classic RDP only (no encryption — not recommended)
security_layer=tls

; Encryption level:
;   low    - 56-bit encryption
;   medium - 128-bit encryption
;   high   - maximum encryption (recommended)
;   fips   - FIPS mode
crypt_level=high

; TLS certificate path
certificate=/etc/xrdp/cert.pem

; TLS private key path
key_file=/etc/xrdp/key.pem

; Allowed TLS versions (disables TLS 1.0 and 1.1 for security)
ssl_protocols=TLSv1.2, TLSv1.3

; TLS cipher suites (optional — strong configuration)
tls_ciphers=HIGH:!aNULL:!MD5:!RC4
```

> **Note:** With `security_layer=tls`, older Windows clients (before Windows 7) may not be able to connect. Use `security_layer=negotiate` for broader compatibility.

Save and close the file (`Ctrl+X`, `Y`, `Enter`).

---

## Configuring the Desktop Environment for XRDP

XRDP uses the `~/.xsession` or `~/.Xclients` file to determine which desktop to launch for the user.

### For XFCE:

```bash
echo "xfce4-session" > ~/.xsession
chmod +x ~/.xsession
```

### For KDE Plasma:

```bash
echo "startplasma-x11" > ~/.xsession
chmod +x ~/.xsession
```

### For GNOME:

```bash
echo "gnome-session" > ~/.xsession
chmod +x ~/.xsession
```

> **Important — GNOME + XRDP:** GNOME on Ubuntu 22.04+ starts a Wayland session by default, which XRDP does not support. Create `~/.xsessionrc` to force X11:
>
> ```bash
> cat > ~/.xsessionrc << 'EOF'
> export GNOME_SHELL_SESSION_MODE=ubuntu
> export XDG_SESSION_TYPE=x11
> export XDG_CURRENT_DESKTOP=ubuntu:GNOME
> EOF
> ```

### Global configuration (for all users)

Edit the XRDP startup script:

```bash
sudo nano /etc/xrdp/startwm.sh
```

Locate the last lines and replace with:

```bash
# For XFCE
exec startxfce4

# OR for KDE Plasma
# exec startplasma-x11

# OR for GNOME
# exec gnome-session
```

> **Note:** Comment out the original lines before adding new ones.

---

## Configuring the Firewall

### With UFW:

```bash
# Allow the default RDP port
sudo ufw allow 3389/tcp

# Check the rules
sudo ufw status
```

### Restrict access by IP (more secure):

```bash
# Allow only from a specific IP or subnet
sudo ufw allow from 192.168.1.0/24 to any port 3389 proto tcp

# Check
sudo ufw status numbered
```

---

## Enabling and Starting the Service

```bash
# Enable to start with the system
sudo systemctl enable xrdp

# Start the service
sudo systemctl start xrdp

# Check the status
sudo systemctl status xrdp
```

Add the `xrdp` user to the `ssl-cert` group (required to read the certificate):

```bash
sudo adduser xrdp ssl-cert
sudo systemctl restart xrdp
```

Verify the server is listening on port 3389:

```bash
ss -tlnp | grep 3389
```

---

## Connecting to the XRDP Server

### Windows

1. Open **Remote Desktop Connection** (`mstsc.exe`)
2. Enter the server IP and click **Connect**
3. Accept the certificate (if self-signed)
4. Log in with your Ubuntu username and password

### Linux (Remmina)

```bash
sudo apt install remmina remmina-plugin-rdp
```

1. Open Remmina
2. Create a new RDP connection
3. Enter the IP, username, and password
4. Under **Advanced**, select **TLS** as the security protocol

### Linux (FreeRDP via terminal)

```bash
sudo apt install freerdp2-x11

# Connect with TLS
xfreerdp /v:SERVER_IP:3389 /u:YOUR_USER /p:YOUR_PASSWORD /tls-seclevel:1 /cert:ignore
```

---

## Useful Commands

```bash
# Start the xrdp service
sudo systemctl start xrdp

# Stop the xrdp service
sudo systemctl stop xrdp

# Restart the xrdp service
sudo systemctl restart xrdp

# View detailed status
sudo systemctl status xrdp

# View logs in real time
sudo journalctl -u xrdp -f

# View session logs
sudo journalctl -u xrdp-sesman -f

# Check the TLS certificate in use
openssl x509 -in /etc/xrdp/cert.pem -noout -text | grep -E "Subject:|Issuer:|Not After"

# Manually test the TLS connection
openssl s_client -connect localhost:3389 -starttls rdp 2>/dev/null | openssl x509 -noout -text | grep -E "Subject:|Not After"

# Check port in use
ss -tlnp | grep 3389
```

---

## Troubleshooting

### Black screen after login

The desktop environment was not configured correctly. Check:

```bash
# Verify that ~/.xsession exists and is correct
cat ~/.xsession

# Check session logs
cat /var/log/xrdp-sesman.log

# Alternative: configure globally
sudo nano /etc/xrdp/startwm.sh
```

### Session closes immediately after login (GNOME)

GNOME is trying to start a Wayland session, which XRDP does not support. Fix:

```bash
cat > ~/.xsessionrc << 'EOF'
export GNOME_SHELL_SESSION_MODE=ubuntu
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=ubuntu:GNOME
EOF
sudo systemctl restart xrdp
```

### TLS certificate error

```bash
# Check certificate validity
openssl x509 -in /etc/xrdp/cert.pem -noout -dates

# Regenerate self-signed certificate
sudo openssl req -x509 -newkey rsa:4096 \
  -keyout /etc/xrdp/key.pem \
  -out /etc/xrdp/cert.pem \
  -days 1095 -nodes \
  -subj "/CN=$(hostname -f)"
sudo chown root:xrdp /etc/xrdp/key.pem /etc/xrdp/cert.pem
sudo chmod 640 /etc/xrdp/key.pem
sudo systemctl restart xrdp
```

### Connection refused

```bash
# Check if the service is running
sudo systemctl status xrdp

# Check if the port is open
ss -tlnp | grep 3389

# Check the firewall
sudo ufw status

# View error logs
sudo journalctl -u xrdp --no-pager | tail -30
```

### Authentication failed

- Make sure the user exists on the Ubuntu system
- Verify the password is correct
- The user **must not** be logged in graphically on the local console at the same time

```bash
# Check if the user exists
id YOUR_USER

# Check sesman status (authentication manager)
sudo systemctl status xrdp-sesman
sudo journalctl -u xrdp-sesman --no-pager | tail -20
```

### Slow performance

- Use the XFCE environment instead of GNOME
- Reduce the color depth in the RDP connection (16-bit)
- On the Windows client, disable visual effects under **Experience**
- Check available bandwidth

### Multiple sessions for the same user

By default, XRDP creates a new session for each connection. To reconnect to an existing session, configure XRDP for persistent sessions via `~/.xsession` and enable it in `sesman.ini`:

```bash
sudo nano /etc/xrdp/sesman.ini
```

Make sure the `KillDisconnected` option is set to `false`:

```ini
KillDisconnected=false
DisconnectedTimeLimit=0
```

---

## References

- [XRDP official website](http://xrdp.org)
- [XRDP GitHub repository](https://github.com/neutrinolabs/xrdp)
- [XRDP Wiki](https://github.com/neutrinolabs/xrdp/wiki)
- [Ubuntu Server documentation](https://ubuntu.com/server/docs)
