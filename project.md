# Couple's Private Vault App — Full Project Specification

> This document is the single source of truth for building this application.
> Read this entire file before writing any code. Do not stop until every
> feature listed here is fully implemented, tested, and working end-to-end.
> If something is ambiguous, make the most reasonable implementation choice
> and note your assumption in a `DECISIONS.md` file rather than stopping to ask.
> Only stop to ask the user for the specific external credentials/values
> listed in the **"Required From User"** section at the very end — nothing else.

---

## 1. What This App Is

A **private, self-hosted, end-to-end encrypted vault app for a married couple**
(husband and wife only). It lets a husband and wife who are physically apart
(e.g. one working abroad) privately share text, photos, videos, voice notes,
and chat — as a halal alternative to pornography, so they can stay emotionally
and physically connected to *each other* while apart.

This is **not** a general-purpose app. It is built for exactly two users per
deployment: one husband, one wife. Every design decision should assume this.

## 2. Non-Negotiable Principles (read this twice)

1. **Security and privacy come before every other feature.** If a feature
   request conflicts with security, security wins. Always ask "could this leak
   private media to someone who isn't the husband or wife?" before building
   anything.
2. **Fully self-hosted. No third-party servers, ever.** No Firebase, no AWS,
   no Google Cloud Messaging relay of actual content, no third-party VPN
   tools (Tailscale etc.), no managed hosting suggestions. The **only**
   server involved is the user's own VPS. If push notifications require
   touching a third-party network (e.g. FCM/APNs, which is unavoidable for
   OS-level push), keep the payload generic/non-descriptive (see §7) so no
   private content or detail ever leaves the user's VPS.
3. **Open source.** Frontend and backend both open source. No obfuscation
   that would prevent the user or others from auditing the code.
4. **Not published to any app store.** Distributed as an installable APK that
   users self-host the backend for and sideload.
5. **Dual-consent is the core trust mechanic.** Either spouse can *add*
   content, reactions, comments, chat messages, wishlist items, etc. freely.
   But **editing or deleting** vault content (text/photo/video entries)
   always requires the *other* spouse's explicit approval before it takes
   effect.
6. **No feature in this document should be dropped or simplified away
   silently.** If something is technically hard, implement the best
   reasonable version of it — do not silently omit it.

---

## 3. Tech Stack

- **Frontend:** Flutter (Android first; keep iOS-compatible where reasonable)
- **Backend:** Python, FastAPI
- **Database:** PostgreSQL
- **Media storage:** filesystem or MinIO on the same VPS, encrypted at rest
- **Realtime:** WebSockets (FastAPI supports this natively) for chat,
  reactions, notifications
- **Face recognition/verification:** self-hosted, containerized service
  (e.g. CompreFace or an equivalent open-source, dockerized face-embedding +
  liveness solution) — must run entirely on the user's VPS, no cloud API
- **Deployment:** Docker Compose, single VPS, one-command install script
- **Reverse proxy / HTTPS:** Caddy or Traefik with automatic Let's Encrypt

---

## 4. High-Level Architecture

```
[ Flutter App (Husband's phone) ]     [ Flutter App (Wife's phone) ]
              |                                    |
              |---------- HTTPS / WSS -------------|
                            |
                     [ User's own VPS ]
                            |
        ------------------------------------------------
        |            |            |            |
   FastAPI       PostgreSQL    Media Storage   Face-verify
   backend       (encrypted)   (encrypted)     service
        |
   Caddy/Traefik (HTTPS, reverse proxy)
```

No component of this system lives outside the user's VPS, except the
minimal, content-free push notification relay described in §7.

---

## 5. Onboarding & Setup Flow

1. User deploys the backend on their own VPS via Docker Compose (one script:
   checks for Docker, installs if missing, pulls containers, prompts for
   `.env` values — domain, DB password, etc.).
2. A lightweight **web-based Admin/Setup Panel** comes up automatically at
   `https://<domain>/admin`, protected by a first-run password the user sets
   immediately.
3. From the Admin Panel, the user generates a **one-time setup code**,
   shown both as text and as a **QR code**.
4. On each spouse's phone, install the Flutter APK, scan (or manually enter)
   the server address + setup code. This auto-fills the connection details.
5. Each spouse independently:
   - Chooses their role (Husband / Wife) — only one of each allowed per
     deployment.
   - Sets their own app password.
   - Registers their face (liveness check via blink detection) for face
     verification.
6. No email/username/traditional account system is used anywhere.
7. **Two spouses can set up from two completely separate physical phones** —
   there is no requirement that both faces be registered from the same
   device.

---

## 6. Authentication & Security

- **Two-factor local auth:** password **and** face verification, both
  required every time the app is opened (not an either/or).
- Face verification includes a liveness check (blink detection) to resist
  simple photo spoofing.
