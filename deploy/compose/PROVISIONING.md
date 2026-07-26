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

- **Name:** globally unique, e.g. `rphaf-backup-bucket` (add a suffix if taken).
- **Block all public access:** ON (default). Leave it.
- **Bucket Versioning:** **Enable** — a delete becomes a recoverable *delete marker* rather than
  destruction. (Note it does little against *overwrites* here: `backup.sh` writes every run to a
  fresh timestamped prefix, so nothing is ever overwritten in the first place.)
- **Default encryption:** SSE-S3 (default). Covers the `.env` snapshot at rest without a passphrase
  you'd have to store off-box.
- **Object Ownership:** *Bucket owner enforced* (default). This matters for cross-account writes —
  it makes objects written by the relay owned by **you**, avoiding the classic S3 trap where the
  writing account keeps ownership and the bucket owner can't read its own backups.

### Retention: two tiers, not one

`backup.sh` files each run under `daily/` or `monthly/` (the first successful run of each calendar
month becomes that month's monthly). Retention differs per tier, which is the whole point:

| Prefix | Keep | Answers |
|---|---|---|
| `relay/daily/` | **30 days** | "restore last night" — VM died, disk failed, someone deleted a channel |
| `relay/monthly/` | **365 days** | "this data was quietly wrong months ago" — a bad migration, a bug that dropped events, a compromise with long dwell time |

**Why a flat 30 days is not enough.** At any moment you'd hold the last 30 nights — fine for the
loud failures, useless for the quiet ones. If damage lands on day 0 and nobody notices until day 37,
every surviving backup already contains it. The monthly tail is what makes a problem discovered in
month six recoverable, and it costs almost nothing because the data is small.

**Set these via the CLI, not the console.** The console's rule builder makes it very easy to save an
expiration without its noncurrent-version counterpart — which, on a versioned bucket, silently means
nothing is ever deleted (see the warning below). This applies the whole configuration at once, so
the end state is exactly what's written regardless of what's there now. Run it in **CloudShell**
(the `>_` icon in the console top bar — already authenticated, nothing to install):

```bash
cat > /tmp/lifecycle.json <<'EOF'
{
  "Rules": [
    {
      "ID": "expire-dailies",
      "Status": "Enabled",
      "Filter": { "Prefix": "relay/daily/" },
      "Expiration": { "Days": 30 },
      "NoncurrentVersionExpiration": { "NoncurrentDays": 7 },
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 7 }
    },
    {
      "ID": "expire-monthlies",
      "Status": "Enabled",
      "Filter": { "Prefix": "relay/monthly/" },
      "Expiration": { "Days": 365 },
      "NoncurrentVersionExpiration": { "NoncurrentDays": 7 },
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 7 }
    },
    {
      "ID": "clean-delete-markers",
      "Status": "Enabled",
      "Filter": { "Prefix": "relay/" },
      "Expiration": { "ExpiredObjectDeleteMarker": true }
    }
  ]
}
EOF

aws s3api put-bucket-lifecycle-configuration \
  --bucket rphaf-backup-bucket --lifecycle-configuration file:///tmp/lifecycle.json
```

> **⚠️ On a versioned bucket, `Expiration` alone deletes nothing.** It inserts a *delete marker* —
> the object disappears from listings while the bytes become a **noncurrent version** that is stored
> and billed **forever**. Only `NoncurrentVersionExpiration` reclaims them. This fails in the safe
> direction (nothing is lost) but silently defeats the cost ceiling, and you'd discover it a year
> later as an unexplained bill. It is the single easiest thing to get wrong on this page.

`ExpiredObjectDeleteMarker` needs its **own** rule — S3 rejects it in the same `Expiration` block as
`Days`. And note a daily now takes 30 + 7 = 37 days to vanish permanently; that grace period is
deliberate.

> **Mind the prefix filter.** A rule with an empty prefix applies to the *whole bucket*, so a
> 30-day rule with no filter would quietly delete your monthlies too — the exact failure the tiers
> exist to prevent.

**Verify what S3 actually stored**, rather than what the form appeared to accept:

```bash
aws s3api get-bucket-lifecycle-configuration --bucket rphaf-backup-bucket \
  --query 'Rules[].{ID:ID,Prefix:Filter.Prefix,Days:Expiration.Days,Noncurrent:NoncurrentVersionExpiration.NoncurrentDays,Status:Status}' \
  --output table
```

Check: both tiered rules `Enabled`, each with a **non-empty prefix and no leading slash** (`/relay/…`
matches nothing — S3 keys don't start with a slash, and a rule matching nothing never expires
anything), a **`Noncurrent` value present on both**, and 30 on `daily` / 365 on `monthly` rather than
swapped.

These rules **are** the offsite retention policy. `backup.sh`'s `KEEP_DAYS` prunes only the local
copy on the VM — nothing in the script ever deletes anything offsite, by design (see §6b).

### Cost, and the one thing that would change it

Roughly `(30 + 12) × <nightly size> × $0.023/GB` per month — so a 500 MB nightly set is about
**$0.50/month**, and 5 GB is about **$5**.

> **The scaling trap:** these are **full** backups, not incrementals, so cost is retention ×
> dataset. That's irrelevant at friend-group scale, but if shared media ever grows into tens of GB,
> revisit this before the bill does — either shorten the daily tier, transition `monthly/` to
> Glacier Instant Retrieval via a lifecycle *transition* rule, or move to incrementals
> (`restic`/`borg`) instead of `rclone copy`.

Note the bucket ARN — `arn:aws:s3:::rphaf-backup-bucket` — you'll need it twice below.

### b. In the RELAY's account: an instance role that can write but not delete

IAM → **Roles** → Create role → **AWS service** → **EC2** → name it `rphaf-relay-backup`. Attach an
inline policy (substitute your bucket name):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::rphaf-backup-bucket" },
    { "Effect": "Allow", "Action": ["s3:PutObject", "s3:GetObject"],
      "Resource": "arn:aws:s3:::rphaf-backup-bucket/*" }
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
      "arn:aws:s3:::rphaf-backup-bucket",
      "arn:aws:s3:::rphaf-backup-bucket/*"
    ]
  }]
}
```

Cross-account access needs **both** sides to agree: the identity policy in §6b *and* this bucket
policy. Granting only one silently fails with `AccessDenied` — that's the usual reason a
cross-account setup "should work" but doesn't.

### d. On the VM: rclone against the instance role

```bash
curl https://rclone.org/install.sh | sudo bash

