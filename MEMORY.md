# MEMORY.md — rphaf project context

Working notes for humans (and agents) collaborating on this fork. This is a
**self-hosted team-chat** project built on top of Buzz. Keep it short and current.

## What this repo is

- `rphaf` (aka "rocpile") is a **fork of [block/buzz](https://github.com/block/buzz)** — a
  Nostr-relay-based workspace where humans and AI agents share rooms.
- Goal: run a **plain team-chat app** for us and friends, self-host the relay, and use it to
  learn the infrastructure. Agents/workflows/git-forge/voice are on the roadmap, not the first cut.

### Git remotes
- `origin` → `github.com/mpimenta8/rphaf` (our repo — we push here; add friends as collaborators).
- `upstream` → `github.com/block/buzz` (**fetch-only**, push disabled). Pull Block's updates with
  `git fetch upstream && git merge upstream/main`.
- **Keep upstream merges clean:** prefer changes that don't rewrite shared server/Rust files.

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
- **Self-host the relay:** run the relay `Dockerfile` + managed Postgres + Redis; point friends'
  desktop apps at the relay URL. Add friends as collaborators on `mpimenta8/rphaf`.

## Key references

- `CLAUDE.md` / `CONTRIBUTING.md` — contributor + agent guide, quality gates (`just ci`).
- `ARCHITECTURE.md`, `NOSTR.md` — system design + the event model.
- Event kinds: `crates/buzz-core/src/kind.rs`. Desktop features: `desktop/src/features/`.
