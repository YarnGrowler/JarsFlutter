iOS ONBOARDING
SKILL DOCUMENT
Front-to-end reference for building iOS onboarding that actually converts

TYPE
Reference / Skill Doc	PLATFORM
iOS (Swift / Flutter)	UPDATED
April 2026
 
00 — The Mental Model
Before any screen is designed, internalize this hierarchy. Every decision in onboarding flows from it.

GOAL	Get the user to their first AHA moment — the moment they feel the value of your app — as fast as possible, while collecting enough information to make their experience personal and sticky.
NOT THE GOAL	Teaching the user how to use your app. Listing your features. Making them admire your design. If they can't feel the value themselves in the first session, the onboarding failed.

Retention stat: 77% of daily active users stop using an app within 3 days of install. iOS apps sit at ~25.6% Day 1 retention. Onboarding is the entire lever you have on this number.

The Three Jobs of Onboarding
•	1. Convince — prove the app is worth keeping before the user has a reason to leave
•	2. Personalize — collect just enough data to tailor the first experience meaningfully
•	3. Activate — get the user to complete the core action of the app at least once

Everything — every screen, every question, every animation — must serve at least one of these three jobs. If it doesn't, cut it.
 
01 — Anatomy of a Full Onboarding Flow
A well-structured iOS onboarding is not a set of slides. It is a sequential funnel, each stage earning the right to the next. Below is the canonical full flow. Not every app needs every stage — remove what doesn't serve your three jobs.

#	Stage	Duration	What Happens / What You Get
01	Splash / Welcome	1 screen, ~3s	Single powerful outcome statement. No features. CTA: Get Started or Continue with Apple.
02	Value proposition slides	0–3 screens max	Only use if your app is genuinely novel. Each slide answers: 'Why does my life get better?' Not: 'Here is a feature.' Skip entirely for task/utility apps.
03	Sign-in / Account creation	1 screen	Sign in with Apple first. Email second. Social third. Never put this screen first — show value before asking for identity.
04	Personalization questions	3–8 questions	The engine of the flow. Each answer must change something downstream. If the answer changes nothing, the question gets cut. Drives investment + tailoring.
05	Processing / Plan reveal	5–10 second screen	'Analyzing your answers... building your plan.' Animated loader + social proof. Creates anticipation. Psychological priming before paywall. Table stakes in 2026.
06	Paywall / Subscription	1 screen (long scroll)	Placed AFTER personalization so copy reflects the user's stated goals. Annual plan as default. 3-day or 7-day trial. See Section 06 for full paywall anatomy.
07	Permission priming screens	1 screen per permission	YOUR screen explaining WHY they need the permission, shown BEFORE the iOS system dialog. Dramatically increases grant rate. Never fire the OS dialog cold.
08	iOS system permission dialogs	OS-controlled	Notifications, location, camera etc. Must only appear after priming screen. Purpose string must be specific: 'to send your study reminders' not 'for better experience'.
09	First-run experience / activation	First session	The onboarding does not end at the paywall. Guide the user to complete the core action. Tooltips, coach marks, empty state CTAs. Contextual, not a tour.
 
02 — Welcome Screen & Value Proposition
The Welcome Screen (Stage 01)
This is the most important screen in the app. You have approximately 3–5 seconds. The user is asking one question: 'Is this worth keeping?' Your welcome screen must answer it before they consciously ask it.

Anatomy of a high-converting welcome screen
•	Headline: outcome-driven, not feature-driven. 'Sleep better in 7 days' beats 'The ultimate sleep tracker'
•	Subheadline: optional, 1 sentence max. Makes the headline specific or adds the mechanism
•	Visual: single, clear illustration or animation. Not a screenshot of the app UI
•	Primary CTA: one button. 'Get Started' or 'Continue with Apple'. Never two equal-weight buttons
•	Sign-in link: subtle, below CTA. 'Already have an account? Sign in'
•	NO: feature lists, logo-heavy headers, navigation bars, multiple CTAs

Copy formula that converts
WRONG: 'StudyFlow — Your school task manager with visual calendar and SMS notifications' RIGHT: 'Never miss a deadline again.' — then subhead: 'Your assignments, exams and projects, with reminders that actually reach you.'

The right copy formula: [Emotional outcome] + [Mechanism that makes it believable]. Users don't care about your features — they care about their problem disappearing.

