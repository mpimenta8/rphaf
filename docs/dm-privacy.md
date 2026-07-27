# Can the boysch read my DMs? 🪨

Someone asked. It's the right question and it deserves a straight answer rather
than a shrug, so here's the answer, what we can do about it, and what we think
we should do.

**The short version: today, yes — anyone who can log into the server can read
every DM in rphaf. Nobody has to hack anything; it's one database query. That
list is currently one or two people. This document is about how we shrink that
to nobody.**

---

## Part 1 — for everyone

### What's actually true right now

DMs in rphaf are private **from each other** and not private **from whoever runs
the server**.

The first half is real and we checked it properly. Another member of the group
cannot read your DMs — not by clicking around, not through a side door in the
app, not by being an admin. There's no "admin can join any conversation" button,
and it isn't an oversight that we'd patch later; the permission checks sit on
every path that can read a message.

The second half is the problem. Your messages are stored on our server as
**ordinary readable text**. The app is what enforces "only these two people can
see this" — and someone logged into the server isn't going through the app. They
open the database directly and the rules simply aren't in the room.

That's not a bug or sloppiness on our part. It's how nearly every self-hosted
chat app works, and honestly it's how Slack works too — a workspace admin on the
right plan can export your DMs. The difference is that here the admin is a
friend of yours rather than a stranger in an office, which somehow makes it feel
worse rather than better.

### Things that sound like they'd help but don't

- **"The disk is encrypted."** It is. That protects us if the physical drive is
  stolen. To someone already logged into the machine it's invisible — the files
  just open.
- **"Only trusted people have access."** True, and it's why this isn't an
  emergency. But it's a promise about people, not a property of the system. The
  point of the question is that you shouldn't have to take anyone's word for it.
- **"There are backups, so it's fine."** Backups make it *worse* — they're
  another copy of the same readable messages, somewhere else.

### The one thing that would actually fix it

**End-to-end encryption.** Your device scrambles the message before it leaves,
and only the recipient's device can unscramble it. The server stores something
it genuinely cannot read — not "is not allowed to read", *cannot*. The question
stops being about trust and starts being about arithmetic.

Two real costs, and we should be honest about both:

1. **Searching your DMs breaks.** Right now the server can search your DM
   history because it can read it. Once it can't read them, that has to be
   rebuilt to happen on your own device, or it goes away.
2. **Losing your key gets worse.** Today, losing your key means losing your
   account — it's already unrecoverable, there's no password reset (see the
   identity section in [`threat-model.md`](threat-model.md), and please back
   your key up). With encryption on, you also lose **every DM you've ever
   sent or received**, permanently, with nobody able to get it back for you.

The group has to actually want that second one. It's the whole trade: real
privacy means no safety net.

### Why we can't just build it this week