- **Password recovery:** if the password is forgotten, it can only be reset
  after **both spouses** independently pass face verification. No email
  reset, no backend-admin-only reset. (Admin panel access is a separate,
  VPS-owner-level concern — not a normal in-app recovery path.)
- **Auto-lock/timeout:** app locks itself after a period of inactivity,
  requiring full re-authentication.
- **Screenshot & screen-recording block:** `FLAG_SECURE` (Android) / the
  iOS equivalent, applied app-wide.
- **Screen-off auto-hide:** when the app goes to background, the
  recent-apps preview must show a blurred/blank placeholder, never real
  content.
- **App icon disguise:** the installed app can be configured to appear on
  the home screen under a different, innocuous name/icon.
- **Duress/panic PIN:** a secondary PIN that, if entered, opens a decoy
  version of the app with no real/sensitive content, instead of triggering
  any alert.
- **End-to-end encryption:** all vault content, chat messages, and media are
  encrypted such that only the two registered devices can decrypt them; the
  server stores ciphertext only.
- **No local unencrypted backups.** Explicitly excluded — this was
  evaluated and rejected due to risk (see project history: weak-passphrase
  brute-forcing, accidental cloud sync exposure, restore bypassing
  dual-consent). Do not add this feature.
- **No third-party hosting, relay, or VPN app dependency of any kind** for
  core functionality. Connectivity is VPS-based only (see §2.2).

---

## 7. Notifications

- Real-time in-app events (new content, reactions, comments, chat messages,
  consent requests) trigger push notifications to the other spouse.
- Notification **copy must be generic and non-descriptive** — e.g. "You have
  a new update in the app" — never include actual message text, image
  descriptions, or any identifying detail, since push delivery may pass
  through OS-level services (FCM/APNs) outside the user's own
  infrastructure.
- **Daily reminder notifications:** once daily, husband's phone gets a short
  message from a rotating pool along the lines of "your wife has memories
  and things waiting for you that will bring you joy — halal and yours
  alone", and the wife's phone gets the equivalent framed around the
  husband. Maintain a pool of 20–30 varied, short message templates so it
  doesn't feel repetitive; select one at random each day. Every message
  should carry a halal framing intended to redirect interest away from
  haram alternatives.

---

## 8. Core Navigation & Screens

**Post-login home:**
- Two top-level tabs: **Husband** / **Wife**
- Inside each: three content-type sub-tabs: **Text**, **Photo**, **Video**
- A small **History** entry point (icon/button) accessible from Home

**History screen:**
- Chronological list of all activity across both tabs
- Each row shows a preview: thumbnail for photo/video, first portion of
  text for notes
- Tapping an entry navigates directly to that content's full detail view

**Favorite screen:**
- Any text/photo/video entry can be marked favorite
- Dedicated screen listing only favorited content

**Reel screen:**
- TikTok/Reels-style vertical swipe feed combining both spouses' photo/video
  content
- Reactions/comments accessible inline while scrolling
- Should support filtering (e.g. favorites-only, by category)
- **Match effect:** if both spouses have given a ❤️ reaction to the same
  piece of content, show a special highlight/celebration animation the next
  time either of them views it in the feed or detail view

**Categories:**
- Text/photo/video entries can be assigned to user-created, fully custom
  categories (freeform — the app does not hardcode category names)

**Profile screens (one per spouse):**
- Basic profile info, profile photo
- **Anniversary / important dates** field(s)
- **Wishlist** section: each spouse maintains their own wishlist of
  things they'd like; the other spouse can view it. Wishlist items support
  custom categories too (e.g. food, personal preferences)

**"Favorite Lines / Our Phrases" screen:**
- Feature-flag: a Settings toggle to enable/disable this screen entirely
  (off by default is a reasonable choice — confirm with user or default to
  on, your call)
- Two fixed categories: **Husband → Wife** and **Wife → Husband**
- Each is a freeform list where the couple types and saves their own lines
  (the app does not generate or suggest explicit content — it is purely a
  storage/rating tool for content the couple writes themselves)
- Each line supports independent star/numeric ratings from each spouse
  separately (not averaged — show both)
- Supports reactions and comments, same as other content
- Sortable by rating

**Chat screen:**
- Real-time (WebSocket-based) 1:1 chat between the two spouses only
- Supports text, photo, video, voice notes, and small file attachments
  (e.g. PDF)
- Fully end-to-end encrypted, same guarantee as vault content

**Reactions & comments (apply across text/photo/video/chat/phrases):**
- Long-press the react button to open an emoji picker; multiple reactions
  per item allowed
- Show a breakdown of how many reactions came from husband vs. wife
- Comments supported on all content types
- Comments themselves support exactly one reaction type: ❤️ (not a full
  emoji picker)