Value Proposition Slides (Stage 02)
Only use these if your app category is genuinely unfamiliar or if you have a mechanism that users would not expect. Duolingo uses them because 'gamified language learning' is still worth explaining. A to-do list app does not.

Rules if you use them
•	Maximum 3 slides. Optimal is 2. Any more and completion rate drops sharply
•	Each slide: one idea, one visual, one headline, one supporting sentence. That is four elements maximum
•	Progressive: each slide builds on the previous. Not random feature facts
•	The last slide should prime the user for the next step (account creation or personalization)
•	Color system must be consistent across all slides — no per-slide palette changes
•	No skip button if you can avoid it. If you need one, your slides are not earning the tap

The skip button is an admission. Every user who taps it is telling you the screen was not worth their time. Track your skip rate per slide — anything above 20% is a slide that needs to be cut or rewritten.

Current Jars implementation (what’s in the repo right now)
•	Slide 01 — ROOM: Minimal typography + a single “hairline” gradient divider. Message: your crew has one shared leaderboard
•	Slide 02 — PRESSURE: Asymmetric, editorial layout. Message: streaks, ranks, receipts (social pressure as the mechanic)
•	Slide 03 — LOG (interactive): Starts with a random bodyweight exercise and an auto-rolling reps number (0 → target). User completes the moment by press-and-holding anywhere on the screen:
	- Hold progress ring draws around the reps number (not the finger)
	- A purple radial flood expands from the touch point (behind text)
	- Confetti burst fires at the touch point on completion
	- On completion we advance to the next stage
 
03 — Personalization Questions
This is where conversion actually happens. Duolingo, Noom, Fastic, Blinkist — every top-performing subscription app has a question flow. It is not a survey. It is a commitment machine.

Why questions convert
•	The Ikea Effect: people value things they help build. An app that 'knows' your goals feels personal and hard to replace
•	Sunk cost priming: the more a user invests in answering, the less likely they are to abandon before the paywall
•	Progressive commitment: small yes → small yes → small yes → big yes (subscription). Never jump from nothing to a purchase
•	Personalization: if answers genuinely change recommendations, users feel seen — which is the strongest retention signal in mobile

Question design rules
The golden rule: if the answer changes nothing, cut the question
Every question in onboarding must change at least one downstream thing: the plan shown, the paywall copy, the recommendations, the default settings, the empty state. If you are asking 'What is your name?' but not using it in the paywall copy, delete it.

Question format hierarchy
•	Single-select tile grid: best for broad categorization (goal, user type, frequency). Large tappable tiles with icon + label. 2 or 3 columns
•	Multi-select: use sparingly. Best for 'which of these apply to you?' type questions. Max 6 options visible without scroll
•	Binary choice: high-contrast two-option layout. Use for branching logic (student vs professional, beginner vs advanced)
•	Slider / continuous input: use for quantitative input (age range, usage frequency, goal weight). Never use a text field where a slider works
•	Text input: last resort only. Use only for name, email, phone number. Never use for questions with predictable answer sets

Question progression pacing
•	Start easy: first question should be answerable in under 2 seconds with zero anxiety
•	Build toward identity: early questions are behavioral ('how often do you study'), later questions are goal-oriented ('what do you want to achieve')
•	Never ask for sensitive info (age, phone number) before the user has answered at least 3 questions
•	Show progress: 'Step 2 of 6' or a progress bar. Users complete more when they can see the end
•	Positive micro-copy after each answer: 'Got it', 'Great', 'Perfect' — one to two words only, before advancing to next question

Question count benchmarks
Question Count	Drop-off Risk	Best For
1–3 questions	Very low — but low investment	Simple utilities, tools, B2B
4–8 questions	Low — sweet spot	Most consumer apps
9–15 questions	Medium — requires strong pacing	Health, fitness, education, diet
16+ questions	High — only if personalization is core product promise	Noom, Hims/Hers, clinical apps

Advanced question techniques
•	Emotional anchoring: ask 'What would it mean to you if you never missed a deadline?' before asking about features. Gets users into an emotional frame that primes conversion
•	Social proof injection: between questions, add a single-screen social proof beat — '3.2M students have used this to stay on top of their work.' Not a question, just a confidence booster
•	User-type branching: early question identifies a segment (student vs professional), rest of the flow shows different questions, illustrations, and paywall copy for each segment
•	HDYHAU (How Did You Hear About Us): ask this on screen 2 or 3, before personalization. Critical for attribution. Don't put it after the paywall — data quality drops
•	Age/demographic: ask late in the flow. Older users convert to annual at higher rates — use this to inform default plan shown on paywall
 
