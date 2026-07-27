# Threat model — who can read what, and who we're trusting

Written for the rocpile, not for auditors. It answers the question that comes up
the moment someone realises we host this ourselves: **"wait, can you read my
DMs?"**

The short answer is **yes, whoever holds SSH on the server can.** The rest of
this page explains exactly why, what protects you from *everyone else*, and what
we'd have to build to change it.

> This is about `rphaf` as we run it — a closed relay for a friend group. It is
> not a claim about upstream [block/buzz](https://github.com/block/buzz), which
> is deployed differently.

---

## The one-paragraph version

DMs are **private from other members** and **not private from the server
operator**. The app's permission checks are real and correctly placed — a member
cannot read another pair's DMs, and an admin cannot add themselves to your DM.
But every message is stored as **plaintext in Postgres**, so anyone who can log
into the box reads everything with one SQL query. Membership in the chat and
access to the server are two different levels of trust, and we should keep
naming which one each person holds.

---

## How DMs actually work

A DM is not a special encrypted object. It's a **channel with a participant
list**.

| Step | What happens | Where |
|---|---|---|
| You open a DM | Relay creates a `channels` row with `channel_type = 'dm'`, keyed by a hash of the participant set | `crates/buzz-relay/src/handlers/command_executor.rs` (`handle_dm_open`) |
| You send a message | Ordinary event row; body lands in `content TEXT NOT NULL` — **plaintext** | `migrations/0001_initial_schema.sql` |
| Someone reads it | SQL join: you get channels you hold a `channel_members` row for, plus all `visibility = 'open'` ones | `crates/buzz-db/src/channel.rs` (`get_accessible_channel_ids`) |

So access control is **a database query, not cryptography**. That distinction is
the whole threat model.

## What that protects you from (genuinely)

The application layer is tighter than "self-hosted chat app" instincts suggest.
Checked, not assumed:

- **Other members can't read your DMs.** They're never in the accessible-channel
  set — and the check runs on *every* read surface, not just the obvious one:
  WebSocket `REQ` (`handlers/req.rs`), `COUNT` (`handlers/count.rs`), and the
  HTTP bridge (`api/bridge.rs`). There's no back door via `POST /query`.
- **Admins have no DM override.** `handle_dm_add_member` requires the caller to
  *already be a participant* before adding anyone. There is no role-based bypass
  — being an admin does not let you join a conversation you weren't in.
- **DMs are excluded from the search index** at the storage layer, alongside
  gift wraps, reminders, and membership notices.
- **The relay is closed.** Unknown pubkeys are rejected at connect. A stranger
  who finds `jean.rphaf.io` cannot enumerate anything.

The risk here is **not** sloppy app logic. It's infrastructure.

## What it does not protect you from

Everything above lives *above* the database. Below it:

- **Root/SSH on the instance reads every message.** `docker exec` into Postgres,
  `SELECT content FROM events`. No app code is involved, so no app check applies.
- **Encryption at rest does not help.** The EBS volume is encrypted, but that's
  transparent to anyone logged in. It defends against a stolen disk, not an
  administrator.
- **Backups carry the same plaintext.** Wherever backups land inherits the
  server's trust level — which is why the offsite target needs its own
  encryption and its own access list.
- **`authorized_keys` is the real perimeter.** Every line in it is a
  passwordless path to root, and therefore to every DM in the group. Audit it
  (`ssh-keygen -lf ~/.ssh/authorized_keys`) and prune anything you can't
  personally account for.

**Practical upshot:** the list of people who can read all DMs is exactly the list
of people with SSH keys on the box. Keep that list short, and keep it public
within the group.

## Why it isn't end-to-end encrypted yet

Half the road is already paved. The relay **supports NIP-17 gift wrap
(kind `1059`)** — it accepts, stores, routes, and search-excludes them — and the
codebase has NIP-44 primitives available.

What's missing is the client. **No client publishes gift wraps for DMs today**;
the only reference to `1059` outside the relay is the desktop E2E mock bridge.

Closing that gap is real work, and the hard part isn't the crypto:

- client-side key handling and decryption on the message path
- **multi-device** — a second machine can't read history it has no key for
- **search and notifications** degrade; the server can't index or preview what
  it can't read
- **no recovery.** Today a lost `nsec` costs you your account. With E2E DMs it
  also costs you every conversation, permanently.

That last point is the honest trade: real DM privacy makes the "I lost my key"
failure strictly worse.

## Where we've landed

**Decision: accept the current model, state it plainly, and shrink the blast
radius. Real E2E DMs stay on the roadmap, not the critical path.**

1. **Say it out loud.** Nobody should discover this property by reading source.
   DMs are private from each other, not from the operator — roughly the trust
   model of any self-hosted Slack alternative, and arguably of Slack itself,
   where workspace admins can export DMs on the right plan.
2. **Keep SSH to one or two people**, audit `authorized_keys`, and encrypt
   offsite backups separately from the host.
3. **Treat gift-wrapped DMs as a named roadmap item.** The server side is done;
   it's client work, and it needs the multi-device and recovery answers first.

## Identity is the other sharp edge

Not a DM issue, but it's the thing that will actually bite someone.

Identity is a **Nostr keypair**. No email, no password, no reset flow — and none
can be added, because there's no account to recover *to*. Whoever holds the
private key **is** that user.

- **Lose your `nsec` and the account is gone.** Permanently.
- **Back it up on day one** — password manager *and* somewhere offline.
- Anyone who obtains your `nsec` becomes you, with no signal that it happened.

This belongs in the onboarding message in bold, every time.

## Availability

Not confidentiality, but the same "what are we actually signing up for"
conversation:

- **Single EC2 instance, no redundancy.** `restart: unless-stopped` recovers a
  crashed container. It does nothing for a lost host or a bad disk.
- **`backup.sh` exists; it is not yet scheduled**, and `BACKUP_RCLONE_REMOTE`
  defaults to empty. The script says it itself: a backup that lives only on the
  same VM does not survive losing the VM.
- **No restore drill, no alerting, no billing alarm.** An unnoticed cost increase
  in an account we don't own would surface as someone else's surprise bill.

**The one thing to do before inviting people is the nightly offsite backup, plus
one real restore.** Everything else here degrades gracefully. Data loss doesn't.

## See also

- [`dm-privacy.md`](dm-privacy.md) — the group-facing answer to "can you read my
  DMs?", the path to end-to-end encryption, and corrections to the
  "why it isn't end-to-end encrypted yet" section above
- [`aws-deployment.md`](aws-deployment.md) — what's running, security posture, operating it
- [`distribution.md`](distribution.md) — how builds reach people
- [`../deploy/compose/PROVISIONING.md`](../deploy/compose/PROVISIONING.md) — the runbook, including backups
