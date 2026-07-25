# Self-hosting planning — rphaf relay

Two decisions to settle **before** you provision anything:

1. **Your owner identity key** — who administers the relay (Part 1).
2. **Which host to run on** — the box the stack lives on (Part 2).

Neither is hard, but both are annoying to change after the fact, so decide them up front.

---

## Part 1 — Your owner pubkey (sort this first)

### Why it matters
The relay runs in **closed mode** (`BUZZ_REQUIRE_RELAY_MEMBERSHIP=true`). One identity is the
**owner/admin**, set via `RELAY_OWNER_PUBKEY` in `.env`. The owner can add/remove members and
manage the community. Everyone else is a member you invite.

### The trap (read this twice)
A Buzz identity **is** a Nostr keypair, and **the desktop app generates a fresh keypair per device
by default** (Settings → Profile → Identity reads *"your keypair … is fixed for this device"*).

So this fails silently:

1. You set `RELAY_OWNER_PUBKEY = <key A>` and start the relay.
2. You connect the desktop, and let it mint a brand-new `<key B>`.
3. `<key B>` is now just an ordinary member — **you locked yourself out of your own admin.**

**Ownership is decided solely by which private key you hold.** There is no email, no password, and
**no recovery**. Get this right on the first boot.

### hex vs npub (same key, two encodings)
- `RELAY_OWNER_PUBKEY` wants the **64-character hex** form of your *public* key.
- The friendly form you'll usually see is an **`npub1…`** (bech32). It encodes the same bytes.
- `./run.sh add-member` accepts **either** hex or `npub`; the `.env` owner field wants **hex**.
- Where to find your hex pubkey: the desktop identity panel, and it's printed in the app's boot logs
  (e.g. `generated and saved identity pubkey 6d00f86a…`). Any Nostr key tool converts `npub → hex`.

### The three keys, so you don't mix them up
| Key | Form | What it is | Rule |
|---|---|---|---|
| **Your private key** | `nsec1…` / 64-hex secret | *You.* Whoever holds it is you. | **Back it up. Loss = permanent.** |
| **Your public key** | `npub1…` / 64-hex | Your address / identity id | Shareable; this is `RELAY_OWNER_PUBKEY` |
| **Relay's private key** | 64-hex (`BUZZ_RELAY_PRIVATE_KEY`) | The *relay's* own identity (not yours) | `gen-env.sh` makes it; keep it stable forever |

### Recommended flow — decide identity first
1. **Pick the identity you'll own with.** Simplest: use the one you already created during local
   testing, or make a fresh one in the desktop app now.
2. **Back up its `nsec` immediately** — a password manager entry **plus** one offline copy (paper /
   encrypted USB). Non-negotiable; this is the exact discipline every member also needs.
3. **Get its hex pubkey** and pass it as `./gen-env.sh --owner <hex>` (or edit `RELAY_OWNER_PUBKEY`).
4. **Use that same key everywhere you want admin.** When you connect the desktop (and mobile) to the
   *production* relay, **import that `nsec`** — do **not** let the app generate a new key. (Mobile can
   inherit your desktop identity via the QR device-pairing flow.)

### Alternative — bootstrap then set
Bring the relay up, connect the desktop, read the pubkey it generated (Settings → Profile →
Identity), set `RELAY_OWNER_PUBKEY` to it, and `./run.sh restart`. Works fine — but you've now
committed to *that device's* key as owner, so back up its `nsec` right away.

### Your friends
Each friend is their own keypair. Flow: they install the desktop app → connect to your
`wss://…` relay → create their identity → send you their `npub` → you run
`./run.sh add-member <npub>`. **Tell every friend up front: back up your `nsec` or you lose your
account.** That one sentence is the entire UX tax of self-sovereign identity — pay it early.

### Pre-boot checklist
- [ ] Owner `nsec` backed up (password manager **and** offline)
- [ ] `RELAY_OWNER_PUBKEY` = the hex of the key you will actually log in with
- [ ] You imported that key on the desktop (not a freshly generated one)
- [ ] Every friend warned to back up their `nsec`

