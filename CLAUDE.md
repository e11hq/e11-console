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
**"Redraw" also means sliding and heights — every app (E11 Console, E11 Talk, any new one), now and later (Haris 2026-11-13: "by
redraw i also mean … whenever you update anything the whole thing slides or the heights of other things re adjust"):** an
update to one thing never makes the page slide, never moves what's around it, and never changes another row's height. A row
that changes in place is set at once, laid out without animation, and only its own look changes; nothing else on the page
moves. Rows slide only when a row really came or went — or grew or shrank (a reaction's pill under a bubble): then the rows
below slide smoothly to make room, never jumping (Haris 2026-11-13), the changed row's own content still. Talk's bubbles are
the first done this way (the rule under E11 Talk).
**Never skipped, and checked (Haris, 2026-11-08: "This rule should not be ignored and checked"):** every change to a
native screen is checked against it before it's built — nothing drawn again that didn't change, nothing taken off a screen
that stays (the task page's grey bands vanished on a redraw). The self-test checks it on every build: with a task open the
app goes to another app and back (`away` → `awayBack`) and no screen may be drawn again (`Main.lookRedraws` unchanged), its
Details still on the page (`awayCells` — the grey bands went with Details fully Apple, 2026-11-09). (The redraw came from iPhone's app-switcher pictures, taken in light and dark, read as the phone
changing its look — `followPhoneLook` ignores look changes while the app is in the background.)
**Me too (Haris, 2026-11-08: "Is the me page drawing on every open?"):** Me and its pages set a row again only when what it
shows changed (`HomeView.applyMeList` — each row, the card and each block with a fingerprint); the self-test leaves Me for
another tab and opens it again (`meAway` → `meAgain`) and no row may be set again (`Main.meRows` unchanged).

**Touch and hold, everywhere (Haris, 2026-11-03):** as the comment cards — the whole card shrinks as one (the shared
`PressShrink`) from the moment the finger is down, nothing inside it moves (cards are placed with bounds + center, never
`frame`, so a shrunk card isn't re-laid out); held long enough: a medium haptic, iPhone's own sheet slides up, and the
card springs back. No grey highlight, no iOS context menu with a lifted preview.
**Comments, fully Apple (Haris 2026-11-09 23:14, mock-up "Task Comments — fully Apple" approved, 23:15 "Yes" to the code):**
a comment held gets Apple's own lift and menu — the reactions as Apple's palette on top, then Reply · Edit Comment · Copy
Text, and Trash Comment — not the shrink and sheet above; swipe right on a comment is Apple's Reply and never moves Details ·
Comments (from the left edge or beside a comment it still goes to Details); the comments are rows of Apple's list (a table,
each row's exact height given); + in the comment box is Apple's menu (Camera · Photos · Files); the @ / # lists are Apple's
rows; a reaction or a trashed comment shows at once. Plan: project doc `claude/ios-comments-apple.md`.
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
**And the page still scrolls while typing (Haris, 2026-11-08: "throughout, except task description"):** a list under the
finger scrolls as usual, dragging down takes the keyboard down with the finger (`.interactive`), and only a tap puts it
down — tapping nothing else (`KeyTap` on the list: Apple's tap recognizer, which a scroll never sets off; the list's own
taps wait for it). A button or switch under the finger: the cover takes it, a tap there only puts the keyboard down.
Comments and replies do the same with their own tap (`CommentsFeed`).

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
**Between tabs too — Haris's own exception to Don'ts 4 / 9 (Haris, 2026-11-08 20:07: "add the squash and stretch on +
buttons, if it'll break anything we'll remove"):** as a tab changes and both tabs' first screens have a button in the corner
with different words (+ New task ↔ + Add client), the new one squashes and stretches out of the old one's size, the words
crossfading (`AppleTabs` → `HomeView.fabArrive`). It is OUR animation, not Apple's — Apple's tab switch itself is untouched
and has none. Kept only while it breaks nothing; if anything breaks, it's removed.

**E11 Talk (the chat app, named 2026-11-05 20:11 — was "E11 Chat") is never part of the E11 Console iPhone app (Haris, 2026-11-05: "Remember that"):** on the iPhone, chat is only
ever its own app, E11 Talk — no chat screen, tab or section in E11 Console's iPhone app. On the Mac app it's a separate
Chat section of E11 Console (not on the website — Haris, 2026-11-05). (Plan: project doc `claude/client-groups-app-idea.md`.)
E11 Talk is built on the **test server** first (talk-test.e11hq.com), with its own sign-in for now; **before the App
Store, the shared sign-in goes into both apps and both are sent for review together** (Haris, 2026-11-06).

**E11 Talk design — APPROVED (Haris 2026-11-11 23:49: "Ok all approved"):** the whole canvas "E11 Talk — design" (59
screens dark, the main five light); the startup logo animation stays as Talk has it today (talk/App/Splash.swift).
**E11 Talk is built exactly as its mock-ups (Haris 2026-11-11 23:41):** the canvas "E11 Talk — design" is followed strictly —
every gap, size, colour, placement and every animation, done the Apple way (Apple's parts and Apple's animations set to
match, never our own drawing). Light and dark follow the iPhone. Decisions: project doc `claude/talk-design-reference.md`.
**E11 Talk — every new page carries what the done pages have, from now on (Haris 2026-11-13: "All new pages will have the
same changes onwards"):** each page after 2a–2d is built with every change made on the done ones, without being asked again —
rows as Apple's own cells set to the board (AgencyCell / GroupCell), set again only when what they show changed (a fingerprint),
crossfading in place (`Crossfade` — a still picture inside the row, the old look fading over the new, never both fading);
rows coming, going or moving glide first, the changed ones crossfading after (`applySteady`); search hidden until pulled
down where the board hides it, the head (filters, logo) going with its room while searching, found rows their own identity
(never the list's rows), the words found marked (dark: the board's brown; light: a soft yellow); a search left open closes when
the page leaves; Apple's empty views, their words kept while they fade away and crossfading from one to another; a line under
the title as Apple's subtitle, crossfading; your photo top left, + top right; typing shown in blue on the row; heights from the
content, nothing jumping (no keyboard or note of yours moving a chat); light and dark the phone's, pictures that follow the look.
Before a page is called done, check it against this list and the rules above.
**E11 Talk's messages — one steady behaviour for every bubble (Haris 2026-11-13: "nothing slides while anything changes"):**
a message that changes in place — a reaction, a tick, an edit, a card or link brought up to date, a picture arriving — is set at
in place, crossfading to its new look, no words or pictures inside the bubble moving (set and laid out without animation —
the cell is set inside `performWithoutAnimation`); when it grows or shrinks (a reaction's pill under it) the messages below
slide smoothly to make room, never jumping (Haris 2026-11-13: the pill stays under the bubble).
Only a message coming or going fades in or out. A chat opens where it should without moving (cards kept on the phone). Held:
the bubble lifts in its own shape, tail and all, with nothing round it and no shadow. Every bubble kind, now and later.
**E11 Talk is always the account E11 Console is signed in as (Haris 2026-11-11 23:55):** never a different account on the
same phone; no "Use Another Account" in Talk (dropped, Haris 23:55) — to change account, sign out of E11 Console. Client contacts (no Console)
sign in to Talk only, with Console's sign-in steps (email, password; first time the admin's sign-in code + new password).
**E11 Talk builds — the same way as Console's (Haris 2026-11-12 07:57):** quick builds while working (talk.yml: built,
started once in the simulator, signed and kept — about 2 minutes); a brief self-test of the app runs as the last step,
before a release. Still only on his "build"; TestFlight only on his yes.
**E11 Talk never follows "View as" (Haris 2026-11-11 23:39):** "View as…" is only for E11 Console — E11 Talk always stays
on the main account signed in on the phone (it switched Talk to that person before and cost Haris his own chats, 17:04).
And a backup is always restorable from Settings → Chat Backup (not only on a new phone).
**Initials skip a middle "Al" (Haris, 2026-11-08):** a picture's initials use the first name and the name after a middle
"Al" — Yousef Al Hwij → YH, Lana Al Ramli (or Al-Ramli) → LR. Done in E11 Console (website, Mac and iPhone — every
`initials` in web/ and server/claimsheet.js). **Remember when other apps start or resume (E11 Talk's `Talk.initials`,
any new app): the same rule.**

**Never start a build until Haris says "build" in so many words (Haris, 2026-11-08 10:48: "never send anything to build
untill i say"):** agreeing to a change, a mock-up or "build it this way" is not a build order. Make the change, keep it
local, and wait for him to say to build.

**Every build only on Haris's yes — check builds too (Haris, 2026-11-08: "ask me everytime you run build"):** ask before
any build runs, the simulator check build included. A push to an `ios-*` branch starts a check build by itself, so
changes stay as local commits and are pushed only once Haris says yes to building. **Since 2026-11-08 a push starts no build
at all**, and there's no separate check build: one TestFlight build (`gh workflow run ios.yml --ref ios-nav -f send=yes
-f walk=no`) runs the self-test and **signs and sends nothing if any self-test step fails**.
**Quick builds while working (Haris 2026-11-11 13:00: "I dont want long simulator test now … do it briefly as the last
step"):** builds while working add `-f checks=none` — the app built, signed and sent with no simulator self-test (~10 min,
not ~35); the full self-test (`checks=full`, the default) runs as the last step, before a release or a lock.
**Compile checks (Haris 2026-11-11 14:12: "Yes, compile checks OK"):** `-f checks=compile` only builds the app for the
simulator — nothing signed or sent; run freely while working. The real (TestFlight) build still only on his "build".

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
11. Never make a change that changes the look of an area that's already approved or locked (Haris, 2026-11-08: Home's
    frost, locked, changed by a later setting and broken). A change elsewhere must leave every approved area looking exactly
    as approved — if it would touch one, stop and ask first.

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
- The list: our cards in Apple's list (UICollectionView list), Apple's swipe actions. **Since 2026-11-09 (Haris: "yes" to
  the fully-Apple mock-up "E11 Day — fully Apple"): every task — Home, My Tasks, a client's page, search — is Apple's own
  list cell (HomeCard gives its UIListContentConfiguration: Apple's status symbol in the status colour, title, the line with
  our CD chip, search's "found in" as a third line) in Apple's inset groups with Apple's headers (Today's run by client, then
  Overdue — the order kept); ours inside it only the Urgent / P1 tag and the faces (a green ring when their part is done,
  +N); a client found by search is Apple's cell too. Tap: Apple's selection; hold: Apple's menu with its lift (Attach Files —
  Camera, Photos, Files; Copy link and Trash are on the swipe); swipes: Apple's. Our own card drawing, swipe buttons, press sheet and move animation removed.**
- **The frost: Apple's own, untouched — exactly as in build 1550** (the list's and the search results' `topEdgeEffect.style
  = .automatic`, nothing of ours setting or drawing it). Haris 2026-11-08 11:29: "back how it was, apple's own, on the
  previous locked home" — the firm frost with its line (builds 1562 / 1566) taken off Home. Which frost other Apple pages
  get (the task page had the firm frost with its line since 1566): **since 2026-11-09 every Apple page has Apple's own
  frost untouched, as Home** (Haris: "Automatic, as Home" — the firm one showed at the top under a search bar).
  **The exception: the task's comments (and a thread) — Apple's soft frost, as Details shows** (Haris 2026-11-10: "the
  same soft blur on comments tab as in details"); on automatic Apple picks its firm frost with a line there, because the
  day pills are floating headers.
- Opening a page from it: Apple's push; **the tab bar is hidden with Apple's tab bar call once the page has arrived**,
  and comes back as the slide back begins — never "hide the bottom bar when pushed", and nothing told to the tab bar at
  the slide's first moment: either makes Apple's bar snap small and the big title jump into it.

**iPhone Home, fully Apple — APPROVED and LOCKED (Haris, 2026-11-09 14:04: "Homepage is approved. Lock it."):** build
**1607**, commit 40b3f95, branch `locked/ios-home-1607` (never moved or deleted; the earlier Home lock branches stay as
history). Page 2 of the page-by-page way, from the mock-up "E11 Day — fully Apple": every task Apple's own list cell in
Apple's inset groups (Today's run by client, then Overdue), Apple's status symbol, the line with our CD chip, our Urgent / P1
tag and faces (green ring, +N) as the cell's accessory, an overdue row's faint red tint (10% dark, 6% light), Apple's tap,
Apple's hold menu (Attach Files only), Apple's swipes (Done · Due / Copy link · Trash — rounded while swiped, Apple's own:
left as it is), the counts' jump on Apple's own scroll (left as it is); search: Apple's cells (clients too), "found in" as
Apple's third line, its rows with their own identity (f:) and their own cells; toasts a full pill from their first frame.
The same cell on My Tasks, a client's page and search. Nothing touches it — look, behaviour or code, or a shared piece it
uses (HomeView, HomeCard, HomeClientRow, AppleTabs, AppleNav, SharedFab, ToastCapsule…) — without telling Haris first and his
yes.

**iPhone Home, the task page and My Tasks — LOCKED at build 1629 (Haris, 2026-11-09 22:53: "Home page, Task page, My tasks — Lock"):**
commit 37ac6d4, branches `locked/ios-home-1629`, `locked/ios-task-1629`, `locked/ios-mytasks-1629` (never moved or deleted; the
earlier lock branches stay as history). Holds everything since 1607: the task page's Details fully Apple (Apple's grouped list,
our chips centred, no lines on the boxes' edges, the task cards' colour, Home's background, the grey lock on what you can't
change, Show More, steady heights — no cell, header or footer taking the safe area, the crash found and fixed), a trashed
file going at once, the upload bar with Cancel, My Tasks' strike-through fix and its title exception, E11 Day's three boxes in
the card colour, the list's end gap. Nothing touches them — look, behaviour or code, or a shared piece they use — without
telling Haris first and his yes. (The TestFlight crash recorder, LoopProbe, taken out 2026-11-11 — Haris
asked; no crash notes since.)

**iPhone Home and the task page — COMPLETED and LOCKED (Haris, 2026-11-08 13:21: "the home page and task page is
completed, and they need to be locked, no changes will touch these pages now without me knowing"):** build **1571**, commit
e52c4d7, marked by the branches `locked/ios-home-1571` and `locked/ios-task-1571` (never moved or deleted; 1550's branch
stays too).
**Home's lock updated to the latest (Haris, 2026-11-08 13:43): commit 6545ee0, branch `locked/ios-home-6545ee0`** — 1571
plus tapping Home's tab again scrolling all the way up, the big title opening again (not built yet; the next build carries it). **Nothing may touch either page — its look, behaviour or code — without telling Haris first and his yes**,
including a change made for another page or a shared piece they use (the frost, the floating button, the keyboard rule,
CommentsFeed, PageCell, AppleTabs, AppleNav…). Project doc `claude/ios-apple-structure.md`.
- **Every other page follows the locked page of its category** (Don't 9):
  - **Big-title pages** — every tab's first screen: My Tasks, Inbox, Clients, Me, and the role tabs: Content plans (Social),
    Reviews (the CD), Overview / Team / Claims / Expenses (Office Admin) — follow **Home**: Apple's navigation in Apple's tab bar, Apple's big
    title and line, Apple's search in the bar, Apple's bar buttons, our cards in Apple's list with Apple's swipes, **Apple's
    own frost untouched** (as Home), the floating button as Home's.
  - **Pushed pages** — anything opened from a tab: a client's page, Client Assets and its folders, a team member, Me's pages,
    a reply, a content plan (and Content plans opened from Me), a CD's review request, a claim or an expense — follow **the
    task page**: Apple's push, Apple's bar with ‹ / name or control in the middle / •••, the tab bar hidden once the page has
    arrived (Apple's call), each row its own cell of Apple's list (frame placing), **Apple's own frost, untouched, as Home** (Haris 2026-11-09), the
    keyboard rule (lists scroll while typing, drag down, a tap only puts it down).
- Sheets (New task, Add claim / expense, Request amendments, a plan's post, the date and people sheets) are neither: they
  stay iPhone's own sheets as they are.
- What 1571 holds beyond the 1550 lock: Home's frost Apple's own (`.automatic`); "+ New task" not greyed behind a sheet;
  the task page: Details · Comments in Apple's bar, the client line, every row its own cell, the keyboard guide; comments:
  smooth scroll to a highlighted comment, scrolling while typing, Apple's soft blur under the comment box.

**iPhone My Tasks — APPROVED and LOCKED (Haris, 2026-11-08 14:43: "My tasks approved, lock it"):** build **1572**, commit
d592905, branch `locked/ios-mytasks-1572` (never moved or deleted). Nothing touches it — look, behaviour or code, or a shared
piece it uses (HomeView, AppleTabs, AppleNav, AppleMyTasks) — without telling Haris first and his yes. It follows Home: its
own Apple navigation in Apple's tab bar; Apple's big title "My Tasks" with the line under it (how many open; one filter's
name or "N filters"); Apple's search bar (Search tasks, clients or people — it searches everything, as Home's); your photo,
no Talk; Apple's filter button with Apple's own menu (Due ticks; People and AMs with the picked names under them — one, two,
or "first + N more" — both opening the people sheet with search and ticks; Assigned to me for the CD; Waiting for CD review
when on; Clear filters), Apple's filled filter symbol while a filter is on; All / Done as Apple's segmented control at the
top of Apple's list; the cards in Apple's list with Apple's swipes; tasks open with Apple's push; the app opened afresh
starts it with no filters, on All. (Since 1576 the latest: its "+ New task" slides back with the page as Home's — 5eeb050.)

**iPhone Inbox — APPROVED and LOCKED (Haris, 2026-11-08 16:39: "Home, Task, My Tasks, Inbox is locked"):** build **1576**,
commit 5eeb050, branch `locked/ios-inbox-1576` (never moved or deleted). Nothing touches it — look, behaviour or code, or a
shared piece it uses (HomeView, AppleTabs, AppleNav, AppleInbox, SharedFab) — without telling Haris first and his yes. It
follows Home: its own Apple navigation in Apple's tab bar; Apple's big title "Inbox" with its line (how many unread); "Mark all
read" / "Mark all unread" and your photo as Apple's bar buttons, no Talk, no search; All / Unread / Mentions as Mail's
buttons at the top of Apple's list, scrolling away with it; opens on Unread — on All when nothing is unread (Haris 2026-11-10) — (the unread ones at the start stay until another
list is picked); the rows in Apple's list edge to edge as Mail's, with Apple's own swipe (Read / Unread — its button where
Apple puts it, left as it is: Haris 16:15); a birthday opens their greeting; "+ New task" as Home's.
**When the Inbox's page-by-page turn comes (Haris 2026-11-09):** its rows as Apple's cells, edge to edge (mock-up "Inbox —
with the rules", B, approved), **and holding a row shows Apple's peek** (Haris 23:42: "I like this"): the comment or change
it's about, in full, above Apple's menu — without opening the task or marking it read, as peeking a mail in Mail; the
preview tapped opens it. Drawn from the phone's copy (works offline). Mock-up first.
**Started 2026-11-10 09:09 (Haris: "Start inbox apple page"):** each row Apple's own list cell (`InboxCell`, Apple's
subtitle configuration: picture, who did what — bold while unread — the task, one line of what), Apple's highlight, swipe,
hold with the peek (`InboxPeekVC`, from the copy: `notifOpen` → the task's and comments' screens) and Apple's line between
rows; ours inside Apple's cell, as Haris picked: the unread dot and **the time on the first line** (A2), and **Mail's
buttons** stay ours (B1). Empty: Apple's unavailable view (iOS 16: a line). **Locked at build 1643 (Haris 2026-11-10 11:51).**
**My Tasks' and the Inbox's big title — Haris's exception (2026-11-09 19:15):** each time the page shows, Apple's bar is told
its list again (`setContentScrollView` in viewDidAppear). On his phone (iOS 27.2) the bar was left following another, empty
list in the page and the big title stuck; the cause wasn't found, and he chose this over more builds hunting it.

**EVERYTHING LOCKED at the latest — every Apple page, notifications, the server (Haris, 2026-11-10 11:51: "lock the server
states to latest. lock all the apple pages, notification as on the latest state and what ever we have done up till the
latest state"):** iPhone build **1643**, commit 39227d9 — branches `locked/ios-home-1643`, `locked/ios-task-1643`,
`locked/ios-mytasks-1643`, `locked/ios-inbox-1643`, `locked/ios-clients-1643`, `locked/ios-me-1643`,
`locked/ios-comments-1643`, `locked/ios-notifications-1643`; the server **1.9.27**, commit 12191cb — branch
`locked/server-1.9.27` (never moved or deleted; every earlier lock branch stays as history). Locked as they are now:
E11 Day, My Tasks, the task page (Details and comments, fully Apple), the Inbox (fully Apple — Apple's cells, the dot and
time on the first line, ›, Mail's buttons, the peek with the faded comment before, opening on All when nothing is unread),
the Clients pages, Me and its pages, the Claims tab's highlight; notifications — the held preview (notifyui: the task and
the comment as cards, the faded one before), Reply · Mark as Read · Open Task (NotifActions), the categories and thread
from the server, the test notification, which notifications reach the phone (rules.js `onPhone`), the occasion reminders'
recipients, the role in the @ lists; the server's rules and screens at 1.9.27. **Nothing touches any of it — look,
behaviour or code, or a shared piece it uses — without telling Haris first and his yes.**

**iPhone Home, My Tasks, the task page, the Clients list, a client's page, a client's Client Assets and a folder —
LOCKED at the latest (Haris, 2026-11-08 19:19):** commit 0cf8dd7, branches `locked/ios-home-0cf8dd7`,
`locked/ios-mytasks-0cf8dd7`, `locked/ios-task-0cf8dd7`, `locked/ios-clients-0cf8dd7` (never moved or deleted; the earlier
lock branches stay as history). Built in 1579 (with your photo filling its circle without glass, and My Tasks' All / Done going
while searching) plus, not built yet: client logos whole on their own background (LogoLook), the Clients tab's pages
keeping the tab bar. Nothing touches them — look, behaviour or code, or a shared piece
they use (HomeView, AppleTabs, AppleNav, AppleClients, AppleMyTasks, AssetsCtl, SharedFab, LogoLook…) — without telling
Haris first and his yes. The Clients pages: the list follows Home (big title "Clients" and its line, Apple's search, Talk
and your photo, the clients in Apple's list, + Add client); a client's page, a client's Client Assets and a folder are
Apple's pushed pages (‹ · the name and its line · ••• as Apple's own menu, the tab bar staying, each block its own cell of
Apple's list, Apple's own frost as Home (2026-11-09), Apple's search for a client's files, the folders row on top of a client's page
as before).
**iPhone Content plans — mock-up APPROVED (Haris 2026-11-10 18:13: "mockup are approved, dont build it yet"):** canvas
"Content plans — fully Apple". Social's own tab "Plans" (a big-title tab as Home: big title "Content plans" and its line, Apple's
search, your photo — no Talk, no "+ New task"); everyone else from Me › Content plans (pushed, the tab bar staying). The month
tabs under the search (ours, as the Inbox's Mail buttons) — the only way to change month. Waiting for you first, its own group;
status pills ours. A skeleton: status cell, occasions, posts by day; Send Back · Approve on Apple's toolbar (Approve dimmed
while a post is marked); ••• Copy Link and **Trash Skeleton — only its maker (the SE) and the Social Manager, only before any
task is made from it, 30 days in the Trash** (new: website and server too). A post: Apple's sheet, Ask for Changes · Looks
Good; files in Quick Look, links in Safari. Ask for changes: Apple's sheet. Not started: Apple's empty state.
**iPhone Team members — mock-up decisions (Haris 2026-11-10 19:50: "A1, B1, C2, D1, E2, F1, G1"):** canvas "Team members —
fully Apple". Me › Team members (pushed) and an Office Admin's Team tab (big title), Apple's search with Active · Past as its
scope bar, people as Apple's cells in groups by role, each person's role as the website's Role column shows it (Creative Director, Social
Manager, Office Admin + Finance Admin…) as our coloured words under the email. Hold (Admins): Apple's lift and Apple's menu with every
action straight in it — Change Role (Social Manager a role in it, as the website's Role column already shows it — Haris 20:01 "social manager is
already a role"; underneath a Social person in socialMgrIds, nothing changes on the server), Super Admin Rights, Finance Access, Clients They Can See (Freelancers), Make Creative
Director, Restore Access / Remove from Team (only here); your own row only your Finance access; the owner's account locked.
The role guide its own pushed page "What Each Role Can Do". Add member: on Me › Team members (pushed) Apple's + in the bar; on the Team tab "+ Add member" as Home's + New task (Haris 20:07).
A member's page: Apple's grouped list — the person as Apple's cell, Email / Where / Status / Open tasks, Role and Finance Access
as Apple's pull-down menus, Super Admin Rights and Creative Director as Apple's switches. Add Team Member: Apple's sheet.
Mock-up approved (Haris 19:58: "yes").
**iPhone Office Admin (Overview, Claims, Expenses), Me › Trash, Me › My profile — mock-up APPROVED (Haris 2026-11-11 07:25:
"A–I go for it", "use same function we have"):** canvas "Remaining pages — fully Apple". All the first options: **A1** Overview's
three numbers as Apple's cells in a "November" group, each opening its tab; Need HR approval / Office expenses / Client Assets
as Apple's groups with See All. **B1** ••• Month (the last 12, as the website) on Claims and Office Expenses. **C1** ••• Mark All
HR Approved · Set All Paid On… (Finance Admins). **D1** under All: No claims and Not answered yet, as the website's. **E1** a
claim opened: its own pushed page — the person, items by date (a tap opens the receipt in Quick Look), Share PDF, Paid On… ·
HR Approved on Apple's toolbar. **F1** ended subscriptions their own faded group. **G1** Trash: a file or folder shows its own
picture. **H1** a trashed task opens the task page itself, view only, Restore on Apple's toolbar, ••• Delete Forever (Super
Admins). **I1** My profile: Apple's header as Settings (photo, Edit → Apple's menu Take Photo · Choose Photo · Remove Photo,
name, role). Everywhere: Apple's cells, swipes (Claims: right HR Approved, left Paid On…; Office expenses / Trash: left
Delete), hold menus with Apple's lift; Add Claim / Add Subscription / Add Office Expense as Apple's form sheets. Ours, said
plainly: "+ Add …" as Home's, the claims' coloured status words, My profile's role pills, Trash's Mail buttons. Every action
the same function the website / server already has (no new server acts unless the website has it).
**Remind Haris before any Mac app work starts (Haris 2026-11-10 18:34):** the Mac App Store app needs a build for
content skeleton links (files…/p/<id> — the handler is in mac/swift/main.swift on main, commit 4815aab; the server
1.9.30 already tells Apple /p/ is the apps'): until it's out, a skeleton link on a Mac with the app may not open there.
**The Terminal-installed Mac app — put aside (Haris 2026-11-10 18:38: "discard the terminal app for now"):** releases don't
build it (release.yml's mac job off, commit d10cfe1); the installer keeps its last stored build. Its build was failing since
2026-11-09 (pendingFileLink declared only in the App Store app's part). Back only when Haris says.
**The website out of the iPhone app — STARTED (Haris 2026-11-11 08:07: "remove the website completely and only cloudflare
signing will be the only website left"; 08:15 answers):** the iPhone app only — the website stays on the server for the Mac
app (the website in a window) and browsers. In the app the only web pages left: Cloudflare's sign-in / sign-out, and App
Review's own sign-in (`/review/`, kept for now). Yes to cutting the dead website code inside the locked pages (look and
behaviour unchanged, the self-test checks each) and to Home's background behind Home's, My Tasks' and the Inbox's lists. Order:
the main self-test's checks into the no-website run first, Me's 12 hand-offs say "try again", the cut page by page, then after
Cloudflare a tiny server address instead of `/`. Stays (not the website): the shared engine, Svg.swift's hidden logo drawer.
Audit: project doc `claude/ios-website-dependencies-audit.md`.
**Our own sign-in — DECIDED; mock-ups APPROVED (Haris 2026-11-11: "All approved", canvas "Sign-in — fully Apple": email ·
password · sign-in code · set password · Face ID · an admin's code sheet · the other admins' alert · the owner's password and
owner code); server 1.9.36. **LIVE and TEST use only our sign-in since 2026-11-11 16:53 (Haris: "do it")** — Cloudflare's
page skipped (instant authentication, our login method alone on the E11 Console and E11 Console Test Access apps; E11 Talk
still the email code). Back to the email code: add One-time PIN again on that Access app. Plan: project doc `claude/own-sign-in-plan.md`):**
E11 Console first (website, Mac and iPhone; test site first), E11 Talk the same when its work starts. No email, no SMS.
- Cloudflare stays in front, our server its only sign-in provider (Generic OIDC); our page (the wordmark design).
- The email is the username. A password once set; else a **4-digit sign-in code** from an admin: made by any Super Admin
  or Office Admin, for anyone (admins too); one use, only for that email, **24 hours**; a new one cancels the old; 5 wrong
  tries lock it. The first sign-in with a code lets nothing in until a new password is set.
- After that: the apps signed in for good (device key), the website ~30 days; Face ID / Touch ID signs back in on that device.
- A password set with a code: the old one stops at once and that account is **signed out everywhere, silently**. If an
  admin made the code, **every other Super Admin and Office Admin** (not the one who made it, not the person) gets an
  Inbox notification **and a push**: "<admin> made a sign-in code for <person>, and <person>'s password was changed". A
  code that's never used: nothing.
- **The owner's standing code (Haris 2026-11-11 13:11):** the owner signs in the first time on a fresh app — and any time
  the owner's password isn't set or is forgotten — with a fixed 4-digit owner code, always there, the owner's email only;
  then sets a password and adds the team from the owner's view. Its digits are never written in code, GitHub, docs or
  chat — only a hash in the NAS settings; 5 wrong tries lock it for an hour, never for good.
- Both admins locked out: the **owner, through the owner's view**, makes a code for anyone — **no notification to anyone**,
  and the owner's codes stay out of the admins' record (only the owner's view shows them).
- Passwords and codes kept only as hashes; every code recorded (who, for whom, when); removed from the Team page = every
  sign-in stops. Live only after Haris has signed in with it on test (website, Mac, iPhone); the live site switches back to
  Cloudflare's own sign-in with one setting.
**Remind Haris once every page is done page by page (Haris 2026-11-10 17:39):** (B) DONE 2026-11-11 (the website cut, build 1677,
and its last pieces: /app/in, the new client's page) — take out the leftover website code from
the Apple pages (about 60 `pageReady` branches — dead on the phone, which runs without the website), moving the main
self-test's checks into the no-website run (`walktest.py --apple`) page by page first; and the smoothness check — the
self-test filming each moment (open, back, tab switch, a row coming or going, words changing) and flagging a frame that
jumps, as a report first, stopping builds once tuned.
**iPhone Review Requests — mock-up "Review Requests — fully Apple" (Haris 2026-11-10):** content skeletons sent to the CD
come into Review Requests — their own group "Content plans" at the top of Waiting, a tap opening the skeleton (the approved
Content plans page, pushed on the Reviews tab, ‹ back to Reviews) — **A2, Haris 21:09** (asked to be reminded 20:25). The
files sent: a grid of previews (photo / video picture with ▶ and length, a PDF's first page, other files their kind), a tap
opening Apple's Quick Look (Haris 21:04). **Decided 21:15: A2 · B1 · C1 · D2 · G2** — Approve / Request Amendments on
Apple's toolbar (B1); hold: Approve · Request Amendments… · Open Task (C1); the files large and swipeable on the page with a
strip, as now (D2); no download on the iPhone (G2). **21:18: E2 · F2** — Waiting · Reviewed at the
top of the list, scrolling away with it (as My Tasks' All · Done); after a decision, back to the list, the decided one
fading out of Waiting. D2's files swipe left / right between that request's files; a tap opens Quick Look. **Mock-up APPROVED (Haris 21:20: "approved, make it
locally, dont build it yet").** Made locally (not built): the Reviews tab its own Apple screen (MeTabVC "reviews",
APPLE_ROLE_TABS), the requests Apple's cells (Me.swift rvItem), the toolbar, back to the list after a decision; the skeletons
from the engine's `plansForMe` (main, commit 5332db9 — needs the next server release, published together with the app).
**Remind Haris when the Clients pages' page-by-page work starts (Haris 2026-11-09 21:12):** background uploads and downloads
go in with them — plan in project doc `claude/ios-background-transfers-plan.md`.

**iPhone Me and its pages — in Apple's navigation, as iPhone's Settings (Haris 2026-11-08 20:07: "start the me page …
me page and its inner pages"; bar: "Nothing"; "No search"):** Me is its tab's own Apple screen, its big title "Settings" (the tab stays "Me") (AppleMe.swift, AppleTabs'
`meNav`); its pages pushed on it (MePageVC — the tab bar staying, Apple's own frost as Home). Rows are Apple's own: grouped
sections, Apple's headers / footers, Apple's list cells set by Apple's configurations, ›, value, Apple's switch, Apple's
highlight (`HomeView.applyMeList` — a path only Me's pages use; Haris: "Yes, go ahead"). Ours, shown by Apple's cells: the
icons and pictures, and the pages' own blocks (Appearance's phones, About's cards, a member's header, a plan's posts).
**Every new page from now on: Apple's own cells set to our design — never our own views drawing a row (Don't 9; Haris
2026-11-08: "all this time i was thinking we are going apple way").** Say plainly, before it's approved, anything of ours.

**NO DIFFERENCES — every new page (Haris, 2026-11-08 16:39: "there will be no differences in the new pages from these"):**
Home, the task page, My Tasks and the Inbox are locked, and every new page is the same as the locked page of its category —
look, behaviour, animation, and every fix the locked page has had (a Home fix that never reached My Tasks and the Inbox let
their "+ New task" pop in after the slide back: Haris 16:32 "follow the locked page rules strictly"). Before a new page is
built, go through the locked page's behaviours and fixes one by one and match each; the self-test checks the slide back on
every tab with its own Apple screen (`slide_*`).
**No rule missed, no mistakes (Haris, 2026-11-08 16:40: "you will not miss any rule, and no mistakes or miss on those"):**
every rule in this file and the Don'ts is followed on every change — none skipped, none half-done. Before any change: read
the rules that apply (locks, categories, standards, Don'ts, builds, commits) and check the change against each; after it,
check again that nothing was missed — on the change itself and on every page that follows a locked one.

**Steady heights and smooth, every native page — now and later (Haris, 2026-11-09: "Add the height and smoothness to rules
also"):** a row never changes height unless what it shows changed — not as the tab bar goes, not as it scrolls in or out, not
coming back to the page. Our pieces get their exact height, worked out once for the list's width (`DetailCell`); Apple's
rows keep Apple's own height. No cell takes the bar's safe area into its margins (`TaskPage.noSafeArea` — cells and
headers / footers: `insetsLayoutMarginsFromSafeArea = false`): a row passing under Apple's bar took the bar's room into its
height and grew (the rows growing as they scrolled, and the layout loop that stopped the app — found 2026-11-09). Everything comes
in smoothly: no empty flash, nothing growing from nothing, a change crossfading in place (the words, headers and footers),
new rows fading in and gone ones out, the rest sliding only when something really came, went or changed height. The
self-test checks it on every build: each row's height once a page has arrived, after scrolling, and back at the top — the
same row the same height (`holdArrived` / `holdScrolled` / `holdTop`). Every new page too.

**Smooth, everything — every native page, now and later (Haris, 2026-11-09 23:27: "Smoothness add as a rule"):** nothing on
a page ever snaps, blinks, jumps or pops. Every change moves: a new row fades in, a gone one fades out, the others slide
only when something really came, went or changed height (Apple's own list animations); a row that changes in place (a
reaction, an edit, a status) crossfades to its new look; words that change crossfade; a page opens where it should without
jumping (exact heights known up front); scrolling to something is Apple's smooth scroll; what you do shows at once and
animated, and the server's answer takes its place with no blink (a pending one replaced by the real one: no fade, it's
just there). Apple's own animations wherever Apple has one — ours only where Apple has none, and never fighting Apple's.
Before any change is called done, check each moment of it for a snap, blink or jump. Every new page too.

**Smoothness means no snap at all — everything, every app (E11 Console, E11 Talk, any new one), now and later (Haris 2026-11-13:
"on everything smoothness means no snap at all"):** nothing ever appears, disappears or changes in a single frame — not a row,
a word, a picture, a button, a badge, a reaction, a heading, a bar item, a tab's content, a toast, nor what sits beside
something held (the forward button, reactions). A change in place crossfades to its new look in its place (`Crossfade`); what
comes fades in, what goes fades out; something hidden for a moment (while held, while searching) fades out and back. Together
with "redraw" meaning no slide and no other heights changing: the change fades, and nothing else moves. Before any change is
called done, check every moment of it — opening, closing, holding, letting go, a change arriving — for a snap.
**Haris's own exceptions stay (Haris 2026-11-13: "the one i did on purpose stays as it is"):** the no-snap, no-slide and
redraw rules never undo an exception Haris chose on purpose — e.g. a chat's cover and its title bar when it's tapped, the
squash and stretch between tabs, My Tasks' / the Inbox's title exception — each stays exactly as he made it. When a fix for
these rules would touch something that might be one, ask him first.
**What you do shows at once, every Apple page — now and later (Haris, 2026-11-09 20:11):** anything you remove, add, tick or
change on a page (a file trashed, a checklist item ticked, a status set…) shows on the page at once — the gone one fades
out and the rest slide in, Apple's own list animation — never waiting for the server's answer. The server's answer then
draws the page as it really is (a failure brings it back). Every new page too.

**The list's end, every native list page — now and later (Haris, 2026-11-09 18:57):** scrolled to the end, the last card
stops as far above "+ New task" as the button sits above the tab bar (about 19 — `HomeView.endRoom`), the same on E11 Day,
My Tasks, the Inbox, Clients and every new list page; with no button, as far above the tab bar (or the bottom edge).

**One card colour, every native page — now and later (Haris, 2026-11-09 18:59):** every card, box and list row (an inset
group's rows, the task page's Details boxes, E11 Day's three boxes…) has the task cards' own colour (`HomeLook.card`, light
and dark), with no border. Apple's highlight stays Apple's. Every new page too.
The Inbox is apart (Haris 2026-11-09 19:28, mock-up "Inbox — with the rules", B): its rows edge to edge as Mail's with
no colour behind the list — straight on the page's background, Apple's thin lines between them.
**Empty pages, Apple's own — every Apple page, now and later (Haris, 2026-11-10: "for all apple pages and future"):** a list
with nothing to show uses Apple's own empty state (`UIContentUnavailableConfiguration` — its symbol, bold title, the grey line
under it, centred; `AppleEmpty` in a cell under what's above it, or behind the whole list as My Tasks and Home), never a line
of ours; loading is Apple's loading view, never "Loading…"; a search with nothing found is Apple's "No Results · Check the
spelling or try a new search." (iOS 16: the line alone.) Every new page too. Me's pages too since
2026-11-10 (Haris: "do 1–4").
**The line between rows, every Apple page — now and later (Haris, 2026-11-10: Apple's own, "softer"):** the lines in Apple's
lists (Home's, My Tasks', Clients', search's and Me's groups, the task page's Details, the @ / # lists) are Apple's separator
a little fainter (`HomeLook.line`, light and dark). The Inbox's own lines stay as they are. Every new Apple page sets its
list's separator to it.
**One page background, every native page — now and later (Haris, 2026-11-09 19:00):** every page — tabs, pushed pages,
the task page and its comments — has Home's own background (`HomeLook.bg`, light and dark), never Apple's grouped or plain
system background. iPhone's own sheets stay as they are. Every new page too.

**Light and dark, Apple's way — every native screen, now and later (Haris, 2026-11-09: "Yes, start"):** the iPhone app
follows the phone's look and nothing of ours forces one — never `overrideUserInterfaceStyle` on a view, sheet, alert,
nav or the tab bar. Our colours are Apple's dynamic colours (`Look.c(dark, light)`, the system colours, `HomeLook`'s —
each holds both looks), so iPhone switches every screen itself, in its own fade, with nothing drawn again. Only what
Apple can't switch by itself — a layer's border / shadow colour, a gradient — is set again on the change
(`view.followLook`); pictures (the tab bar's icons, the task page's file chips) are drawn again. The website in the app
no longer decides the app's look (`setAppearance` keeps only Automatic's setting). A drawing's signature uses
`HomeLook.key`, never a colour object. The self-test switches the simulator light ↔ dark with the app open
(`lookFlip` → `lookLight` → `lookDark`): every tab's screen on show in the phone's look, none forced, nothing drawn again
(`Main.lookRedraws`). Look.swift; project doc `claude/ios-task-page-apple.md` step 5.

**Page by page, fully Apple — every native page from now on (Haris, 2026-11-09: "we will do each page with all
capabilities before we move to next"):** one page at a time, each finished before the next. Before starting a page, read
every rule in this file and the Don'ts again and check the page against each (Haris 2026-11-09: "read all the rules …
before starting. nothing should be missed"). Each page:
1. Mock-up first (Apple's parts in our design); everything decided with Haris before any code.
2. Fully Apple — only what Apple has no part for is ours, drawn inside Apple's parts; said plainly before it's approved.
3. Light / dark follows the phone (the rule above), nothing drawn again.
4. Only changes update — live, smoothly (the redraw and Live rules above).
5. No website behind it: its data from the copy on the phone; it works offline.
6. Super fast and lightweight; no empty flash; no leftover code (Don'ts 2, 3, 7).
7. Every other rule here (locks, Don't 11, builds, commits).
8. The self-test checks it.
9. The phone keeps only what's needed: the copy updated as data changes and old data discarded — deleted items gone, saved
   screens and pictures / files capped and cleaned, another person's copy removed on a switch or sign-out; what the phone
   keeps is measured (first measured with the startup screen).
10. The first start with no copy on the phone: the startup screen shows Apple's spinner and "Setting up your account"
    under the logo until the copy is in (only then; never again on that phone).
Order: 1 the startup screen (our animated logo stays — Haris 2026-11-09), then Home per its fully-Apple mock-up, then the rest.

**THE iPHONE APP — FINAL, STABLE and LOCKED at build 1690 (Haris, 2026-11-11 19:51: "The app is finalized now. Mark it as
stable release and lock it"):** commit 68753a4, branches `stable/ios-1690` and `locked/ios-app-1690` (never moved or
deleted; every earlier lock and stable branch stays as history). The whole iPhone app is locked as it is — every page, every
behaviour, every shared piece: nothing changes in its look, behaviour or code without telling Haris first and his yes. 1690 =
1687 + the role pages keeping the tab bar away when a count changes (a review request, a content plan, a claim) + photos
tried again by themselves and given to every list showing that person. The full self-test of 2026-11-11 (run 43032414483:
109 + 28 passed, every role walked to the end; its one finding — the Clients rows set again — was Lana's late photo, fixed in
1690) is the release's self-test; no other is run before the App Store (Haris 19:37). The server stays at 1.9.38 on live
(its stable); main's 3a81fe3 (Finance-only search finds no tasks) is on test only. Next: the App Store screenshots — the
approved Style F Dark frames with real captures from the App Review copy (project doc `claude/app-store-screenshots-plan.md`),
then the release.
**THE iPHONE APP — LOCKED at build 1693 (Haris, 2026-11-12 22:45: "lock e11 console after test flight"):** commit 2791fda,
branches `stable/ios-1693` and `locked/ios-app-1693` (never moved or deleted; 1690's stay as history). 1693 = 1690 + links
from another app (E11 Talk) opening their task / file / folder every time (waits until the app is active), and a Client
Assets folder link going to the Clients tab to open there. Quick build, no simulator self-test (Haris: "No not full test").
Nothing changes in its look, behaviour or code without telling Haris first and his yes.
**THE iPHONE APP — LOCKED at build 1694 (Haris, 2026-11-12 23:06: "Yes"):** commit f2aea47, branches `stable/ios-1694` and
`locked/ios-app-1694` (never moved or deleted; 1693's and 1690's stay as history). 1694 = 1693 + a Client Assets folder link
opening even when that client's Client Assets hadn't been worked out on the phone yet (from Home it was dropped without a
word). Quick build, no simulator self-test. Nothing changes in its look, behaviour or code without telling Haris first and his yes.
**THE iPHONE APP — LOCKED at build 1695 (Haris, 2026-11-12 23:28: "Yes"):** commit dc88240, branches `stable/ios-1695` and
`locked/ios-app-1695` (never moved or deleted; 1694's and earlier stay as history). 1695 = 1694 + a folder link closing the
Client Assets left open from before (after a folder was closed, the next link did nothing) + a file or folder link that can't
open saying why on the screen on show. Quick build, no simulator self-test. Nothing changes without telling Haris first and his yes.
**THE iPHONE APP — LOCKED at build 1696 (Haris, 2026-11-12 23:52: folder links "opening now"):** commit d32e7b6, branches
`stable/ios-1696` and `locked/ios-app-1696` (never moved or deleted; 1695's and earlier stay as history). 1696 = 1695 + a
folder link from any tab going to the Clients tab (its key is "projects" — the link looked for "clients", and from Home the
folder opened out of sight). Quick build. Nothing changes without telling Haris first and his yes.
**THE iPHONE APP — LOCKED at build 1699 (Haris, 2026-11-13 10:44: "build and then lock 1698" — the build came out as 1699,
the number taken by a cancelled compile check):** commit 5677572, branches `stable/ios-1699` and `locked/ios-app-1699` (never
moved or deleted; 1696's and earlier stay as history). 1699 = 1696 + a Client Assets photo link opening every time (tried
again until its folder's files are in — de000ad) + the phone's notification address only on the server the app is on now (moved
live ↔ test, the server before is told to forget it — live's morning summary reached a phone on test). Quick build. Nothing
changes without telling Haris first and his yes.
**THE iPHONE APP — LOCKED at build 1700 (Haris, 2026-11-13 19:06: "Lock 1700"):** commit 3ba6903, branches `stable/ios-1700`
and `locked/ios-app-1700` (never moved or deleted; 1699's and earlier stay as history). 1700 = 1699 + the Sign-in Code sheet's
four boxes each its own view with its own colour (dark grey / white digit in dark, light grey / black digit in light — on the
glass sheet the label's own background came out reversed and the code couldn't be read). Quick build. Nothing changes without
telling Haris first and his yes.
**THE iPHONE APP — LOCKED at build 1710 (Haris, 2026-11-13 22:05: "build both and lock after testflight"):** commit 5387955,
branches `stable/ios-1710` and `locked/ios-app-1710` (never moved or deleted; 1700's and earlier stay as history). 1710 = 1700 +
Out of Office (Me's switch, Apple's calendar sheet sized to it, the card's and the people sheet's orange line, shown at once) +
the Talk button (your Talk unread count as Apple's badge, live from the server; a tap opens E11 Talk) + Me's footers crossfading
when their words change + shorter sheet notes. Quick build. Nothing changes without telling Haris first and his yes.
**THE iPHONE APP — STABLE, LOCKED, the App Store release candidate: 1.2.0 build 1728 (Haris, 2026-11-14 14:53: "Send 1728 and
mark it as release candidate and lock it"):** commit 202ef25, branches `stable/ios-1728`, `locked/ios-app-1728` and
`candidate/appstore-ios-1.2.0-build-1728` (never moved or deleted; 1710's and earlier stay as history). 1728 = 1710 + the
App Review sign-in link under our own sign-in page + the timing trial's five fixes, no timers (project doc `claude/speed-plan.md`):
the scripts only when the server's version changes (server 1.9.54+), client logos made ahead small and kept, a task row's CD
chip / status symbol / faces made once and kept, Client Assets' pictures read small and kept (fading in the first time), Me's
pages drawn once. Quick build, no simulator self-test. Nothing changes in its look, behaviour or code without telling Haris
first and his yes.
**E11 TALK — LOCKED at build 109 (Haris, 2026-11-13 22:05):** commit 13abaa4 on talk-chat-1, branches `stable/talk-109` and
`locked/talk-109` (never moved or deleted). Holds every page as built today: Settings and its pages, Auto-download, who reacted,
shared sign-in, client contacts and their codes, Mark as Unread, a chat opening without waiting (row heights kept, photos made in
the background, no repeated server asks), the first start's "Setting up your account", a tab tapped again going to the list's start.
Nothing changes in its look, behaviour or code without telling Haris first and his yes.
**E11 TALK — LOCKED at build 120 (Haris, 2026-11-14 12:02: "Send to test flight and lock after that"):** commit 7563719 on
talk-chat-1, branches `stable/talk-120` and `locked/talk-120` (never moved or deleted; 109's stay as history). 120 = 109 +
a video playing as it opens; a held bubble lifting as a picture in its exact shape (tail and reaction pill), its place empty
while it's up, held anywhere on it (cards included), a held card / photo / link never opening; Talk following E11 Console's
server and its App Review sign-in; the sign-in page the whole screen in Talk's colours; and the speed work (the startup
screen not waiting for the server, one ask at start, link cards' pictures / links / card logos made once off the main thread,
120 Hz) — measured with five timing builds (project doc `claude/speed-plan.md`). Nothing changes in its look, behaviour or
code without telling Haris first and his yes.
**E11 TALK — STABLE, LOCKED, the App Store release candidate: 1.0.0 build 123 (Haris, 2026-11-14 13:08: "Lock the talk app as
stable app store release candidate"):** commit 5f06b6a on talk-chat-1, branches `stable/talk-123`, `locked/talk-123` and
`candidate/appstore-talk-1.0.0-build-123` (never moved or deleted; 120's and 109's stay as history). 123 = 120 + the photo
viewer's buttons Apple's own glass (top, ☺︎, Reply, reactions; Share · Forward + Save · Delete as Photos), the reactions pill as
tall as ☺︎, the foot's soft shade as the top's, the reaction pill no longer cut as a photo flies back into its bubble, your
long messages without the extra room above the words (measured at the width they're laid out at). Kept for later, not done
(Haris 13:04): the viewer's photo blurry then sharp — project doc `claude/speed-plan.md`. Nothing changes in its look,
behaviour or code without telling Haris first and his yes.
**E11 TALK — STABLE, LOCKED, the App Store release candidate: 1.0.0 build 126 (Haris, 2026-11-14 14:01: "Make talk as release
candidate"):** commit 5a55c69 on talk-chat-1, branches `stable/talk-126`, `locked/talk-126` and
`candidate/appstore-talk-1.0.0-build-126` (never moved or deleted; 123's, 120's and 109's stay as history — 126 replaces 123 as
the candidate). 126 = 123 + the files folder made again after signing out (restored photos, a photo sent and group pictures
were lost until the app was closed), the backup keeping a file while a message points to it and keeping group pictures, a file
the server no longer has brought from the iCloud backup, group pictures tried again by themselves, Edit Group held while a new
picture goes up (✕ and Done dimmed, the sheet springs back), and signing out keeping your chats on the phone (the same account
finds them at once; another account's sign-in wipes them first, asked of the server before anything is read). Needs server
1.9.55 (a group's picture stays while the group uses it). Nothing changes in its look, behaviour or code without telling Haris
first and his yes.
**E11 TALK — STABLE, LOCKED, the App Store release candidate: 1.0.0 build 130 (Haris, 2026-11-14 15:04: "130 is a release
candidate, lock it"):** commit 9c8fa29 on talk-chat-1, branches `stable/talk-130`, `locked/talk-130` and
`candidate/appstore-talk-1.0.0-build-130` (never moved or deleted; 126's and earlier stay as history — 130 replaces 126 as the
candidate). 130 = 126 + a group's picture that can't be had showing its client's logo meanwhile (the picture fading in if it
comes); letting go of a held message exactly as in 126 / 127 (128's and 129's changes taken back, Haris 14:50 — the wavy words
as the menu closes are iPhone's own glass). Needs server 1.9.55. Nothing changes in its look, behaviour or code without telling
Haris first and his yes.
**Compile checks: `-f checks=compile -f walk=no`** — without `walk=no` the walk-through for every role runs too (~20 min),
holding the Mac (2026-11-13).
**The App Store release waits for E11 Talk (Haris, 2026-11-11 20:16: "3"):** the Talk button (E11 Day, Clients) does nothing
yet — App Review would reject a button that does nothing (2.1) — so E11 Console and E11 Talk are sent for review together,
Talk's button opening the real app; it stays as it is until then (not hidden, not changed). The screenshots keep it.
**STABLE — iPhone build 1687 and server 1.9.38 (Haris, 2026-11-11 17:41: "secure 1687 aside as the stable version"):**
commit aa5f787, branch `stable/ios-1687`; the server commit 2415d3b, branch `stable/server-1.9.38` (never moved or deleted).
The version to go back to if later work breaks something. Next, in order (Haris 17:41): background uploads and downloads;
then the full self-test in the simulator (roles, smoothness, the rules, reminders, every function) — **not sent to
TestFlight**, its results shared and decided on; then new App Store screenshots (very interactive — mock-ups first) and the
release.
**The App Store release — APPROVED (Haris, 2026-11-06):** the iPhone app 1.1.0, build 1472 (commit 9ca8c16, marked by
the branch `approved/appstore-ios-1.1.0-build-1472` — never moved or deleted) is approved as it is for the App Store.
From now on:
- **Each change is only that change.** It touches only the code for what Haris asked, without disturbing any other code.
- **Before any change, tell Haris what it can reach.** Check what else uses the code it touches. If it can change anything
  beyond what he asked for — or it's a shared rule (a standard above, a shared piece like PressShrink, the top buttons, the
  file row, the frost bar) — tell him first, plainly (which screens or behaviour, and how), and change it only on his yes.
  Say so too when it touches nothing else.
- Nothing is changed, built or sent without his word.
