# Velocity Remote — Setup Guide

The parts:
1. **Remote server** (on Vultr). It connects technician and customer PCs, including through home routers.
2. **Velocity platform** (already live on staging). It handles linking, tickets, approvals and history.
3. **Two Windows apps**, built on GitHub:
   - `VelocityRemoteSupport-Setup.exe` for customers
   - `VelocityRemoteTechnician-Setup.exe` for staff

---

## Part 1: Vultr server (about 15 minutes)

### 1. Create the server
In the Vultr dashboard: **Deploy +** → **Deploy New Server**.
- **Type:** Cloud Compute, Shared CPU, Regular. The smallest plan is enough for remote support; check the current monthly price on the page.
- **Location:** the city closest to you and your customers.
- **Image:** Ubuntu 24.04 LTS x64.
- **SSH Keys:** optional. Without one, Vultr shows a root password on the server's page.
- **Hostname / label:** for example `velocity-remote`.
- Leave **Firewall Group** empty. The install script opens the ports on the server itself.
- Click **Deploy Now**. When the status says Running, copy the **IP Address** from the server's page.

### 2. Install the RustDesk server
In PowerShell on your PC:
```powershell
ssh root@YOUR_SERVER_IP
```
Type `yes` the first time, then paste the root password from the Vultr page (it won't show as you type).

On the server:
```bash
curl -fsSL https://raw.githubusercontent.com/velocityBuilds/velocity-support-client/velocity/velocity/install-rustdesk-server.sh | bash
```
When it finishes, it prints **VELOCITY_SERVER** and **VELOCITY_KEY**. Send both to Claude, or put them in GitHub yourself (Part 2).

> Back up `/opt/rustdesk-server/data/id_ed25519` and `id_ed25519.pub`. If you lose them, both apps have to be rebuilt and reinstalled.

**If you add a Vultr Firewall Group later**, allow these from anywhere:

| Protocol | Port |
|---|---|
| TCP | 22 (SSH) |
| TCP | 21114-21119 |
| UDP | 21116 |

**Recommended:** point a domain name at the IP (for example `remote.yourdomain.com`, an A record). On Cloudflare, set it to **DNS only (grey cloud)**, because the Cloudflare proxy can't carry remote-desktop traffic. Then use the domain as VELOCITY_SERVER, so a new server or IP never means a rebuild.

**Keep it updated:** log in once a month and run `apt update && apt upgrade -y`, then `cd /opt/rustdesk-server && docker compose pull && docker compose up -d`.

---

## Part 2: Build the apps
1. Open https://github.com/velocityBuilds/velocity-support-client/settings/variables/actions
2. Set:
   - **VELOCITY_SERVER**: your server IP or domain
   - **VELOCITY_KEY**: the long key
   - **VELOCITY_API**: the Velocity platform address (already set to staging)
3. Go to **Actions → Build Velocity Remote (Windows) → Run workflow**. It takes about an hour.
4. Download both installers from the finished run's **Artifacts**.

For a permanent download link, push a tag (`git tag v1.0 && git push fork v1.0`). That creates a GitHub Release with both installers attached.

**Your logo:** save a square PNG as `branding/icon-source.png`, run `python branding/make_icon.py rustdesk-src`, then commit and push.

---

## Part 3: Day-to-day use
**Linking a customer PC (once):**
1. In the admin site, open the customer's computer page and click **Make link code**.
2. The customer installs `VelocityRemoteSupport-Setup.exe` and types the code.

**Getting help:**
- The customer clicks **Request Support**, which creates a ticket.

**Connecting:**
1. Open **Velocity Remote Technician** on your PC and sign in with your staff account.
2. In the admin site, click **Connect** on the ticket or the computer and give a reason.
3. The customer sees your name, the ticket and the reason, and clicks **Accept**.
4. The remote window opens by itself in the technician app.
5. The customer can disconnect at any time. Every new session needs a new Accept.

---

## Notes
- **Windows warning:** an unsigned installer shows "Windows protected your PC" (More info → Run anyway). A code-signing certificate removes it, and is required before any automatic updates.
- **No unattended access:** passwords and connecting without the customer's Accept are switched off on purpose.
- **Open-source license (AGPL-3.0):** the fork is public, which satisfies the license. The small "Powered by RustDesk" line is kept on purpose.