rphaf is a fork of [block/buzz](https://github.com/block/buzz). We deliberately
run **their** app code, unchanged, and layer our own hosting and identity on top.
That's what keeps this maintainable by a group of friends — we pull their
improvements down and they merge cleanly, because we haven't touched anything.

If we wrote encryption into our own copy of the app, we'd own that code forever.
Every future update from upstream would have to be manually reconciled against
our changes — in the message-sending code, the most sensitive part of the app,
where a merge mistake is exactly the kind that quietly breaks the privacy we
built it for. That's a bad trade for a group that does this in its spare time.

The good news is that **the server half is already built** — upstream has
supported encrypted messages for a while. What's missing is the app half. So the
sensible move is to build it *with upstream*, and get it back the normal way,
by updating. That's not us being lazy; it's the only version of this that we
can still maintain in a year.

### What we're proposing

1. **Shrink the trust list now.** Cut server access to the minimum, make what
   access remains leave a record elsewhere that the same people can't quietly
   erase, and encrypt the backups separately. This changes nothing about the
   honest answer — it just makes the list short, explicit, and known to
   everyone. Days of work, no risk.
2. **Be blunt in the meantime.** rphaf DMs are fine for the overwhelming
   majority of what we use them for. They're not the place for anything that
   would genuinely hurt if the wrong person read it. Use Signal for that. This
   is not a temporary embarrassment — it's the correct advice for any group
   chat someone you know is hosting.
3. **Aim at real encryption via upstream.** Named, agreed, and worked on — but
   on their schedule, not ours, and we shouldn't promise a date we don't
   control.

**What we need from the group:** is (2) acceptable to live with for now, and is
the "lose your key, lose your history" trade one we actually want when (3)
lands? Those are the two decisions. Everything else is our problem, not yours.

---

## Part 2 — technical appendix

For whoever wants to check the reasoning or do the work. Three claims in
[`threat-model.md`](threat-model.md) made end-to-end encryption look more
expensive than it is; they have been corrected there, and this is the evidence
behind those corrections.

### Where DM plaintext lives

A DM is a `channels` row with `channel_type = 'dm'`, keyed by a participant
hash; messages are ordinary kind-9 events with the body in `content TEXT NOT
NULL`. Read access is `get_accessible_channel_ids` in
`crates/buzz-db/src/channel.rs` — a SQL join, applied consistently across
`handlers/req.rs`, `handlers/count.rs`, and `api/bridge.rs`. The application
layer is sound; the exposure is entirely below it.

**There is a second plaintext copy.** `migrations/0005_agent_turn_metric_fts.sql`
excludes kinds `1059, 30300, 30622, 44100, 44101, 44200` from the tsvector — that
is gift wraps, DM visibility state, and agent internals. It does **not** exclude
DM message bodies, which are kind 9 like everything else. Confidentiality against
other members still holds — `ChannelScope` in `crates/buzz-search/src/query.rs`
scopes every FTS query to accessible channels — but that is a query-time control,
not an indexing one, so for the operator threat there are two copies of DM
plaintext to reason about, not one. (`threat-model.md` previously implied DM text
was excluded from the index; corrected in place.)

### The server side of NIP-17 is done

- `KIND_GIFT_WRAP = 1059` (`crates/buzz-core/src/kind.rs:60`).
- `handlers/event.rs:659` exempts 1059 from the `event.pubkey != auth_pubkey`
  check, which is what lets ephemeral per-message sender keys work at all.
- Excluded from FTS (above).
- **Push already works.** 1059 is in `PUSH_KINDS`
  (`handlers/push_lease.rs:15`), and `push_runtime.rs:290` documents and
  enforces the subtle part: because gift wraps are globally stored, a lease may
  only match wraps addressed to its own author, or wake timing leaks recipient
  activity. Someone thought carefully about this.

That last point contradicts "notifications degrade" in the threat model. Delivery
is fine and already hardened; what's lost is **preview text**, which the client
has to decrypt locally on wake.

### Multi-device is mostly a non-problem here

`threat-model.md` lists "a second machine can't read history it has no key for."
That's the cost in protocols with per-device keys. rphaf identity is a single
keypair, and NIP-AB pairing (`crates/buzz-core/src/pairing/NIP-AB.md`) transfers
the private key itself between devices over an authenticated channel with SAS
confirmation. Gift wraps are addressed to the identity pubkey and stored
server-side, so a newly paired device syncs and decrypts the full history.

So of the four blockers the threat model lists, two (multi-device,
notifications) are substantially already solved, one (search) is real and
understated, and one (no recovery) is a product decision rather than an
engineering one.

### The primitives are already shipping in both clients

NIP-44 is not new ground here. Desktop exposes `nip44_encrypt_to_self` /
`nip44_decrypt_from_self` (`desktop/src-tauri/src/commands/identity.rs:468`),
surfaced through `desktop/src/shared/api/tauri.ts:1145`. Mobile has full
conversation-key ECDH in `mobile/lib/shared/crypto/nip44.dart`, used in
production today for read state, mutes, stars, and channel sections.

The remaining work is the DM send path (wrap to recipient *and* to self),
the read path (decrypt, hold decrypted state in memory rather than the event
store), and a client-side search index to replace what FTS stops providing.

### Why this must go upstream

Per [CLAUDE.md](../CLAUDE.md), application code tracks upstream exactly. A
client-side fork of the DM send/read path would put permanent conflict
resolution in the most security-sensitive files in the tree, on every
`git merge upstream/main`, forever. The failure mode isn't a merge conflict —
it's a merge that resolves *cleanly* and silently degrades the crypto. Not a
tradeoff a spare-time fork should take on.

Signing is **not** an argument against any of this, and shouldn't be cited as
one: per [`distribution.md`](distribution.md) we already ship unsigned by
decision on every platform. Building this adds no signing burden we don't
already carry.

### Sequencing

| Step | Work | Divergence | Blocks on |
|---|---|---|---|
| Shrink SSH, external audit trail, separately-encrypted backups | days | none | us |
| Document the boundary; Signal for anything sensitive | hours | none | group agreement |
| Gift-wrap DM client support, contributed upstream | weeks | none if merged | upstream review |

Note that the ops step **cannot** produce a "no" answer to the original
question. Whoever controls the AWS account can undo any control we put in the
account. That work buys evidence and friction, not prevention. Only the third
row changes the answer, which is why it stays on the roadmap and doesn't get
quietly dropped.

## See also

- [`threat-model.md`](threat-model.md) — the fuller picture, including identity
  and availability
- [`aws-deployment.md`](aws-deployment.md) — what's running and who can reach it
- [`distribution.md`](distribution.md) — builds and signing
