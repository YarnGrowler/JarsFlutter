# Jars 2.0 — Redesign Design Doc

**Status:** Proposal / thinking doc
**Direction (decided):** Co-op — *the crew fills one jar together*
**Scope (decided):** Decisive redesign on the existing foundation (keep Supabase/auth/push/realtime + the clean services→providers→screens architecture; rebuild the *model*, *mechanics*, and *UX* on top)
**Goal (decided):** Win back the actual crew (optimize for small, real groups of friends)

---

## TL;DR

Old Jars = **competitive surveillance**: climb 36 ranks, don't fall behind, or we shame you. It spikes for ~2 weeks then collapses — and worst of all it has a **death spiral**: when people go quiet, the app broadcasts everyone's absence to the survivors and *accelerates* the collapse.

New Jars = **co-op**: your crew has **one shared jar** to fill together each cycle. Every workout from anyone fills it. You win as a team. The jar **auto-scales to who's actually active**, so a small or shrinking crew is the *normal, winnable* state — not a failure. We delete every loss-framed mechanic and replace shame with support and celebration.

The name finally means something: **you're all filling the same jar.**

---

## 1. Why the old Jars died (diagnosis)

Grounded in the current code:

1. **Every mechanic is loss-framed.** "You're losing ground" (`__OVERTAKE__`), "you have 30 min to respond" (`__CLOSE_GAP__`), "your streak needs 7 more pts before midnight" (patch `34_streak_nudge`), "X's streak died" (`__DEAD_STREAK__`), "👻 X hasn't logged in 14 days" (`__WAKE__`). The app runs on **guilt and surveillance**.

2. **There's a literal death spiral.** When members go idle, `ensure_idle_wake_cards()` (patches 17–29) fills the feed with ghost cards, the leaderboard fills with zeros (`leaderboard_row.dart`), and the rivalry banner says "no one has punched in today." The app becomes a **funeral broadcast to the people who could still save the room.** One person leaves → it looks deader → the next leaves.

3. **The "welfare stimulus" rewards quitting** (patch `39_idle_welfare_stimulus`). Idle 48h+ → free random points, scaled so the people at the *bottom* (most likely to quit) get the *most*, then announced in the feed. It rewards disappearing, insults the recipient, and demoralizes the active.

4. **The one daily action is slow.** Logging a set = ~15–20 taps/gestures + a 2-second hold-to-confirm + 0–999 scroll wheels (`log_sheet.dart`, ~2,100 lines). Competitors do it in ~15s. Friction on the *one habit the app depends on* is fatal.

5. **It's extrinsic all the way down.** Arbitrary points, meme end-game ranks ("Skibidi," 135k points). Nothing ties to actually getting fitter, so when the competition dies there's nothing left to return for.

**Root cause:** the app optimizes for *activation* (pushing you back) over *retention* (a reason to stay), and it has **negative network effects when it shrinks** instead of degrading gracefully.

---

## 2. The new thesis

> **Keep your crew going. You move together.**

Co-op flips the three fatal properties:

| Old (zero-sum) | New (co-op) |
|---|---|
| You rank *against* friends; someone is always last | You contribute *with* friends; there is no "last" |
| A shrinking room looks dead and doom-loops | The jar auto-scales; a small crew is the ideal, winnable unit |
| Absence is shamed and broadcast | Absence fades quietly; the crew supports and welcomes you back |
| Motivation is fear of falling behind | Motivation is "we're so close — finish the jar" + showing up for people you like |

---

## 3. Core model: **The Jar**

The central object of the whole app.

- Each crew (room) has **one active Jar** = a recurring goal cycle. **Default cycle = 1 week** (Mon–Sun, America/Chicago — the codebase already centralizes day boundaries there; revisit per-crew TZ later).
- The Jar has a **fill target that auto-scales to active crew size.**
  `target = BASE_PER_PERSON × active_member_count` (with a floor so a solo crew still gets a real but achievable goal).
  *Active* = logged ≥1 real workout in the last N days (e.g. 14). Inactive members **don't inflate the target** — so the goal is always sized to who's actually here.
