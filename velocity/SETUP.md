# VelocitySupport — Setup Guide

Your two parts:
1. **Server** (free, on Oracle Cloud). It connects you and your customers.
2. **Client** (`VelocitySupport.exe`). Customers double-click it and read you their ID and password.

---

## Part 1: Oracle Cloud server (about 20 minutes)

### 1. Sign up
- Go to https://signup.cloud.oracle.com. A card is required for verification. Always Free resources are not charged.
- **Pick your home region carefully, because you can't change it later.** Choose the one closest to your customers.
- Optional: upgrade to *Pay As You Go* later. You stay free inside the limits, Oracle stops reclaiming "idle" free VMs, and Ampere capacity is easier to get.

### 2. Create the VM
Console → **Compute → Instances → Create instance**
- **Image:** Canonical Ubuntu 24.04
- **Shape:** Ampere `VM.Standard.A1.Flex`, 1 OCPU / 6 GB (Always Free).
  If you see "Out of capacity", choose `VM.Standard.E2.1.Micro` (AMD, also free). That's plenty for remote support.
- **Networking:** create a new VCN with a public subnet, and keep **Assign a public IPv4 address** on.
- **SSH keys:** click **Save private key** and keep that file safe.
- Click **Create**. Copy the **Public IP address** when the instance shows Running.

### 3. Open the ports in Oracle's firewall
Instance page → click the **Subnet** → **Security Lists** → **Default Security List** → **Add Ingress Rules**:

| Source CIDR | Protocol | Destination port |
|---|---|---|
| 0.0.0.0/0 | TCP | 21114-21119 |
| 0.0.0.0/0 | UDP | 21116 |

### 4. Install the server
In PowerShell on your PC:
```powershell
ssh -i C:\path\to\ssh-key.key ubuntu@YOUR_PUBLIC_IP
```
On the VM:
```bash
curl -fsSL https://raw.githubusercontent.com/velocityBuilds/velocity-support-client/velocity/velocity/install-rustdesk-server.sh | sudo bash
```
When it finishes, it prints **VELOCITY_SERVER** and **VELOCITY_KEY**. Copy both.

> Back up `/opt/rustdesk-server/data/id_ed25519` and `id_ed25519.pub`. If you lose them, every client has to be rebuilt.

**Recommended:** point a domain at the IP (for example `remote.yourdomain.com`, an A record). On Cloudflare, set it to **DNS only (grey cloud)**. Then use the domain as VELOCITY_SERVER, so a changed IP never means a rebuild.

---

## Part 2: Build the branded client
1. Open https://github.com/velocityBuilds/velocity-support-client/settings/variables/actions
2. Set **VELOCITY_SERVER** (your IP or domain) and **VELOCITY_KEY** (the long key).
3. Go to **Actions → Build VelocitySupport (Windows) → Run workflow**. It takes about 60 minutes.
4. Download `VelocitySupport.exe` from the finished run's **Artifacts**.
   For a permanent download link, push a tag instead:
   `git tag v1.0 && git push fork v1.0`. That creates a GitHub Release with the exe attached.

**Your logo:** save a square PNG as `branding/icon-source.png`, run
`python branding/make_icon.py rustdesk-src`, then commit and push.

---

## Part 3: How you connect (technician side)
Install the normal RustDesk app on **your** PC from https://rustdesk.com, then open
**Settings → Network → ID/Relay server**:
- ID server: your VELOCITY_SERVER
- Relay server: your VELOCITY_SERVER
- Key: your VELOCITY_KEY

Customer flow: they run `VelocitySupport.exe` and read you the ID and password. You type the ID, connect, and enter the password.

---

## Notes
- **SmartScreen warning:** an unsigned exe shows "Windows protected your PC" (More info → Run anyway). To remove it, buy a code-signing certificate (Certum open-source cert is about $30/yr; Azure Trusted Signing is about $10/mo) and add signing to the workflow.
- **Open-source license (AGPL-3.0):** your fork is public, which satisfies the license. The small "Powered by RustDesk" line is kept on purpose.
- **Unattended access** (connecting without the customer there): on the customer's PC, install VelocitySupport (it offers to install), then set a permanent password during a session.
