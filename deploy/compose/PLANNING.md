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
- **RAM:** 4 GB works; **8 GB is comfortable** (relay + Postgres + Redis + MinIO + Caddy, with room
  to re-enable agents/voice later). 2 GB is tight — avoid unless you're only kicking tires.
- **CPU/disk:** 2 vCPU, 40–80 GB NVMe to start (Postgres + MinIO media grow; add block storage later).
- **Network:** inbound **80/443** open, ability to run Docker, a region near you + friends.
- **Bandwidth:** chat traffic is trivial; **media (images/video via MinIO) is the variable** — check
  the egress allowance if you'll share lots of media.

### The matrix
Prices are **approximate (early 2026, USD/mo)** — verify current rates. "Managed PG in-house" = the
host offers its own managed Postgres for the future escape hatch (but see the note below — you're not
locked to it).

| Host | Plan (vCPU / RAM / disk) | ~$/mo | Egress | Managed PG? | Best for |
|---|---|---|---|---|---|
| **Hetzner Cloud** | CPX31 (4 / 8 GB / 160 GB) | **~$16** | 20 TB | ✗ | Best value & headroom; EU + US regions |
| **DigitalOcean** | Basic (2 / 4 GB / 80 GB) | ~$24 | 4 TB | ✓ | Best docs/DX; smooth managed-PG path |
| **Vultr** | Regular (2 / 4 GB / 80 GB) | ~$24 | 3–4 TB | ✓ | Many regions; hourly billing |
| **Linode / Akamai** | Shared (2 / 4 GB / 80 GB) | ~$24 | 4 TB | ✓ | Solid, well-documented |
| **AWS Lightsail** | (2 / 4 GB / 80 GB) | ~$24 | generous | ✓ (RDS) | On-ramp if you want AWS later |

**Wildcards (not recommended for a shared relay, but worth knowing):**
- **Oracle Cloud "Always Free"** — Ampere A1 up to 4 OCPU / 24 GB for **$0**. Tempting, but A1
  capacity is a well-known lottery and free instances can be reclaimed. Fine to *experiment*, risky
  to *depend on*.
- **Home mini-PC / Raspberry Pi + Cloudflare Tunnel** — ~$0/mo + electricity, maximum learning. But
  home uptime, residential IP, and exposing your LAN are real downsides for something friends rely on.

### Recommendation: **Hetzner CPX31 (8 GB) — ~$16/mo**

Rationale:
- **Fits your budget with the most headroom.** At ~$16 it lands inside your $15–20 range while giving
  **8 GB** — twice the RAM of the $24 competitors' 4 GB tiers. That headroom means MinIO + Postgres
  never fight for memory, and you can flip agents/voice back on later without re-sizing.
- **Bandwidth won't bite you.** 20 TB egress dwarfs the 4 TB competitors — media sharing stays free
  of overage anxiety.
- **Best price/performance, full stop** — the standard pick for value self-hosting.

Trade-offs to accept:
- **Plainer console** and **no in-house managed Postgres.** The DX is a notch below DigitalOcean's,
  and account verification can be stricter on signup.
- Mitigated by the note below — the managed-PG gap doesn't actually lock you in.

### Runner-up: **DigitalOcean 4 GB (~$24, split-friendly)**
If you want the **smoothest first-time-self-hoster experience** — best-in-class tutorials, a polished
console, snapshots, and same-VPC managed Postgres when you graduate off all-in-one — DO is worth the
few extra dollars, especially if friends chip in. You'd start on 4 GB (fine) and can resize up.

### The managed-Postgres escape hatch is host-independent
Don't over-weight "does my VM host offer managed PG." Moving to managed Postgres later is a one-line
`DATABASE_URL` swap, and it can point at **any** provider — Neon, Supabase, Crunchy, or a cloud's
managed PG — regardless of where the VM lives. So Hetzner's lack of in-house managed PG is a minor
con: you can still adopt a managed database later from a specialist host.

### Bottom line
- **Default pick:** Hetzner CPX31 (8 GB, ~$16) — best value, in budget, room to grow.
- **Pick DO instead if** you value maximum hand-holding/docs over price and are OK ~$24 (split it).
- **Either way:** start all-in-one, add the nightly `pg_dump` backup on day one, and treat the
  managed-PG move as a later, host-independent option.

See `README.md` for the deploy commands and `gen-env.sh` for `.env` bootstrap. Full context lives in
the repo-root `MEMORY.md` under "Self-hosting the relay."
