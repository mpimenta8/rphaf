# rphaf brand pass — design

**Date:** 2026-07-25
**Status:** approved, ready for implementation plan

## Goal

Give the fork an rphaf identity on its outward-facing docs, early, while being
honest that the re-skin is partial. Friends are starting to join the repo; the
front page should read as ours, name the vocabulary they'll hear, and point
deferred work at a roadmap instead of pretending it's done.

Scope is documentation only. No code, no strings in the app, no relay config.

## Decisions

| Decision | Choice |
|---|---|
| Product noun | `rphaf`, used as a plain noun everywhere. No second brand ("Roc", "Rocpile") to explain. |
| Emoji | `🪨` replaces `🐝`. |
| Tagline | **Rocpile Hard AF** on the README; spelled out in full once in IDENTITY.md. No asterisk-censoring anywhere — it's either abbreviated or written out. |
| README treatment | Full rewrite. The inherited Buzz pitch is dropped, not re-skinned. |
| Screenshots | Keep exactly one (`docs/assets/screenshots/channel-thread.png`), captioned honestly as upstream chrome. |
| Deeper re-skin | Deferred to ROADMAP.md. |

## Deliverables

### 1. `README.md` — full rewrite

Target ~90 lines, down from 267.

| Section | Content |
|---|---|
| Banner | `# rphaf 🪨`, tagline, one-line what-it-is, nav links to IDENTITY.md / ROADMAP.md / upstream / LICENSE |
| Still layering in | Honest note: forked from Buzz, chat-first, brand going on in coats |
| What this is | Self-hosted chat for the boysch, on a relay we own. Two or three lines |
| What it looks like | The kept screenshot + caption naming it as upstream Buzz chrome |
| Get in | The boysch path: install the build, point at the relay, get added as a member. Marked **not live yet** — see below |
| Run it yourself | Condensed dev quick start: hermit, `just setup`, `just dev`, relay on `ws://localhost:3000` |
| Roadmap | Three-line teaser → ROADMAP.md |
| Where this came from | Credit `block/buzz`, Apache 2.0, Block attribution retained |

**Dropped from the README** (files stay on disk; the README just stops being
their front door): the three "little stories", the works-today/wired-up/opinions
table, "Why Buzz is better", "I work at Block", the ASCII architecture diagram,
the crate map, the six `VISION_*.md` links, the Windows prerequisites section.

**"Get in" honesty requirement.** Per `MEMORY.md` the relay deploy is planned,
not done, and the relay hostname is an open question (`boysch.rphaf.io` vs
`jean.rphaf.io`). This section describes the real intended flow and carries an
explicit "not live yet — ask Matt" marker. It must not contain copy-pasteable
instructions that quietly fail.

**Attribution is non-negotiable.** Apache 2.0 and the `block/buzz` credit stay,
prominently. Re-skinning must not read as claiming authorship of the engine.

### 2. `IDENTITY.md` — new

The anchor doc. Its job is to stop brand drift as friends start committing.

- **rphaf** — the full phrase, spelled out here and only here. Origin: J-Roc,
  *Trailer Park Boys*. Note it's a slogan first and a project name second.
- **rocpile** — the friend group; one of our words for ourselves.
- **boysch / the boysch** — the members, collectively and individually.
- **Usage** — how to write the name (lowercase `rphaf`), the `🪨` rule, when to
  use **Rocpile Hard AF** vs the full phrase, what the tone is and isn't.

### 3. `ROADMAP.md` — new

Where deferred work lives. Lifted and expanded from the roadmap section of
`MEMORY.md`:

- **Tier 1 — cosmetic strings.** User-visible Buzz→rphaf strings, relay NIP-11
  name (`crates/buzz-relay/src/nip11.rs`). Low churn.
- **Tier 2 — app identity.** `tauri.conf.json` productName / identifier /
  deep-link scheme, mobile bundle IDs, icons. Medium churn, breaks installed
  builds.
- **Tier 3 — internal renames.** `buzz-*` crate names, `BUZZ_*` env vars,
  storage keys. ~1,200 files; abandons clean upstream merges. Marked
  *probably never*.
- **Fold agents back in** — Experiments toggles + running agent processes.
- **Self-hosting milestones** — deploy the relay, add the boysch as members,
  backups + restore drill.
- **Open decision** — relay subdomain: `boysch.rphaf.io` vs `jean.rphaf.io`.
  `MEMORY.md` and `deploy/compose` currently say `chat.rphaf.io`; those are not
  changed in this pass.
- **Known cost** — the README merge divergence, below.

### 4. `CONTRIBUTING.md` + `CLAUDE.md` — pointer only

One small additive block in each pointing at `IDENTITY.md`, so humans and agents
write in-brand. No restructuring, no reflow of surrounding text — the edit
surface stays as small as possible to limit future merge conflicts.

### 5. `.gitattributes` — new

```gitattributes
README.md merge=ours
```

Requires a one-time per-clone `git config merge.ours.driver true`.

## The README merge divergence

`README.md`, `CONTRIBUTING.md`, and `CLAUDE.md` are upstream files. A full README
rewrite means every future upstream README change conflicts on
`git merge upstream/main`. This is the first time the fork diverges on a shared
doc, and it is permanent.

The `merge=ours` driver resolves it automatically in our favour. Two things must
be documented alongside it, or it becomes a trap:

1. **It is per-clone.** The `merge.ours.driver` config is not carried by the
   repo. A fresh clone that skips it falls back to a normal conflict — noisy but
   safe. Add the config line to the remote-repair recipe in `MEMORY.md`.
2. **It silently discards upstream README changes.** That is the intent, but it
   means genuinely useful upstream additions (a new setup step, a changed
   command) will vanish without a conflict marker. Mitigation: at sync time,
   occasionally run `git diff HEAD upstream/main -- README.md` and eyeball it.

`CONTRIBUTING.md` and `CLAUDE.md` are deliberately **not** given the `merge=ours`
driver — their edits are small and additive, so ordinary conflict resolution is
correct there and upstream improvements should keep flowing in.

## Out of scope

Explicitly not touched in this pass: app strings, relay NIP-11 name, Tauri
config, icons, crate names, env vars, `deploy/compose` hostnames, the
`VISION_*.md` files, `ARCHITECTURE.md`, `MEMORY.md`'s deploy sections.
`MEMORY.md` gets one addition only: the `merge.ours.driver` config line in the
remote-repair recipe.

## Success criteria

- README reads as rphaf's, not Buzz's, and a friend opening the repo cold
  understands what it is, that it's early, and how to get in.
- Every term a new contributor will hear (`rphaf`, `rocpile`, `boysch`) is
  defined in one findable place.
- No claim in the README describes a feature that is gated off or a relay that
  isn't running.
- Upstream attribution and Apache 2.0 remain prominent.
- `just ci` is unaffected (docs-only change).
