# Achievements

## Overview

- **Edge function** `process-achievements` runs after each real workout log (Flutter invokes with `log_id`).
- **Overtakes / ranks** are computed in Edge from live `scores` (same math as client `EventService`), so achievements do **not** depend on `__OVERTAKE__` feed rows (those are inserted after achievements run).
- **Feed:** `__ACH__|` JSON card when something unlocked; **bonus pts** via `achievement_apply_bonus`.

## Deploy

1. SQL: `supabase_patches/36_room_achievements.sql`
2. `npx supabase functions deploy process-achievements --no-verify-jwt`

## Catalog (high level)

| Family | Keys |
|--------|------|
| Habit / volume | night_creature, spam_demon, breaker, exploded |
| Streak | engine, machine |
| Room / idle | warmup, witness, ghost |
| Rivalry | head_hunter, executioner, nemesis |
| Comeback | last_to_first, from_the_dead, uno_reverse, clutch, reclaim_throne |
| Dominance | tyrant, untouchable, no_contest, monopoly |
| Behavior | one_hit_wonder, late_entry, almost, troll_tiny |
| Combo | perfect_storm |

Progress JSON (server) examples: `overtake_total`, `victim_ids`, `max_lead_gap`, `ltf_count`, `uno_total`, `tyrant_logs`, `cushion_logs`, etc.

## Flutter PATH (Windows / Git Bash)

To use `flutter` / `dart` in a shell session:

`export PATH="$PATH:/c/Users/email/flutter_sdk/flutter/bin"`

Add the same line to `~/.bashrc` if you want it permanent in Git Bash.