- **Every workout from anyone adds fill.** Fill is derived from the existing per-exercise value (we keep the exercise catalog — it's good and a lot of work). It's now your **contribution to the jar**, not "points to beat people."
- The jar shows **stacked contribution slices** (one color per member). You can see who's pulling weight — light, honest accountability — but it is **not a 1st/last ranking.** Nobody is at the bottom of a list.
- **Fill the jar before the cycle ends → crew win:** celebration, the jar **levels up** (crew tier++), the next jar is a touch bigger/fancier. *Shared progression replaces the individual 36-rank grind.*
- **Don't fill it → no punishment.** "We got 78% — solid. Fresh jar starts now." The frame is always forward. Maybe a little carried momentum.

This single object kills the death spiral: there is no leaderboard-of-zeros, no "you're behind," and a shrinking crew gets a smaller jar instead of a graveyard.

---

## 4. Mechanics: old → new

| System | Old | New |
|---|---|---|
| **Headline metric** | Individual points → 36 ranks (meme end-game) | **Crew jar fill %** + crew tier (shared). Personal contribution shown as a slice, not a rank. |
| **Progression** | Grind to 135k points solo | **Crew tiers** — the jar gets bigger/nicer as the crew sustains cycles |
| **Streak** | Individual, daily, all-or-nothing; one missed day nukes it | **Crew streak** = consecutive cycles the jar was filled (shared → the crew carries an off-week). **Personal rhythm** = "active days in last 7" rolling dots, *no reset, no punishment* |
| **Re-engagement** | Ghost cards, welfare points, midnight guilt push, "you're dead" broadcasts | **Graceful fade** (inactive members quietly de-emphasized) + **opt-in warm support** ("miss you, no pressure") + **comeback celebration** ("Sarah's back! 🎉 the crew kept the jar going") |
| **Notifications** | 3–5 per log; deadlines; "losing ground" | Tight, positive, batched: "jar's 80% full — one session finishes it 🫙", "Marcus hit a PR 🎉", "the crew missed you" |
| **Feed** | Surveillance + ghosts + fake welfare cards | Celebration + support: workouts (jar ticking up live), PRs, comebacks, crew-win moments, reactions/hype |
| **Celebrations / AI** | Manufactured rivalry drama ("respond in 30 min") | AI as a **crew hype-man**: celebrates, encourages, keeps the feed warm when humans are quiet — never a fake rival |
| **Logging** | 2-sec hold + 0–999 scroll wheels, ~15–20 actions | Pick → steppers/type → **one Log tap** (<15s). Last set pre-filled (one-tap repeat). Satisfying "drops into the jar" confirmation |

---

## 5. UX / IA redesign

**Nav (today):** Room · Log · Ranks · You
**Nav (new):** **Crew** · **Log** · **Progress** · **You**

- **Crew (home).** Hero = **the Jar**: "Our jar — 64% full · 3 days left · you + 3 crewmates filling it," with stacked slices. The jar **fills in realtime** as crewmates log (the magic moment: you see it tick up when your friend trains). Below: the warm feed (workouts, PRs, comebacks, crew-win). Replaces `room_screen.dart` + the death-spiral feed.
- **Log.** The fast path above. The single most important UX fix. Rebuild of `log_sheet.dart` down from ~2,100 lines.
- **Progress.** Crew tiers / jar history / crew streak + **your personal journey** (your own contribution over time, PRs, strength milestones, consistency dots). Replaces the shaming `ranks_screen.dart`. This is where the *intrinsic* "I'm actually getting fitter" layer lives.
- **You.** Profile, crews, notification settings (now sane), settings.

**Onboarding:** trim the 8-screen flow; for the relaunch, returning users get a short **"Jars is different now"** moment (see §7).

---

## 6. Systems & architecture

Keep the foundation; rebuild the model on top.

### Keep (the expensive, working plumbing)
- Supabase auth, Postgres, **Realtime**, RLS patterns
- Push infra (FCM native + Web Push) and the `notifications` → Edge → device pipeline
- Riverpod services→providers→screens layering
- The **exercise catalog** (`exercise_data.dart`) and per-room `exercises`
- Reactions; achievements table (repurposed to celebrate effort/comebacks/crew wins, not just top-3)

### Build / change
- **Evolve `group_goals` → the Jar.** Make it **recurring** + **auto-scaling**. Add cycle fields (`cycle_start`, `cycle_end`, `cycle_index`, `target`, `filled`, `status`) — likely a new `crew_jar_cycles` table (room_id, cycle window, target, filled, status) plus `crew_streak` on the room/jar. Progress stops being a naive client-side `sum(points_earned)` (`goal_service.dart`) and becomes an authoritative server value.
- **Move contribution scoring server-side.** Today the client computes points and the server *trusts* them (`log_sheet.dart`), which risks cheating/divergence and breaks if the client dies mid-flow. New: a Postgres function/trigger computes contribution on log insert **and atomically updates jar fill.** One source of truth.
- **Define "active member"** (last real log within N days) once, server-side; it drives target scaling, the active-crew view, and graceful fade.
- **Streaks:** crew streak = consecutive filled cycles (on the jar). Personal rhythm = rolling active-days derived from logs — retire reliance on the brittle consecutive-day `streak_current` chain.
- **Wire realtime to the jar.** The architecture review found streams exist but may not be fully wired to UI. The jar filling live as crewmates log is the emotional core — make it realtime.

### Delete (and good riddance)
> Removing these also deletes the **single buggiest subsystem in the repo** (idle-wake = 16 patches of churn). Code-health win *and* product win.

- Idle-wake ghost cards: `ensure_idle_wake_cards`, `__WAKE__` rows, `notify_room_on_wake_card`, spurious-wake guards (patches 17–29) + `wake_nudge_service.dart` + `wake_quips.dart`
- Welfare stimulus: patch `39`, `__STIMULUS__` rows
- Streak-at-risk guilt cron: patch `34_streak_nudge`
- Loss-framed broadcasts: `__OVERTAKE__`, `__CLOSE_GAP__`, `__DEAD_STREAK__` event types
- The all-member ranking leaderboard (replaced by jar slices + crew progress)

---

## 7. Winning back the crew (relaunch)

The goal isn't "growth," it's **getting your specific friends back.** Trust was burned; the relaunch has to *say so*.

1. **"Jars is different now" screen** for returning users — name what changed in plain language: *no streak shaming, no ghost cards, no charity points. One jar, filled together.* Acknowledging the old hurt is what rebuilds trust.
2. **"Get the band back together"** — one tap to re-invite everyone who was in the room. A reunion flow, not a cold start.
3. **First jar is small and winnable in days** — engineer an early co-op win to rebuild momentum and prove the new vibe within the first session or two.
4. **The feed is warm from second one** — a welcome, the jar, a friendly hype line. It must *never* look dead.

---

## 8. Phased roadmap

- **Phase 0 — Stop the bleeding (do first, ships fast).** Delete the death-spiral mechanics (ghost cards, welfare, guilt cron, loss broadcasts). Make logging fast. Make personal consistency forgiving (no punishing reset). This alone makes the app *not hostile* and is low-risk because it's mostly deletion + one screen rebuild.
- **Phase 1 — The co-op core.** The Jar: recurring, auto-scaling, shared fill + crew streak. Reframe home around it. Realtime fill. Comeback/welcome-back. Support-not-shame re-engagement. Server-side contribution.
- **Phase 2 — Relaunch to the crew.** "It's different now" re-onboarding, reunion re-invite, first winnable jar, celebration polish, AI repurposed as hype-man.
- **Phase 3 — Depth & stickiness.** Personal progress / intrinsic-fitness layer, jar tiers / cosmetics / rewards, richer crew identity, polish.

---

## 9. Open design questions

1. **Cycle length** — weekly (recommended: rhythm + forgiving) vs. flexible/crew-chosen?
2. **Does any individual visibility remain?** Recommendation: contribution *slices* yes, competitive *ranking* no. Confirm.
3. **What does a crew win unlock?** Cosmetic jar tiers (cheap, safe) vs. something with more teeth?
4. **Timezone** — keep Chicago-only, or per-crew? (Matters for cycle boundaries.)
5. **Intrinsic layer now or later** — how much personal "getting fitter" tracking in v1 vs. Phase 3?

---

## 10. The line that sums it up

The old app implemented re-engagement as **funeral announcements visible to the mourners.** The new app makes the default experience *"we've got you, and we're filling this together."*
