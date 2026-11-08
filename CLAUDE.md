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
**Never skipped, and checked (Haris, 2026-11-08: "This rule should not be ignored and checked"):** every change to a
native screen is checked against it before it's built — nothing drawn again that didn't change, nothing taken off a screen
that stays (the task page's grey bands vanished on a redraw). The self-test checks it on every build: with a task open the
app goes to another app and back (`away` → `awayBack`) and no screen may be drawn again (`Main.lookRedraws` unchanged), the
bands still on the page. (The redraw came from iPhone's app-switcher pictures, taken in light and dark, read as the phone
changing its look — `followPhoneLook` ignores look changes while the app is in the background.)

**Touch and hold, everywhere (Haris, 2026-11-03):** as the comment cards — the whole card shrinks as one (the shared
`PressShrink`) from the moment the finger is down, nothing inside it moves (cards are placed with bounds + center, never
`frame`, so a shrunk card isn't re-laid out); held long enough: a medium haptic, iPhone's own sheet slides up, and the
card springs back. No grey highlight, no iOS context menu with a lifted preview.
Where iPhone's own small popup menu is used instead (file thumbnails and file rows, rows with a menu — Haris 2026-11-06):
it shrinks while pressed, then **Apple's own lift** with its menu (Haris 2026-11-07: "Remove it" — the 2026-11-06
"at its own size" tweak is gone; `PressPreview.make` keeps only the rounded shape). Every new popup-menu hold does the same.

⟶ *Being replaced by Don't 10 (Haris 2026-11-07): page by page, as each moves into Apple's navigation, tab bar and top bar, Apple's own does this — this rule then no longer applies there. Done: Home.* **The shared top buttons, everywhere (Haris, 2026-11-03):** they always belong to exactly one screen — the one on top, or,
while it's going (‹, the edge swipe, a tab change), already the one it's going back to, which is shown in place before
the slide starts. Never a moment with no screen (the buttons fade out and in) or a screen hidden under others. Each new
native screen tells the shared buttons where its ‹ / 🔍 / photo / ••• are (`screenSpots`), and its going-back passes
them on the same way as the task page, the client's page and Client Assets do.

**NOT JUST ANY AGENCY, everywhere (Haris, 2026-11-03):** at the end of every native list screen, beside "+ New task"
(or in the middle when there's none). It shows at once when the whole list fits on the screen, and otherwise fades in
when the list reaches its end and out on scrolling back. Every new native list screen has it.

⟶ *Being replaced by Don't 10 (Haris 2026-11-07): page by page, as each moves into Apple's navigation, tab bar and top bar, Apple's own does this — this rule then no longer applies there. Done: Home.* **Search and filters stick under the bar, everywhere (Haris, 2026-11-03: "that's a standard"):** on every native list
screen with a search bar or filters (My Tasks, the Trash, …) they sit at the top of the list and, once they reach the bar,
stay stuck under it with the frost behind them (`HomeView.pinHead` for a page's own; My Tasks' listHead). Every new one too.

⟶ *Being replaced by Don't 10 (Haris 2026-11-07): page by page, as each moves into Apple's navigation, tab bar and top bar, Apple's own does this — this rule then no longer applies there. Done: Home.* **The scroll bar, everywhere (Haris, 2026-11-03):** on every native page its track starts right under the frost bar's
line — under stuck search / filters too — from the very first moment, and ends just above the tab bar (or the bottom
edge). Never iPhone's own safe-area adjusting (`automaticallyAdjustsScrollIndicatorInsets = false`). Every new page too.

**Live, everywhere (Haris, 2026-11-03: "it is a standard"):** every native page and list shows changes made anywhere else
(another phone, the Mac app, the website) as they happen, without leaving and coming back — drawn again from the app's own
copy when the live stream brings a change (`AppData.listen` → `watchCopy`: task pages, comments, Home, My Tasks, Inbox,
Clients), or sent again by the page when what it shows changes (Me and its pages; Client Assets: `asked` in NativeAssets —
a client gone takes its screens away with a toast). Something deleted while it's open goes away with a toast. Every new
native page too.

**A tap away from typing only puts the keyboard away, everywhere (Haris, 2026-11-04):** on every native page where you
type (comments, Team members' search, My profile…), a tap anywhere else while the keyboard is up
closes the keyboard and nothing else — it never taps the row, card or button under the finger (`KeyboardShield.attach`).
The box being typed in, and the comment box's own buttons, keep working. A task's description is apart: it locks the page
while it's edited and ends only with Done. Every new native page too.

⟶ *Being replaced by Don't 10 (Haris 2026-11-07): page by page, as each moves into Apple's navigation, tab bar and top bar, Apple's own does this — this rule then no longer applies there. Done: Home.* **‹ goes back the way you came, everywhere (Haris, 2026-11-03):** on every native page, ‹ and the edge swipe go back to
where you were before (history) — not up the page's own path. A client's page opened from Home's search goes back to
Home's search, not the Clients list (`clientFrom`, the page's `PageHistory.prev`). Tapping a tab again still goes to that
tab's first screen. Every new native page too.

⟶ *Being replaced by Don't 10 (Haris 2026-11-07): page by page, as each moves into Apple's navigation, tab bar and top bar, Apple's own does this — this rule then no longer applies there. Done: Home.* **A page with its name in the middle of the bar (a client's, Client Assets, Me's pages…), everywhere (Haris, 2026-11-03):**
only that centred name — Home's small title never comes in over it.

⟶ *Being replaced by Don't 10 (Haris 2026-11-07): page by page, as each moves into Apple's navigation, tab bar and top bar, Apple's own does this — this rule then no longer applies there. Done: Home.* **The frost bar — LOCKED (Haris, 2026-11-03: "all pages get the Inbox frost bar except…"):** two kinds, on every native page
now and later (`HomeView.applyFrost`, `Frost`, `FrostWatch` in Home.swift):
- **The Inbox's frost** — iPhone's **firm** scroll-edge frost (`.hard`), even down to the line, **with the line** — on big-title
  pages (Home, My Tasks, Inbox, Clients, Me) and on every page with something stuck under the bar (Trash, Team members, the
  task page with Details · Comments, comments).
- **The soft frost, as Home had it up to 2026-11-03** — iPhone's **soft** frost as strong as Mail's (`FrostReach`, ~20 pt
  below the bar), **no line** — on pages with their name in the middle and nothing stuck (a client's page, Client Assets
  and its folders, My profile, About, Appearance, Shortcuts, a team member).
- Both: **nothing at the top of a page**; they come in once something is under the bar (the firm one fades in where iPhone
  lets it, else it just comes on). A list placed again without scrolling (a category switched back) asks the frost again at
  once (`Frost.nudge`). The switch-over (big title → small title, Mail's timings) is unchanged and locked too.
- Don't change any of it without Haris. Every new native screen uses HomeView's bar.

**Words that change on a showing screen, everywhere (Haris, 2026-11-05: "make it a standard"):** a floating button whose
label changes while it shows (+ Add subscription ↔ + Add office expense, as a tab switches) squashes and stretches into
its new width with the words crossfading (`HomeView.setFab` → `squashFab`); the grey line under a title, or under a page's
centred name, crossfades to its new words instead of jumping (`HomeView.fadeText`). Every new native button and title
line does the same.

**E11 Talk (the chat app, named 2026-11-05 20:11 — was "E11 Chat") is never part of the E11 Console iPhone app (Haris, 2026-11-05: "Remember that"):** on the iPhone, chat is only
ever its own app, E11 Talk — no chat screen, tab or section in E11 Console's iPhone app. On the Mac app it's a separate
Chat section of E11 Console (not on the website — Haris, 2026-11-05). (Plan: project doc `claude/client-groups-app-idea.md`.)
E11 Talk is built on the **test server** first (talk-test.e11hq.com), with its own sign-in for now; **before the App
Store, the shared sign-in goes into both apps and both are sent for review together** (Haris, 2026-11-06).

**Initials skip a middle "Al" (Haris, 2026-11-08):** a picture's initials use the first name and the name after a middle
"Al" — Yousef Al Hwij → YH, Lana Al Ramli (or Al-Ramli) → LR. Done in E11 Console (website, Mac and iPhone — every
`initials` in web/ and server/claimsheet.js). **Remember when other apps start or resume (E11 Talk's `Talk.initials`,
any new app): the same rule.**

**Every build only on Haris's yes — check builds too (Haris, 2026-11-08: "ask me everytime you run build"):** ask before
any build runs, the simulator check build included. A push to an `ios-*` branch starts a check build by itself, so
changes stay as local commits and are pushed only once Haris says yes to building.

**TestFlight only on Haris's yes (Haris, 2026-11-03):** "publish, publish app build" builds, self-tests and signs the
iPhone app, then keeps it on his Mac (ios.yml `send: ask`, the default). When a build has finished, ask Haris; only on
his yes send it with the "Send to TestFlight" workflow (testflight.yml, its build number).
Every time Haris says yes and it's sent, tell him in the same reply what changed since the last TestFlight build, as
short points (new / better / fixed — from the commits between the two builds) — Haris 2026-11-04.

**Commits in Haris's name (Haris, 2026-11-06):** every commit from now on is authored as
`Muhammad Haris Sharif <haris.insights@gmail.com>`, with Claude as co-author (the `Co-Authored-By: Claude …` line). The
commits before stay as they are — published history is never rewritten.

**Which app a change is for (Haris, 2026-11-06):** once E11 Talk is being built, when a request doesn't say clearly
which app it's for (E11 Console iPhone, E11 Console Mac / website, or E11 Talk), ask Haris first — one short question —
before changing anything.

**DON'TS — every app, now and in the future: E11 Console (iPhone, Mac, website), E11 Talk and any new one; each new app's
repo gets them in its CLAUDE.md from the start (Haris, 2026-11-07; project doc `claude/00-DONTS-every-app.md`):**
1. Never alter Apple's code to get something. Find the solution the Apple way — more efficient, never fighting Apple's own
   animations and code.
2. Never leave useless code on a page that doesn't belong to that page.
3. Every app stays lightweight, efficient and super fast — now and in the future.
4. A design change: done by setting Apple's own parts where possible — never our own code mimicking what isn't Apple's.
5. When Haris says something is wrong: first analyse what the real problem is, then fix that problem — never cover it
   over with code of ours that overrides it.
6. Apple never releases broken parts. When an Apple part acts oddly (the big title missing at the start, then taking its
   hidden room on the search results), the cause is ours — find it. Never hide, pad or push the symptom away.
7. Never hide an old part that's no longer used (the old tab bar left invisible). Remove it.
8. Never force something to behave the way it's wanted with code of ours. Find why it doesn't, and fix that.
9. Once Home is final, every page follows Home's structure, and nothing breaks. Apple's parts are set to look exactly like
   our design — never our own code made to draw that design. Every behaviour, animation and reaction is Apple's, in our
   design.
10. Every iOS app from now on uses Apple's navigation, Apple's tab bar and Apple's top bar.

**iPhone Home — LOCKED, the template for every page (Haris, 2026-11-08 01:13: "All fixed and approved, lock it"):** build
**1550**, commit 81ec9dd, marked by the branch `locked/ios-home-1550` (never moved or deleted). Every big-title page
follows it (Don't 9); don't change any of it without Haris. Project doc `claude/ios-apple-structure.md`. In short:
- Its own Apple navigation as the tab's view controller in Apple's tab bar; Apple's big title with the date line under
  it (our 34 bold / 15 grey, set on Apple's bar), shrinking to the small title as the list scrolls — all Apple's.
- Search: Apple's own search bar under the big title, always in the bar (UISearchController, results in Home's own list),
  stuck under the bar as it scrolls. No box of ours, no 🔍 button.
- Bar buttons: Apple's own bar buttons with a picture of ours — your photo; E11 Talk's bubble + "Talk" in the bar's ink
  (white in dark, black in light — no blue), the same room left and right of the two as above and below (commit e3f7099,
  after build 1550 — part of the lock, Haris 2026-11-08).
- The list: our cards in Apple's list (UICollectionView list), Apple's swipe actions; Apple's own frost.
- Opening a page from it: Apple's push; **the tab bar is hidden with Apple's tab bar call once the page has arrived**,
  and comes back as the slide back begins — never "hide the bottom bar when pushed", and nothing told to the tab bar at
  the slide's first moment: either makes Apple's bar snap small and the big title jump into it.

**Before the next App Store review — remember (Haris, 2026-11-08):** do **light ↔ dark switching smoothly, Apple's way**
first (task page plan step 5, project doc `claude/ios-task-page-apple.md`): our screens' colours as Apple's dynamic
colours so iOS fades the look itself, the tab bar following the phone. Not now — only before sending the iPhone app to
App Store review; remind Haris then.

**The App Store release — APPROVED (Haris, 2026-11-06):** the iPhone app 1.1.0, build 1472 (commit 9ca8c16, marked by
the branch `approved/appstore-ios-1.1.0-build-1472` — never moved or deleted) is approved as it is for the App Store.
From now on:
- **Each change is only that change.** It touches only the code for what Haris asked, without disturbing any other code.
- **Before any change, tell Haris what it can reach.** Check what else uses the code it touches. If it can change anything
  beyond what he asked for — or it's a shared rule (a standard above, a shared piece like PressShrink, the top buttons, the
  file row, the frost bar) — tell him first, plainly (which screens or behaviour, and how), and change it only on his yes.
  Say so too when it touches nothing else.
- Nothing is changed, built or sent without his word.