04 — Permission Strategy
iOS permissions are the single most mishandled part of onboarding. Getting them wrong costs you half your active user base before they experience your core feature.

The hierarchy of permissions
Permission Type	When to Ask	Priming Required?	Grant Rate Without Priming
Push Notifications	End of onboarding, after value is established	YES — always	~40–50%
Camera	Contextual — when user first tries to use camera	YES for non-obvious apps	~55–65%
Location (When In Use)	Contextual OR end of onboarding if core feature	YES — always	~45–60%
Location (Always)	Only after granting When In Use. Never in onboarding.	YES — always	~15–25%
Contacts	Contextual — when user tries a social/share feature	YES — always	~30–45%
Microphone / Speech	Contextual — when voice feature is first accessed	YES	~50–65%
Health / HealthKit	Only after user has seen value from the app	YES — always	~35–50%

The priming screen formula
The priming screen is YOUR screen, shown before the iOS system dialog fires. It is the most high-leverage single screen in the entire onboarding flow. Its only job is to maximize the accept rate on the system dialog.

Priming screen anatomy
•	Large icon: the permission type, clearly visualized (bell for notifications, location pin, camera etc.)
•	Headline: outcome-first, not feature-first. 'Get reminded before every deadline' not 'Enable notifications'
•	Body: one to two sentences. Explains exactly what you will and won't do. Be specific about frequency
•	Primary CTA: 'Enable Reminders' — use the benefit word, not the technical word 'notifications'
•	Secondary option: 'Not now' — small, below the CTA. Builds trust by showing you respect the choice

Copy research from NNG: 'Let StudyFlow send reminders for your deadlines' converts 81% better than 'StudyFlow would like to access your notifications.' Specificity is everything.

The word 'reminders' vs 'notifications'
Never use the word 'notifications' in your priming copy. Users have trained themselves to deny notifications after years of spam. 'Reminders' is personal, useful, and desired. 'Notifications' is unwanted interruption. This single word change measurably lifts accept rates.

Re-engagement after denial
•	If the user denies, never immediately re-request — iOS will not show the system dialog again
•	Show a dismissable in-app banner when they reach the feature that needs the permission
•	Include a deep link to your app's Settings page: UIApplication.open(URL(string: UIApplication.openSettingsURLString)!)
•	Copy: 'Turn on reminders in Settings so you never miss a deadline →'
 
05 — Animation, Motion & Haptics
In 2026 with iOS 18+, animation is not decoration. It is the UX. The difference between an app that feels premium and one that feels vibe-coded is almost entirely the quality of its motion. Flashy is not the goal — purposeful physics is.

The four purposes of animation in onboarding
•	Orientation: shows the user where things came from and where they went. Spatial memory
•	Feedback: confirms that a tap registered. Without it, users tap again
•	Pacing: controls the user's attention and reading speed. Animation slows down overload
•	Delight: earns trust by signaling craft. But only works when it doesn't get in the way

Screen transition animations
The canonical iOS onboarding transition
•	Incoming content: slides in from trailing edge (right), with slight scale-up from 0.95 → 1.0 simultaneously
•	Outgoing content: slides out to leading edge (left), with slight scale-down 1.0 → 0.95
•	Duration: 280–320ms. Never above 400ms — it starts to feel sluggish
•	Easing: spring(response: 0.35, dampingFraction: 0.85). Natural, not mechanical
•	SwiftUI: .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity))

Question card transitions
•	Option tiles: stagger-in. Each tile appears 40–60ms after the previous. Creates a cascade that draws the eye
•	Selected state: scale 1.0 → 1.04 on tap (spring), background fills with accent color
•	Deselected state: scale returns to 1.0, background reverts. Instant — no animation needed
•	Advancing to next question: selected tile briefly pulses (scale 1.04 → 1.08 → 1.0) then full screen transitions

