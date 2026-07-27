# rphaf quick-start 🪨

For the first few testers. You're technical, so this doesn't hedge — it tells
you what works, what doesn't, and what we actually need you to try.

rphaf is a self-hosted chat app: channels, threads, DMs, search, files. It runs
on a relay we own rather than someone else's server. It's a fork of
[Buzz](https://github.com/block/buzz) by [Block, Inc.](https://block.xyz), and
all of the hard parts are theirs.

Relay: **`wss://jean.rphaf.io`**

---

## Getting in

**1. Install the app.** Latest **Buzz Desktop** release from
[block/buzz/releases](https://github.com/block/buzz/releases):

| You have | Take |
|---|---|
| Apple Silicon Mac (M1–M4) | the `aarch64` `.dmg` |
| Intel Mac | the `x64` `.dmg` |
| Linux | `.AppImage` or `.deb` |

Not sure which Mac? `uname -m` — `arm64` means Apple Silicon.

Yes, that's upstream's build, not ours. Our relay runs stock upstream code, so
the official signed app connects fine and you skip the Gatekeeper dance. It says
"Buzz" everywhere. That's expected.

**2. Enter the relay** when it asks for a community: `wss://jean.rphaf.io`

**3. Get rejected.** You'll land on a screen headed **"Not a member yet"**. This
is the system working — the app minted you a fresh identity and our roster is a
closed list, not a signup form.

**4. Send Matt your npub.** It's on that screen with a copy button. It's your
*public* key — safe to paste anywhere.

**5. Hit "Try again"** once you've been added. No reinstall, no restart.

If you already have a Nostr identity, that same screen takes an existing `nsec`
instead of the one it generated for you.

---

## Back up your key. Seriously.

**Settings → Profile** reveals your `nsec` — the private half of your identity.
Put it in a password manager now.

There is no reset email, no recovery, and no admin who can restore it. It isn't
stored on our server. Lose it and the account is gone, and you start over as a
new person with a new npub. That's the tradeoff for running our own thing.

---

## The rest of Buzz is right there

The upstream build ships a much larger surface than we use: AI agents as room
members, workflow automation, voice huddles. Our relay is stock upstream with
nothing switched off, so it's all there — we simply haven't used any of it. Our
own build hides it behind Settings → Experiments to keep the day-to-day simple;
the build you just installed doesn't.

Day to day, rphaf is chat: channels, threads, DMs, search, files. But if you
want to tinker, tinker. You'd be the first, and we'd genuinely like to know what
happens.

Two things to know before you do:

- **Agents run on your machine, not the relay.** The ACP harness spawns local
  subprocesses with shell and file-edit tools. That's fine if you're expecting
  it and surprising if you aren't.
- **Huddles have never been exercised here.** Not "known broken" — just never
  once tried against this relay. Assume nothing.

If you break something, that's a useful result. Say what you did.

---

## What we need you to test

Two people have used this for about an hour. Channel messages, typing
indicators, and unread badges work between two accounts. **Everything below has
never run with more than one person**, so it's genuinely unknown — you're not
double-checking our work, you're doing the first pass.

Roughly in order of how much it'd hurt:

**1. Reconnect.** Shut the lid, come back in an hour, open it. Does it rejoin on
its own, and does it backfill what you missed while away? This matters more than
anything else here because it's what daily use actually looks like.

**2. DMs.** A completely separate path from channel messages — different event
type, different plumbing. Send one each way.

**3. Threads.** Reply to each other inside one thread and check the reply count
reads correctly *on both screens*. Those counters are stored on the thread root
and updated by hand in the code, which is exactly the shape of thing that
drifts when two people write at once.

**4. Media.** Upload an image; confirm someone else can load it. Files go
through separate storage and a separate URL path, and a config bug there took
down all connections once already.

**5. Search.** Full-text search over messages that other people wrote, not just
your own.

**6. Just talk in it for a few days.** The bugs we most want are the boring
ones — a badge that won't clear, a message that arrives twice, ordering that
goes strange after you've been away.

---

## Known rough edges

- **Nothing monitors whether the relay is up.** If it dies at 3am, nobody is
  paged. Tell us and we'll restart it.
- **Desktop only.** The mobile app has no feature gating yet, so it would expose
  the entire Buzz surface on a phone. Not shipping it until that's sorted.
- **The app is branded Buzz throughout.** Renaming 1,200 files of crates and env
  vars is a much bigger job than renaming the project. See
  [ROADMAP.md](../ROADMAP.md).
- **Backups are nightly and offsite**, tiered 30 days daily / 12 months monthly,
  and have been restore-tested. Your messages are safe. Your key is not our
  problem to lose — see above.

---

## Reporting things

Post it in the relay itself if it's up. If it isn't, that's the one thing you
can't report from inside — text Matt.

Useful: what you did, what happened, what you expected, roughly when (we can
match it against relay logs), and which machine. Screenshots are great.

"It feels slow sometimes" is also a legitimate report. Say it.
