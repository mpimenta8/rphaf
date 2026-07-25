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
