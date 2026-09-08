# 🪟 Prelimsify — *The Prelims Sahchari*

**A self-hosted, installable UPSC-style test-practice app** — static frontend on
GitHub Pages, Supabase for auth + database + row-level security, wrapped in an
Apple-inspired **"Liquid Glass"** design system.

No build step. No server to maintain. Every rule about who can see or touch what
data lives inside Postgres itself.

```
┌─────────────────────────────┐        ┌───────────────────────────┐
│   Browser (GitHub Pages)     │        │   Supabase (hosted)        │
│   HTML + CSS + vanilla JS    │ ─────▶ │   Postgres · Auth · RLS    │
│   installable as a PWA       │ ◀───── │   SECURITY DEFINER RPCs    │
└─────────────────────────────┘        └───────────────────────────┘
```

---

## 📚 Table of Contents

1. [What it does](#1--what-it-does)
2. [Module map](#2--module-map)
3. [Module: `index.html` — the app shell](#3--module-indexhtml--the-app-shell)
4. [Module: `js/app.js` — the engine](#4--module-jsappjs--the-engine)
5. [Module: `css/styles.css` — the Liquid Glass design system](#5--module-cssstylescss--the-liquid-glass-design-system)
6. [Module: `admin.html` + `js/admin.js` — the admin console](#6--module-adminhtml--jsadminjs--the-admin-console)
7. [Module: Supabase — schema, RLS & functions](#7--module-supabase--schema-rls--functions)
8. [Module: PWA layer — manifest, service worker, offline page](#8--module-pwa-layer--manifest-service-worker-offline-page)
9. [Module: `js/no-inspect.js` — soft anti-cheat layer](#9--module-jsno-inspectjs--soft-anti-cheat-layer)
10. [Data flow: life of a test attempt](#10--data-flow-life-of-a-test-attempt)
11. [File structure](#11--file-structure)
12. [Setting it up from scratch](#12--setting-it-up-from-scratch)
13. [Debugging history — issues found & fixed](#13--debugging-history--issues-found--fixed)
14. [Known trade-offs](#14--known-trade-offs)

---

## 1 · What it does

| Feature | Description |
|---|---|
| 🕐 **Timed tests** | Loads a question set (`.json` or a custom `.hysom` text format), renders a question palette, applies negative marking, and produces a pass/fail results screen. |
| 💾 **Saved Projects** | Question sets can be saved and re-attempted or re-shared later without re-uploading the source file. |
| 🏆 **Score history / Score Board** | Every completed test is logged privately, and a shared board shows everyone's results. |
| 👤 **Accounts** | Username-based sign-up/login via Supabase Auth (email confirmation disabled → behaves like plain username + password). |
| 🛡️ **Admin panel** | A separate `admin.html` page — an `admin`-role account can view every user, grant/revoke `can_use_app`, and manage any user's saved projects. |
| 📲 **Installable (PWA)** | The same site installs to a phone home screen or desktop while remaining a normal website. |

---

## 2 · Module map

Every piece of the app is one of these seven modules. Click a heading below to jump to its deep-dive.

```
                         ┌─────────────────────┐
                         │      index.html       │  ← app shell / markup
                         └──────────┬───────────┘
                                    │ loads
              ┌─────────────────────┼─────────────────────┐
              ▼                     ▼                     ▼
      css/styles.css          js/app.js            js/no-inspect.js
     (Liquid Glass UI)     (engine, 1700+ lines)     (soft anti-cheat)
                                    │
                                    │ talks to
                                    ▼
                          Supabase JS client (CDN)
                                    │
                                    ▼
                    ┌───────────────────────────────┐
                    │   Postgres + Auth + RLS         │
                    │   profiles · quiz_projects       │
                    │   test_history · scoreboard_view  │
                    └───────────────────────────────┘
                                    ▲
                                    │ same backend, separate page
                         ┌──────────┴───────────┐
                         │  admin.html + admin.js │
                         └───────────────────────┘

               ┌─────────────────────────────────────┐
               │  manifest.json · sw.js · offline.html │  ← PWA layer, sits
               │  (installability, not offline data)    │    beside everything
               └─────────────────────────────────────┘
```

---

## 3 · Module: `index.html` — the app shell

`index.html` is pure markup — no inline logic beyond wiring up scripts. It's built as a
stack of **overlays and screens** that `app.js` shows/hides rather than separate pages,
so navigation feels instant (no reload, no route changes):

- **`#homeScreen`** — landing view: `authGate` (Login / Create account) if signed out,
  or `loggedInHome` (account panel, Start Test, Score Board button) if signed in.
- **`#authOverlay`** — the login/signup modal, one shared form (`#authForm`) whose
  mode (`login` vs `signup`) is tracked in a hidden input and swapped by `app.js`.
- **`#scoreHistoryOverlay`** — modal listing the signed-in user's past attempts.
- **`#appShell`** — the test-taking surface itself:
  - a **loader body** (`#loaderBody`) with two input paths — paste raw JSON
    (`#jsonInput`) / upload a `.json` or `.hysom` file (`#fileInput`), or paste
    `.hysom`-format text directly (`#hysomInput`) — plus test settings
    (time limit, marks for correct/wrong, pass mark) and the **Saved Projects** list.
  - the **live test UI**: timer, answered/total counter, running score, a question
    palette, zoom controls, pause/exit/reset buttons, and a progress bar.
  - a **results screen** rendered once the paper is submitted or the timer expires.

The `<head>` also carries the PWA hooks (`<link rel="manifest">`, icon links,
theme-color) and the Supabase JS CDN `<script>` tag that `app.js` depends on.

---

## 4 · Module: `js/app.js` — the engine

The single largest file in the project (**~1,735 lines**) and the brain of the whole
app. It has no framework and no build step — everything runs as plain functions wired
to DOM events. Grouped by responsibility:

| Group | Representative functions | What it does |
|---|---|---|
| **Zoom & gestures** | `getTextZoom`, `applyTextZoom`, `changeTextZoom`, `bindTrackpadGestures` | Lets a user pinch/zoom the question text without zooming the whole page. |
| **Session persistence** | `saveTestSession`, `restoreTestSession`, `clearTestSession` | Snapshots an in-progress test to `localStorage` so a refresh doesn't lose answers. |
| **Screen navigation** | `showTest`, `showHome`, `exitTestToUploadPage` | Swaps which overlay/screen is visible — the app's "router." |
| **Pause / timer** | `pauseTest`, `resumeTest`, `togglePauseTest`, `startTimer`, `formatTime` | Countdown timer with a genuine pause (not just a display freeze). |
| **Score history** | `loadScoreHistory`, `saveScoreHistory`, `renderScoreHistory` | Reads/writes `test_history` in Supabase, mirrored to `localStorage`. |
| **Saved Projects** | `loadSavedProjects`, `saveCurrentQuestionSet`, `deleteSavedProject`, `renameSavedProject`, `renderSavedProjects` | The **local-first sync** system — see §10 below. |
| **Question parsing** | `parseHysom`, `cleanHysomLine`, `validateData`, `loadQuestionSet`, `loadFromTextarea`, `loadHysomFromTextarea` | Converts pasted JSON or `.hysom` text into the internal question-set format, with validation and error messaging. |
| **Auth** | `signInWithUsername`, `createUsernameAccount`, `renameCurrentUsername`, `logoutCurrentUser`, `loadCurrentProfile`, `usernameEmail`, `initSupabase` | Wraps Supabase Auth behind a **username**, not an email — internally maps `username` → a synthetic email address Supabase accepts. |
| **Quiz engine** | `buildQuiz`, `renderQuestionPalette`, `clearQuestionResponse`, `updateScore`, `lockPaper`, `submitPaper`, `finalizeResult` | Renders questions/options, tracks answers, applies negative marking live, and computes the final result. |

**Design principle running through the whole file:** every write (saving a project,
logging a score) hits `localStorage` **first** for instant UI feedback, then syncs to
Supabase in the background — see the [data flow](#10--data-flow-life-of-a-test-attempt)
section for exactly how that plays out.

---

## 5 · Module: `css/styles.css` — the Liquid Glass design system

A single ~1,100-line stylesheet, no CSS framework, built entirely on **CSS custom
properties** so the whole visual language is swappable from one `:root` block:

```css
/* Frosted-glass surfaces */
--glass-bg: rgba(255,255,255,.46);
--glass-blur: blur(20px) saturate(180%);
--glass-shadow: 0 8px 32px rgba(31,38,90,.14), 0 1px 0 rgba(255,255,255,.6) inset;

/* Apple-style radii, motion & accents */
--r-xl: 28px;
--spring: cubic-bezier(0.25, 1, 0.5, 1);
--accent: #0A84FF;   --accent-2: #5E5CE6;   --accent-3: #FF375F;
```

- **Frosted "glass" cards** — translucent panels (`--glass-bg`, `backdrop-filter: blur`)
  floating over a cinematic wallpaper backdrop, echoing macOS/iOS Big Sur-era glassmorphism.
- **Bento-style layout** — content grouped into rounded, shadowed blocks (`--r-xl`/`--r-lg`)
  rather than flat full-width sections.
- **Spring motion** — every hover/transition uses the same `cubic-bezier` spring curve
  instead of linear/ease, so interactions feel physical rather than mechanical.
- **Legacy tokens preserved on purpose** — original black/white variables (`--paper`,
  `--ink`, `--rule`) are kept even though the new palette supersedes them, *specifically*
  so no selector in `app.js`/`admin.js` breaks — the visual refactor never touched a
  single class name.

---

## 6 · Module: `admin.html` + `js/admin.js` — the admin console

A deliberately **separate, tiny page** (22 lines of markup, ~40 lines of logic) rather
than a hidden tab inside the main app — so a non-admin never even downloads admin code:

- Checks the signed-in user's `profiles.role` on load; anything other than `'admin'`
  shows an explicit error (not a silent blank page — see the debugging notes in §13.3
  for why that distinction mattered).
- Lists every user with their `can_use_app` flag and a toggle to grant/revoke access —
  the manual "approve new signups" gate.
- Can view, rename, and delete **any** user's saved projects, not just its own — enabled
  entirely by extra admin-scoped RLS policies on the database side (§7), not by any
  special privilege in the JS itself.

---

## 7 · Module: Supabase — schema, RLS & functions

There is **no custom backend server**. GitHub Pages only ever serves static files —
every permission check happens inside Postgres, enforced automatically the moment the
browser calls Supabase.

### Tables

| Table | Purpose | Key columns |
|---|---|---|
| `profiles` | One row per user, auto-created by an `on_auth_user_created` trigger. | `id` (= `auth.users.id`), `username`, `role` (`user`/`admin`), `can_use_app` |
| `quiz_projects` | Saved question sets. | `user_id`, `project_number`, `paper` (jsonb — the full question set + settings), `saved_at` |
| `test_history` | One row per completed test attempt. | `user_id`, `title`, `marks`, `max_marks`, `percentage`, `passed`, `correct`, `wrong`, `unanswered`, `completed_at` |
| `scoreboard_entries` *(view)* | What the homepage Score Board actually queries. | Joins `test_history` ⋈ `profiles`, filtered to `can_use_app = true` |

### Row Level Security, in plain terms

- **Own-data rule (everyone):** a user can `select`/`insert`/`update`/`delete` only
  rows where `user_id = auth.uid()`.
- **Admin override:** an additional policy per table/action, gated by `is_admin()`,
  lets an `admin`-role account see or modify **any** user's rows — this is what powers
  the admin console without any client-side "trust me, I'm an admin" logic.
- **`scoreboard_entries` exists specifically** so the public Score Board can show
  everyone's results without granting every user raw `select` on `test_history` rows
  they don't own — the view does the joining, RLS never has to be loosened.

### Helper functions (`SECURITY DEFINER`)

| Function | Job |
|---|---|
| `is_admin()` | Checks the caller's own role **without** triggering RLS recursion (the exact bug this avoids is documented in §13.3). |
| `can_use_app()` | Checks the caller's `can_use_app` flag. |
| `ensure_my_profile()` | Self-heals a missing `profiles` row on login. |
| `admin_get_me` / `admin_list_users` / `admin_set_user_permission` | RPCs written for the admin panel — the shipped `admin.js` currently queries `profiles` directly under RLS instead; both work, the RPCs are a documented, ready alternative. |

---

## 8 · Module: PWA layer — manifest, service worker, offline page

Added without changing how the site behaves as a normal website — every piece is
additive.

- **`manifest.json`** — app name, black/white theme colors matching the brand,
  `display: standalone` (hides browser chrome once installed).
- **`icons/`** — 192px & 512px icons, a maskable 512px variant for Android's adaptive
  icon shapes, and a 180px Apple touch icon.
- **`sw.js`** — a service worker that is **deliberately network-first**, not
  cache-first, for *every* request:
  ```js
  // Page navigations & static assets: try network first,
  // cache the response as a fallback, only serve cache/offline.html
  // when the network genuinely fails.
  ```
  This matters because the site ships `no-cache` headers on `index.html` while under
  active development — a cache-first worker would silently keep serving old, buggy
  versions after every fix.
- **`offline.html`** — a minimal, friendly dead-end shown only with zero connectivity.
  The app is inherently online-only (everything is Supabase-backed), so this is not
  real offline functionality, just a softer failure state.

**Install behaviour:** Android Chrome shows an automatic install prompt · iPhone
Safari requires Share → *Add to Home Screen* (Apple disallows automatic prompts for
third-party sites) · desktop Chrome/Edge shows an install icon in the address bar.

---

## 9 · Module: `js/no-inspect.js` — soft anti-cheat layer

A small (36-line), intentionally lightweight script that discourages casual
right-click / dev-tools snooping during a live test. It is **not** a security
boundary — anyone determined can bypass it — it just raises the bar against casual
peeking at answer keys mid-test.

---

## 10 · Data flow: life of a test attempt

```
 1. User opens loader → pastes/uploads a question set (JSON or .hysom)
                              │
                              ▼
 2. parseHysom() / validateData()  →  in-memory question-set object
                              │
                              ▼
 3. buildQuiz()  →  renders questions + palette; saveTestSession()
                     snapshots progress to localStorage on every change
                              │
                              ▼
 4. Timer runs (startTimer) — pause/resume genuinely stops the clock
                              │
                              ▼
 5. submitPaper() / time expires  →  finalizeResult()
                              │
             ┌────────────────┴────────────────┐
             ▼                                  ▼
   Result screen renders            saveScoreHistory() writes to
   instantly from local state       localStorage FIRST (instant),
                                     then inserts into Supabase
                                     `test_history` in the background
                                                  │
                                                  ▼
                                   scoreboard_entries view picks it
                                   up automatically for the shared
                                   Score Board (subject to RLS)
```

The same **local-first, then-sync** pattern governs Saved Projects:
`loadSavedProjects()` always renders whatever is cached in `localStorage`
immediately, then fetches from Supabase and merges — so the panel never looks
empty just because the network is slow. The trade-off: the cache is **per device**,
so a brand-new login on a new device starts empty until the Supabase fetch
completes (expected behaviour, not a bug).

---

## 11 · File structure

```
index.html                        Main app page/markup
admin.html                        Admin console page/markup
manifest.json                     PWA manifest
sw.js                             Service worker (network-first)
offline.html                      PWA offline fallback page
icons/                            PWA icon set
css/styles.css                    Liquid Glass design system (all styling)
js/app.js                         Main app logic + Supabase calls
js/admin.js                       Admin console logic
js/no-inspect.js                  Soft anti-cheat layer
assets/images/                    Static images (pass/fail/scoreboard icons)
supabase_schema.sql               Base schema: tables, view, RLS, helper functions
admin_rls_patch.sql               Admin RPC functions (admin_get_me, etc.)
saved_projects_admin_patch.sql    Admin RLS policies for quiz_projects
test_scores_setup.sql             Superseded/unused alternate scores schema — kept for history
SUPABASE_SETUP.md                 Original setup notes (auth config, first-admin SQL)
```

> ⚠️ **Repo hygiene note:** the archive also contains a stale nested
> `Prelimsify/Prelimsify/` folder — an older copy of `index.html`/`app.js` with no
> admin link and old scoreboard code. GitHub Pages doesn't serve it as long as the
> site's source is the repo root, but it's a trap for editing the wrong copy by
> accident — safe to delete.

---

## 12 · Setting it up from scratch

1. Create a Supabase project.
2. **Authentication → Providers → Email →** turn **Confirm email OFF** (so sign-up
   behaves like plain username + password).
3. Run `supabase_schema.sql` in the SQL Editor, then `admin_rls_patch.sql`, then
   `saved_projects_admin_patch.sql`.
4. Promote the first admin:
   ```sql
   update public.profiles
   set role = 'admin', can_use_app = true
   where lower(username) = 'your_username_here';
   ```
5. Push every file — including `manifest.json`, `sw.js`, `offline.html`, `icons/` —
   to the GitHub repo backing GitHub Pages.
6. Visit the site — install prompts appear automatically where supported.

---

## 13 · Debugging history — issues found & fixed

Kept as a record of what actually broke and why, so a similar symptom is easy to
recognize if it reappears.

### 13.1 · Deleted saved projects reappeared after reload

**Two bugs, both had to be fixed together:**
1. `deleteSavedProject()` / `renameSavedProject()` filtered by
   `.eq('user_id', supabaseUser.id)` — correct for a user deleting their own project,
   but wrong for an **admin** deleting someone else's: the query effectively asked
   "delete where `id = X` **and** `user_id = <the admin's own id>`," matching zero
   rows. Supabase doesn't error on a zero-row delete, so nothing signaled the failure.
2. On the database side, the matching `quiz_projects_update_admin` /
   `quiz_projects_delete_admin` RLS policies had never actually been created — an
   earlier patch script had been interrupted partway.

**Fix:** removed the incorrect `user_id` filter (RLS decides access now, not the
client) and created the missing admin policies.

### 13.2 · Completed test scores didn't save or show

**Root cause:** `app.js` inserts every completed test into `test_history` — a table
that **did not exist** on the live Supabase project. Every insert silently failed
inside a `try/catch` that only logged a console warning.

**Fix:** created `test_history` with correct columns, indexes, and own-row RLS
policies, and (re)created `scoreboard_entries` to read from it.

### 13.3 · Admin page showed "Access denied" for an actual admin

**Root cause:** `profiles` had **two generations of admin policies** stacked at
once — old ones querying `profiles` from *inside a policy defined on `profiles`
itself* (a self-referencing subquery), alongside newer, safer ones built on
`is_admin()`. Postgres RLS re-evaluates on every row access, so a self-referencing
policy triggers infinite recursion — Postgres refuses the whole query with
`infinite recursion detected in policy for relation "profiles"`. This surfaced as a
Supabase error that the page originally masked behind a generic "Access denied."

**Fix:** dropped the old recursive policies, and patched `admin.js` to surface the
actual Supabase error message instead of collapsing every failure into one generic
message — which is what made the recursion error visible in the first place.

### 13.4 · Non-issue: a brand-new phone account had no saved projects/scores

Not a bug. Saved projects and scores are tied to the specific `user_id` that created
them — a new account on a phone is a different user by design and starts empty.
Signing into the *same* account used on desktop restores everything via the sync
described in §10.

---

## 14 · Known trade-offs

- **No build tooling** — every fix is hand-edited directly into `js/app.js` /
  `js/admin.js`. Fine at this size; worth revisiting if the app grows much larger.
- **The service worker adds no real offline capability** — network-first means it
  only buys installability plus a graceful "you're offline" screen, which is
  intentional given how actively the backend/data changes.
- **`admin.js` talks to `profiles`/`quiz_projects` directly under RLS** rather than
  through the `admin_*` RPC functions in `admin_rls_patch.sql`. Both approaches are
  valid — just don't assume the RPCs are already wired in if you go looking for them.