Micro-interaction animations
Element	Animation	SwiftUI
Button tap	scaleEffect 1.0 → 0.96 on press, 0.96 → 1.0 on release	.scaleEffect(pressed ? 0.96 : 1.0) .animation(.snappy(duration: 0.18))
Card hover/lift	scaleEffect 1.0 → 1.02, subtle shadow appears	.scaleEffect(hover ? 1.02 : 1.0) .animation(.spring(response: 0.3))
Progress bar fill	Width expands with spring. Slight overshoot and settle	.animation(.spring(response: 0.4, dampingFraction: 0.7))
Checkmark on selection	Scale from 0 → 1.2 → 1.0 with spring. Opacity 0 → 1	.scaleEffect(selected ? 1 : 0).opacity(selected ? 1 : 0) .animation(.spring(response: 0.3, dampingFraction: 0.6))
Page dot indicator	Active dot: scaleEffect 1.0 → 1.3, width expands to pill. Inactive: 1.0	.scaleEffect(active ? 1.3 : 1.0) .animation(.spring())
Lottie icon animation	Plays on screen appear. Loop gently (2–3s loop). Stops on CTA tap	LottieView(animation: .named("bell")).playing(loopMode: .loop)
Text stagger in	Headline appears 0ms, subtitle at 80ms, CTA at 160ms. Each: opacity 0→1 + offset -12→0	.offset(y: appeared ? 0 : -12) .opacity(appeared ? 1 : 0) .animation(.easeOut.delay(0.08 * index))

Haptics
Haptics are the most underused tool in onboarding. They add physicality. They confirm state. They reward progress. iOS has four haptic types — use them correctly.

Haptic Type	When to Use in Onboarding	Swift API
Impact — Light	Tile selection, toggle state changes, tab switches	UIImpactFeedbackGenerator(style: .light).impactOccurred()
Impact — Medium	CTA button press ('Get Started', 'Continue'), page advance	UIImpactFeedbackGenerator(style: .medium).impactOccurred()
Impact — Heavy	Paywall subscribe button, account creation success	UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
Notification — Success	Completing onboarding, first core action completed, trial started	UINotificationFeedbackGenerator().notificationOccurred(.success)
Notification — Warning	Permission denied, validation error	UINotificationFeedbackGenerator().notificationOccurred(.warning)
Selection	Scrolling through picker options, slider movement	UISelectionFeedbackGenerator().selectionChanged()

Haptics are triggered on user action, not on animation completion. The haptic fires the moment the finger lifts (or on touchdown for heavy actions). Never fire haptics in loops or on screen transitions — it becomes noise.

What NOT to animate
•	Do not animate text that the user needs to read. If text is animating in, the user is not reading it
•	Do not run animations while the user is expected to be making a decision
•	Do not use bounce/overshoot on progress indicators — they feel unstable
•	Do not loop hero animations indefinitely at high intensity — they become distracting
•	Do not animate the background. Gradient shifts and particle effects behind content are 2019
•	Do not use the same animation for every interaction — differentiation communicates meaning
The test: if you turned off every animation in your onboarding, could the user still complete it without confusion? If yes, your animations are purely additive (good). If no, you have embedded navigation logic in motion (bad).
 
06 — Paywall Design & Placement
The paywall is not the end of onboarding. It is the moment the narrative your onboarding built cashes out. Design it as a continuation, not a wall.

When to place the paywall
Placement	Conversion Data	Best For
During onboarding, after questions	Highest. At Mojo, 50% of trial starts come from onboarding paywall	Most consumer subscription apps. Recommended default.
After AHA moment (first core action)	High. User has experienced value — convert at peak motivation	Apps where AHA is achievable in one session (photo editing, AI tools)
Contextual (at feature gate)	Medium. Lower intent users, but very high relevance	Apps with robust free tier
Post-trial expiry	Lower for acquisition, higher for LTV among those who convert	B2B, enterprise tools, high-trust categories

Paywall anatomy
•	1. Hero statement: re-uses the user's stated goal from onboarding. 'You said you want to stop missing deadlines. Here is how.'
•	2. Plan selector: 2–3 options maximum. Annual as default with visible savings ('Save 52%'). Monthly visible but de-emphasized. Never more than 3 plans
•	3. Feature list: 4–6 bullets. Benefits, not features. 'Never miss a deadline' not 'Push notification support'
•	4. Social proof: star rating + review count, or single testimonial from a user with the same goal as this user
•	5. Trial framing: '7 days free, then $X/week. Cancel anytime.' This exact format consistently outperforms alternatives
•	6. CTA: 'Start My Free Trial' or 'Unlock StudyFlow'. Never 'Subscribe Now' — it signals extraction, not value
•	7. Escape: 'Maybe later' or 'Continue with limited access'. Must exist. Apple requires it. Users who see it actually convert MORE because trust increases
•	8. Legal: auto-renews at $X/[period] unless cancelled at least 24h before end of trial. Links to Terms and Privacy. Required by Apple.