- Any reaction or comment triggers a (generic, per §7) notification to the
  other spouse

**Countdown to next meet:**
- A settable target date/time for the next in-person reunion, shown
  prominently (e.g. on Home), with a live countdown

**Audit log:**
- Records every consent-relevant action: who added/edited/deleted what and
  when, and who approved/rejected edit/delete requests
- Also records content **views**: which photo/video was viewed, when, and
  how many times, as a simple list

---

## 9. Content & Consent Model

- Either spouse can freely **add** new text/photo/video/chat/comment/
  reaction/wishlist/phrase content.
- **Editing or deleting** an existing text/photo/video vault entry requires
  a request-and-approve flow: requester triggers a request, the other
  spouse gets notified, and the change only takes effect after they
  approve. Until approved, the original content is unchanged.
- All of this is logged in the audit log (§8).

---

## 10. Design System

- Visual style: **minimal, modern**, generous white space, card-based
  layouts
- Primary accent color: **green** ("halal green" — a clean, natural green,
  not neon)
- Both **light mode and dark mode** required, full parity between the two
- Reference pattern (already reviewed with the user): card-based screens,
  soft rounded corners, a hero/status card at the top of key screens,
  bottom navigation bar with an active-state indicator, color-coded status
  badges for pending/approved/rejected states — apply this general visual
  language throughout, adapted to this app's actual screens (not literally
  a prayer-tracker layout)

---

## 11. Deployment Requirements

- Entire backend + admin panel + face-verification service ships as a
  **Docker Compose** stack
- Provide a single install script that:
  - Checks for/installs Docker
  - Prompts for `.env` values (domain, secrets, etc.)
  - Brings up all containers
  - Configures HTTPS automatically via Caddy/Traefik + Let's Encrypt
- Provide a clear `README.md` with step-by-step VPS setup instructions
- The Flutter app is built and given to the user as an installable APK —
  the user will install this themselves; **you (Claude Code) only need to
  scaffold/create the Flutter project structure initially if the user asks
  for that separately — otherwise focus on making the full app buildable
  from source.**

---

## 12. Explicitly Rejected / Out of Scope

Do not implement these — they were considered and rejected during planning:

- Local unencrypted or user-managed encrypted backups
- Any non-VPS "local-only" or phone-as-server mode
- Any third-party hosting, relay service, or VPN app (e.g. Tailscale) as a
  requirement for core connectivity
- Publishing to Google Play / any app store
- Traditional email/username account systems

---

## 13. Self-Verification & Autonomous Problem-Solving

You are expected to work completely autonomously until the entire app
described in this document is built, working, and verified — not just
written.

- After implementing each piece (backend endpoint, screen, feature), test
  it yourself. Run the backend, run relevant checks/tests, fix any errors,
  warnings, crashes, or broken flows you find — do not leave known-broken
  code behind and move on.
- If you hit a bug, missing dependency, build error, type error, or any
  other technical obstacle, **solve it yourself.** Research the fix, try
  alternative approaches, install what you need, adjust the architecture if
  required — do not stop to ask the user how to fix a technical problem.
- If a design decision is ambiguous or not fully specified in this
  document, make the most reasonable choice yourself and record it in
  `DECISIONS.md`. Do not pause the build to ask about it.
- Keep working through the entire feature list in §8–§9 end-to-end —
  backend, Flutter frontend, and their integration — until the app is fully
  functional as a whole, not just individual pieces in isolation.
- The **only** acceptable reason to stop and contact the user before full
  completion is a genuine external blocker that cannot be resolved with
  information or tools available to you (e.g. you truly need a live VPS to
  deploy to, or a real push-notification credential to test real device
  delivery). Everything else — code errors, missing packages, unclear
  implementation details, design ambiguity — is yours to resolve.
- Only once the entire app is built, integrated, and verified working (to
  the fullest extent possible without the items in §13's checklist) should
  you stop and present the "Required From User" list below. Do not ask for
  any of it earlier.

## 14. Required From User (ask for these only at the very end)

Once the app is otherwise fully built and ready to deploy/test, stop and
ask the user for exactly the following, then wire them in:

- [ ] A domain name (for HTTPS via Let's Encrypt) — or confirm IP-only/
      self-signed setup is acceptable for testing
- [ ] VPS access details (IP, SSH access) if you need to deploy directly,
      or confirm the user will run the install script themselves
- [ ] Firebase Cloud Messaging (or equivalent) server key/credentials, if
      push notifications are to be wired to real device delivery (content
      of pushes must stay generic per §7 regardless)
- [ ] Any preferred final app name / icon (for the disguised app icon
      option, and for the true app identity)
- [ ] Confirmation of default state for the "Favorite Lines" feature toggle
      (on or off by default)

Do not ask for anything else mid-build — make a reasonable call and note it
in `DECISIONS.md` instead.
