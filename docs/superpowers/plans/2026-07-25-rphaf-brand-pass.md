# rphaf Brand Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the fork an rphaf identity on its outward-facing docs — a rewritten README, an IDENTITY.md anchoring the vocabulary, a ROADMAP.md holding deferred work — while being honest that the re-skin is partial.

**Architecture:** Documentation only. Five files: three written from scratch (`IDENTITY.md`, `ROADMAP.md`, `.gitattributes`), one rewritten (`README.md`), two given small additive pointers (`AGENTS.md`, `CONTRIBUTING.md`). No code, no app strings, no relay config, no `deploy/` changes. Order matters: IDENTITY and ROADMAP are written first because the README links to both.

**Tech Stack:** Markdown. Verification is `grep` / `test -f` / `wc -l`, not a test runner — there is no code under test.

**Spec:** `docs/superpowers/specs/2026-07-25-rphaf-brand-pass-design.md`

## Global Constraints

These apply to every task. Copy rules are exact.

- **Product noun is `rphaf`**, always lowercase — never `RPHAF`, `Rphaf`, `Roc`, or `Rocpile` as the app name. Lowercase even at the start of a sentence.
- **Emoji is `🪨`** (U+1FAA8, "rock"). It replaces `🐝` in the fork's own docs.
- **Tagline on outward-facing pages is `Rocpile Hard AF`.** The full phrase — "Rocpile Hard As Fuck" — appears **exactly once in the whole repo**, in `IDENTITY.md`. No asterisk-censoring anywhere (`F***` is not used).
- **Attribution is non-negotiable.** Every rewritten doc keeps a visible credit to [`block/buzz`](https://github.com/block/buzz) and Apache 2.0. Nothing may read as claiming authorship of the engine.
- **No claim may describe a feature that is gated off or a relay that is not running.** The relay is not deployed; the hostname is undecided.
- **Do not touch:** app strings, `crates/`, `desktop/`, `mobile/`, `deploy/`, `tauri.conf.json`, icons, env vars, `VISION_*.md`, `ARCHITECTURE.md`. `MEMORY.md` gets exactly one addition (Task 4) and nothing else.
- **`CLAUDE.md` is a symlink to `AGENTS.md`.** Edit `AGENTS.md`; never write through the symlink, and never convert it to a regular file.
- **Never run `git commit --no-verify`.** If a hook blocks a commit, fix the cause.
- Activate the toolchain before any git or `just` command in this repo: `. ./bin/activate-hermit`.

---

### Task 1: IDENTITY.md — the vocabulary anchor

Written first because README and ROADMAP both link to it. This is the one file
where the full phrase is spelled out.

**Files:**
- Create: `IDENTITY.md`

**Interfaces:**
- Consumes: nothing.
- Produces: the anchor document. Later tasks link to it as `IDENTITY.md` from the repo root, with link text "Identity". Section anchors later tasks may rely on: `#rphaf`, `#rocpile`, `#boysch--the-boysch`.

- [ ] **Step 1: Write `IDENTITY.md`**

Create `IDENTITY.md` with exactly this content:

```markdown
# Identity

The words we use and where they came from. If you're writing something other
people will read — this README, docs, a channel topic, a commit message — this
is the reference. It exists so the brand doesn't drift as more of us start
committing.

---

## rphaf

**"Rocpile Hard As Fuck."**

The slogan came first; the repo is just where it landed. It's a name for the
project because it was already a thing we said.

Fashioned from J-Roc of *Trailer Park Boys*, whose entire bit is announcing how
hard he goes at things. We kept the shape and put our own word in the middle.

**How to write it:**

- Lowercase, always: `rphaf`. Not `RPHAF`, not `Rphaf`. Lowercase even at the
  start of a sentence.
- It's the app, the project, and the repo. There is no second product name to
  learn — "rphaf is a chat app", "the rphaf relay", "open rphaf".
- Outward-facing pages use the short tagline: **Rocpile Hard AF**.
- The full version is written out on this page and nowhere else in the repo.
  It isn't a secret — it's just not the front door.

---

## rocpile

Us. The friend group.

One of several words we've landed on for ourselves over the years, and the one
that stuck hardest. Lowercase in prose; capitalised only inside the tagline,
where it's doing proper-noun work.

---

## boysch / the boysch

What we call each other, collectively. **The boysch** is all of us; it's also
how you'd address the group.

The singular hasn't settled and this doc isn't going to decide it — if you find
yourself needing one, that's a conversation, not a style rule.

---

## The 🪨 rule

`🪨` is the mark. It sits next to the name in headers and sign-offs:

```
# rphaf 🪨
```

One rock. Not a pile of them, however tempting. Don't scatter it through body
text — it's punctuation for the name, not decoration.

Upstream Buzz uses `🐝`. Wherever we've rewritten a doc, the bee becomes a rock.
Wherever we haven't, it's still a bee, and that's just where the paint has
reached so far.

---

## Tone

The honesty is the brand. This is a fork of a serious piece of software, run by
a group of friends, and half the paint isn't on yet. Saying so plainly is
funnier and more useful than pretending otherwise.

**What it is:** dry, plain, a bit self-aware. Short sentences. Says what's
broken. The joke is in the gap between "Rocpile Hard AF" and "a self-hosted
chat app with a Postgres dependency", so it doesn't need help.

**What it isn't:** corporate voice, hype, or a pitch. We are not selling this to
anyone. Nobody is evaluating us. Don't write like they are.

**On the engine:** rphaf is a fork of [Buzz](https://github.com/block/buzz),
built by [Block, Inc.](https://block.xyz) and licensed Apache 2.0. We renamed
the project, not the work. Credit them clearly wherever it comes up.
```

- [ ] **Step 2: Verify the full phrase appears exactly once in the repo**

```bash
. ./bin/activate-hermit
grep -rn --include='*.md' 'Hard As Fuck' . --exclude-dir=node_modules --exclude-dir=target --exclude-dir=docs/superpowers | grep -v '^./docs/superpowers'
```

Expected: exactly one line, in `./IDENTITY.md`. If more, the constraint is broken — fix before committing.

- [ ] **Step 3: Verify no asterisk-censoring crept in**

```bash
grep -n 'F\*\*\*' IDENTITY.md
```

Expected: no output (exit code 1). The censored form is not used anywhere.

- [ ] **Step 4: Commit**

```bash
. ./bin/activate-hermit
git add IDENTITY.md
git commit -m "Add IDENTITY.md to anchor the rphaf vocabulary

Friends are starting to join the repo and the terms they'll hear -- rphaf,
rocpile, boysch -- were only ever defined in conversation. Writing them
down once keeps the brand from drifting as more people commit."
```

---

### Task 2: ROADMAP.md — where the deferred re-skin lives

**Files:**
- Create: `ROADMAP.md`
- Read for source material: `MEMORY.md` (roadmap + self-hosting sections)

**Interfaces:**
- Consumes: `IDENTITY.md` from Task 1 (links to it).
- Produces: `ROADMAP.md` at repo root, linked from README as "Roadmap".

- [ ] **Step 1: Write `ROADMAP.md`**

Create `ROADMAP.md` with exactly this content:

```markdown
# Roadmap

What's deferred and why. rphaf is a fork of [Buzz](https://github.com/block/buzz)
running chat-first; everything below is either paint we haven't applied or an
engine we've deliberately switched off.

Nothing here is scheduled. It's a list of what we know we're not doing yet.

---

## The rebrand, in tiers

Renaming the project was cheap. Renaming the software is not, and the cost goes
up sharply at each tier. See [IDENTITY.md](IDENTITY.md) for the naming rules
these tiers apply.

### Tier 1 — cosmetic strings

User-visible "Buzz" text and the relay's NIP-11 name
(`crates/buzz-relay/src/nip11.rs`). Low churn, low risk, mostly a find-and-read
exercise. This is the next tier worth doing.

### Tier 2 — app identity

`desktop/src-tauri/tauri.conf.json` productName, bundle identifier, and
deep-link scheme; mobile bundle IDs; icons. Medium churn. Changing the
identifier or the deep-link scheme breaks already-installed builds and any
`buzz://` link anyone has saved, so this wants doing once, deliberately, when
there are few enough installs to re-issue.

### Tier 3 — internal renames

`buzz-*` crate names, `BUZZ_*` env vars, storage keys. Roughly 1,200 files.

**Probably never.** It touches every high-churn file in the repo and would end
clean upstream merges permanently — which is the single thing making this fork
sustainable. The names are internal. Nobody using rphaf ever sees them.

---

## Fold the agents back in

The AI-agent surface is fully present and switched off, not removed. Turning it
back on is two moves: flip the toggles in **Settings → Experiments**, then
actually run the agent processes (`sprig` / `buzz-acp` / `buzz-agent`) as relay
clients.

Same story for voice huddles, git hosting, and workflow automation. Gated, not
deleted — that was the whole point of doing it with feature flags.

---

## Self-hosting

The deploy tooling exists (`deploy/compose/`) and the decisions are made; the
relay just isn't up yet.

- [ ] Provision the VM and deploy the relay
- [ ] Add the boysch as relay members
- [ ] Nightly backups running, with an offsite target set
- [ ] Do the restore drill once — a backup nobody has restored isn't a backup

**Open decision: the relay hostname.** `boysch.rphaf.io` or `jean.rphaf.io`.
`MEMORY.md` and `deploy/compose` still say `chat.rphaf.io`; they get updated
once this is settled, not before.

---

## Known cost: the README no longer merges

`README.md` is a fork-owned file now. It's protected by a `merge=ours` driver
(see `.gitattributes`), so `git merge upstream/main` keeps ours automatically
instead of conflicting every time.

The tradeoff is that upstream README changes vanish **silently** — no conflict
markers, no notice. If upstream adds a genuinely useful setup step, we won't
see it. Mitigation is manual and occasional:

```bash
git diff HEAD upstream/main -- README.md
```

`CONTRIBUTING.md` and `AGENTS.md` are deliberately **not** protected this way.
Our edits there are small and additive, so ordinary conflict resolution is the
right behaviour and upstream improvements keep flowing in.
```

- [ ] **Step 2: Verify every local link resolves**

```bash
for f in IDENTITY.md .gitattributes MEMORY.md deploy/compose crates/buzz-relay/src/nip11.rs; do
  test -e "$f" && echo "OK   $f" || echo "MISS $f"
done
```

Expected: `IDENTITY.md`, `MEMORY.md`, `deploy/compose`, and `nip11.rs` all report `OK`. `.gitattributes` reports `MISS` — it is created in Task 4. That is expected at this point and must be `OK` by the end of Task 4.

- [ ] **Step 3: Commit**

```bash
. ./bin/activate-hermit
git add ROADMAP.md
git commit -m "Add ROADMAP.md for the deferred rebrand and self-hosting work

The README rewrite drops the inherited Buzz pitch, so the work we've put
off needs somewhere honest to live. Records why tier 3 of the rename is
probably never worth doing: it would end clean upstream merges."
```

---

### Task 3: README.md — full rewrite

**Files:**
- Overwrite: `README.md` (currently 267 lines)
- Referenced, not modified: `docs/assets/screenshots/channel-thread.png`

**Interfaces:**
- Consumes: `IDENTITY.md` (Task 1), `ROADMAP.md` (Task 2). Both must exist before this task runs, or the README ships dead links.
- Produces: the repo front page. No later task depends on its internals.

- [ ] **Step 1: Confirm the screenshot exists before referencing it**

```bash
test -f docs/assets/screenshots/channel-thread.png && echo OK || echo MISSING
```

Expected: `OK`. If missing, stop — do not ship an `<img>` to a file that isn't there.

- [ ] **Step 2: Overwrite `README.md`**

Replace the entire file with exactly this content:

```markdown
<h1 align="center">rphaf 🪨</h1>

<p align="center"><strong>Rocpile Hard AF</strong></p>

<p align="center">
  Self-hosted chat for the boysch, on a relay we own.
</p>

<p align="center">
  <a href="IDENTITY.md">Identity</a> ·
  <a href="ROADMAP.md">Roadmap</a> ·
  <a href="https://github.com/block/buzz">Upstream</a> ·
  <a href="LICENSE">Apache 2.0</a>
</p>

---

## Still layering in

This is a fork of [Buzz](https://github.com/block/buzz), and the paint is going
on in coats. The name, this page, and the vocabulary are ours. Most of the app
still says Buzz, because renaming the software is a much bigger job than
renaming the project — that's tracked in [ROADMAP.md](ROADMAP.md).

Nothing here is finished. It's ours and it runs.

---

## What this is

A chat app we host ourselves. Channels, threads, DMs, search, files — the normal
stuff — on a relay we control instead of someone else's server.

Buzz underneath is a much larger machine: AI agents as room members, git
hosting, workflow automation, voice huddles. We've switched all of it off on
purpose. rphaf is chat first. The rest is still in there, gated behind
**Settings → Experiments**, waiting until we actually want it.

New here? [IDENTITY.md](IDENTITY.md) explains what "rphaf", "rocpile", and
"boysch" mean.

---

## What it looks like

<p align="center">
  <img src="docs/assets/screenshots/channel-thread.png" alt="A channel with a threaded conversation" width="100%">
</p>

<p align="center">
  <sub><em>Upstream Buzz chrome — the rocpile paint is still going on in coats.</em></sub>
</p>

---

## Get in

> **Not live yet.** The relay isn't deployed. Ask Matt where things stand.

When it is, joining takes three things:

1. **A build.** The desktop app, built from this repo — our version, with the
   non-chat features already switched off.
2. **The relay address.** The app points at `ws://localhost:3000` out of the
   box; you'll change it to ours.
3. **An invite.** The relay is closed on purpose — membership is an explicit
   list, not a signup form. Send your npub to Matt and you get added.

The app makes you a fresh identity on first launch. Back up the key it gives
you. Losing it means losing the account, and there's no reset email — that's
the deal with running your own thing.

---

## Run it yourself

The developer path. You need [Docker](https://docs.docker.com/get-docker/) and
[Hermit](https://cashapp.github.io/hermit/) (Hermit pulls the right Rust, Node,
pnpm, and `just` — no system installs).

**Once:**

```bash
git clone https://github.com/mpimenta8/rphaf.git && cd rphaf
. ./bin/activate-hermit
just setup && just build
```

**Every day:**

```bash
. ./bin/activate-hermit
just dev
```

`just dev` runs the relay on `ws://localhost:3000` and opens the desktop app.
It owns the relay — don't also run `just relay`, the port will clash.

Want the relay logs separate from the frontend? `just relay` in one terminal,
`just desktop-dev` in another.

Before you push anything: `just ci`.

---

## Roadmap

The rebrand is tiered — cosmetic strings are cheap, renaming 1,200 files of
crates and env vars is not. The agents, git hosting, and voice huddles are
gated off rather than deleted, so folding them back in is a toggle and a
process, not a re-fork. The relay still needs deploying.

Details, and why tier 3 is probably never worth it: **[ROADMAP.md](ROADMAP.md)**.

---

## Where this came from

rphaf is a fork of **[block/buzz](https://github.com/block/buzz)** — a Nostr
relay where humans and AI agents share rooms, built by
[Block, Inc.](https://block.xyz) and licensed under
[Apache 2.0](LICENSE). All of the hard parts are theirs. We renamed it and
turned some things off.

Upstream's own docs are still in this repo and still worth reading:
[ARCHITECTURE.md](ARCHITECTURE.md) for the system design,
[NOSTR.md](NOSTR.md) for the event model,
[CONTRIBUTING.md](CONTRIBUTING.md) for setup and PR process.

---

<p align="center">
  <sub>rphaf 🪨</sub><br>
  <sub>Apache 2.0 · forked from <a href="https://github.com/block/buzz">Buzz</a> by <a href="https://block.xyz">Block, Inc.</a></sub>
</p>
```

- [ ] **Step 3: Verify every remaining "Buzz" mention is deliberate attribution**

```bash
grep -in 'buzz' README.md
```

Expected: 9 lines, every one of them either an upstream link (`github.com/block/buzz`), the honest screenshot caption, or the "fork of Buzz" credit. There must be **no** line where "Buzz" is used as the name of this product. Read each hit; do not skim.

- [ ] **Step 4: Verify the branding constraints**

```bash
grep -c '🐝' README.md; grep -c 'F\*\*\*' README.md; grep -c 'Hard As Fuck' README.md; grep -c 'Rocpile Hard AF' README.md
```

Expected, in order: `0`, `0`, `0`, `1`. (`grep -c` prints `0` and exits 1 on no match — that's fine.)

- [ ] **Step 5: Verify every local link target exists**

```bash
for f in IDENTITY.md ROADMAP.md LICENSE ARCHITECTURE.md NOSTR.md CONTRIBUTING.md docs/assets/screenshots/channel-thread.png; do
  test -e "$f" && echo "OK   $f" || echo "MISS $f"
done
```

Expected: all `OK`.

- [ ] **Step 6: Commit**

```bash
. ./bin/activate-hermit
git add README.md
git commit -m "Rewrite the README as rphaf's rather than Buzz's

Friends are joining the repo and the front page sold them an agent
platform we've deliberately switched off. Says what this actually is --
self-hosted chat, early, forked -- and moves the deferred work to
ROADMAP.md. Upstream attribution stays prominent."
```

---

### Task 4: Protect the README from upstream merges

**Files:**
- Create: `.gitattributes`
- Modify: `MEMORY.md` (one addition, in the remote-repair recipe under "Git remotes")

**Interfaces:**
- Consumes: nothing.
- Produces: `.gitattributes` at repo root — the file `ROADMAP.md` (Task 2) already references.

- [ ] **Step 1: Create `.gitattributes`**

The repo has no `.gitattributes` today, so this is a new file:

```gitattributes
# README.md is fork-owned: it describes rphaf, not upstream Buzz.
# Keep ours on `git merge upstream/main` instead of conflicting every time.
#
# Requires a one-time, per-clone: git config merge.ours.driver true
# Without it this falls back to a normal conflict -- noisy, but safe.
#
# Tradeoff: upstream README changes are discarded SILENTLY. Occasionally run
#   git diff HEAD upstream/main -- README.md
# to see what we're skipping. See ROADMAP.md.
README.md merge=ours
```

`CONTRIBUTING.md` and `AGENTS.md` are deliberately absent from this file — their
edits are additive and upstream improvements should keep arriving normally.

- [ ] **Step 2: Enable the merge driver in this clone**

```bash
. ./bin/activate-hermit
git config merge.ours.driver true
git config --get merge.ours.driver
```

Expected: prints `true`. This config lives in `.git/config` and is **not**
committed — every fresh clone needs it again, which is why Step 3 records it.

- [ ] **Step 3: Record the config in `MEMORY.md`**

`MEMORY.md` documents that remotes drift and need repairing after a fresh clone.
The merge driver has the same problem, so it belongs in the same recipe. Find
the repair block under **Git remotes** that ends with:

```
  `git remote set-url --push upstream DISABLED`.
```

Immediately after that line, add this bullet:

```markdown
- **A fresh clone also needs the README merge driver:** `git config merge.ours.driver true`.
  `.gitattributes` marks `README.md merge=ours` so upstream merges keep our rewritten README,
  but the driver config lives in `.git/config` and isn't cloned. Without it, merges that touch
  the README conflict instead — noisy, not dangerous. Note the driver discards upstream README
  changes *silently*; `git diff HEAD upstream/main -- README.md` shows what we're skipping.
```

Change nothing else in `MEMORY.md`.

- [ ] **Step 4: Verify the attribute is actually in effect**

```bash
git check-attr merge -- README.md
git check-attr merge -- CONTRIBUTING.md
```

Expected: `README.md: merge: ours` and `CONTRIBUTING.md: merge: unspecified`.
If the README line says `unspecified`, the pattern didn't match — fix it.

- [ ] **Step 5: Confirm the MEMORY.md edit is the only one**

```bash
git diff --stat MEMORY.md
```

Expected: one file changed, roughly 6 insertions, **0 deletions**. Any deletion
means something else was disturbed — revert and redo.

- [ ] **Step 6: Commit**

```bash
. ./bin/activate-hermit
git add .gitattributes MEMORY.md
git commit -m "Keep our README on upstream merges

The rewritten README diverges from upstream permanently, so every future
merge from block/buzz would conflict on it. A merge=ours driver resolves
that in our favour. It discards upstream README changes silently, so the
tradeoff and the periodic diff check are written down next to it."
```

---

### Task 5: Point contributors and agents at IDENTITY.md

Small and additive on purpose — both files are upstream-tracked and are **not**
protected by the merge driver, so the smaller the edit, the cheaper future
conflicts are.

**Files:**
- Modify: `AGENTS.md` (insert after line 5, before the first `---`)
- Modify: `CONTRIBUTING.md` (top-of-file note, before the `---` above the Table of Contents)

**Interfaces:**
- Consumes: `IDENTITY.md` (Task 1).
- Produces: nothing later tasks depend on. This is the last task.

- [ ] **Step 1: Confirm the symlink before editing**

```bash
ls -la CLAUDE.md
```

Expected: `CLAUDE.md -> AGENTS.md`. Edit `AGENTS.md` only — editing it covers
both filenames. If this ever shows a regular file, stop and ask.

- [ ] **Step 2: Add the pointer to `AGENTS.md`**

The file opens with:

```markdown
# AGENTS.md — AI Agent Contributor Guide

This guide is for AI agents contributing to the Buzz codebase. It covers
agent-specific context and conventions. For general contributor info (setup,
code style, PR process, architecture), see [CONTRIBUTING.md](CONTRIBUTING.md).
```

Insert this immediately after that paragraph, before the `---` that follows:

```markdown
> **This repo is `rphaf`, a fork.** The code is still named `buzz` throughout
> and that's intentional — see [ROADMAP.md](ROADMAP.md) for why the internal
> rename is deferred. But anything **user-facing you write** — docs, README
> prose, UI copy, commit messages — follows [IDENTITY.md](IDENTITY.md): the
> product noun is `rphaf`, lowercase, and the mark is 🪨.
```

Leave the existing paragraph and the rest of the file untouched.

- [ ] **Step 3: Add the pointer to `CONTRIBUTING.md`**

The file opens with a welcome paragraph and a line about GitHub Discussions,
then a `---` before the Table of Contents. Insert this immediately before that
`---`:

```markdown
> **Note for rphaf:** this is a fork of Buzz. Everything below about setup,
> tests, code style, and PRs applies unchanged. What differs is naming — user-facing
> prose uses `rphaf`, per [IDENTITY.md](IDENTITY.md). The code keeps its `buzz`
> names on purpose ([ROADMAP.md](ROADMAP.md)).
```

Leave the welcome paragraph and everything below the `---` untouched.

- [ ] **Step 4: Verify both edits are purely additive**

```bash
git diff --numstat AGENTS.md CONTRIBUTING.md
```

Expected: two lines, each with a small insertion count and **`0` deletions**.
Any deletion means surrounding text was disturbed — revert and redo.

- [ ] **Step 5: Verify the symlink survived**

```bash
ls -la CLAUDE.md && head -12 CLAUDE.md
```

Expected: still a symlink to `AGENTS.md`, and the pointer text is visible
through it.

- [ ] **Step 6: Run the full gate**

```bash
. ./bin/activate-hermit
just ci
```

Expected: PASS. This change is documentation-only, so `just ci` must be
unaffected. If it fails, the failure is pre-existing or unrelated — confirm by
checking whether it reproduces on a clean checkout before touching anything.

- [ ] **Step 7: Commit**

```bash
. ./bin/activate-hermit
git add AGENTS.md CONTRIBUTING.md
git commit -m "Point contributors and agents at IDENTITY.md

New contributors hit code named buzz inside a repo named rphaf and
reasonably conclude the naming is up for grabs. Names the split: code
keeps buzz, user-facing prose uses rphaf. Kept additive so these two
upstream files still merge cleanly."
```

---

## Self-review

**Spec coverage** — every deliverable in the spec maps to a task: IDENTITY.md → 1, ROADMAP.md → 2, README rewrite + kept screenshot + honest "Get in" → 3, `.gitattributes` + the per-clone config + the MEMORY.md line → 4, CONTRIBUTING/CLAUDE pointers → 5. The spec's merge-divergence section is covered in both Task 4 (mechanism) and Task 2 (documentation). The "spelled out exactly once" rule is enforced by a repo-wide grep in Task 1 Step 2.

**Two deviations from the spec, both deliberate:**
- The spec says "CONTRIBUTING.md / CLAUDE.md touch-ups". `CLAUDE.md` is a symlink to `AGENTS.md`, so Task 5 edits `AGENTS.md` — one edit covering both names.
- The spec's ordering implied README first. IDENTITY and ROADMAP are written first so the README never ships dead links.

**Placeholders:** none. Every file's full content is in the plan; no step says "similar to" or "add appropriate X".

**Naming consistency:** `rphaf` lowercase throughout; `🪨` in all three new/rewritten docs; `Rocpile Hard AF` in README only; `Rocpile Hard As Fuck` in IDENTITY.md only; link text "Identity"/"Roadmap" consistent across README, AGENTS.md, and CONTRIBUTING.md.
