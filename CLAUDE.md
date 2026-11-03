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

**NOT JUST ANY AGENCY, everywhere (Haris, 2026-11-03):** at the end of every native list screen, beside "+ New task"
(or in the middle when there's none). It shows at once when the whole list fits on the screen, and otherwise fades in
when the list reaches its end and out on scrolling back. Every new native list screen has it.

**Search and filters stick under the bar, everywhere (Haris, 2026-11-03: "that's a standard"):** on every native list
screen with a search bar or filters (My Tasks, the Trash, …) they sit at the top of the list and, once they reach the bar,
stay stuck under it with the frost behind them (`HomeView.pinHead` for a page's own; My Tasks' listHead). Every new one too.

**The frost bar — LOCKED (Haris, 2026-11-03: "revert the frost bar to how it was and lock it"):** on every native screen
the bar's frost is iPhone's own **soft** scroll-edge frost (`topEdgeEffect.style = .soft`), as up to build 1331; only
My Tasks' tabs and filters stuck under the bar use the firm one (`.hard`) while stuck. (Tried and dropped the same day: the
firm frost everywhere, builds 1339 and 1343.) Its strength matches Mail's (Haris 2026-11-03, measured from his screenshots): an invisible `FrostReach`
view joins the frost and reaches 20 pt below the bar as the line comes in, so the strong part covers the whole bar. **Kept and locked as it is (Haris 2026-11-03, build 1345):** a light frost shows ~20 pt below the line —
iPhone's soft frost can't be cut at the line; don't shorten it or switch to the firm one without Haris. The switch-over (big title → small title, Mail's timings) is unchanged and
locked too. Don't change either without Haris. Every new native screen uses HomeView's bar.

**TestFlight only on Haris's yes (Haris, 2026-11-03):** "publish, publish app build" builds, self-tests and signs the
iPhone app, then keeps it on his Mac (ios.yml `send: ask`, the default). When a build has finished, ask Haris; only on
his yes send it with the "Send to TestFlight" workflow (testflight.yml, its build number).
