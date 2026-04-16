# Jars — why it exists, what it does, why you’ll actually use it

**Jars** is a **group fitness app with a scoreboard**: you and your people share a **room**, log real workouts (reps, time, weight), and earn **points** that stack into a **live leaderboard**. It turns “we should work out more” into something **visible, competitive, and a little unhinged** — without turning into a corporate wellness program.

---

## The problem it solves

- **Solo apps** feel empty after week two.  
- **Group chats** devolve into memes; accountability dies.  
- **Spreadsheets** are where motivation goes to die.

Jars gives your crew a **single place** where effort is **counted**, **ranked**, and **celebrated** (or roasted) so showing up is easier than ghosting.

---

## What makes Jars different

### 1. **Your room, your rules**

Create a room, invite friends or teammates, and everyone **competes on the same board**. Points reflect what you logged — weighted exercises, timed holds, cardio blocks — so different training styles can still play in one room.

### 2. **A leaderboard that tells a story**

It’s not just “who has the most points.” You get **rank movement**, **streaks**, **today vs. all-time**, and feed moments when someone **passes** someone else, hits a **PR**, breaks a **silence**, or comes back after disappearing. The room has **memory**.

### 3. **A social feed that isn’t Instagram**

Workouts and special events land in a **room feed** others can react to — so wins (and shame) are **public inside the group**, not lost in DMs.

### 4. **Achievements & milestones**

Room achievements reward **patterns**: consistency, comebacks, rivalries, weird streaks, and moments that only happen when people **actually log**. It’s extra motivation for the middle of the pack, not just #1.

### 5. **AI color commentary (optional)**

The app can run **AI narrative events** after logs: short, persona-voiced lines that react to the board — drama, stats, jokes — so the room feels **alive** even when everyone’s busy. (Toggle and model live in your Supabase setup.)

### 6. **Designed so logging never blocks you**

Logging is built to be fast; the server handles **idle reminders**, **wake nudges**, and **special feed rows** so the group keeps momentum without you playing PM.

---

## Who it’s for

- **Friend groups** who said they’d train together “this year.”  
- **Roommates**, **classmates**, **gym crews**, **remote teams** who want a lightweight competition.  
- Anyone who likes **leaderboards**, **streaks**, and **a little trash talk** more than another habit tracker that guilt-trips you in private.

---

## Why use Jars instead of “just text the group”

| Text thread | Jars |
|-------------|------|
| “Nice!” and forgotten | **Points, ranks, streaks** that accumulate |
| No shared history | **Feed + milestones** |
| You nag people | **The room** nags everyone equally |
| Motivation dies | **Competition + achievements** keep it sticky |

---

## In one sentence

**Jars is Strava’s competitive cousin for your group chat: log workouts, climb the board, and let the room see who’s actually putting in work.**

---

## Technical note (for admins)

Room data, logs, scores, and members live in **Supabase**; the Flutter app is the client. Full-room exports for analysis can be pulled with SQL snapshots (see `docs/sql/room_full_snapshot.sql`).
