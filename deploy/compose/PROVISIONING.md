# VM provisioning — from bare box to running relay

Steps to stand up the rphaf/Buzz relay on a fresh **Ubuntu 24.04 LTS or newer** VM, harden it,
install Docker, open the firewall, deploy, and wire nightly offsite backups.

**Written for AWS EC2**, which is what the relay actually runs on: a `t4g.medium` in `us-east-1`,
in a friend's personal account funded by his credits. §3 onward is provider-agnostic and was
originally proven on DigitalOcean; §1–§2 are AWS-specific and call out the DO equivalents where they
differ. Assumes the `rphaf.io` domain and that you've settled your **owner key** (see `PLANNING.md`
Part 1 — note `PLANNING.md` itself still recommends DigitalOcean and is pending the same update).

Commands are copy-paste; run them in order. `sudo`-prefixed commands need root.

> **One exception to "in order":** §0 (DNS) needs the VM's IP from §1. Read §0 first, create the VM
> (§1), then set the DNS record and keep working through §3–§4 while it propagates.

> **On AWS, §2 is a no-op — skip it.** Canonical's AMI already ships what it builds by hand. See §2.

---

## 0. DNS — self-serve in Route 53

`rphaf.io` is registered by a friend, but its hosted zone lives in **the same AWS account we have
access to**, so this is a **solo step, not a hand-off** — no waiting on anyone. (Earlier revisions of
this guide framed it as a request to send; that was wrong and cost a round-trip.)

### Sequencing
The record needs the VM's public IP, which doesn't exist until §1 — but DNS is also the slowest link
in the chain, and Caddy can't issue a TLS cert until the name resolves. So:

1. **Create the VM first** (§1) and attach its **Elastic IP**. Use the *Elastic* IP, never the
   auto-assigned public one — that changes on every stop/start and would silently break DNS and TLS.
2. **Then** create the record below.
3. Continue with §3–§4 (firewall, Docker) **while DNS propagates** — neither needs DNS.
4. Only §5 (deploy) actually blocks on the record being live.

### Pick the hostname
**`jean.rphaf.io` is settled** — it's baked into the A record, the TLS cert, five `.env` values, and
every client's stored relay URL. Don't change it casually; see §5b for what that costs (it breaks
every historical image and video).

### Create the record

Route 53 → **Hosted zones** → `rphaf.io` → **Create record**:

```
Record name:  jean          (full name: jean.rphaf.io)
Record type:  A
Value:        <ELASTIC_IP>
TTL:          300
Routing:      Simple routing
```

Low TTL (300s) on purpose so mistakes are fixable in minutes rather than a day.

> **To *edit* an existing record, tick its checkbox** — clicking the record *name* doesn't reveal
> the "Edit record" button, which looks exactly like missing permissions and is not.

### If the domain ever moves behind a proxy (Cloudflare et al.)
Not currently applicable on Route 53, but if `rphaf.io` is ever fronted by Cloudflare, the record
**must be "DNS only" (grey cloud), not proxied (orange cloud)** — a proxied record breaks this stack
two ways:

- Caddy's Let's Encrypt **HTTP-01 challenge** fails, because the proxy terminates :80/:443 itself —
  so the relay never gets a certificate.
- Default proxy timeouts sever **long-lived WebSocket** connections, which is the relay's entire
  transport (`wss://`).

### Hold off on the AAAA record
**Add IPv4 only to start**, even if the host has a public IPv6 address. Let's Encrypt *prefers* IPv6
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

## 1. Create the VM (EC2)

EC2 → **Launch instance**:

- **Name:** `rphaf-relay`.
- **AMI:** Ubuntu Server **24.04 LTS or newer** (the default has moved past 24.04 — 26.04 is fine and
  was a non-event in practice).
