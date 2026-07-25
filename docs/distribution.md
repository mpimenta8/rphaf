# Getting rphaf to friends — builds, signing, and platforms

How we put the app on other people's machines, what it costs, and why the first
cut is desktop-only.

**Decision: desktop-first, unsigned.** Ship the macOS/Linux/Windows build with a
one-time "click through the warning" instruction. Defer mobile, and defer the
$99 Apple Developer Program until an iPhone actually needs to be supported.

---

## We build it ourselves — the upstream pipeline is closed to us

`just release-desktop` tags a version that triggers `release.yml` **in
`block/buzz`**, which builds, signs, and notarizes using *Block's* Apple
credentials (see `RELEASING.md`). A fork has no access to those secrets, so that
path doesn't exist for us. Same for `sprout-releases`, the Block-internal
Buildkite pipeline that produces `-block`-suffixed signed builds.

What we have instead:

```bash
just desktop-release-build                          # Apple Silicon (default)
just desktop-release-build x86_64-apple-darwin      # Intel Mac
```

The recipe is already labelled "unsigned, for testing" — that's exactly what we
want, we just also use it for distribution.

> **Sidecars are stubs.** `desktop-release-build` `touch`es empty placeholder
> binaries for `buzz-acp`, `buzz-agent`, `buzz-dev-mcp`, `git-credential-nostr`,
> and the `buzz` CLI. Anything depending on them won't work in that build. For
> the "just chat" cut this is fine — agents are gated off anyway — but it's a
> real constraint the day we fold agents back in.

## You don't need any of this to test the relay

`just dev` runs a local build with your own identity. Signing only matters when
handing an installer to someone else. Don't let the signing question block
relay work — it's entirely downstream of it.

## What each platform costs

| Platform | Free? | What your friend experiences |
|---|---|---|
| **Linux** | ✅ clean | AppImage/`.deb` just runs. No gatekeeping. |
| **Android** | ✅ clean | Self-signed APK. Enable "install unknown apps" once. No Play Store needed (that's a separate $25 one-time fee we don't need). |
| **Windows** | ⚠️ free, with friction | SmartScreen: "Windows protected your PC" → *More info* → *Run anyway*. Recurs per new build. Real code-signing certs run ~$300–500/yr — worse value than Apple's. |
| **macOS** | ⚠️ free, with friction | Blocked on first launch. They must go **System Settings → Privacy & Security → "Open Anyway"**. The old Control-click → *Open* bypass no longer works on recent macOS. CLI alternative: `xattr -dr com.apple.quarantine /Applications/rphaf.app` |
| **iOS** | ❌ **no free path** | See below. |

### iPhone is the only hard paywall

There is no free way to put an app on someone else's iPhone and have it *stay*
there:

- **Free Apple ID sideloading** issues a **7-day** provisioning profile. The app
  stops launching after a week and must be re-signed. AltStore/SideStore
  automate the re-signing, but every friend has to set that up and keep it
  running — untenable for something people rely on for daily chat.
- **TestFlight** and **ad-hoc** distribution both require the paid program.

**One $99/yr membership covers both Apple platforms.** It is not per-platform:

- **Developer ID** signing + notarization → the macOS Gatekeeper warning
  disappears entirely.
- **TestFlight** → iPhones. Up to 100 internal testers with no review; builds
  expire after 90 days.

For a friend group, TestFlight is the nicest distribution channel available at
any price. If we ever pay the $99, we get the Mac fix for free alongside it.

**It's the only part of this project with an external queue** — enrollment can
take days. Start it early if it's needed at all.

## Mobile has no feature gating (the unpriced cost)

The entire "just chat" strip-down is **desktop-only**: `preview-features.json`
plus `<FeatureGate>` / `useFeatureEnabled` under `desktop/src`. There are
**zero** feature-flag references anywhere in `mobile/lib`.

So shipping the Flutter app as-is would hand friends the **full** Buzz surface
on their phones — agents, huddles, workflows, projects — while desktop hides all
of it. Two consequences:

1. Mobile and desktop wouldn't match, which is confusing for precisely the
   non-technical audience this fork exists for.
2. Reaching parity means porting the gating pass to Flutter. That's real work,
   not a config change, and it has to be maintained against upstream.

## What would change the decision

Revisit when any of these becomes true:

- **Someone actually needs mobile.** Then price the Flutter gating work *and*
  the $99 together — they arrive as a pair, not separately.
- **A friend refuses to click through the Gatekeeper warning.** That's the
  cheapest possible trigger for buying the $99, since it fixes macOS alone.
- **We fold agents back in.** The stub-sidecar constraint above stops being
  acceptable, and the build recipe needs real sidecar binaries.

## See also

- `RELEASING.md` — upstream's release flow (the one we can't use)
- `MEMORY.md` § "The 'just chat' strip-down" — how desktop gating works
- `ROADMAP.md` — deferred rebrand and self-hosting work
