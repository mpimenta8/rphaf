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
- **Keep upstream merges clean:** prefer changes that don't rewrite shared server/Rust files.

### Pushing (use SSH, not HTTPS)
- `origin` is an **SSH** URL. If it ever reverts to HTTPS, pushes that touch `.github/workflows/*`
  get **rejected** — a GitHub `gh` OAuth token lacks the `workflow` scope, and workflow-file changes
  arrive routinely via upstream merges. SSH is not subject to that restriction, so we push over SSH.
- Fix if you hit it: `git remote set-url origin git@github.com:mpimenta8/rphaf.git` (or, to stay on
  HTTPS, `gh auth refresh -s workflow`).
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
- **Rebrand** Buzz → rphaf/rocpile, tiered: (1) cosmetic strings + relay NIP-11 name
  (`buzz-relay/src/nip11.rs`), (2) app identity (`tauri.conf.json` productName/identifier/deep-link
  scheme, mobile bundle IDs, icons), (3) internal `buzz-*` crate names / `BUZZ_*` env / storage keys
  (~1,200 files, high-churn — abandons clean upstream merges; do last if ever).
- **Self-host the relay:** see the dedicated section below. Add friends as collaborators on
  `mpimenta8/rphaf` for the *code*; add them as relay *members* separately (`./run.sh add-member`).

## Self-hosting the relay

**Vision: start all-in-one, add automated backups on day one.** One small VM ($6–12/mo, 2GB RAM is
plenty for a friend group) runs the whole stack via Docker Compose; a nightly `pg_dump` offsite
closes the only scary failure mode (losing the DB) for ~$0. Move Postgres to a managed DB *later*
only if the data's value warrants it — it's a one-line `DATABASE_URL` swap, not a rebuild.

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

### Key facts / decisions
- **The relay image is stock upstream (`ghcr.io/block/buzz:main`) — our fork changes nothing on the
  server.** The whole "just chat" strip-down is *desktop-client* code. So: run the stock relay image,
  and distribute our custom desktop build to friends. No custom relay image to build/publish.
- **Closed relay = you own it.** Prod `.env` sets `BUZZ_REQUIRE_AUTH_TOKEN=true` +
  `BUZZ_REQUIRE_RELAY_MEMBERSHIP=true` and needs `RELAY_OWNER_PUBKEY` = your 64-hex Nostr pubkey
  (the desktop identity pubkey). Friends join via `./run.sh add-member <npub-or-hex>` (add `sleep 1`
  between multiple adds; no parallel adds — same-second timestamp collisions in the roster event).
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
./gen-env.sh --domain chat.yourdomain.com --owner <your-64-hex-pubkey>
#   ^ generates .env: fills all secrets (openssl), sets domain/owner + our
#     strip-down toggles. Run on the VM. Without flags it leaves owner/domain
#     as CHANGE_ME. `run.sh` refuses to boot while any CHANGE_ME remains.
BUZZ_COMPOSE_TLS=true ./run.sh start
./run.sh add-member <your-npub> --role admin
./run.sh add-member <friend-npub>
./run.sh status && ./run.sh backup-hint
```

### Backups (day one, non-negotiable)
`./run.sh backup-hint` lists everything: `.env` secrets (esp. `BUZZ_RELAY_PRIVATE_KEY`), the Postgres
data (`pg_dump`), MinIO/S3 bucket, the `buzz-git-data` volume, and Caddy volumes — **snapshot
Postgres + object/git state from the same window.** Minimum viable: a nightly cron `pg_dump` piped to
offsite object storage. That single job defuses the "VM disk died" catastrophe.

### Managed-Postgres later (the escape hatch)
Point `DATABASE_URL` at a managed DB and delete the `postgres` service + its `depends_on` in
`compose.yml`. The relay VM becomes stateless/disposable; backups + PITR become the provider's job.

## Key references

- `CLAUDE.md` / `CONTRIBUTING.md` — contributor + agent guide, quality gates (`just ci`).
- `ARCHITECTURE.md`, `NOSTR.md` — system design + the event model.
- Event kinds: `crates/buzz-core/src/kind.rs`. Desktop features: `desktop/src/features/`.
