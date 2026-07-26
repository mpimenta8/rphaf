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
- **The README merge driver is set by `just setup`** (`scripts/dev-setup.sh`, beside the
  `core.hooksPath` line) — no longer a manual step. `.gitattributes` marks `README.md merge=ours`
  so upstream merges keep our rewritten README, but the driver config lives in `.git/config` and
  isn't cloned. If you ever skip `just setup`, set it by hand:
  `git config merge.ours.driver true`. Without it, merges touching the README conflict instead —
  noisy, not dangerous. Note the driver discards upstream README changes *silently*;
  `git diff HEAD upstream/main -- README.md` shows what we're skipping.
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
- **Also check what the README driver swallowed:** `git diff HEAD upstream/main -- README.md`.
  `merge=ours` keeps our README with no conflict and no notice, so this is the only way upstream's
  README changes ever surface. Do it as part of the merge, not "occasionally" — otherwise never.
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

- **`Desktop Build (macOS)` fails on our fork, on `main`, and always has** — it dies fetching the
  `mesh-llm` git dependency (`mesh-llm checkout for 43103c5 not found after cargo fetch`). Same for
  the Block-internal publish/build jobs. **Not caused by your PR.** Judge a PR by the jobs that
  actually exercise it (Desktop Core, Desktop E2E, Smoke E2E) plus a local `just ci`.
