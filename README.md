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
hosting, workflow automation, voice huddles. rphaf is chat first — we're not
using any of that yet, and our own build keeps it out of the way behind
**Settings → Experiments** rather than deleting it.

That gating is in *this* repo's build, though. The app you're told to install
below is upstream's, so you'll see the full Buzz surface — agents, repos,
huddles, all of it. And since our relay is stock upstream with nothing switched
off, it all works. We just don't use it. Day to day, rphaf is channels,
threads, DMs, search, and files; the rest is there if someone wants to play.

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

The relay is live at **`wss://jean.rphaf.io`**. Membership is an explicit list,
not a signup form, so getting in is: install, get turned away, send your npub,
get added.

**1. Install the app.** Grab the latest **Buzz Desktop** release from
[block/buzz/releases](https://github.com/block/buzz/releases) — the `.dmg` for
macOS, `.AppImage` or `.deb` for Linux. That's upstream's signed build, and it
talks to our relay fine; our relay runs stock upstream code. (It still says
Buzz everywhere. That's expected — see [ROADMAP.md](ROADMAP.md).)

**2. Point it at the relay.** When it asks for a community, enter
`wss://jean.rphaf.io`.

**3. Get turned away.** This part looks like a failure and isn't. The app mints
you a fresh identity on first launch, the relay has never heard of it, and you
land on a screen headed **"Not a member yet"**. That's the system working.

**4. Send your npub.** That screen shows your public key with a copy button.
Send it to Matt. It's public — safe to paste anywhere.

**5. Hit "Try again".** Once you've been added, the same screen's button lets
you straight in. No reinstall.

> **Back up your key.** Settings → Profile reveals your `nsec` — the private
> half. Put it in a password manager. There is no reset email and no recovery:
> lose it and the account is gone. That's the deal with running your own thing.

If you already have a Nostr identity you'd rather use, the denial screen also
takes an existing `nsec` instead of the one the app generated.

Testing for us? **[docs/quickstart.md](docs/quickstart.md)** has the same steps
plus what's still unproven and worth poking at.

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
process, not a re-fork. The relay is deployed and backed up nightly; mobile
isn't gated yet, so it's desktop-only for now.

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
