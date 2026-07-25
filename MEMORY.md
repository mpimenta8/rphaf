# MEMORY.md — rphaf project context

Working notes for humans (and agents) collaborating on this fork. This is a
**self-hosted team-chat** project built on top of Buzz. Keep it short and current.

## What this repo is

- `rphaf` (aka "rocpile") is a **fork of [block/buzz](https://github.com/block/buzz)** — a
  Nostr-relay-based workspace where humans and AI agents share rooms.
- Goal: run a **plain team-chat app** for us and friends, self-host the relay, and use it to
  learn the infrastructure. Agents/workflows/git-forge/voice are on the roadmap, not the first cut.

### Git remotes
- `origin` → `git@github.com:mpimenta8/rphaf.git` (our repo — we push here; add friends as
  collaborators). **Uses SSH**, on purpose — see "Pushing" below.
- `upstream` → `github.com/block/buzz` (**fetch-only**, push disabled). Pull Block's updates with
  `git fetch upstream && git merge upstream/main`.
- **Both drift and need re-establishing after a fresh clone** (seen 2026-07-25: `origin` had reverted
  to HTTPS and `upstream` was missing entirely, which silently breaks the sync recipe above). Repair:
  `git remote set-url origin git@github.com:mpimenta8/rphaf.git`,
  `git remote add upstream https://github.com/block/buzz.git`,
  `git remote set-url --push upstream DISABLED`.
- **Keep upstream merges clean:** prefer changes that don't rewrite shared server/Rust files.

### Pushing (SSH — now actually configured)
- `origin` is an **SSH** URL, and as of 2026-07-25 SSH auth genuinely works: local
  `~/.ssh/id_ed25519` is registered on the GitHub account as **`rphaf-dev`**. Before that it was
  configured but unusable (key never registered), so pushes failed with `Permission denied
  (publickey)` — and, on a fresh `known_hosts`, `Host key verification failed` first. If the latter
  recurs, add GitHub's keys from the authoritative source: `curl -s https://api.github.com/meta`
  → `.ssh_keys`, rather than blindly trusting `ssh-keyscan`.
- **The original reason for preferring SSH is now stale.** It was "a `gh` OAuth token lacks the
  `workflow` scope, so HTTPS pushes touching `.github/workflows/*` get rejected" — but the token
  carries `workflow` (plus `admin:public_key` since registering the key). HTTPS is a perfectly good
  fallback; SSH is now preference, not necessity.
- Pre-push hooks run clippy + unit tests (Rust, desktop, Tauri, mobile). **Activate hermit first**
  (`. ./bin/activate-hermit`) or the hooks fail with `just: command not found`.

### Syncing upstream (proven clean)
- Cadence: **sync often** — small, frequent merges beat one giant catch-up.
- Verified end-to-end once already: merged **36 upstream commits (→ v0.4.25) with ZERO conflicts**;
  our gating survived; full test suite green. Strategy A works — this is the payoff.
- Recipe: `git fetch upstream && git merge --no-edit upstream/main`, then `just ci` (or at least
  `cd desktop && pnpm typecheck && pnpm check`), then `git push origin main`.
- Low-but-nonzero future risk: if upstream edits the *exact lines* we gated (e.g. the agents nav
  item, the `HuddleBar` mount), expect a **small** conflict — re-apply the `<FeatureGate>` wrap around
  their new code. Minutes, not days.

## Running it locally

Requires Docker running (Postgres/Redis/MinIO come up via `docker-compose.yml`).

```bash
. ./bin/activate-hermit    # toolchain (Rust, Node, pnpm, just) — no system installs
cp .env.example .env       # first time only
just setup                 # deps + DB migrations + docker services
just dev                   # all-in-one: its own relay (ws://localhost:3000) + Tauri desktop app
```

Notes:
- `just dev` **owns the relay** — don't also run `just relay` (port 3000 clashes; it refuses).
- `just desktop-dev` = faster web-only frontend loop against a running relay.
- First launch: create a local identity (Nostr keypair). macOS keychain will prompt — click
  **"Always Allow"** (unsigned dev builds re-prompt after a rebuild; that's expected, not malware).
- Closing the app window ends the whole `just dev` session.

## The "just chat" strip-down (Strategy A — disable, don't delete)

Branch `just-chat-strip-down`. We **hide** non-chat features behind the existing desktop
preview-flag system rather than deleting code — so everything is re-enableable and upstream
merges stay clean. **No Rust/server edits.**

Hidden by default (toggle back on in **Settings → Experiments**): agents, huddles (voice),
mesh-compute, agent-memory — plus workflows/projects/pulse/forum (already gated upstream).
git/forge is covered by the `projects` gate.

How the gating works:
- `preview-features.json` (repo root) — add a default-off entry; it auto-appears as a toggle in
  Settings → Experiments. **Semantics:** id *in* manifest → off unless enabled; id *not* in
  manifest → always shown (fail-open). So to hide something, it must be **added** to the manifest.
- `<FeatureGate feature="id">` / `useFeatureEnabled("id")` (`desktop/src/shared/features/`) hide UI.
- Agents nav gate: `sidebar/ui/AppSidebarPinnedHeader.tsx`; route warning: `app/routes/agents.tsx`.
- Huddle: gate `<HuddleBar>` in `app/AppShell.tsx` — **leave `<HuddleProvider>` mounted**
  (ChannelMembersBar's `useHuddle()` needs it). Inline call button gated in `ChannelMembersBar.tsx`.
- Welcome persona banner ("@Fizz…"): **self-gates** inside `WelcomeComposerBanner.tsx`.
- @-mention autocomplete: `buildMentionSuggestionPool()` in `messages/lib/mentionCandidates.ts`
  drops agent/persona/team candidates when agents disabled.
- Settings tabs gated via `featureGate` field in `settings/ui/SettingsPanels.tsx` (agents, compute).
- Relay subsystem toggles in **`.env`** (gitignored, local only): `BUZZ_HUDDLE_AUDIO_AVAILABLE=false`,
  `BUZZ_SERVE_GIT_WEB_GUI=false`. Applied on next `just dev` (relay reads `.env` at startup).

To **re-enable agents later:** flip the Experiments toggles ON, then run the agent processes
(`sprig` / `buzz-acp` / `buzz-agent`) as relay clients. No re-fork needed — that's the point.

## Gotchas learned the hard way

- **Hiding UI ≠ deleting data.** The seeded dev community ships a real `@Fizz` agent *member* on the
  relay; feature gates hide agent UI but can't remove identities already in the event log. A fresh
  community you create has **no** agents unless someone runs an agent process.
- **File-size guard (1000 lines/file)** — `pnpm check:file-sizes`, runs in pre-commit. `ChannelPane.tsx`
  and `useMentions.ts` were already *at* the ceiling upstream, so any edit trips it. Rule: **split /
  move logic to a helper or leaf component — do NOT bump the limit or add an override.** That's why
  agent/huddle gating lives in small leaf files, not in the big `ChannelPane`.
- **Kinds are accepted regardless of UI.** The relay's `ALL_KINDS` is just a dup-check test, not an
  acceptance gate (real gate: `required_scope_for_kind` in `buzz-relay/src/handlers/ingest.rs`). We
  intentionally leave the relay accepting all kinds — harmless, keeps upstream clean.

## Roadmap

- **Fold agents back in** (Experiments toggle + run agent processes).
- **Brand pass — docs only, spec + plan approved 2026-07-25**
  (`docs/superpowers/specs/2026-07-25-rphaf-brand-pass-design.md`, `…/plans/…`). Product noun is
  plain **`rphaf`** (no second brand), emoji **🪨** replaces 🐝, README tagline **"Rocpile Hard AF"**,
  full README rewrite (~267 → ~90 lines) plus new `IDENTITY.md` and `ROADMAP.md`. Scope is
  documentation only — **no code, no app strings, no relay config.** Constraint: nothing may claim a
  feature that's gated off or a relay that isn't running. Carries the open hostname decision above.
- **Rebrand** (deeper tiers, beyond the docs pass) Buzz → rphaf, tiered: (1) cosmetic strings + relay NIP-11 name
  (`buzz-relay/src/nip11.rs`), (2) app identity (`tauri.conf.json` productName/identifier/deep-link
  scheme, mobile bundle IDs, icons), (3) internal `buzz-*` crate names / `BUZZ_*` env / storage keys
  (~1,200 files, high-churn — abandons clean upstream merges; do last if ever).
- **Self-host the relay:** see the dedicated section below. Add friends as collaborators on
  `mpimenta8/rphaf` for the *code*; add them as relay *members* separately (`./run.sh add-member`).

## Self-hosting the relay

**Vision: start all-in-one, add automated backups on day one.** One small VM (~$24/mo, see host
decision below) runs the whole stack via Docker Compose; a nightly `pg_dump` offsite closes the only
scary failure mode (losing the DB) for ~$0. Move Postgres to a managed DB *later* only if the data's
value warrants it — it's a one-line `DATABASE_URL` swap, not a rebuild.

### Settled decisions (2026-07-25)
- **Owner identity:** `6a68bbc04fad286751cb73a699ca9428dfe038399e60653428a0864f19c05b2f`
  (`npub1df5thsz0455xw5wtwwnfnj559r07qwpenesx2dpg5zry7xwqtvhsks7c9c`). Derived from the backed-up
  `nsec` and cross-checked against the Nostr client. This is `RELAY_OWNER_PUBKEY`.
- **Domain:** `rphaf.io`, registered by a friend — **DNS changes require a hand-off**, they're not
  self-serve. Keep the A-record TTL at 300 so future re-points (e.g. moving hosts) are fast.
- **⚠️ OPEN: the relay hostname.** `deploy/compose/*` and this file were written against
  `jean.rphaf.io`, but the brand pass (`docs/superpowers/specs/2026-07-25-rphaf-brand-pass-design.md`
  §84) treats it as undecided and proposes `boysch.rphaf.io` / `jean.rphaf.io`. **Settle this before
  the DNS request goes to the domain owner** — it's baked into the A record, the TLS cert, five
  `.env` values (`BUZZ_DOMAIN`, `RELAY_URL`, `BUZZ_MEDIA_BASE_URL`, `BUZZ_MEDIA_SERVER_DOMAIN`,
  `BUZZ_CORS_ORIGINS`), and every client's relay URL. Changing it later means a new record, a
  re-issued cert, and re-pointing everyone.
- **Host: DigitalOcean, $32/mo Premium Intel — 2 vCPU / 4 GB / 120 GB NVMe / 4 TB transfer**, US
  region. Took NVMe + the larger disk over the $24 Regular SSD tier: Postgres is I/O-sensitive, and
  disk is what grows (MinIO media) — DO disk resizes are the one change that is *not* reversible.
  Note the $24 row in DO's *Premium* list is only **2 GB** — not the same as the $24 Regular 4 GB
  tier the earlier docs cited. Everyone is US-based, and EU hosting's ~90–120ms
  hurts *media upload/download* specifically (chat send/receive is imperceptible). 4 GB is ~3x the
  estimated ~1.2 GB steady state for "just chat"; DO's CPU/RAM resize is reversible, so starting
  small is low-risk.
- **Hetzner is no longer the pick.** Their **15 June 2026** increase raised CPX/CCX ~2.4–3x: CPX31 is
  now ~$74/mo in the US (dead) and ~$42 in Nuremberg. US locations only offer CPX/CCX, so there's no
  cheap Hetzner-US option at all. The surviving value play is **CAX21 (Arm, 4 vCPU / 8 GB, ~$12/mo)**
  — but it's **EU-only** (Nuremberg/Falkenstein/Helsinki). Reconsider it if the group ever goes EU.
- **The stack is fully multi-arch**, so Arm hosts need *no* `compose.yml` changes: `block/buzz:main`
  publishes `amd64`+`arm64` (verified against the GHCR manifest), as do `postgres:17-alpine`,
  `redis:7-alpine`, `minio`, `caddy:2-alpine`.
- **Clone over HTTPS on the VM, not SSH.** `mpimenta8/rphaf` is **public** and the VM only ever
  *reads* (`git pull` for `./run.sh upgrade`), so HTTPS needs no credentials — whereas an SSH key on
  an internet-facing host could push to the repo. Protocol is per-clone, so this is independent of
  the laptop's SSH origin. If the repo ever goes private, use a **read-only deploy key**, not a
  normal SSH key.
- **Rejected: hosting on a friend's Raspberry Pi / Pi-hole box.** Not for lack of specs (a Pi 4/5
  clears the ~1.2 GB need, and the stack is arm64) but because: SD cards fail under Postgres/MinIO
  write load (needs a real SSD), and co-locating with Pi-hole means a relay overload takes down
  *household DNS*. The residential blockers (dynamic IP, CGNAT, ISP-blocked :80/:443, uptime) apply
  on top. A *dedicated* Pi + SSD + tunnel is a legitimate later migration target.
- **On a 4 GB box: add 2 GB swap** (cloud VMs ship with none; see `PROVISIONING.md` §3b). Optionally
  cap Redis — it's started with no `maxmemory`, though Buzz only stores *expiring* keys there
  (presence, rate limits, NIP-98 replay), so `volatile-lru` is the safe policy if you bother.

### The tooling already exists — `deploy/compose/`
- `compose.yml` (`name: buzz-prod`) — **relay** (`ghcr.io/block/buzz:main`) + **postgres:17** +
  **redis:7** + **minio** (media). Relay ports: 3000 (WS+HTTP), 8080 (health), 9102 (metrics).
- `compose.caddy.yml` + `Caddyfile` — Caddy reverse-proxy with automatic Let's Encrypt TLS for
  `$BUZZ_DOMAIN`; enable with `BUZZ_COMPOSE_TLS=true` (drops the direct relay port via `!reset`).
- `run.sh` — wrapper: `start | stop | restart | pull | upgrade | logs | status | config |
  backup-hint | add-member | remove-member | list-members`. `require_env` refuses to boot with
  `CHANGE_ME` placeholders left in `.env`.
- `.env.example` — copy to `.env`, replace every `CHANGE_ME`. **`.env` is gitignored — never commit
  real secrets.**
- `gen-env.sh` — bootstraps `.env` (secrets + toggles + owner/domain). `backup.sh` — nightly backup.
- **`PLANNING.md`** — pre-deploy decisions: owner-key guide + host-options matrix/recommendation.
- **`PROVISIONING.md`** — step-by-step: bare Ubuntu VM → hardening → Docker → ufw → deploy → backup
  cron → restore drill.

### Key facts / decisions
- **A fresh `deploy/compose` install was broken until upstream `5e2e132a4` (merged 2026-07-25).**
  The relay crash-looped under `restart: unless-stopped` with
  `BUZZ_GIT_PACK_CACHE_PATH=/data/git/.pack-cache could not be created: Permission denied`: Docker
  only seeds a volume mount point's ownership from the image if that path already exists there, so
  `/data/git` was created `root:root` while the image runs as `buzz:buzz`. **The fix ships in the
  image, not our repo** — confirmed live in `ghcr.io/block/buzz:main` at revision `499c5d349`. If
  that error ever appears, the image is stale: `./run.sh pull`.
- **The relay image is stock upstream (`ghcr.io/block/buzz:main`) — our fork changes nothing on the
  server.** The whole "just chat" strip-down is *desktop-client* code. So: run the stock relay image,
  and distribute our custom desktop build to friends. No custom relay image to build/publish.
- **Closed relay = you own it.** Prod `.env` sets `BUZZ_REQUIRE_AUTH_TOKEN=true` +
  `BUZZ_REQUIRE_RELAY_MEMBERSHIP=true` and needs `RELAY_OWNER_PUBKEY` = your 64-hex Nostr pubkey
  (the desktop identity pubkey). Friends join via `./run.sh add-member <npub-or-hex>` (add `sleep 1`
  between multiple adds; no parallel adds — same-second timestamp collisions in the roster event).
- **Importing an existing `nsec` on desktop is only reachable via the "membership denied" screen**
  (`importExistingKey` is wired solely to `MembershipDenied`, see `OnboardingFlow.tsx:437`). Normal
  onboarding always mints a *fresh* key. So the real first-connect flow to a closed relay is:
  app generates key B → relay rejects it → the denial screen offers a "paste your nsec1…" form →
  import key A → you're the owner. The "you'll lock yourself out" warning in `PLANNING.md` is
  therefore recoverable in practice, **provided `RELAY_OWNER_PUBKEY` is correct before first boot.**
- **Secrets to generate once and keep stable** (regenerating = broken identity/data): every value on
  the target VM with e.g. `openssl rand -hex 32` — `BUZZ_RELAY_PRIVATE_KEY` (the relay's own Nostr
  key), `BUZZ_GIT_HOOK_HMAC_SECRET`, `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `BUZZ_S3_ACCESS_KEY`,
  `BUZZ_S3_SECRET_KEY`. (`TYPESENSE_API_KEY` in `.env.example` is vestigial — search uses Postgres
  FTS; set any random value.) Generate secrets **on the VM**, don't paste them around.
- **Our strip-down relay toggles belong in this `.env` too:** `BUZZ_HUDDLE_AUDIO_AVAILABLE=false`,
  `BUZZ_SERVE_GIT_WEB_GUI=false`.
- **Migrations:** prod `compose.yml` defaults `BUZZ_AUTO_MIGRATE=false`, but `.env.example` sets it
  `true` for first-boot bootstrap of a fresh DB. Alternative: run `buzz-admin migrate` explicitly.
- Domain settings in `.env`: `BUZZ_DOMAIN`, `RELAY_URL=wss://<domain>`, `BUZZ_MEDIA_BASE_URL`,
  `BUZZ_MEDIA_SERVER_DOMAIN`, `BUZZ_CORS_ORIGINS`. Friends connect the desktop app to `RELAY_URL`.

### Deploy recipe
```bash
# on a VM with Docker + Docker Compose v2.24.4+, DNS A-record -> VM IP:
cd deploy/compose
./gen-env.sh --domain jean.rphaf.io --owner 6a68bbc04fad286751cb73a699ca9428dfe038399e60653428a0864f19c05b2f
#   ^ generates .env: fills all secrets (openssl), sets domain/owner + our
#     strip-down toggles. Run on the VM. Without flags it leaves owner/domain
#     as CHANGE_ME. `run.sh` refuses to boot while any CHANGE_ME remains.
BUZZ_COMPOSE_TLS=true ./run.sh start
./run.sh add-member <your-npub> --role admin
./run.sh add-member <friend-npub>
./run.sh status && ./run.sh backup-hint
```

### Backups (day one, non-negotiable)
`deploy/compose/backup.sh` does it: `pg_dump` + MinIO/git volume tars + `.env` snapshot + local
rotation + optional offsite via rclone (`BACKUP_RCLONE_REMOTE`, e.g. in a gitignored `backup.env`).
Schedule it nightly via cron. A local-only backup dies with the VM — **set the offsite target.**
`./run.sh backup-hint` prints the full checklist. **A backup you haven't restore-tested isn't a
backup** — do the restore drill once (see `PROVISIONING.md` §7).

### Managed-Postgres later (the escape hatch)
Point `DATABASE_URL` at a managed DB and delete the `postgres` service + its `depends_on` in
`compose.yml`. The relay VM becomes stateless/disposable; backups + PITR become the provider's job.

## Key references

- `CLAUDE.md` / `CONTRIBUTING.md` — contributor + agent guide, quality gates (`just ci`).
- `ARCHITECTURE.md`, `NOSTR.md` — system design + the event model.
- Event kinds: `crates/buzz-core/src/kind.rs`. Desktop features: `desktop/src/features/`.