mkdir -p ~/.config/rclone
cat > ~/.config/rclone/rclone.conf <<'EOF'
[offsite]
type = s3
provider = AWS
env_auth = true
region = us-east-1
no_check_bucket = true
EOF
```

> **`no_check_bucket = true` is required, not tuning.** Before uploading, rclone verifies the
> destination bucket exists and **tries to create it** if that check fails. The §6b role has no
> `s3:CreateBucket`, so without this line every upload dies with
> `AccessDenied … s3:CreateBucket` *before* it ever attempts `PutObject` — while `lsd` keeps
> working, because listing never triggers the check. Do not "fix" this by granting `CreateBucket`:
> that would let a compromised relay host create buckets in your account, to satisfy a check we
> don't need.

> **If `sudo` asks for a password here, nothing is wrong.** The `ubuntu` account's password is
> **locked by design** — its sudo rights come from cloud-init's `NOPASSWD` rule in
> `/etc/sudoers.d/90-cloud-init-users`, so there is no password to type and none was ever set.
> Upstream's install line begins `sudo -v ;`, which asks sudo to *authenticate the user* rather than
> authorize a command and therefore can never succeed against a locked password; it's dropped above
> for that reason. Ordinary `sudo <command>` works fine — check with `sudo -n true` (`-n` fails
> instead of prompting). Note this is unrelated to SSH's `PasswordAuthentication no` from §2: one
> governs remote login, the other local privilege escalation.

`env_auth = true` is the whole point: rclone picks up credentials from EC2 instance metadata, so
**no key is ever written to disk**. Confirm it works before going further:

```bash
rclone lsd offsite:rphaf-backup-bucket; echo "exit=$?"
```

> **Read the exit code, not the output.** On an empty bucket a *successful* `lsd` prints **nothing** —
> indistinguishable at a glance from a command that failed. `exit=0` is the signal.

Then prove it end to end. `lsd` only exercises `ListBucket`; the nightly backup also needs
`PutObject`, and those are separate grants that fail independently:

```bash
echo "probe $(date -u)" > /tmp/rphaf-probe.txt
rclone copy /tmp/rphaf-probe.txt offsite:rphaf-backup-bucket/relay/daily/_probe/
rclone ls offsite:rphaf-backup-bucket/relay/          # must list the probe file
```

The probe goes under `relay/daily/` so the 30-day rule disposes of it. **You cannot delete it
yourself** — the role has no `s3:DeleteObject` (§6b). That's the design working, and it's better to
meet it here than during an incident.

An `AccessDenied` means §6b or §6c is incomplete — fix it now, not after the first cron run fails at
03:15. It won't say which half is missing, so work in this order:

```bash
# 1. Is a role actually attached? (IMDSv2 — an unauthenticated GET returns 401 with an empty
#    body, so the older token-less one-liner looks identical to "no role".)
TOKEN=$(curl -sX PUT http://169.254.169.254/latest/api/token \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/; echo
#    -> prints the role name, or nothing if none is attached (fix: §6b, Modify IAM role)
#    The trailing `; echo` matters: IMDS sends no newline, so without it the role name
#    collides with your shell prompt (`rphaf-relay-backupubuntu@ip-…`) and reads as empty.

# 2. Role attached but denied? Then the bucket policy (§6c) doesn't name that exact role ARN.
```

### e. Point the backup at it

```bash
cd /opt/rphaf/deploy/compose
cat > backup.env <<'EOF'
BACKUP_RCLONE_REMOTE=offsite:rphaf-backup-bucket/relay
KEEP_DAYS=14
EOF
chmod 600 backup.env      # backup.env is gitignored (see root .gitignore) — won't be committed
```

`KEEP_DAYS` governs **local** rotation only. Offsite retention is the lifecycle rule from §6a.

### f. Test by hand, then schedule

```bash
sudo mkdir -p /var/backups/buzz && sudo chown "$USER" /var/backups/buzz
./backup.sh                       # watch it dump, archive, ship offsite
rclone lsf offsite:rphaf-backup-bucket/relay/            # expect: monthly/ (first run of the month)
rclone ls  offsite:rphaf-backup-bucket/relay             # confirm the objects actually landed
```

Make the log writable, then install the schedule **without hand-editing**:

```bash
sudo touch /var/log/buzz-backup.log && sudo chown "$USER" /var/log/buzz-backup.log

( crontab -l 2>/dev/null | grep -v 'backup\.sh' ; \
  echo '15 3 * * * cd /opt/rphaf/deploy/compose && ./backup.sh >> /var/log/buzz-backup.log 2>&1' \
) | crontab -

crontab -l | tail -1 | cat -A      # must end exactly: ...2>&1$
```

> **Don't paste the line into `crontab -e`.** On an empty crontab it lands above the default comment
> header **without a trailing newline**, gluing the header onto your command:
> `… 2>&1# Edit this file to introduce tasks…`. Cron honours `#` only at the *start* of a line, so
> the shell reads the redirect target as `1#` — an invalid descriptor, the redirection fails, and
> `backup.sh` never runs. It fails **silently**, because cron mails the error to a local user on a
> box with no MTA. `echo` supplies the newline; `cat -A` renders the line ending (`$`) so you can
> see it's clean.

**Prove cron actually runs it**, rather than assuming — its environment is minimal and differs from
your login shell:

```bash
# one-off run 3 minutes from now, alongside the real entry
( crontab -l ; echo "$(date -u -d '+3 minutes' '+%M %H') * * * cd /opt/rphaf/deploy/compose && ./backup.sh >> /var/log/buzz-backup.log 2>&1" ) | crontab -

# wait ~4 minutes, then:
cat /var/log/buzz-backup.log
cat /var/backups/buzz/LAST_SUCCESS
rclone lsf offsite:rphaf-backup-bucket/relay/daily/     # a new timestamped dir

# remove the one-off
( crontab -l | grep -v "$(date -u -d '+3 minutes' '+%M %H')" ) | crontab -
```

This also exercises the **`daily/`** branch of the tier logic for the first time — every earlier run
goes to `monthly/`, so without this the path that runs 30 nights out of 31 stays untested.

> **Verified 2026-07-26:** the scheduled run fired on time, chose `daily/` correctly (July's monthly
> already existed), and shipped offsite. Cron's `PATH` found `docker` and `rclone` unaided, so no
> `PATH` line is needed in `backup.sh`.

> Don't stop at "the first run worked." A backup job that breaks in month three fails **silently** —
> cron mails nobody and the log is only read by people who already suspect a problem. Wire the
> failure alert in §6g, then do the restore drill in §7.

### g. Alert on failure

`backup.sh` supports an optional `BACKUP_ALERT_CMD`, run only when a backup fails. Until it's set,
**a failed backup tells nobody** — the alerting path exists but is dormant. Target an **SNS topic**
in the relay's account. Do these in order; the last step doesn't work without the first three.

**1. Create the topic** — SNS → Topics → Create topic → type **Standard**, name `rphaf-alerts`.

**2. Subscribe your email** — on that topic → Create subscription → Protocol **Email** → your
address. **Then open the confirmation mail and click the link.** AWS silently discards messages to
unconfirmed subscriptions, so skipping this leaves you with alerting that looks configured and
delivers nothing.

**3. Let the role publish** — IAM → Roles → `rphaf-relay-backup` → its inline policy → add:

```json
{ "Effect": "Allow", "Action": "sns:Publish",
  "Resource": "arn:aws:sns:us-east-1:<RELAY_ACCOUNT_ID>:rphaf-alerts" }
```

**4. On the VM, install the CLI and let it resolve the account ID** (this also re-confirms the
instance role works):

```bash
sudo snap install aws-cli --classic
aws sts get-caller-identity --query Account --output text
```

**5. Append the setting to `backup.env`.**

> ⚠️ **This is a config line, not a command.** Typing it at the shell makes bash read
> `<RELAY_ACCOUNT_ID>` as an input redirect and fail with `No such file or directory`. Use the
> heredoc — note `>>` (append, don't clobber) and the *unquoted* `EOF` so `${ACCT}` expands:

```bash
cd /opt/rphaf/deploy/compose
ACCT=$(aws sts get-caller-identity --query Account --output text)
cat >> backup.env <<EOF
BACKUP_ALERT_CMD="aws sns publish --region us-east-1 --topic-arn arn:aws:sns:us-east-1:${ACCT}:rphaf-alerts --subject rphaf-backup-FAILED --message"
EOF
cat backup.env      # confirm the ARN has a real 12-digit account, not a placeholder
```

> **Two things about that value are load-bearing.**
>
> **It must be quoted.** Unquoted, `BACKUP_ALERT_CMD=aws sns publish …` is shell syntax for *"run
> `sns publish …` with `BACKUP_ALERT_CMD=aws` set for that one command"* — so sourcing the file
> fails with `Command 'sns' not found` and the variable never gets set at all.
>
> **No argument inside it may contain spaces.** `backup.sh` runs `$ALERT_CMD "$msg"` unquoted so the
> command word-splits, and quotes *within* a variable's value are not re-interpreted as quotes after
> expansion — `--subject "rphaf backup FAILED"` would arrive as four arguments carrying literal
> quote characters. Hence the hyphenated subject. It costs nothing: `backup.sh` already prefixes the
> message with `rphaf backup FAILED on <host>:`. If you ever need spaces in an argument, put the
> command in a wrapper script and point `BACKUP_ALERT_CMD` at that instead.

**6. Prove it delivers**, rather than waiting for a genuine failure to find out:

```bash
set -a; . ./backup.env; set +a
echo "$BACKUP_ALERT_CMD"      # must print the whole command — if it prints "aws", it wasn't quoted
$BACKUP_ALERT_CMD "test alert - rphaf alerting setup, ignore"
```

An email should arrive within seconds. Nothing arriving means the subscription is unconfirmed (step
2) or the role lacks `sns:Publish` (step 3).

> **Prefer no AWS CLI?** Any command taking the message as its final argument works — a
> [healthchecks.io](https://healthchecks.io) `curl` is a fine substitute, and has the advantage of
> being a *dead man's switch*: it alerts when an expected ping fails to arrive, which catches a run
> that never happened at all. `BACKUP_ALERT_CMD` fires only on failure, so it can't.

### h. Notice the failures alerting can't see

Retention only buys time if something tells you to *use* it. Three failures survive everything above,
because in each one the backup job either succeeds or never runs:

| Failure | Why alerting misses it | Cheap check |
|---|---|---|
| Cron never fires (bad crontab, VM stopped) | No run, so no failure to report | `cat /var/backups/buzz/LAST_SUCCESS` — stale date = no backups |
| Backups succeed but restore doesn't work | Every run is green | §7, done for real, at least once |
| Data was already corrupt when dumped | A faithful backup of bad data | The `monthly/` tier — the only way back past the damage |

The first is worth automating: an S3 **CloudWatch alarm** on the bucket's `PutRequests` metric,
alerting to the same SNS topic when it drops to zero over 48 hours, catches "the backups quietly
stopped" without any code on the VM. Everything else on this page fails loudly; that one fails
silently, which is why it deserves the alarm.

### i. Budget alarms (both accounts)

Two accounts carry cost risk, for different reasons:

| Account | Risk | Threshold |
|---|---|---|
| **The relay's** (friend's) | The instance runs on **expiring credits**. When they run out, charges start — and without an alarm that arrives as an invoice rather than a warning. `t4g` is also burstable, so CPU overage lands here. | ~$10/mo |
| **Yours** (backups) | Runaway storage. Full backups × retention scales multiplicatively, so growing media quietly grows the bill. | ~$5/mo |

**Use AWS Budgets, not a CloudWatch billing alarm.** CloudWatch's billing metric first requires
enabling *Receive Billing Alerts* in Billing preferences, which is **root-only** — and in the
relay's account you're an IAM user, so you'd be blocked. Budgets needs no such preference, emails
you directly without an SNS topic, and can alert on **forecasted** spend, which warns you before the
money is gone instead of after.

In each account: **Billing and Cost Management → Budgets → Create budget**

- Template **Monthly cost budget**, amount from the table above
- Alert at **85% of actual** *and* **100% of forecasted** — the forecast alert is the one that gives
  you warning rather than a post-mortem
- Recipient: your email

> Check **Billing → Budgets** loads in the relay's account before planning around it. An IAM user
> often has no billing permissions, in which case the account owner either grants them or creates
> the budget themselves.

## 7. Restore drill (a backup you haven't restored isn't a backup)

> **☠️ Never restore into the running stack.** `backup.sh` dumps with `--clean --if-exists`, so the
> SQL **drops every object before recreating it**. Piping it into the live `postgres` service — or
> untarring a volume archive over `buzz-prod_buzz-minio-data` — destroys production and replaces it
> with the backup. An earlier version of this section did exactly that while telling you to "use a
> scratch box", which is how a safety procedure becomes the outage.
>
> The drill below is **safe by construction**: it restores into a throwaway container with its own
> name and its own volume, and never references a `buzz-prod_*` volume or the compose stack.

Run it on the relay host — no scratch box needed, because nothing here touches the live stack.

**a. Pick a backup set and check it against its own manifest.**

```bash
cd /opt/rphaf/deploy/compose
BK=$(ls -1d /var/backups/buzz/*/ | tail -1); echo "using $BK"
( cd "$BK" && sha256sum -c SHA256SUMS )     # every line must say OK
```

**b. Stand up a throwaway Postgres** — same major version as the stack, its own container name,
never joined to the compose project:

```bash
PGU=$(grep -E '^POSTGRES_USER=' .env | cut -d= -f2-)
PGD=$(grep -E '^POSTGRES_DB=' .env | cut -d= -f2-)

docker run -d --name buzz-restore-drill \
  -e POSTGRES_USER="$PGU" -e POSTGRES_DB="$PGD" \
  -e POSTGRES_PASSWORD=throwaway-drill-password \
  postgres:17-alpine
sleep 5
```

**c. Restore into it, and read the errors.**

```bash
gunzip -c "$BK/postgres.sql.gz" \
  | docker exec -i buzz-restore-drill psql -U "$PGU" -d "$PGD" > /tmp/restore.log 2>&1
grep -c '^ERROR' /tmp/restore.log     # a few "does not exist" from --if-exists are normal
tail -20 /tmp/restore.log
```

**Expect `errors: 0`.** `--if-exists` is exactly what stops `DROP` from complaining about objects
that were never there, so a clean restore into an empty database produces no errors at all — the
tail should be an unbroken run of `CREATE TABLE` / `COPY` / `ALTER TABLE`. A non-zero count is worth
reading before you trust the backup.

**d. Prove the data is actually there — compare against production.**

```bash
# restored copy
docker exec buzz-restore-drill psql -U "$PGU" -d "$PGD" -tAc 'select count(*) from events;'
# live relay
docker compose --env-file .env -f compose.yml exec -T postgres \
  psql -U "$PGU" -d "$PGD" -tAc 'select count(*) from events;'
```

Both `select`s are read-only. The counts should match (or differ by whatever arrived since the
dump). **A restore that "succeeds" with zero rows is the failure this step exists to catch** — and
it's invisible in step (c), because an empty restore produces no errors at all.

> **Drill run 2026-07-26, first time, on the live relay:** `errors: 0`, **48 events restored vs 48
> live** — exact match. Backup set was 622 KB (`postgres.sql.gz` 162 KB, `minio-data.tar.gz` 447 KB,
> `git-data.tar.gz` 188 B — empty, as expected while the git feature is off). Every `SHA256SUMS`
> line `OK`. Use these as the shape of a healthy result, not as targets.

**e. Check the media archive lists and extracts.**

```bash
tar tzf "$BK/minio-data.tar.gz" | head
tar tzf "$BK/git-data.tar.gz"   | head
```

`tar tz` reads the archive without writing anything, so it cannot touch the live volumes.

**f. Tear the drill down.**

```bash
docker rm -f buzz-restore-drill
```

That removes the container and its anonymous volume. Nothing else was ever touched.

### What a real recovery would add

The drill deliberately stops short of a full recovery, because the remaining steps are destructive
by nature. When actually recovering onto a **fresh** host: restore `.env` from `env.snapshot` first
(the relay's identity keys live there — a new `BUZZ_RELAY_PRIVATE_KEY` means a different relay),
bring the stack up so the volumes exist, stop it, untar the volume archives over them, then restore
Postgres. Order matters: Compose creates the named volumes, so they must exist before you populate
them.

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