---

## Part 2 — Host options

### What the relay actually needs
- **RAM:** **4 GB is plenty for "just chat"** — estimated steady state is ~1.2 GB (Ubuntu ~400 MB,
  Postgres ~300 MB, MinIO ~250 MB, relay ~150 MB, Redis ~80 MB, Caddy ~30 MB). **8 GB** only buys
  headroom to re-enable agents/voice later. 2 GB is tight — avoid unless you're only kicking tires.
  On a 4 GB box, add swap (see `PROVISIONING.md`).
- **CPU/disk:** 2 vCPU, 40–80 GB NVMe to start (Postgres + MinIO media grow; add block storage later).
- **Network:** inbound **80/443** open, ability to run Docker, a region near you + friends.
- **Bandwidth:** chat traffic is trivial; **media (images/video via MinIO) is the variable** — check
  the egress allowance if you'll share lots of media.

### ⚠️ Hetzner raised prices on 15 June 2026 — this section was rewritten

The original version of this doc recommended Hetzner CPX31 at ~$16/mo. **That price no longer
exists.** Hetzner's June 2026 adjustment raised the CPX and CCX lines by roughly 2.4x–3x, citing
hardware procurement costs. The CX and CAX lines rose only ~1.3–1.4x, so the cheap tier moved rather
than vanished — but it moved to **Arm, EU-only**.

Verified in the Hetzner console, July 2026:

| Hetzner plan | Specs | ~$/mo | Verdict |
|---|---|---|---|
| CPX31 — Ashburn / Hillsboro (US) | 4 / 8 GB / 160 GB | **~$74** | Dead. 2.98x increase. |
| CPX31 — Nuremberg (EU) | 4 / 8 GB / 160 GB | ~$42 | Poor value now. |
| **CAX21 — Nuremberg / Falkenstein / Helsinki** | 4 / 8 GB / 80 GB | **~$12** | Cheapest option — but **EU-only**. |

**US locations only offer CPX/CCX**, which are exactly the lines that took the big hit. So "Hetzner
in the US" is no longer a value play at all.

### The matrix
Prices are **approximate (July 2026, USD/mo)** — verify current rates, and re-verify Hetzner's
specifically, since they've proven volatile. "Managed PG in-house" = the host offers its own managed
Postgres for the future escape hatch (but see the note below — you're not locked to it).

| Host | Plan (vCPU / RAM / disk) | ~$/mo | Egress | Managed PG? | Best for |
|---|---|---|---|---|---|
| **DigitalOcean** | Basic (2 / 4 GB / 80 GB) | **~$24** | 4 TB | ✓ | **US-based groups.** Best docs/DX; reversible resize |
| **Hetzner CAX21** (Arm) | (4 / 8 GB / 80 GB) | **~$12** | 20 TB | ✗ | **EU-based groups.** Cheapest, most RAM — EU-only |
| **Vultr** | Regular (2 / 4 GB / 80 GB) | ~$24 | 3–4 TB | ✓ | Many regions; hourly billing |
| **Linode / Akamai** | Shared (2 / 4 GB / 80 GB) | ~$24 | 4 TB | ✓ | Solid, well-documented |
| **AWS Lightsail** | (2 / 4 GB / 80 GB) | ~$24 | generous | ✓ (RDS) | On-ramp if you want AWS later |
| ~~Hetzner CPX31 (US)~~ | (4 / 8 GB / 160 GB) | ~~~$74~~ | 1 TB | ✗ | Was the recommendation; no longer competitive |

**Arm is a non-issue technically.** Every image in the stack is multi-arch (`arm64` + `amd64`):
`ghcr.io/block/buzz:main` (verified against the GHCR manifest), `postgres:17-alpine`,
`redis:7-alpine`, `minio/minio`, `caddy:2-alpine`. Running CAX21 needs **no changes to
`compose.yml`**. The only real cost of CAX21 is geography.

**Wildcards (not recommended for a shared relay, but worth knowing):**
- **Oracle Cloud "Always Free"** — Ampere A1 up to 4 OCPU / 24 GB for **$0**. Tempting, but A1
  capacity is a well-known lottery and free instances can be reclaimed. Fine to *experiment*, risky
  to *depend on*.
- **Home mini-PC / Raspberry Pi + Cloudflare Tunnel** — ~$0/mo + electricity, maximum learning. But
  home uptime, residential IP, and exposing your LAN are real downsides for something friends rely on.

### Recommendation: **DigitalOcean 4 GB (~$24/mo), US region**

Since we and our friends are all US-based, this is now the pick.

Rationale:
- **Latency goes where the users are.** An EU relay adds ~90–120ms round-trip. That's invisible for
  sending/receiving chat, adds ~half a second to initial connect, but is genuinely noticeable on
  **media upload/download** — the one interaction where it would bug people daily.
- **4 GB is enough for "just chat."** The 8 GB figure below was sized for *re-enabling agents and
  voice*, not for the first cut. Estimated steady state for a small group is **~1.2 GB total**
  (Ubuntu ~400 MB, Postgres ~300 MB, MinIO ~250 MB, relay ~150 MB, Redis ~80 MB, Caddy ~30 MB) —
  roughly 3x headroom. Confirm with `docker stats` once you're live.
- **The resize is reversible.** DO's CPU/RAM resize goes both directions (only *disk* growth is
  one-way), so outgrowing 4 GB is a temporary bump, not a migration. This de-risks starting small in
  a way that picking the wrong Hetzner *region* does not.