The processing screen before the paywall
This is now table stakes in top-performing apps. After the final onboarding question, show a 5–10 second screen that says 'Analyzing your answers... building your plan...' with a progress bar and rotating social proof callouts. What it actually does:
•	Creates anticipation — the user expects something personalized
•	Provides social proof while they wait — '3.2M students trust StudyFlow'
•	Frames the paywall as the delivery of the personalized plan they just built
•	Converts at higher rates than jumping directly from question to paywall

Pricing strategy data (2026)
Best setup by 1-year LTV: weekly plan with a 3-day free trial. Generates 1.5x the average LTV of all other configurations. Annual plans without trials are the worst LTV configuration. Source: Adapty 2026 Paywall Report.

•	Productivity, Lifestyle, Utilities: weekly plan with trial is the 2026 benchmark
•	Health & Fitness, Education: annual plans continue to grow — users invest in longer horizons
•	Shorter trials (3–7 days) outperform 14–30 day trials. They create faster activation-to-pay decisions
•	Annual plan default: users who choose annual have dramatically higher LTV and lower churn than monthly
 
07 — UX Patterns That Separate Good from Great
Progressive commitment arc
The psychological backbone of a converting onboarding. Every step asks for a slightly larger commitment than the previous. The user never faces a big ask cold.
•	Micro-commitment 1: tap 'Get Started' (cost: 1 tap, no risk)
•	Micro-commitment 2: answer an easy question (cost: 1 tap, slightly personal)
•	Micro-commitment 3: answer a goal question (cost: 1 tap, emotionally invested)
•	Micro-commitment 4: create account (cost: email, identity revealed)
•	Macro-commitment: subscribe (cost: money, but preceded by 4 smaller yeses)

The Foot-in-the-Door principle: people who commit to small requests are significantly more likely to comply with larger ones later. Each tap in your question flow is priming the yes on the paywall.

The AHA moment
The AHA moment is the first time the user experiences the actual value of your product — not a description of it, but the thing itself. Map it for your app and then design the entire onboarding to reach it in the minimum number of steps.
•	Spotify: first listen to a personalized playlist after selecting 3 artists
•	Duolingo: completing the first lesson and seeing the XP and streak
•	PhotoRoom: seeing their product photo with the background instantly removed
•	StudyFlow (should be): seeing a reminder actually arrive on the lock screen for a task they just added

FOMO and social proof placement
•	User counts: '3.2M students already on top of their work' — use large round numbers, cite recency
•	Ratings: show App Store rating (if 4.7+) with star count. Place near the CTA, not at the top
•	Testimonials: must match the user's goal/segment. A health app testimonial from 'Sarah, 28' converts better for a female user than 'James, 41'
•	FOMO injection: 'Join 12,000 students who added their exams this week' — recency + specificity

Guest pass / referral before paywall
One pattern worth testing: before the paywall, offer users the ability to invite a friend ('Give a friend 7 days free'). Users who invite before the paywall are more engaged and convert at higher rates. Organic installs from this flow also reduce CAC.

The first-run experience (post-onboarding)
The onboarding does not end at the paywall or permission screens. It ends when the user has successfully completed the core action of the app. Until then, you are still onboarding.
•	Empty state CTAs: never show an empty list with no direction. Empty state must have a clear action: 'Add your first assignment →'
•	Tooltips / coach marks: show only on first launch, max 3 per session, on the highest-value action only. Dismiss on first tap anywhere
•	Contextual hints: triggered by user action, not timer. 'Tap a day to assign tasks to it' appears first time the user views the calendar
•	Never show a feature tour as a modal. Feature tours are 2015. Show contextual hints exactly once at the moment of relevance

What great apps do that average apps don't
•	They name the user. 'Welcome, Alex. Here is your plan.' Personalization that feels human
•	They show a personalized summary screen before the paywall: your goal, your plan, your frequency
•	They use the user's stated goal in the paywall copy. 'For students studying 3x per week who want to stop missing exams'
•	They don't end onboarding at the paywall — they guide the first action inside the app
•	They A/B test every screen. Headline, button copy, illustration, question order, paywall position — everything is a test
 
08 — Copy & Tone System
The words in your onboarding determine your conversion rate more than the design. A badly designed screen with perfect copy will outperform a beautifully designed screen with lazy copy.