- **⚠️ Switch the architecture selector to `64-bit (Arm)` on the AMI card *before* picking the
  instance type** — it defaults to x86 and `t4g.*` simply won't appear in the list. The whole stack
  is multi-arch (verified against every image's manifest), so Arm is free performance-per-dollar.
- **Instance type:** `t4g.medium` (2 vCPU / 4 GB). Idle footprint is ~485 MB, so 4 GB is
  right-sized with headroom. Resizing later is stop → change type → start, and both the EBS volume
  and the Elastic IP survive it.
- **Key pair:** your existing ed25519 key, imported (ours is `rphaf-navi`). Never create a new one
  that overwrites `~/.ssh/id_ed25519` locally — that's the key registered with GitHub.
- **Storage:** 120 GB `gp3`, and **tick Encrypted** (default `aws/ebs` key is fine).
  - **You cannot encrypt in place later** — it's snapshot → copy-with-encryption → swap volumes.
    It's free and snapshots inherit it, so there is no reason not to.
  - Set **Delete on termination: No**, and enable **Termination protection** (Advanced details).
    Both free; together they turn a misclick from "restore everything from backup" into a non-event.
- **Security group** `rphaf-relay-sg`: `22` = My IP, `80` + `443` = `0.0.0.0/0`. Both of the latter
  **must** be world-open — Let's Encrypt validates from unpredictable IPs, and friends connect from
  anywhere.
  - The SG is **in addition to** `ufw` in §3, not instead of it. If the SG blocks 80/443, Caddy
    can't complete its ACME challenge and you'll spend an hour debugging a firewall you forgot
    existed.
- **`t4g` is burstable** (CPU credits, "unlimited" mode on by default). Irrelevant for an idle chat
  relay, but it's where a surprise CPU bill would come from — set a billing alarm regardless, so
  credits running out arrives as an alert and not an invoice.

Then **allocate and associate an Elastic IP** (EC2 → Elastic IPs → Allocate → Associate):

> **This is mandatory, not optional.** EC2's auto-assigned public IP **changes on every stop/start**,
> which would silently break DNS and TLS for everyone — and resizing the instance *requires* a
> stop/start. It's free while attached, and it's the address that goes in the §0 A record.

SSH in — the login user is **`ubuntu`**, not `root`:

```bash
ssh ubuntu@<ELASTIC_IP>
```

> **Now create the DNS record from §0** with this Elastic IP, then continue. Propagation runs in the
> background while you do §3–§4.

<details>
<summary>DigitalOcean equivalent (the original target; kept as a fallback)</summary>

- Image **Ubuntu 24.04 LTS**; plan **Basic → Premium Intel/AMD, 2 vCPU / 4 GB / 120 GB NVMe**
  (~$32/mo). Beware the `$24` row in the *Premium* list — it's only **2 GB**, which `PLANNING.md`
  calls too tight.
- Add your SSH public key during creation. If DO's flow suggests `ssh-keygen` and the file already
  exists, **answer `n`** — overwriting destroys the key registered with GitHub.
- Backups **off** (§6 covers offsite), monitoring **on**, IPv6 **on**.
- Skip DO's cloud firewall — §3 configures `ufw`. If you add one anyway it must allow inbound
  **22, 80, 443**, or it silently overrides everything `ufw` permits and locks you out.
- Login is `ssh root@<IP>`, so **§2 applies on DO** — unlike AWS.

</details>

## 2. Baseline hardening — **skip this entirely on AWS**

Canonical's AWS AMI already ships exactly what this section builds by hand: a non-root sudo user
(`ubuntu`) with key-only SSH, **root login disabled, and password auth disabled**. Adding a separate
`buzz` user buys no security and re-takes the lockout risk for nothing. Everything downstream uses
`$USER`, so `ubuntu` works throughout.

**Verify rather than assume** — this takes one command:

```bash
sudo sshd -T | grep -Ei 'permitrootlogin|passwordauthentication'
# expect: permitrootlogin no / passwordauthentication no
```

> `sudo` is required: unprivileged, `sshd -T` dies on
> `/etc/ssh/sshd_config.d/50-cloud-init.conf: Permission denied`.

`sshd -T` prints the **effective** config and is the only real check. We once ran a `sed` over
`/etc/ssh/sshd_config` that silently left `PermitRootLogin yes` in force while we assumed it had
applied — don't trust the edit, trust `sshd -T`.

**Audit the keys, though — that part still applies on AWS.** Every line in `authorized_keys` is a
passwordless path to root:

```bash
cat ~/.ssh/authorized_keys
```

Ours started with two and we pruned one belonging to a **work-issued Mac** (IT holds admin/MDM/remote
-wipe on it, and it goes back if the job ends). Also remove retired keys from the **provider account**
— otherwise they get re-injected into every future VM.

Enable automatic security patches:

```bash
sudo apt-get update && sudo apt-get install -y unattended-upgrades
sudo dpkg-reconfigure -f noninteractive unattended-upgrades
```

<details>
<summary>Non-AWS hosts (DigitalOcean etc.): create the non-root user by hand</summary>

DO drops you in as `root` with no unprivileged user, so build one:

```bash
adduser --gecos "" buzz            # set a password when prompted
usermod -aG sudo buzz
rsync --archive --chown=buzz:buzz ~/.ssh /home/buzz   # copy your authorized_keys over
```

Open a **second** SSH session as the new user and confirm it works *before* locking root out:

```bash
ssh buzz@<VM_PUBLIC_IP>            # from your laptop, in a new terminal
```

Once that works:

```bash
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sshd -t                       # validate BEFORE restarting — a typo locks you out
sudo systemctl restart ssh
sudo sshd -T | grep -Ei 'permitrootlogin|passwordauthentication'   # verify the effective config
```

Keep the second session open until a **third** one verifies. Note cloud-init already sets
`PasswordAuthentication no` (in `50-cloud-init.conf`) whenever the VM is created with an SSH key, so
that half was never actually your doing.

</details>

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

## 3c. Let Redis fork safely

Redis forks to snapshot, which can fail on a small box without memory overcommit. One line, worth
doing on any new host:

```bash
sudo sysctl -w vm.overcommit_memory=1
echo 'vm.overcommit_memory=1' | sudo tee /etc/sysctl.d/99-redis-overcommit.conf
```

## 4. Install Docker Engine + Compose plugin

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"      # run docker without sudo
newgrp docker                        # apply the group now (or log out/in)
docker compose version               # expect v2.24.4+
```

> **If this fails on a brand-new Ubuntu release:** `get.docker.com` keys off the release codename and
> can lag by a few weeks. Fall back to the previous LTS codename, or to Ubuntu's own `docker.io` +
> `docker-compose-v2` packages. (This did **not** happen on 26.04 — the script already supported it.)

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

### Troubleshooting: "Community rejected: Load failed"

That message in the desktop app's **Add Community** dialog is a **transport failure, not a
membership rejection** — a real denial names your pubkey. The usual cause is CORS.

The Tauri app is not served from your domain; its webview origin is `tauri://localhost`
(macOS/Linux) or `http://tauri.localhost` (Windows). If `BUZZ_CORS_ORIGINS` lists only
`https://<your-domain>`, the relay omits the `access-control-allow-origin` header and **every**
desktop client fails — the official upstream build included.

Confirm from any machine:

```bash
curl -sS -i -X OPTIONS https://jean.rphaf.io/ \
  -H "Origin: tauri://localhost" -H "Access-Control-Request-Method: POST" | grep -i access-control
```

No `access-control-allow-origin` line means this is your problem. Fix on the relay host:

```bash
cd /opt/rphaf/deploy/compose
sed -i 's|^BUZZ_CORS_ORIGINS=.*|BUZZ_CORS_ORIGINS=https://jean.rphaf.io,tauri://localhost,http://tauri.localhost|' .env
grep ^BUZZ_CORS_ORIGINS .env
./run.sh restart
```

`gen-env.sh` now includes the desktop origins automatically, so fresh installs don't hit this.

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

### The shape of this, and why

Offsite is **Amazon S3**, in a **different AWS account from the relay**. Three decisions are load-bearing:

| Decision | Why |
|---|---|
| S3, not Backblaze/other | `backup.sh` ships a **full** backup nightly, not an incremental. EC2 → S3 **in the same region is free**; anywhere else is metered egress that grows with your media volume. |
| A **separate AWS account** you own | The relay runs in a friend's personal account on **expiring credits**. Same-account backups die with that account — suspension, closure, or a falling-out takes the relay *and* its only copy at once. Backups are the one thing that must outlive the host account. |
| Instance role, **no stored key** | The alternative is a long-lived access key sitting in `backup.env` on an internet-facing host. An EC2 instance role gives S3 access with zero stored credentials, rotated by AWS. |

Cost is ~$1–2/month at this scale — not covered by the friend's credits, and deliberately so.

> **Region matters.** The bucket **must** be in the relay's region (`us-east-1`). Same-region
> transfer is free *even across accounts*; a bucket elsewhere silently puts every nightly full
> backup on metered inter-region transfer.

### a. In YOUR account: create the bucket

S3 → **Create bucket**, in **`us-east-1`**:

- **Name:** globally unique, e.g. `rphaf-relay-backups` (add a suffix if taken).
- **Block all public access:** ON (default). Leave it.
- **Bucket Versioning:** **Enable** — protects against a corrupted object overwriting a good one.
- **Default encryption:** SSE-S3 (default). Covers the `.env` snapshot at rest without a passphrase
  you'd have to store off-box.
- **Object Ownership:** *Bucket owner enforced* (default). This matters for cross-account writes —
  it makes objects written by the relay owned by **you**, avoiding the classic S3 trap where the
  writing account keeps ownership and the bucket owner can't read its own backups.

Then add a **Lifecycle rule** (Management → Create lifecycle rule), applying to the whole bucket:

- Expire **current** versions after **30 days**.
- Permanently delete **noncurrent** versions after **7 days**.

That rule *is* the offsite retention policy. `backup.sh`'s `KEEP_DAYS` only prunes the local copy on
the VM — nothing in the script ever deletes anything offsite, by design (see the next step).

Note the bucket ARN — `arn:aws:s3:::rphaf-relay-backups` — you'll need it twice below.

### b. In the RELAY's account: an instance role that can write but not delete

IAM → **Roles** → Create role → **AWS service** → **EC2** → name it `rphaf-relay-backup`. Attach an
inline policy (substitute your bucket name):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::rphaf-relay-backups" },
    { "Effect": "Allow", "Action": ["s3:PutObject", "s3:GetObject"],
      "Resource": "arn:aws:s3:::rphaf-relay-backups/*" }
  ]
}
```

**`s3:DeleteObject` is deliberately absent.** Every run writes to a fresh timestamped prefix, so
`rclone copy` never deletes — and a compromised relay host therefore cannot destroy backup history.
Retention lives with the lifecycle rule in your account, where the relay can't reach it. `GetObject`
is there only so rclone can compare sizes/hashes and skip re-uploads.

Attach it to the instance: EC2 → Instances → `rphaf-relay` → **Actions → Security → Modify IAM
role**. Takes effect immediately; no reboot, no restart.

### c. Back in YOUR account: allow that role in

S3 → your bucket → **Permissions → Bucket policy**. Substitute the relay account ID:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::<RELAY_ACCOUNT_ID>:role/rphaf-relay-backup" },
    "Action": ["s3:ListBucket", "s3:PutObject", "s3:GetObject"],
    "Resource": [
      "arn:aws:s3:::rphaf-relay-backups",
      "arn:aws:s3:::rphaf-relay-backups/*"
    ]
  }]
}
```