- **Best first-time-self-hoster DX** — best-in-class tutorials, polished console, snapshots, and
  same-VPC managed Postgres when you graduate off all-in-one.

Trade-offs to accept:
- **Half the RAM and $12/mo more** than Hetzner CAX21. You're paying for US latency; that's the
  whole trade.
- **4 TB egress** vs Hetzner's 20 TB. Fine unless media sharing gets heavy — watch it if that changes.

Because RAM is the tighter constraint here, do both of these (see `PROVISIONING.md`):
- **Add 2 GB of swap** — these VMs ship with none, and swap converts a would-be OOM-kill into a brief
  slowdown.
- **Cap Redis with `maxmemory`** — `compose.yml` starts Redis with no cap. Buzz only uses it for
  ephemeral pub/sub, presence, and typing indicators, so unbounded growth is unlikely rather than
  impossible — but the cap is free.

### Runner-up: **Hetzner CAX21 (Arm, 8 GB) — ~$12/mo, EU-only**
Half the price *and* double the RAM of the DO box, with 20 TB egress. If the group were EU-based this
would be the obvious pick with no trade-off at all. Also the right answer if you later decide the
media latency doesn't bother anyone and you'd rather have the headroom for agents/voice. Requires no
`compose.yml` changes — the stack is fully arm64.

### The managed-Postgres escape hatch is host-independent
Don't over-weight "does my VM host offer managed PG." Moving to managed Postgres later is a one-line
`DATABASE_URL` swap, and it can point at **any** provider — Neon, Supabase, Crunchy, or a cloud's
managed PG — regardless of where the VM lives. So Hetzner's lack of in-house managed PG is a minor
con: you can still adopt a managed database later from a specialist host.

### Bottom line
- **Default pick:** DigitalOcean 4 GB (~$24) in a **US** region — latency where the users are, and
  4 GB is ~3x what "just chat" actually needs. Add swap + a Redis cap.
- **Pick Hetzner CAX21 instead if** the group is EU-based, or if $12/mo and 8 GB matter more than
  media-upload responsiveness. Arm is a non-issue — the whole stack is multi-arch.
- **Don't pick Hetzner in the US** — the June 2026 increase put CPX31 at ~$74/mo there.
- **Either way:** start all-in-one, add the nightly `pg_dump` backup on day one, and treat the
  managed-PG move as a later, host-independent option.

See `README.md` for the deploy commands and `gen-env.sh` for `.env` bootstrap. Full context lives in
the repo-root `MEMORY.md` under "Self-hosting the relay."