Hierarchy of copy quality
Tier	Type	Example
F	Feature copy (the worst)	'Visual calendar with color-coded task categories and SMS notification support'
D	Function copy	'See all your assignments on a calendar and get text reminders'
C	Benefit copy	'Stay on top of every deadline so you can actually enjoy your free time'
A	Outcome + emotion copy (the best)	'Never panic about a deadline again.' — subhead: 'Your future self will thank you.'

Copy rules
•	Headline: maximum 5 words. It must be a complete thought. Test it by covering everything else — does it stand alone?
•	Subheadline: maximum 15 words. One sentence. Adds mechanism or specificity to the headline. Not a second headline
•	Question copy: written as the user would say it, not as a survey designer would write it. 'What's your biggest challenge?' not 'Select your primary use case'
•	CTA copy: starts with a verb. The verb names what the user gets, not what they do. 'Start My Free Trial' (what they get) vs 'Continue' (what they do)
•	Permission priming copy: name the specific action the permission enables, not the permission category itself. 'Get reminded before your exams' not 'Allow notifications'

Tone principles
•	Warm, not corporate. You are talking to a person, not filing a form
•	Confident, not pushy. State outcomes as certainties — 'you will never miss' not 'we hope to help you'
•	Short, not truncated. Short copy is a product of editing, not abbreviation. 'Never miss a deadline again' took many drafts to become 5 words
•	Active voice only. 'We'll remind you' not 'Reminders will be sent'
•	Avoid the words: 'notifications', 'features', 'functionality', 'experience', 'seamless', 'powerful', 'intuitive'. These are filler words that signal lazy copy

Single most important copy test: read your headline to someone who has never heard of your app. If they cannot tell you what problem it solves in their own words, rewrite the headline.
 
09 — Visual & UI System
The visual identity of your onboarding sets the brand expectation for the entire app. Decisions made here are permanent — users remember first impressions and compare everything else to them.

Screen layout constraints (iOS)
Element	iPhone (390pt)	Rule
Safe area top (notch/island)	59pt Dynamic Island / 47pt notch	Never place content in safe area. Use safeAreaInsets.
Safe area bottom (home indicator)	34pt (Face ID), 0pt (Touch ID)	CTA buttons must sit above this zone. 24pt padding minimum above indicator.
Horizontal margins	20–24pt standard	Full-bleed backgrounds are fine. Text and interactive elements must respect margins.
Minimum tap target	44 x 44pt (Apple HIG)	This is non-negotiable. Sub-44pt targets cause missed taps and App Store rejection.
CTA button height	50–56pt recommended	Wider than it is tall. Full-width (minus margins) for primary CTA. Avoids precision-tap fatigue.
Hero illustration height	200–280pt	Never let illustration crowd the CTA below the fold on SE/mini sizes.
Progress indicator height	4–6pt track, pill shape	Segment dots or progress bar. Active segment expands to pill width. Never numbers alone.

Color system rules
•	One primary color for actions, selections, and brand. One accent for highlights. Maximum two semantic colors (error red, success green). Everything else is neutral
•	The dark-on-dark neon trap: if your background is dark, your colored elements must have at least 4.5:1 contrast ratio with the background for accessibility. Saturated neon on dark gray fails this
•	Color must be consistent across every screen. Changing hue per screen destroys brand coherence and signals that different people built different parts
•	Dark mode: test every screen in dark mode during design, not as an afterthought. iOS users switch modes constantly
•	Illustrations and icons must use the same color palette as the interface. Importing a third-party illustration set that uses a different palette breaks visual coherence

Typography rules
•	Two font sizes only for body/label hierarchy. Three maximum for the full screen (headline + subtitle + body)
•	Headline: SF Pro Display Bold, 28–34pt. Or brand font at equivalent weight
•	Subtitle/supporting text: SF Pro Text Regular, 15–17pt, secondary color. Not the same color as headline
•	Question option labels: SF Pro Text Semibold, 15–17pt. Must be legible in both selected and unselected states
•	Never use font-weight alone to differentiate hierarchy — always pair weight change with a size change
•	Line length: maximum 35–40 characters per line for body copy on mobile. Longer lines require the eye to travel too far

Illustration and iconography
•	Use Lottie for animated icons in onboarding (bell ringing, calendar flipping, checkmark drawing). Lightweight, crisp, controllable
•	Avoid screenshots of the app as illustrations — they look unfinished and become outdated the moment the UI changes
•	SF Symbols: use consistently for in-app icons. They scale, adapt to weight changes, and feel native. Do not mix SF Symbols with third-party icon sets
•	Custom illustration style: pick one style (line, filled, 3D) and commit. Mixing styles across screens looks like stock art from three different sources
 
