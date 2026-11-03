# E11 Console — read first

**Only one chat works on this repository** (Haris, 2026-10-30): the main E11 Console chat, session
`session_01BLZbkbofDcnmdddBfSoot6`.

If you are any other Claude session:
- Do not change code, commit, push, publish, start builds or edit the project docs.
- Tell Haris at once, in your first reply: "Heads up: this isn't your main E11 Console chat. You asked to keep all
  E11 Console work in that one chat, so I won't change anything here. Please continue there."

(Why: on 2026-10-30 two chats worked on the app at once — separate branches, mixed TestFlight builds and a revert
that never reached main.)

## Rule for every native screen of the iPhone app (Haris, 2026-11-03)
When a screen is drawn again, **only what changed changes**: keep each row / card / tile / section by its id or key
with a signature of what it shows, reuse it when it shows the same, make new only what differs, remove only what's
gone — never rebuild a whole list or page for one change. Build new views with no animation around them
(`UIView.performWithoutAnimation`), then run only the screen's own change animation (new fades in, gone fades out,
others slide only when something really came, went or changed height). Every new native screen is built this way.
(Details: project doc `claude/ios-native-polish.md`.)

**Touch and hold, everywhere (Haris, 2026-11-03):** as the comment cards — the whole card shrinks as one (the shared
`PressShrink`) from the moment the finger is down, nothing inside it moves (cards are placed with bounds + center, never
`frame`, so a shrunk card isn't re-laid out); held long enough: a medium haptic, iPhone's own sheet slides up, and the
card springs back. No grey highlight, no iOS context menu with a lifted preview.

**The shared top buttons, everywhere (Haris, 2026-11-03):** they always belong to exactly one screen — the one on top, or,
while it's going (‹, the edge swipe, a tab change), already the one it's going back to, which is shown in place before
the slide starts. Never a moment with no screen (the buttons fade out and in) or a screen hidden under others. Each new
native screen tells the shared buttons where its ‹ / 🔍 / photo / ••• are (`screenSpots`), and its going-back passes
them on the same way as the task page, the client's page and Client Assets do.
