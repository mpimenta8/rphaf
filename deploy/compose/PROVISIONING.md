# VM provisioning — from bare box to running relay

Provider-agnostic steps to stand up the rphaf/Buzz relay on a fresh **Ubuntu 24.04 LTS** VM,
harden it, install Docker, open the firewall, deploy, and wire nightly offsite backups.

Assumes the recommendation from `PLANNING.md`: a **DigitalOcean 4 GB droplet in a US region**, the
`rphaf.io` domain, and that you've settled your **owner key** (see `PLANNING.md` Part 1). Commands
are copy-paste; run them in order. `sudo`-prefixed commands need root.

> **One exception to "in order":** §0 (DNS) needs the VM's IP from §1, and depends on the domain
> owner. Read §0 first, create the VM (§1), then fire off the DNS request and keep working through
> §2–§4 while it propagates.

---

## 0. DNS — coordinate with the domain owner

`rphaf.io` is registered by a friend, so this is a **hand-off, not a solo step**. Budget for a
round-trip: it's the one part of the process that depends on someone else being awake.

### Sequencing (read before you ping anyone)
The record needs the VM's public IP, which doesn't exist until §1 — but DNS is also the slowest link
in the chain, and Caddy can't issue a TLS cert until the name resolves. So:

1. **Create the VM first** (§1), grab its IP.
2. **Then** send the request below.
3. Continue with §2–§4 (hardening, firewall, Docker) **while DNS propagates** — none of it needs DNS.
4. Only §5 (deploy) actually blocks on the record being live.

### Pick the hostname
`jean.rphaf.io` is the assumed name throughout this guide. If you choose differently, substitute it
everywhere below — it also lands in `.env` via `gen-env.sh --domain`, and changing it later means
re-issuing certs and re-pointing every client.

### What to ask for
Two options — pick one and be explicit about which, since they're very different asks:

| Option | What the owner does | Best when |
|---|---|---|
| **A. Single A record** (recommended) | Adds one record for `jean.rphaf.io`. Nothing else changes. | You need one hostname and don't expect churn. |
| **B. NS delegation** | Delegates all of `jean.rphaf.io` (or a `relay.` subtree) to a nameserver you control. | You want to self-serve future records without asking again. |

Start with **A**. It's a two-minute change on their side and doesn't hand you control of anything
they'd have to trust you with. Move to B only if you find yourself asking repeatedly.

### Message to send

`rphaf.io` is hosted on **AWS Route 53** (verified via `dig NS rphaf.io` — `ns-*.awsdns-*`), so
there's no CDN/proxy layer to worry about and the record is a plain A record:

> Can you add a DNS record for `rphaf.io` in Route 53?
>
> In the `rphaf.io` hosted zone → **Create record**:
>
> ```
> Record name:  jean          (full name: jean.rphaf.io)
> Record type:  A
> Value:        <VM_PUBLIC_IP>
> TTL:          300
> Routing:      Simple routing
> ```
>
> Low TTL (300s) on purpose so we can fix mistakes fast; we can raise it once it's stable.

### If the domain ever moves behind a proxy (Cloudflare et al.)
Not currently applicable on Route 53, but if `rphaf.io` is ever fronted by Cloudflare, the record
**must be "DNS only" (grey cloud), not proxied (orange cloud)** — a proxied record breaks this stack
two ways:

- Caddy's Let's Encrypt **HTTP-01 challenge** fails, because the proxy terminates :80/:443 itself —
  so the relay never gets a certificate.
- Default proxy timeouts sever **long-lived WebSocket** connections, which is the relay's entire
  transport (`wss://`).

### Hold off on the AAAA record
The droplet has a public IPv6 address, but **add IPv4 only to start.** Let's Encrypt *prefers* IPv6
when an AAAA record exists, so if the host's IPv6 routing or firewall isn't right, certificate
issuance fails while everything looks healthy over IPv4 — a confusing way to lose an afternoon. Add
AAAA later, once the relay is up and IPv6 reachability is confirmed.

### Verify before you deploy
From your laptop, once they confirm:

```bash
dig +short jean.rphaf.io            # must print the VM's IP, nothing else
dig +short jean.rphaf.io @1.1.1.1   # check a public resolver too, not just your ISP cache
```