10 — Metrics, Testing & Iteration
An onboarding flow is never finished. It is a continuous experiment. Every number below is a lever, not a score.

The metrics hierarchy
Metric	Benchmark	What to Do When Below Benchmark
Day 1 retention	25%+ (iOS avg)	Shorten time to first core action. Remove friction in first 5 minutes.
Onboarding completion rate	60–75%	Find the drop-off screen. Cut or reorder it. Shorten question count.
Paywall view rate	85%+ of completers	Check if users are exiting before paywall. Add urgency or tighten flow.
Paywall trial start rate	1.35% of installs (onboarding paywall)	A/B test: headline copy, plan default, trial length, CTA button copy.
Trial-to-paid conversion	40–60% (varies by category)	Improve in-trial activation. Send reminder at day 1, day 5 of trial.
Notification permission accept rate	70%+ with good priming	Check priming screen copy. Use 'reminders' not 'notifications'. Test timing.
Question completion rate per screen	>80% per question	Any question with >20% drop means the question feels threatening, too personal, or irrelevant.
Day 7 retention	10–15%+	Improve post-onboarding guidance. Check empty states. Add habit-formation triggers.

What to A/B test first (priority order)
•	Paywall CTA copy — highest impact, lowest effort
•	Paywall plan default (annual vs weekly)
•	Welcome screen headline
•	Question count (cut 2 questions and measure drop-off vs paywall conversion)
•	Paywall placement (during onboarding vs after first core action)
•	Processing screen duration (5s vs 8s vs 12s)
•	Permission priming copy (specific benefit vs generic benefit)

Segmentation to track from day one
•	Channel: organic App Store vs paid UA vs referral. Each segment has different intent and converts differently
•	User type: if you ask a segmenting question early (student vs professional), track all downstream metrics by segment
•	Device: iPhone SE / mini users have different screen constraints than Pro Max users. Drop-off on question screens can be purely layout-related
•	Age: younger users trial more but churn more. Older users convert to annual at higher rates
•	Country/region: pricing expectations, trust signals, and cultural tone vary significantly by market

The most common mistake in onboarding analytics: measuring completion rate of the whole flow instead of per-screen. A 60% completion rate with a 45% exit at screen 3 is a very different problem than a 60% completion rate with distributed 5% drops. Get per-screen data from day one.
 
11 — Apple HIG & App Store Compliance
Non-compliance with Apple guidelines is not a theoretical risk — it is an App Store rejection. These rules are enforced at review and often retroactively via policy updates.

HIG rules that directly affect onboarding
•	Permission purpose strings must be specific. 'Used to send reminders for your assignments' passes. 'For a better experience' will result in rejection
•	Never replicate the system permission dialog with a custom UI. You may show a pre-permission priming screen, but the actual dialog must use the OS standard
•	If your app's core function requires a permission (e.g. camera for an AR app), you may ask at first launch. Otherwise, wait for contextual need
•	Push notifications: you cannot ask for notification permission during onboarding without a clear contextual purpose string. Apple reviews purpose strings
•	'Sign in with Apple' is mandatory if you offer any third-party social sign-in (Google, Facebook). It must be displayed with equal or greater prominence
•	You cannot require a user to sign in before allowing them to explore the app, unless sign-in is required for the core function. Free trials must work without an account

Subscription disclosure requirements
•	Auto-renewable subscriptions must display: trial length, price after trial, billing frequency, and cancellation terms on the paywall — not just in a footer
•	'Cancel anytime' must be truthful. If cancellation stops future charges but does not refund the current period, this must be stated
•	Free trial end reminders: Apple sends a system notification 24h before trial ends. You can and should also send your own in-app reminder
•	Subscription upgrade/downgrade: must honor the current subscription period. Downgrades take effect at next renewal, not immediately

Review guidelines most commonly triggered by onboarding
•	Guideline 2.1 — App Completeness: if critical flows (like account creation or the paywall) are broken or inaccessible to the reviewer, the app is rejected. Always test with a fresh install
•	Guideline 3.1.1 — In-App Purchase: any premium content or feature must be unlockable via IAP. You cannot gate content behind a payment method outside the App Store (except B2B/enterprise)
•	Guideline 5.1.1 — Data Collection: if you collect personal data (name, email, phone for SMS) during onboarding, your privacy policy must describe this collection. Link must be visible on the onboarding screen that collects it