- **No shell script is linted anywhere** — no shellcheck in the Justfile, lefthook, or the
  workflows, and `just ci` never runs `scripts/dev-setup.sh`. Changes to shell scripts need
  hand-verification (`bash -n`, then actually run the changed lines); CI will not catch them.

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
- **Brand pass — docs only, MERGED to `main`** 2026-07-25 as `59e2f3068`
  (squash of **[PR #2](https://github.com/mpimenta8/rphaf/pull/2)** — the 14 individual commits and
  their reasoning live on the PR page, not in `git log`), `just ci` green
  (`docs/superpowers/specs/2026-07-25-rphaf-brand-pass-design.md`, `…/plans/…`). Product noun is
  plain **`rphaf`** (no second brand), emoji **🪨** replaces 🐝, README tagline **"Rocpile Hard AF"**.
  Contains: `IDENTITY.md` (the vocabulary anchor — rphaf/rocpile/boysch, the 🪨 rule, tone; the **only**
  place the full phrase is spelled out), `ROADMAP.md` (deferred tiers + self-hosting), README rewritten
  267 → 132 lines, and the `merge=ours` protection above. Scope was documentation only — **no code, no
  app strings, no relay config.**
  - Standing constraint for anything outward-facing: **nothing may claim a feature that's gated off or
    a relay that isn't running.** The README's "Not live yet" marker stays until the relay is up.
  - New prose — docs, UI copy, commit messages — follows `IDENTITY.md`. Code keeps its `buzz` names.
  - *Get in* points at the **`#rphaf-dev` Slack channel** for both relay status and sending your
    npub — deliberately a channel, not a person, so onboarding doesn't route through one human.
  - Remaining gap: it tells friends the desktop app comes "from this repo" — see the build item below.
- **Ship a packaged desktop build — blocks inviting anyone.** The README's *Get in* path assumes a
  build exists; today each friend would have to compile it themselves, which is a non-starter for
  non-developers. **Planned right after the DigitalOcean VM is up.** Upstream's own release flow is in
  `RELEASING.md`; ours needs to produce our gated ("just chat") desktop build, not the stock one.
- **Rebrand** (deeper tiers, beyond the docs pass) Buzz → rphaf — **[`ROADMAP.md`](ROADMAP.md) is
  canonical**; this is the short version. Tiered: (1) cosmetic strings + relay NIP-11 name
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
- **Relay hostname: `jean.rphaf.io` — settled** (2026-07-25, commit `5cf28ad01`). The brand pass
  briefly reopened this as `boysch.` vs `jean.`; it's closed, and `deploy/compose/*` is written
  against `jean`. Treat it as fixed: it's baked into the A record, the TLS cert, five `.env` values
  (`BUZZ_DOMAIN`, `RELAY_URL`, `BUZZ_MEDIA_BASE_URL`, `BUZZ_MEDIA_SERVER_DOMAIN`,
  `BUZZ_CORS_ORIGINS`), and every client's stored relay URL. Changing it later means a new record, a
  re-issued cert, re-pointing everyone, **and breaking every historical image/video** — media URLs
  are absolute and embedded in immutable events. If it ever must change, keep the old name resolving
  and serve both from Caddy.
- **DNS is AWS Route 53**, verified via `dig NS rphaf.io` — no Cloudflare proxy layer, so the
  grey-cloud/proxy caveat doesn't apply. Request a plain A record. **IPv4 only at first:** Let's
  Encrypt prefers IPv6 when an AAAA record exists, so an unverified IPv6 path fails cert issuance
  while everything looks healthy over IPv4.
- **⚠️ HOST CHANGED 2026-07-25 (late): moving to AWS EC2, in a friend's *personal* account.** He has
  a pile of **AWS credits to burn**, wants hands-on AWS practice, and Matt gets day-job value from
  the same — plus it consolidates with Route 53, which already hosts `rphaf.io`. Credits were the
  explicit tipping point: without them AWS costs *more* than DO (metered egress vs DO's included
  4 TB) and the call was the other way. Ownership/admin dilution is a **non-issue** here: 15+ year
  friendship, former roommates.
  **Live as of 2026-07-25:** instance `rphaf-relay`, `t4g.medium` (ARM Graviton, 2 vCPU / 4 GB),
  **Ubuntu 26.04 LTS** (the AMI default has moved past 24.04 — docs should say "24.04 LTS or newer"
  rather than pinning), 120 GB `gp3` **encrypted** with the default `aws/ebs` key, `us-east-1`.
  SG `rphaf-relay-sg`: 22 = My IP, 80 + 443 = `0.0.0.0/0` (both *must* be world-open — Let's Encrypt
  validates from unpredictable IPs and friends connect from anywhere). Key pair imported as
  `rphaf-navi`. **Elastic IP: `34.224.118.116`.** Start at `medium` — resizing to `large` is
  stop → change instance type → start, with EBS and the EIP surviving intact.
  - **Encrypt the EBS volume at launch** — you *cannot* encrypt in place later (it's
    snapshot → copy-with-encryption → swap volumes). Free, and snapshots inherit it.
  - Set **`Delete on termination: No`** and enable **Termination protection**: both free, and they
    turn a misclick from "restore everything from backup" into a non-event.
- **AWS gotchas (the reason this isn't just "same steps, new provider"):**
  - **An Elastic IP is mandatory.** EC2's auto-assigned public IP **changes on every stop/start**,
    which would silently break DNS + TLS for everyone. It's also what makes resizing safe, since a
    resize *requires* a stop/start. Free while attached. The **EIP** is what goes in the A record.
  - **The Arm architecture selector hides `t4g.*`.** The AMI card defaults to 64-bit x86; switch it
    to **64-bit (Arm)** *before* picking the instance type or `t4g` won't appear at all. Arm is fine
    — the whole stack is multi-arch (verified).
  - **Security Group is *in addition to* `ufw`, not instead of.** If the SG blocks 80/443, Caddy
    can't complete an ACME challenge and you'll debug a firewall you forgot existed.
  - **Login user is `ubuntu`, not `root`** — and **§2's user creation should be skipped entirely on
    AWS.** Canonical's AMI already ships exactly what §2 builds by hand: a non-root sudo user with
    key-only SSH, root login disabled, password auth disabled. Adding a `buzz` user buys no security
    and re-takes the lockout risk for nothing. `PROVISIONING.md` uses `$USER` downstream, so
    `ubuntu` works throughout.
  - **`get.docker.com` keys off the release codename** and can lag a brand-new Ubuntu. If §4 fails
    on 26.04, fall back to the previous LTS codename or Ubuntu's own `docker.io` +
    `docker-compose-v2` packages.
  - `t4g` is **burstable** (CPU credits, "unlimited" mode on by default) — irrelevant for an idle
    chat relay, but it's where surprise CPU charges would come from. Set a **billing alarm anyway**,
    so credits running out arrives as an alert rather than an invoice.
- **The DO droplet stays alive until the relay is verified on EC2**, then gets cancelled before the
  next billing date — it's the rollback. For reference it was `rphaf-ubuntu-nyc3`, NYC3, Ubuntu
  24.04, IPv4 `68.183.145.188`, $32/mo, and it reached: `buzz` user (sudo, key-only SSH),
  `PermitRootLogin no` + `PasswordAuthentication no` (both verified via `sudo sshd -T`), `ufw` active
  with default-deny and only 22/80/443 open (v4 **and** v6), 2 GB swap at `vm.swappiness=10`, Docker
  Compose **v5.3.1**. Idle footprint ~474 MB of 3.8 GB — comfortably under the ~1.2 GB estimate,
  which is the datapoint that says 4 GB is right-sized. **None of that work is wasted:**
  `PROVISIONING.md` §2–§4 are provider-agnostic and port to EC2 nearly unchanged.
- **`PROVISIONING.md` is now AWS-first (done 2026-07-26).** §0–§2 rewritten for EC2; DO kept as
  collapsed `<details>` fallbacks rather than deleted, since it's still the rollback until the
  droplet is cancelled. Corrections worth knowing: **§0 is self-serve** (Route 53 is in the account
  we can reach — the old "message to send the domain owner" framing was wrong and cost a
  round-trip); **§2 is explicitly a no-op on AWS** and now says so in its heading, because it used to
  walk you through an SSH-lockout risk to reach a state Canonical's AMI already ships. New §3c
  (Redis `vm.overcommit_memory`) and the `get.docker.com` codename-lag fallback in §4 were
  hard-won knowledge that had only ever lived in this file.
- **`PLANNING.md` still recommends DigitalOcean** — the last doc pending the AWS rewrite. Its
  owner-key guidance (Part 1) is still correct and referenced from `PROVISIONING.md`; it's the
  host-options matrix that's stale.
- **SSH hardening gotchas, learned the hard way:**
  - **Verify every step with `sudo sshd -T`, never trust the edit.** A `sed` on
    `/etc/ssh/sshd_config` silently left `PermitRootLogin yes` in place while we assumed it applied.
    `sshd -T` prints the *effective* config and is the only real check. Note it needs `sudo` —
    unprivileged it dies on `/etc/ssh/sshd_config.d/50-cloud-init.conf: Permission denied`.
  - **Cloud-init already sets `PasswordAuthentication no`** (in that `50-cloud-init.conf`) when the
    VM is created with an SSH key — so that one was never actually our doing. True on DO; Canonical's
    AWS AMI goes further and disables root login too.
  - **`sudo sshd -t` before every `systemctl restart ssh`**; keep a second session open until a
    third one verifies. A config typo takes the daemon down with no way back in.
  - **Audit `authorized_keys` — every line is a passwordless path to root.** Started with 2 keys;
    pruned an ECDSA key belonging to a **work-issued Mac** (IT holds admin/MDM/remote-wipe on it, and
    it goes back if the job ends). Only the `navi` ed25519 remains — imported into EC2 as the
    `rphaf-navi` key pair. Also remove retired keys from the **provider account**, or they get
    re-injected into every future VM.
  **DNS: DONE 2026-07-25.** `jean.rphaf.io` → **`34.224.118.116`**, confirmed on both the
  authoritative nameserver and a public resolver. The record had originally been created against the
  DigitalOcean IP before the AWS pivot and needed only its *value* edited. **Route 53 is in the same
  AWS account we have access to, so this is self-serve** — Route 53 → Hosted zones → `rphaf.io` →
  **tick the record's checkbox** (clicking the record *name* doesn't reveal "Edit record", which is
  what made it look like we lacked permission) → Edit record → change Value. The 300 s TTL made the
  correction land in minutes; a default 24 h TTL would have cost a day. Verify with
  `dig +short jean.rphaf.io @ns-886.awsdns-46.net` (authoritative, instant) vs `@1.1.1.1` (what the
  world — and Let's Encrypt — sees). **Never `./run.sh start` before the public resolver agrees**:
  Caddy fails the ACME challenge against the wrong host and can burn per-domain rate limits that take
  hours to reset.
  **EC2 hardening done:** `ufw` active, default-deny incoming, only 22/80/443 (v4 **and** v6); 2 GB
  swap; Docker Compose **v5.3.1** installed and usable without `sudo`. Idle at ~485 MB of 3.7 GB —
  same as the DO box, confirming 4 GB is right-sized. **Ubuntu 26.04 was a non-event** —
  `get.docker.com` supported it, so the codename-lag worry didn't materialise. **SSH verified via
  `sudo sshd -T`: `permitrootlogin no`, `passwordauthentication no`.** Hardening is complete —
  §2/§3/§3b/§4 all done and confirmed.
- **🎉 THE RELAY IS LIVE (2026-07-25).** `https://jean.rphaf.io/_liveness` returns `ok` over a valid
  Let's Encrypt cert (`CN=jean.rphaf.io`, valid to 2026-10-23) — **verified from the public
  internet**, not just from the box. All six containers came up healthy on the first
  `BUZZ_COMPOSE_TLS=true ./run.sh start`. Full AWS write-up: [`docs/aws-deployment.md`](docs/aws-deployment.md).
  - **The `/data/git` permission bug did NOT occur** — confirming the upstream fix really does ship
    in `ghcr.io/block/buzz:main`, as the GHCR revision check predicted.
  - **You do not need to add yourself as a member.** The relay auto-provisions `RELAY_OWNER_PUBKEY`
    at first boot with role **`owner`** (which outranks `admin`); `add-member` on your own npub
    correctly no-ops with "already a member". `list-members` shows `added_by: -` for that row.
  - **Ignore a `grep CHANGE_ME .env` hit on line 2** — it's a *comment* in the template
    (`# Copy to .env and replace every CHANGE_ME value…`). `gen-env.sh`'s own check requires
    `KEY=…CHANGE_ME` and is the authoritative one; trust its "No placeholders left".
  **Next:** nightly offsite backups (§6 — the last non-negotiable), a restore drill (§7), a billing
  alarm, cancelling the DO droplet, and `sudo sshd -T` verification on EC2.
- **⚠️ `BUZZ_COMPOSE_TLS=true` belongs on EVERY `run.sh` invocation that touches containers** —
  `restart`, `stop`, `upgrade`, not just `start`. Without it Compose loads only the base file, which
  **excludes Caddy**: you get `WARN Found orphan containers (buzz-prod-caddy-1)`, only 5 of 6
  containers are managed, and Caddy drifts outside the project. It keeps serving (so TLS looks
  fine), but the next `upgrade` skips it and anything with `--remove-orphans` deletes it — taking
  HTTPS down. Reconcile with `BUZZ_COMPOSE_TLS=true ./run.sh restart`.
- **✅ Desktop client connects (2026-07-25).** After the CORS fix the relay logs show the owner
  pubkey authenticating, `/query` + `/events` returning 200, events ingesting, and a live WebSocket
  (`conn_id`, `ws.event` spans). **Fixing CORS alone was enough** — no client change needed. Note the
  first attempt after the server fix still failed: the app had been running since *before* it, and
  webviews cache CORS preflights, so **quit and relaunch the app** after any CORS change.
- **Log noise that is NOT a problem — don't chase these:**
  - **Postgres `ERROR: partition "events_p2026_07" would overlap partition "events_p_future"`**
    (repeats for several months, both `events` and `delivery_log`). **Handled by design:**
    `crates/buzz-db/src/partition.rs:137` catches SQLSTATE `42P17` and treats it as "already
    ensured", because the fresh schema ships a catch-all `*_p_future` covering `2026-07-01 →
    MAXVALUE` (`migrations/0001_initial_schema.sql:251`). Postgres logs the rejected statement;
    the app carries on. Only long-term effect: monthly partitions never get created, so it's one
    big partition — irrelevant at our volume.
  - **NIP-29 `PUT_USER` for pubkeys that aren't ours** — those are *channel* members, not *relay*
    members. `./run.sh list-members` confirmed the roster is still only the owner, and only relay
    members can connect. Don't confuse the two.
- **Redis wanted `vm.overcommit_memory=1`** (fork-for-snapshot can fail without it on a small box).
  Applied via `sudo sysctl vm.overcommit_memory=1` + `/etc/sysctl.d/99-redis-overcommit.conf`.
  Worth doing on any new host.
- **`./run.sh logs` follows the stream** (`docker compose logs -f`) — `--tail N` only sets the
  starting point, so it never exits. For a snapshot use
  `docker compose --env-file .env -f compose.yml logs --tail 50 relay` and name a service; the
  unscoped form interleaves all six containers.
- **CORS bug — fixed 2026-07-25 (commit `07455b291`), worth understanding.** `gen-env.sh` set
  `BUZZ_CORS_ORIGINS` to the relay domain only, but the desktop app's webview origin is
  `tauri://localhost` (macOS/Linux) / `http://tauri.localhost` (Windows). The relay then returned no
  `access-control-allow-origin`, so **every** desktop client — the official upstream build
  included — failed with `Community rejected: Load failed`. **That string is a *transport* failure,
  not a membership rejection**; a real denial names your pubkey. Verified fixed: the relay now
  returns `access-control-allow-origin: tauri://localhost`. Upstream's `.env.example` has the same
  gap — **worth a PR to `block/buzz`**.
  - Lesson on risk attribution: this lived in **our deploy tooling**, not the client fork. The fork
    only hides UI via preview flags ("No Rust/server edits") and cannot cause connection failures.
    Using upstream client builds would not have prevented it. Deploy-tooling bugs are the real
    bespoke surface — and they're front-loaded, surfacing loudly during setup.
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
rotation + offsite via rclone (`BACKUP_RCLONE_REMOTE`, in a gitignored `backup.env`).
Schedule it nightly via cron. A local-only backup dies with the VM — **set the offsite target.**
`./run.sh backup-hint` prints the full checklist. **A backup you haven't restore-tested isn't a
backup** — do the restore drill once (see `PROVISIONING.md` §7).

**Offsite target: S3 in Matt's OWN AWS account — settled 2026-07-25.** Full runbook is
`PROVISIONING.md` §6. Backblaze B2 was considered and rejected. The reasoning, so nobody reopens it:
- **S3 over B2 — because of egress, not credits.** `backup.sh` ships a **full** backup nightly (fresh
  timestamped prefix, never incremental). EC2 → S3 **same-region is free**; any other provider meters
  that egress and the bill grows with the media volume. At ~$1–2/mo the credits argument that drove
  the relay to AWS is *irrelevant* here — this was decided on egress and credential handling.
- **A separate account from the relay — this is the important half.** The relay lives in a friend's
  personal account on **expiring credits**; `docs/threat-model.md` notes credits running out arrives
  as an outage, not a warning. Same-account backups die with that account (suspension, closure,
  falling-out) — the exact failure offsite backups exist to survive. Ownership dilution is a non-issue
  for the relay (MEMORY says so above) but backups are the exception: they must outlive it.
- **Instance role, no stored key.** rclone `env_auth = true` reads EC2 instance metadata, so **no
  credential is ever written to the relay host** — strictly better than B2's keyID/applicationKey in
  `backup.env`. Cross-account needs **both** the role's identity policy *and* the bucket policy;
  granting one silently `AccessDenied`s.
- **The role gets no `s3:DeleteObject`.** Nightly runs write to fresh prefixes, so `rclone copy`
  never deletes — a compromised relay host cannot destroy backup history. **Offsite retention is a
  bucket lifecycle rule** in Matt's account; `KEEP_DAYS` in `backup.env` prunes only the local copy.
  Don't "fix" the script by adding offsite pruning — that's the property, not a gap.
- **Bucket must be `us-east-1`** (relay's region). Same-region transfer is free *across accounts*;
  elsewhere silently reintroduces metered transfer. Also set *Bucket owner enforced* so cross-account
  writes are owned by the bucket owner — otherwise you can't read your own backups.
- SSE-S3 at rest covers the `.env` snapshot without an rclone-`crypt` passphrase, which would
  otherwise have to live off-box or be lost with the VM it protects.

**§6a DONE (2026-07-26).** Bucket **`rphaf-backup-bucket`** exists in Matt's own account,
`us-east-1`, versioned, SSE-S3, with three lifecycle rules verified via
`aws s3api get-bucket-lifecycle-configuration`: `expire-dailies` (`relay/daily/`, 30d),
`expire-monthlies` (`relay/monthly/`, 365d), both with `NoncurrentVersionExpiration: 7`, plus
`clean-delete-markers` (`relay/`, `ExpiredObjectDeleteMarker`).
- **The trap that nearly shipped:** on a *versioned* bucket, `Expiration` alone deletes **nothing** —
  it inserts a delete marker and the bytes live on as a noncurrent version, billed forever. Only
  `NoncurrentVersionExpiration` reclaims them, and the console's rule builder happily saves the first
  without the second. Fails safe for data, silently defeats the cost ceiling. **Set lifecycle rules
  via `put-bucket-lifecycle-configuration` (CloudShell), not by clicking**, and verify with the
  `get-` call — the runbook now does both.
- `ExpiredObjectDeleteMarker` cannot share an `Expiration` block with `Days`; it needs its own rule.
- **rclone needs `no_check_bucket = true` against this least-privilege role.** Before uploading it
  verifies the bucket exists and **tries to create it** on failure; with no `s3:CreateBucket` every
  upload dies `AccessDenied … s3:CreateBucket` *before* reaching `PutObject`. `rclone lsd` keeps
  succeeding throughout, because listing never triggers the check — so **`lsd` alone is a false
  green light**, and only a probe upload proves the path. Don't grant `CreateBucket` to fix it.
- **Retention is two-tier on purpose.** A flat 30 days only answers loud failures (dead VM, deleted
  channel). Damage noticed on day 37 would already be in every surviving backup — hence the 12-month
  `monthly/` tail. `backup.sh` picks the tier by "no monthly exists for this year-month yet" rather
  than "today is the 1st", so a failed run on the 1st doesn't cost the month's restore point.
- Cost ≈ `(30 + 12) × nightly-size × $0.023/GB`. **These are full backups, not incrementals**, so
  cost scales with retention × dataset — revisit if shared media reaches tens of GB.

**AWS access model (as of 2026-07-26) — read before attempting §6.**
- Matt's access to the relay's account is an **IAM user the friend created**, not root and not his
  own account. Console top-right shows `<username> @ <account-alias-or-ID>` (a root login would show
  an email there instead). **That 12-digit number is the `<RELAY_ACCOUNT_ID>`** §6c's bucket policy
  needs — it's readable straight off the console, no need to ask for it.
- **Matt already has his own AWS account** (created before the friend's invite, root login = his own
  email). So §6a is **unblocked** — no account creation needed. The two accounts are entirely
  separate: being invited into the friend's did not link or nest them, and **AWS offers no built-in
  switching**. Different sign-in URLs (generic console → root/own; `https://<account-id>.signin.aws.
  amazon.com/console` → IAM user/friend's), and the wrong door reads as "locked out of my own
  account". Set an **account alias** on each so the console top-right names the account instead of
  showing a bare 12-digit number — cheapest guard against acting in the wrong one.
- **Likely blocker: an IAM user often can't create IAM roles**, which §6b requires in the *friend's*
  account. Check early via IAM → Roles → Create role; if unauthorized, the friend either attaches
  `IAMFullAccess` or creates the role himself from §6b's JSON. Everything else in §6 (bucket,
  lifecycle, bucket policy) is entirely in Matt's own account and unblocked.
- **The console holds one identity per browser**, so signing into one account silently signs you out
  of the other — surfacing as confusing `AccessDenied`s mid-task. §6 alternates accounts four times;
  set up two browser profiles first. Sign-in URLs differ too: the IAM user needs
  `https://<account-id>.signin.aws.amazon.com/console`, not the generic console URL.

**`backup.sh` hardening (same change):** `BACKUP_ALERT_CMD` fires once on failure (an EXIT trap
catches aborts that bypass `die`; a `REPORTED` flag prevents double-reporting); `tar` exit 1 (files
changed mid-archive) is a warning while 2+ is fatal, instead of the old blanket `|| log "skipped"`
that let a failed media archive report success; a `LAST_SUCCESS` marker in `BACKUP_DIR` lets you
detect a run that *never happened* (broken crontab), which alerting alone can't. Remember **no shell
script is linted anywhere** — these were hand-verified by running every failure path.

### Managed-Postgres later (the escape hatch)
Point `DATABASE_URL` at a managed DB and delete the `postgres` service + its `depends_on` in
`compose.yml`. The relay VM becomes stateless/disposable; backups + PITR become the provider's job.

## Getting the app to friends (builds + signing)

**Full write-up: [`docs/distribution.md`](docs/distribution.md).** The need-to-know:

- **⭐ Upstream publishes public, installable builds — daily.** `gh release list --repo block/buzz`
  shows `Buzz Desktop v0.4.26` etc. with `.dmg` (aarch64 + x64), `.deb`, `.AppImage`, and a Windows
  `.exe` marked `alpha-unsigned` (implying the macOS DMGs *are* signed). **Since our relay is stock
  upstream, the official app connects to `jean.rphaf.io` fine** — the fork's only differentiator is
  which features are visible. So the pragmatic path is: friends install the **official signed
  build** (no Gatekeeper dance, no $99, auto-updates), and we keep the fork for branding + gating.
  Switching later is free and per-person: same relay, same keys, same data.
- **Our local build works but the DMG step doesn't.** `just desktop-release-build` produced a valid
  `Buzz.app` (Apple Silicon, ~133 MB) in ~3 min, then failed on `bundle_dmg.sh` — that step drives
  Finder via AppleScript and dies in a non-interactive shell. The `.app` is complete and runnable;
  retry the DMG from an interactive terminal if you need one. Confirmed the sidecar stubs are 0-byte
  as designed.
- **We build and distribute ourselves.** `just release-desktop` triggers `release.yml` in
  `block/buzz`, which signs with *Block's* Apple credentials — closed to a fork. Ours is
  `just desktop-release-build` (already labelled "unsigned, for testing"; note it stubs the
  sidecar binaries, which is fine only while agents stay gated off).
- **Decision: desktop-first, unsigned.** macOS/Windows cost the friend one click-through;
  Linux and Android are clean and free.
- **Device mix: Matt is on iPhone, most of the crew is on Android.** Android is the cleanest free
  path, so the majority costs nothing — but iOS is a *near-term* question, not one we can defer
  indefinitely. For **Matt's own device** there is a free path (Xcode + free Apple ID sideload;
  SideStore automates the 7-day re-signing), which is enough to test from iOS. The $99 only becomes
  unavoidable when a *second* iPhone needs in.
- **iPhone is the only hard paywall** — no free path that survives past 7 days. The $99/yr Apple
  Developer Program covers **both** Apple platforms (macOS notarization *and* TestFlight), and is
  the only item in the project with an external queue.
- **Mobile has NO feature gating** (verified: zero flag references in `mobile/lib`), so shipping
  Flutter as-is exposes the full Buzz surface on phones while desktop hides it.
- Signing is **downstream of everything** — `just dev` tests the relay fine without it.

## Key references

- `CLAUDE.md` / `CONTRIBUTING.md` — contributor + agent guide, quality gates (`just ci`).
- `ARCHITECTURE.md`, `NOSTR.md` — system design + the event model.
- Event kinds: `crates/buzz-core/src/kind.rs`. Desktop features: `desktop/src/features/`.