If the first returns nothing, it hasn't propagated yet — wait, don't retry the deploy. If it returns
a *different* IP, the record points somewhere else (an old host, or a Cloudflare proxy IP if the grey
cloud didn't get set). Resolve that before §5; Caddy will burn Let's Encrypt rate limits retrying
against a name that doesn't point at it.

## 1. Create the VM

- Image: **Ubuntu 24.04 LTS**.
- Plan: **Basic → Premium Intel/AMD, 2 vCPU / 4 GB / 120 GB NVMe** (~$32/mo). Beware DO's `$24` row
  in the *Premium* list — it's only **2 GB**, which `PLANNING.md` calls too tight.
- Add your **SSH public key** during creation (password logins are a liability). If DO's setup flow
  tells you to run `ssh-keygen` and the file already exists, **answer `n`** — overwriting destroys
  the key registered with GitHub. Paste the existing `~/.ssh/id_ed25519.pub` instead.
- Backups **off** (we ship offsite backups in §6), monitoring **on**, IPv6 **on**.
- Skip DO's cloud firewall — §3 configures `ufw`. If you add one anyway, it must allow inbound
  **22, 80, 443**, or it silently overrides everything `ufw` permits and locks you out.

SSH in:

```bash
ssh root@<VM_PUBLIC_IP>
```

> **Now send the DNS request from §0** with this IP, before continuing. Propagation runs in the
> background while you do §2–§4.

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

## 3b. Add swap (do this on a 4 GB box)

Cloud VMs ship with **no swap**. Without it, a momentary memory spike gets a process OOM-killed —
usually Postgres, the one you least want killed. 2 GB of swap turns that into a brief slowdown.

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab   # survive reboot
sudo sysctl -w vm.swappiness=10                              # prefer RAM; swap is a safety net
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf
free -h                                                      # confirm Swap: 2.0Gi
```

> Skip only if you provisioned 8 GB **and** are staying on "just chat". Swap is cheap insurance
> either way.

## 4. Install Docker Engine + Compose plugin

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"      # run docker without sudo
newgrp docker                        # apply the group now (or log out/in)
docker compose version               # expect v2.24.4+
```

## 5. Deploy

**Clone over HTTPS, not SSH.** `mpimenta8/rphaf` is public and the VM only ever *reads* (`git pull`
for `./run.sh upgrade`), so HTTPS needs no credentials at all. Cloning over SSH would mean leaving a
key on an internet-facing host that can push to the repo — an avoidable blast radius. This is
independent of what your laptop uses; protocol is per-clone, not a repo-wide setting.

> If the repo ever goes private, don't reach for a normal SSH key here — add a **read-only deploy
> key** scoped to this repo, so a compromised relay host still can't write to it.

```bash
sudo mkdir -p /opt && sudo chown "$USER" /opt
git clone https://github.com/mpimenta8/rphaf.git /opt/rphaf
cd /opt/rphaf/deploy/compose

./gen-env.sh --domain jean.rphaf.io --owner <your-64-hex-pubkey>
grep -q CHANGE_ME .env && { echo "fill remaining CHANGE_ME first"; grep -n CHANGE_ME .env; }

BUZZ_COMPOSE_TLS=true ./run.sh start
./run.sh status
curl -fsS https://jean.rphaf.io/_liveness && echo " <- relay is up"
```

Add yourself + friends (see `PLANNING.md` Part 1 for the owner-key rule):

```bash
./run.sh add-member <your-npub> --role admin
./run.sh add-member <friend-npub>          # sleep 1 between multiple adds
```

Friends point the desktop app at `wss://jean.rphaf.io`.

### Optional: cap Redis on a 4 GB box
`compose.yml` starts Redis with no `maxmemory`, so nothing bounds its growth. In practice Buzz only
puts **expiring** keys there — presence (`presence.rs`), rate-limit counters (`rate_limiter.rs`), and
NIP-98 replay guards all set TTLs — so runaway growth is unlikely. If you want the belt-and-braces
version anyway, append to the `redis` service `command:`:

```yaml
"--maxmemory", "256mb", "--maxmemory-policy", "volatile-lru"
```

`volatile-lru` only evicts keys that already carry a TTL, so it can't discard anything meant to
persist. Watch it first with `docker compose exec redis redis-cli -a "$REDIS_PASSWORD" info memory`
before deciding you need it.

## 5b. If you ever change the relay hostname (read before you do)

Mechanically it's small: add the new A record, update the five domain values in `.env`
(`BUZZ_DOMAIN`, `RELAY_URL`, `BUZZ_MEDIA_BASE_URL`, `BUZZ_MEDIA_SERVER_DOMAIN`,
`BUZZ_CORS_ORIGINS`), restart, and let Caddy issue a fresh certificate. Everyone then re-points
their client once.

**But never retire the old hostname.** Media URLs are stored **absolute**, not relative —
`crates/buzz-relay/src/api/media.rs` builds `https://<host>/media/<sha256>.<ext>` and that complete
URL is embedded into message events and `imeta` tags at post time. Events are immutable and nothing
rewrites them, so every image and video ever shared keeps pointing at the hostname that was live
when it was posted. Drop that name and your whole media history 404s while text survives — a quiet
failure that only shows up in old scrollback.

Keep the old name resolving to the same box, and serve both from Caddy:

```caddyfile
{$BUZZ_DOMAIN}, old.rphaf.io {
  encode zstd gzip
  reverse_proxy relay:3000
}
```

Caddy accepts comma-separated site addresses and maintains certificates for both. Cost is one DNS
record you simply never delete.

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