Cross-account access needs **both** sides to agree: the identity policy in §6b *and* this bucket
policy. Granting only one silently fails with `AccessDenied` — that's the usual reason a
cross-account setup "should work" but doesn't.

### d. On the VM: rclone against the instance role

```bash
sudo -v ; curl https://rclone.org/install.sh | sudo bash

mkdir -p ~/.config/rclone
cat > ~/.config/rclone/rclone.conf <<'EOF'
[offsite]
type = s3
provider = AWS
env_auth = true
region = us-east-1
EOF
```

`env_auth = true` is the whole point: rclone picks up credentials from EC2 instance metadata, so
**no key is ever written to disk**. Confirm it works before going further:

```bash
rclone lsd offsite:rphaf-relay-backups     # succeeds (empty listing) = role is wired correctly
```

An `AccessDenied` here means §6b or §6c is incomplete — fix it now, not after the first cron run
fails silently at 03:15.

### e. Point the backup at it

```bash
cd /opt/rphaf/deploy/compose
cat > backup.env <<'EOF'
BACKUP_RCLONE_REMOTE=offsite:rphaf-relay-backups/relay
KEEP_DAYS=14
EOF
chmod 600 backup.env      # backup.env is gitignored (see root .gitignore) — won't be committed
```

`KEEP_DAYS` governs **local** rotation only. Offsite retention is the lifecycle rule from §6a.

