# Installing Pet-o-Base on Proxmox

This guide sets up Pet-o-Base in its own small LXC container. It takes about
ten minutes. The steps use the Proxmox web UI wherever possible. A
command-line version is at the end.

Contents:

1. [Download the Debian template](#1-download-the-debian-template)
2. [Create the container](#2-create-the-container)
3. [Install Pet-o-Base](#3-install-cat-o-base)
4. [Open it](#4-open-it)
5. [Optional: a nice address via a reverse proxy](#5-optional-a-nice-address-via-a-reverse-proxy)
6. [Updating](#updating)
7. [Backups](#backups)
8. [Troubleshooting](#troubleshooting)

---

## 1. Download the Debian template

You only need to do this once per Proxmox host.

1. In the left tree, click your node, then the **local** storage.
2. Open **CT Templates** and click **Templates**.
3. Search for `debian-13-standard` (or `debian-12-standard`), select it and
   click **Download**.

## 2. Create the container

Click **Create CT** at the top right and fill in each tab:

| Tab | Setting |
|---|---|
| **General** | CT ID: any free number. Hostname: `cat-o-base`. Set a root password. **Paste your SSH public key** in the box (see the tip below). Leave *Unprivileged container* and *Nesting* ticked. |
| **Template** | Storage `local`, template `debian-13-standard…` |
| **Disks** | Your container storage (e.g. `local-lvm`), **4 GB** |
| **CPU** | **1** core |
| **Memory** | **512** MB, swap **256** MB |
| **Network** | Pick your LAN bridge (e.g. `vmbr0` or `vmbr1`). IPv4: **DHCP**, or **Static** with an address like `192.168.1.67/24` **and** a **Gateway** (your router, e.g. `192.168.1.1`). |
| **DNS** | Leave the defaults |
| **Confirm** | Tick **Start after created**, then click **Finish** |

Then select the new container, go to **Options**, and set **Start at boot**
to *Yes*.

> **Don't skip the Gateway.** With a static IP and no gateway, the container
> can reach your LAN but not the internet, and the install fails with
> *"Network is unreachable"*.

> **Tip: your SSH public key.** On a Mac or Linux machine, run
> `cat ~/.ssh/id_ed25519.pub` (or `id_rsa.pub`) and copy the single line it
> prints. If you have no key yet, create one with `ssh-keygen -t ed25519`.
> Debian containers don't allow root logins with a password over SSH, so the
> key is how you'll connect.

## 3. Install Pet-o-Base

Open the container's console: select the container, click the arrow next to
**Console** and choose **xterm.js** (it lets you paste). Log in as `root`.
Then run:

```bash
apt-get update && apt-get install -y git
git clone https://github.com/dhomak/cat-o-base.git
cd cat-o-base
./install.sh
```

> If the repository is private, `git clone` asks you to log in. The easiest
> alternative is to download the code as a zip from GitHub (**Code →
> Download ZIP**), then copy it in from your computer:
> `scp cat-o-base-main.zip root@<container-ip>:/root/`. In the container, run
> `apt-get install -y unzip && unzip cat-o-base-main.zip && cd cat-o-base-main && ./install.sh`.

The installer:

- checks that the container can reach the internet,
- installs Python,
- copies the app to `/opt/cat-o-base`,
- keeps your data in `/var/lib/cat-o-base`,
- sets up a `cat-o-base` system service that starts on boot.

When it finishes, it prints the address, for example:

```
==> Pet-o-Base is running: http://192.168.1.67:8000
```

## 4. Open it

Go to that address in any browser on your network, then:

1. Click **Add a cat**.
2. Open **Contacts** and add your vet and the nearest 24/7 emergency clinic.
   They appear on the sitter sheet.
3. Optional: subscribe to the calendar feed on the **Due** page
   (`http://<address>/calendar.ics`). Apple Calendar can subscribe from any
   device on your network. Google Calendar only works if the address is
   reachable from the internet.

## 5. Optional: a nice address via a reverse proxy

With **Nginx Proxy Manager**:

1. Go to **Hosts → Proxy Hosts → Add Proxy Host**.
2. Domain: e.g. `cats.example.com`. Scheme `http`, forward to the container's
   IP, port `8000`.
3. On the **SSL** tab, request or choose a certificate.
4. If photo uploads fail with error **413**, paste this into the
   **Advanced** tab:
   ```
   client_max_body_size 200m;
   ```
5. If it's reachable from outside your home network, add an **Access List**
   with a username and password. Pet-o-Base has no login of its own.

Caddy, Traefik and plain nginx work the same way: proxy to `http://<ip>:8000`.

## Updating

In the container:

```bash
cd ~/cat-o-base
git pull
./install.sh
```

The installer replaces the app and keeps your data.

## Backups

- **In the app:** **Backup → Full backup** downloads a zip with the database
  and all photos and documents. **Restore** on the same page loads it back
  into a fresh install.
- **Proxmox:** a normal `vzdump` backup of the container includes everything.
- **Data on your NAS (optional):** bind-mount a NAS folder at
  `/var/lib/cat-o-base`. In an unprivileged container, the `catobase` user
  appears on the host as UID `100000 + its UID`; run `id catobase` in the
  container to see it. Use NFS or a local dataset, **not** SMB/CIFS, because
  SQLite's file locking doesn't work reliably over CIFS.

## Troubleshooting

**"Network is unreachable" or "no longer has a Release file" during install**
The container has no route to the internet. In Proxmox, go to **CT → Network
→ net0** and set **Gateway (IPv4)** to your router's address. To fix it
immediately without a restart, run `ip route add default via 192.168.1.1`
(use your router's address).

**"Temporary failure resolving deb.debian.org"**
DNS isn't working. Check **CT → DNS**, or `cat /etc/resolv.conf` in the
container.

**`Permission denied (publickey,password)` when using ssh/scp**
Debian blocks root password logins over SSH. Add your public key from the
console:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'ssh-ed25519 AAAA...your key...' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

**The page doesn't load**
Run `systemctl status cat-o-base` and `journalctl -u cat-o-base -n 50` in the
container.

**Uploads fail**
See the 413 note in [section 5](#5-optional-a-nice-address-via-a-reverse-proxy).
Also check free space with `df -h`.

---

## Command-line version (Proxmox host shell)

```bash
pveam update
pveam available --section system | grep debian-13   # note the exact name
pveam download local debian-13-standard_<version>_amd64.tar.zst

pct create 124 local:vztmpl/debian-13-standard_<version>_amd64.tar.zst \
  --hostname cat-o-base --cores 1 --memory 512 --swap 256 \
  --rootfs local-lvm:4 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --unprivileged 1 --features nesting=1 --onboot 1 \
  --ssh-public-keys ~/.ssh/authorized_keys
pct start 124
pct exec 124 -- bash -c "apt-get update && apt-get install -y git && \
  git clone https://github.com/dhomak/cat-o-base.git /root/cat-o-base && \
  /root/cat-o-base/install.sh"
```

Change the CT ID, storage and bridge to match your setup. For a static IP, use
`ip=192.168.1.67/24,gw=192.168.1.1`.
