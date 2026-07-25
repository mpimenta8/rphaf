# VM provisioning — from bare box to running relay

Provider-agnostic steps to stand up the rphaf/Buzz relay on a fresh **Ubuntu 24.04 LTS** VM,
harden it, install Docker, open the firewall, deploy, and wire nightly offsite backups.

Assumes the recommendation from `PLANNING.md`: a ~8 GB VM (e.g. Hetzner CPX31), a domain, and that
you've settled your **owner key** (see `PLANNING.md` Part 1). Commands are copy-paste; run them in
order. `sudo`-prefixed commands need root.

---

## 0. Before the VM: DNS

Create a **DNS A record** for your relay host pointing at the VM's public IP:

```
chat.yourdomain.com.   A   <VM_PUBLIC_IP>
```

Do this first — DNS takes a few minutes to propagate, and Caddy needs it resolving before it can get
a TLS certificate.

## 1. Create the VM

- Image: **Ubuntu 24.04 LTS**.
- Size: 8 GB RAM / 2+ vCPU / 80 GB disk (Hetzner CPX31 or equivalent).
- Add your **SSH public key** during creation (password logins are a liability).
- If the provider has its own **cloud firewall / security group**, allow inbound **22, 80, 443**
  there too — the VM's `ufw` (below) is not enough on its own.

SSH in:

```bash
ssh root@<VM_PUBLIC_IP>
```

## 2. Baseline hardening

Create a non-root user with sudo, and move SSH to it (you'll stop logging in as root):

```bash
adduser --gecos "" buzz            # set a password when prompted
usermod -aG sudo buzz
rsync --archive --chown=buzz:buzz ~/.ssh /home/buzz   # copy your authorized_keys over
```

Open a **second** SSH session as the new user to confirm it works *before* locking root out:

```bash
ssh buzz@<VM_PUBLIC_IP>            # from your laptop, in a new terminal
```

Once that works, disable root & password SSH:

```bash
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

Enable automatic security patches:

```bash
sudo apt-get update && sudo apt-get install -y unattended-upgrades
sudo dpkg-reconfigure -f noninteractive unattended-upgrades
```

## 3. Firewall (ufw)

```bash
sudo apt-get install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH          # 22
sudo ufw allow 80/tcp           # Caddy: Let's Encrypt HTTP-01 challenge
sudo ufw allow 443/tcp          # Caddy: HTTPS / wss
sudo ufw enable
sudo ufw status verbose
```

> Don't expose 3000/5432/6379/9000 publicly — with `BUZZ_COMPOSE_TLS=true`, only Caddy (80/443) is
> published; Postgres/Redis/MinIO stay on the internal Docker network.

## 4. Install Docker Engine + Compose plugin

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"      # run docker without sudo
newgrp docker                        # apply the group now (or log out/in)
docker compose version               # expect v2.24.4+
```

## 5. Deploy

```bash
sudo mkdir -p /opt && sudo chown "$USER" /opt
git clone git@github.com:mpimenta8/rphaf.git /opt/rphaf   # or https://… if no deploy key
cd /opt/rphaf/deploy/compose

./gen-env.sh --domain chat.yourdomain.com --owner <your-64-hex-pubkey>
grep -q CHANGE_ME .env && { echo "fill remaining CHANGE_ME first"; grep -n CHANGE_ME .env; }

BUZZ_COMPOSE_TLS=true ./run.sh start
./run.sh status
curl -fsS https://chat.yourdomain.com/_liveness && echo " <- relay is up"
```

Add yourself + friends (see `PLANNING.md` Part 1 for the owner-key rule):

```bash
./run.sh add-member <your-npub> --role admin
./run.sh add-member <friend-npub>          # sleep 1 between multiple adds
```

Friends point the desktop app at `wss://chat.yourdomain.com`.

## 6. Nightly offsite backups (day one)

`backup.sh` dumps Postgres + tars the MinIO/git volumes + snapshots `.env`, rotates locally, and
ships offsite via [rclone](https://rclone.org). A local-only backup dies with the VM — do the offsite
part.

**a. Install + configure rclone** for any object store (Backblaze B2 and S3 are cheap; B2 shown):

```bash
sudo -v ; curl https://rclone.org/install.sh | sudo bash
rclone config      # create a remote, e.g. name it "offsite" (B2/S3/etc.)
```

**b. Point the backup at it** via `backup.env` (keeps secrets out of the crontab):

```bash
cd /opt/rphaf/deploy/compose
cat > backup.env <<'EOF'
BACKUP_RCLONE_REMOTE=offsite:my-bucket/buzz
KEEP_DAYS=14
EOF
chmod 600 backup.env      # backup.env is gitignored (see root .gitignore) — won't be committed
```

**c. Test it once by hand**, then schedule it:

```bash
sudo mkdir -p /var/backups/buzz && sudo chown "$USER" /var/backups/buzz
./backup.sh                       # watch it dump, archive, ship offsite
crontab -e
# add (nightly 03:15 UTC):
15 3 * * * cd /opt/rphaf/deploy/compose && ./backup.sh >> /var/log/buzz-backup.log 2>&1
```

Make the log writable: `sudo touch /var/log/buzz-backup.log && sudo chown "$USER" /var/log/buzz-backup.log`.

## 7. Restore drill (a backup you haven't restored isn't a backup)

On a scratch box or a fresh stack, verify you can actually recover:

```bash
# Postgres:
gunzip -c postgres.sql.gz | docker compose --env-file .env -f compose.yml \
  exec -T postgres sh -c 'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'

# A volume (e.g. media): stop the stack, then repopulate the named volume:
docker run --rm -v buzz-prod_buzz-minio-data:/data -v "$PWD:/backup" alpine \
  sh -c 'cd /data && tar xzf /backup/minio-data.tar.gz'
```

Do this once now so you trust it later.

## 8. Ongoing ops

```bash
cd /opt/rphaf/deploy/compose
./run.sh logs            # follow relay logs
./run.sh upgrade         # pull newer image + restart (then prints backup reminders)
./run.sh backup-hint     # the full backup checklist
```

Keep the code current with upstream on your dev machine (`git fetch upstream && git merge
upstream/main`, then push), and `git pull && ./run.sh upgrade` on the VM. See repo-root `MEMORY.md`
("Syncing upstream", "Self-hosting the relay") for the whole picture.