### f. Test by hand, then schedule

```bash
sudo mkdir -p /var/backups/buzz && sudo chown "$USER" /var/backups/buzz
./backup.sh                       # watch it dump, archive, ship offsite
rclone ls offsite:rphaf-relay-backups/relay   # confirm the objects actually landed
crontab -e
# add (nightly 03:15 UTC):
15 3 * * * cd /opt/rphaf/deploy/compose && ./backup.sh >> /var/log/buzz-backup.log 2>&1
```

Make the log writable: `sudo touch /var/log/buzz-backup.log && sudo chown "$USER" /var/log/buzz-backup.log`.

> Don't stop at "the first run worked." A backup job that breaks in month three fails **silently** —
> cron mails nobody and the log is only read by people who already suspect a problem. Wire the
> failure alert in §6g, then do the restore drill in §7.

### g. Alert on failure

`backup.sh` supports an optional `BACKUP_ALERT_CMD`, run only when a backup fails. The cheapest
useful target is the same **SNS topic** you'll use for the billing alarm — one topic, one email
subscription, both classes of "you need to know this" arriving the same way.

Create the topic once (in the relay's account), subscribe your email, confirm the subscription mail,
then add `sns:Publish` for that topic ARN to the `rphaf-relay-backup` role from §6b and:

```bash
# append to backup.env
BACKUP_ALERT_CMD=aws sns publish --region us-east-1 --topic-arn arn:aws:sns:us-east-1:<RELAY_ACCOUNT_ID>:rphaf-alerts --subject "rphaf backup FAILED" --message
```

Requires the AWS CLI on the VM (`sudo snap install aws-cli --classic`). If you'd rather not install
it, any command taking a message as its final argument works — a [healthchecks.io](https://healthchecks.io)
`curl` is a fine substitute.

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
