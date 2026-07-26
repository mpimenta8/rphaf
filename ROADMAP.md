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

The deploy tooling exists ([`deploy/compose/`](deploy/compose/README.md), with the step-by-step in
[`PROVISIONING.md`](deploy/compose/PROVISIONING.md)) and the decisions are made; the
relay just isn't up yet.

- [x] Droplet up — Ubuntu 24.04, NYC3
- [ ] `jean.rphaf.io` A record — waiting on the domain owner
- [ ] Deploy the relay
- [ ] Add the boysch as relay members
- [ ] Nightly backups running, with an offsite target set
- [ ] Do the restore drill once — a backup nobody has restored isn't a backup

---

## Getting the app to you

Desktop first. Phones later, and not just out of laziness.

We build and hand out the app ourselves — the signed builds come from Block's
release pipeline, and a fork can't reach those credentials. So installers work,
they just aren't signed by anyone your OS recognises:

| | What you'll hit |
|---|---|
| **Linux** | Nothing. It runs. |
| **macOS** | Blocked on first launch — System Settings → Privacy & Security → **Open Anyway**. Once. |
| **Windows** | SmartScreen warning — *More info* → *Run anyway*. |
| **Android** | Allow installing from unknown sources, once. |
| **iPhone** | No free path at all. Sideloaded builds die after 7 days; TestFlight needs the $99/yr Apple Developer Program. |

The bigger reason phones wait: **the mobile app has none of the feature gating
the desktop app has.** The "just chat" strip-down lives entirely in the desktop
code, so shipping the phone app as-is would put agents, huddles, workflows, and
projects in your pocket while the desktop hides them. Fixing that means porting
the gating to Flutter — real work, not a config flag.

**Settled: the relay hostname is `jean.rphaf.io`.** Worth writing down that it's
expensive to change later. It's baked into the A record, the TLS certificate,
five `.env` values, and every client's stored relay URL — and media URLs are
absolute and embedded in immutable events, so retiring the hostname breaks every
historical image and video while leaving text intact. If it ever has to move,
keep the old name resolving and serve both from Caddy.

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
