# TigerVNC Server Installation Guide on Ubuntu

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installing TigerVNC](#installing-tigervnc)
3. [Initial Configuration](#initial-configuration)
4. [Configuring the Desktop Environment](#configuring-the-desktop-environment)
5. [Starting the VNC Server](#starting-the-vnc-server)
6. [Configuring as a systemd Service](#configuring-as-a-systemd-service)
7. [Configuring the Firewall](#configuring-the-firewall)
8. [Connection via SSH Tunnel (recommended)](#connection-via-ssh-tunnel-recommended)
9. [Connecting to the VNC Server](#connecting-to-the-vnc-server)
10. [Useful Commands](#useful-commands)
11. [Troubleshooting](#troubleshooting)

---

## Prerequisites

- Ubuntu 20.04, 22.04, or 24.04 (LTS recommended)
- An account with `sudo` privileges
- Internet connection
- A desktop environment installed (GNOME, XFCE, KDE, etc.)

### Install a desktop environment (if needed)

If your Ubuntu server has no graphical interface, install a lightweight environment such as **XFCE**:

```bash
sudo apt update
sudo apt install -y xfce4 xfce4-goodies
```

Or **GNOME** (heavier):

```bash
sudo apt update
sudo apt install -y ubuntu-desktop
```

---

## Installing TigerVNC

Update packages and install TigerVNC:

```bash
sudo apt update
sudo apt install -y tigervnc-standalone-server tigervnc-common
```

Verify the installed version:

```bash
vncserver --version
```

---

## Initial Configuration

### 1. Set the VNC password

Run the command below with the user who will use VNC (**do not use sudo**):

```bash
vncpasswd
```

You will be prompted to:
- Enter a password (minimum 6 characters, maximum 8)
- Confirm the password
- Optionally configure a view-only password

Passwords are stored in `~/.vnc/passwd`.

---

## Configuring the Desktop Environment

Modern TigerVNC uses the file `~/.vnc/tigervnc.conf` to define the desktop session and other server options.

### Recommended method: tigervnc.conf file

Create the configuration file:

```bash
mkdir -p ~/.vnc
nano ~/.vnc/tigervnc.conf
```

Choose your desired environment and add to the file:

```perl
# Desktop environment (must match a file in /usr/share/xsessions)
$session = "xfce";      # for XFCE
# $session = "gnome";   # for GNOME
# $session = "lxde";    # for LXDE

# Resolution and color depth
$geometry = "1920x1080";
$depth = 24;

# Accept only local connections (use with SSH tunnel)
$localhost = "yes";
```

To list available sessions on the system:

```bash
ls /usr/share/xsessions/
```

### Alternative method: xstartup file

If you prefer manual control, create the `~/.vnc/xstartup` file:

```bash
nano ~/.vnc/xstartup
```

#### For XFCE (recommended for servers):

```bash
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
```

#### For GNOME:

```bash
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XKL_XMODMAP_DISABLE=1
dbus-launch --exit-with-session gnome-session
```

Make the file executable:

```bash
chmod +x ~/.vnc/xstartup
```

---

## Starting the VNC Server

### Start on the default port (display :1 → port 5901)

```bash
vncserver :1
```

### Start with custom options

```bash
vncserver :1 -geometry 1920x1080 -depth 24 -localhost no
```

| Option | Description |
|--------|-------------|
| `:1` | Display number (port = 5900 + number) |
| `-geometry` | Screen resolution (width x height) |
| `-depth` | Color depth (24-bit recommended) |
| `-localhost no` | Allows external connections (no SSH tunnel) |
| `-localhost yes` | Accepts only local connections (default, use with SSH) |

### Stop the VNC server

```bash
vncserver -kill :1
```

### List active sessions

```bash
vncserver -list
```

---

## Configuring as a systemd Service

TigerVNC already includes the unit file `/lib/systemd/system/tigervncserver@.service`. There is no need to create a new service file.

### 1. Map the display to the user

Edit `/etc/tigervnc/vncserver.users` to associate a display number with a system user:

```bash
sudo nano /etc/tigervnc/vncserver.users
```

Add a line in the format `:<display>=<username>`. Replace `YOUR_USER` with the actual username:

```
:1=YOUR_USER
```

Save and close the file (`Ctrl+X`, `Y`, `Enter`).

### 2. (Optional) Configure global server options

To set default options for all users, edit:

```bash
sudo nano /etc/tigervnc/vncserver-config-defaults
```

Example content:

```perl
$geometry = "1920x1080";
$depth = 24;
$localhost = "yes";
```

### 3. Enable and start the service

```bash
sudo systemctl enable tigervncserver@:1.service
sudo systemctl start tigervncserver@:1.service
```

### 4. Verify the service status

```bash
sudo systemctl status tigervncserver@:1.service
```

---

## Configuring the Firewall

### Using UFW

If you are using an SSH tunnel (recommended), **it is not necessary** to open the VNC port in the firewall.

If you need to allow direct access (less secure):

```bash
# Allow port for display :1
sudo ufw allow 5901/tcp

# Allow port for display :2
sudo ufw allow 5902/tcp

# Check rules
sudo ufw status
```

---

## Connection via SSH Tunnel (recommended)

The SSH tunnel encrypts VNC traffic, making the connection secure.

### On the client (your local machine), run:

```bash
ssh -L 5901:localhost:5901 -N -f user@SERVER_IP
```

| Parameter | Description |
|-----------|-------------|
| `-L 5901:localhost:5901` | Forwards local port 5901 to port 5901 on the server |
| `-N` | Does not execute remote commands |
| `-f` | Runs in the background |
| `user@SERVER_IP` | Username and IP of the Ubuntu server |

After establishing the tunnel, connect your VNC client to `localhost:5901`.

---

## Connecting to the VNC Server

### Recommended VNC clients

| Client | Platform | Download |
|--------|----------|----------|
| **TigerVNC Viewer** | Windows, Linux, macOS | https://tigervnc.org |
| **RealVNC Viewer** | Windows, Linux, macOS, Mobile | https://www.realvnc.com |
| **Remmina** | Linux | `sudo apt install remmina` |

### Installing TigerVNC Viewer on Linux client

```bash
sudo apt install tigervnc-viewer
```

### Connecting

```bash
# Without SSH tunnel (direct connection)
vncviewer SERVER_IP:5901

# With active SSH tunnel
vncviewer localhost:5901
```

---

## Useful Commands

```bash
# Start VNC server on display :1
vncserver :1

# Start with custom resolution
vncserver :1 -geometry 1280x720 -depth 24

# Stop VNC server on display :1
vncserver -kill :1

# List all active VNC sessions
vncserver -list

# Change the VNC password
vncpasswd

# Check VNC logs
cat ~/.vnc/*.log

# Start systemd service (display :1)
sudo systemctl start tigervncserver@:1.service

# Restart the systemd service
sudo systemctl restart tigervncserver@:1.service

# Stop the systemd service
sudo systemctl stop tigervncserver@:1.service

# View service logs
sudo journalctl -u tigervncserver@:1.service -f
```

---

## Troubleshooting

### Gray or black screen upon connecting

The `~/.vnc/xstartup` file may be incorrect. Check that:
- The file has execute permission (`chmod +x ~/.vnc/xstartup`)
- The desktop environment specified is installed
- The command in the file is correct for your desktop

```bash
# Check if XFCE is installed
which startxfce4

# Check error logs
cat ~/.vnc/*.log
```

### Error "A VNC server is already running"

```bash
# List and kill all sessions
vncserver -kill :1
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
```

### Connection refused

1. Check if the server is running: `vncserver -list`
2. Check if the port is open: `ss -tlnp | grep 590`
3. Check the firewall: `sudo ufw status`
4. Confirm the server IP: `ip addr show`

### systemd service fails to start

```bash
# View detailed error
sudo journalctl -u tigervncserver@:1.service --no-pager

# Check that the user mapping is correct
cat /etc/tigervnc/vncserver.users

# Check that the VNC password has been set for the user
ls ~/.vnc/passwd
```

### Slow performance

- Use the XFCE environment instead of GNOME
- Reduce resolution: `-geometry 1280x720`
- Use a LAN connection instead of WAN
- Enable compression in the VNC client

---

## References

- [TigerVNC official website](https://tigervnc.org)
- [TigerVNC GitHub repository](https://github.com/TigerVNC/tigervnc)
- [Ubuntu Server documentation](https://ubuntu.com/server/docs)