App Store reviewer tip: reviewers test onboarding on a fresh install with no pre-existing account. If your onboarding has any hard dependencies on server state, network availability, or prior user data, it will fail in review.
 
12 — Anti-Patterns: What Kills Onboarding
Every pattern below has a measurable negative effect on conversion, retention, or both. Avoid them unconditionally.

Anti-Pattern	Why It Kills You
Feature tour slides	Users already downloaded the app. Selling them features they can't experience yet is friction with no upside. Converts 30–40% worse than a question flow.
Permission request on first screen	Users have no context for why you need it. Accept rates drop to 40–50% vs 70–80% with priming. You get one chance per permission type — wasting it here is permanent.
Asking questions that change nothing	Users sense when data entry is theater. Every question must visibly change something downstream or the entire question flow loses credibility.
Onboarding that ends at the paywall	Users who subscribe and then land in an empty app with no guidance churn immediately. The first-run experience is as important as the onboarding flow itself.
Multiple CTAs on one screen	Two equal CTAs create decision paralysis. One primary action per screen, always. Secondary options must be visually subordinate.
Dark patterns on paywall	Hiding the cancel/decline option, pre-checked annual subscription, misleading pricing (showing monthly but billing annually) — these cause App Store removal and chargebacks.
Per-screen color palette changes	Looks like four different apps. Destroys brand coherence. Users associate visual dissonance with untrustworthiness.
Sidebar/navigation in onboarding	Onboarding is a linear funnel. Showing navigation chrome gives users the option to leave the funnel. Remove all navigation until onboarding completes.
No skip button AND no exit path	Trapping users in onboarding triggers rage-quit. A skip/maybe-later option paradoxically increases conversion because it builds trust.
Logo-heavy welcome screen	The first screen is not an advertisement for your brand. It is a promise to the user. Replace logo with the outcome headline.
Collecting SMS/phone during onboarding but never explaining why	Phone number is high-trust personal information. If you collect it without explicitly explaining what you will text and how often, abandonment rate spikes and Apple may reject the app.
 
13 — Pre-Launch Checklist
Run this checklist on a fresh device install before every App Store submission.

Welcome & value prop
•	Welcome headline is outcome-driven, maximum 5 words
•	No feature list on welcome screen
•	Single CTA button on welcome screen
•	If using slides: maximum 3, consistent color palette, each slide earns the next tap

Personalization questions
•	Every question changes at least one downstream experience
•	Progress indicator visible on all question screens
•	No question asks for sensitive data (phone, age) before Q4
•	Question copy reads as human conversation, not a survey
•	HDYHAU question included (Q2 or Q3 position)

Permissions
•	Zero cold OS dialogs — every permission has a priming screen
•	Priming screen uses 'reminders' not 'notifications'
•	Purpose strings in Info.plist are specific and approved by Apple's standards
•	Denied permission path is handled gracefully with deep link to Settings
•	Sign in with Apple present if any social sign-in is offered

Animation & haptics
•	All transitions use spring-based easing, not linear or ease-in-out
•	Haptics fire on user action, not on animation completion or screen transitions
•	Reduce Motion respected: all transitions fall back to opacity-only if enabled
•	No background gradient animations or particle effects
•	Lottie animations stop when user taps CTA

Paywall
•	Paywall copy references the user's stated goal from onboarding
•	Maximum 3 plan options. Annual is default
•	Trial framing: '[N] days free, then $X/period. Cancel anytime.'
•	Escape option visible ('Maybe later' or 'Continue with limited access')
•	Full legal disclosure: auto-renewal price, billing date, cancellation policy
•	Link to Terms and Privacy Policy visible on paywall screen

First-run experience
•	Empty state has a clear action CTA, not just an illustration and text
•	Maximum 3 coach marks or tooltips visible on first launch
•	Core action is achievable within 60 seconds of completing onboarding

Technical
•	Fresh install tested on: iPhone SE (smallest), iPhone 16 Pro Max (largest), both light and dark mode
•	Reduce Motion and Increase Contrast accessibility settings tested
•	Dynamic Type tested: Large and Accessibility XL font sizes
•	Offline state handled: what happens if the user has no internet during onboarding?
•	Onboarding state persisted: if app crashes mid-onboarding, user resumes where they left off
•	Duplicate submission prevented: cannot subscribe twice if tapping rapidly


The onboarding is never done. Ship, measure, iterate.
Every metric is a question. Every question has an experiment. Every experiment compounds.
