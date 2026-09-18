# 7-star experience bar

The 10-star stories define the emotional promise. The 7-star stories define what this portfolio will actually ship and test. Each core moment needs one clear completion metric, one rescue path, and a calm close rather than a dashboard full of numbers.

## Breathe Again: first quit-day

### 10-star storyboard
1. The user wakes to a short Lumo message that uses their own reason for quitting and knows the risky parts of their day.
2. A physical quit kit, healthy substitutes, and a human coach are ready before the first craving.
3. At a usual cigarette moment, support arrives without being asked. The phone guides a breathing reset while a coach stays available live.
4. If the user smokes, nothing breaks and nobody shames them. The plan adjusts around the trigger.
5. At night, Lumo turns the day into a personal story: hard moments survived, money kept, and the next morning's plan.
6. The user ends day one feeling supported and capable, not merely counted.

### Buildable 7-star version
- A first-day cockpit opens on the user's own reason, quit clock, money kept, and one next action.
- A prominent 60-second SOS is always one tap away.
- Honest cigarette logging adjusts progress without resetting or shaming the user.
- A three-choice post-craving check-in records the trigger: stress, routine, or social.
- An evening close celebrates a specific action, then previews tomorrow's first risky moment.
- Lumo's motion and copy change across calm, craving, recovered, and day-complete states.

### Acceptance tests
- New user reaches a useful first-day action within 60 seconds after entitlement.
- SOS starts in one tap from Today and remains usable without network access.
- A logged cigarette never produces failure language or destroys prior progress.
- The day-close statement is based on stored actions, not a generic congratulation.

## Sugar Light: first sugar-light day

### 10-star storyboard
1. Breakfast and snacks matched to the user's tastes arrive at home with added-sugar labels already checked.
2. A nutrition coach knows the user's usual sugary item and weight-loss motivation, without promising a result.
3. Before each usual craving, the app offers one satisfying swap already available nearby.
4. A camera recognizes labels and the day plan adjusts instantly.
5. If the user eats added sugar, the coach helps choose the next meal rather than declaring the day lost.
6. At night, the user sees the choices they changed, money kept, and a simple plan for tomorrow.

### Buildable 7-star version
- The first-day cockpit leads with the user's usual sugary item and one concrete swap, not a smoking-derived timer.
- The primary action is `Log added sugar`; every log can be undone and never resets the day.
- A one-tap craving reset offers water, a two-minute walk, or the user's selected swap.
- The day card reports sugary items avoided and estimated spend kept, with transparent assumptions.
- An evening check-in asks `What helped most?` and carries that choice into tomorrow's plan.
- Lottie/SVG Lumo states make setup, craving support, and day completion feel intentional.

### Acceptance tests
- No cigarette, smoking, breathing-recovery, or disease/cure copy appears anywhere.
- User gets a relevant swap within 60 seconds of finishing onboarding.
- Logging added sugar is reversible and uses neutral language.
- Weight-loss copy stays motivational and explicitly avoids guaranteed outcomes.

## Merchant UPI Soundbox: first missed-alert-free day

### 10-star storyboard
1. A technician delivers a paired, battery-backed device that recognizes every UPI rail and the merchant's preferred language.
2. Every genuine payment is announced instantly even through poor data, reboot, or a noisy shop.
3. A secondary display and watch mirror the amount. Fraud and screenshot attempts are rejected before goods leave the counter.
4. A remote operations team catches a dead listener before the merchant notices.
5. At close, the merchant receives a reconciled ledger with zero uncertain payments.
6. The merchant goes home trusting the till without manually checking the phone.

### Buildable 7-star version
- Four-step setup: choose language/voice, grant notification access, complete one test announcement, reach a green Ready screen.
- Persistent permission-health card shows listener, notification source, battery/background survival, and last successful alert.
- A large Test announcement button works in Tamil, Hindi, and English before the merchant handles a customer.
- Deterministic parser fixtures, deduplication, timestamped audit log, and masked source evidence make each announcement explainable.
- A watchdog flags a dead listener within 60 seconds and guides OEM-specific recovery for Xiaomi, Oppo, Vivo, and Realme.
- End-of-day summary distinguishes announced, duplicate, unsupported, and uncertain notifications. It never claims payment settlement from notification text alone.

### Acceptance tests
- Median install-to-first-test announcement under 60 seconds and at most four user actions.
- Controlled notification-to-announcement success at least 99.9%, p95 latency under one second.
- Listener resumes within 30 seconds after supported reboot/update tests.
- Duplicate fixture never announces twice; uncertain parser input never announces as confirmed.
- Permission failure is visible and actionable, never a silent red state.

## Build order
1. Remove Sugar Light's inherited smoking language and ship its first-day cockpit before showing it to testers.
2. Add Breathe Again trigger check-in and honest day close after v6 reaches the closed track.
3. Build Soundbox's parser/audit/test-announcement harness before visual polish.
4. Dogfood the core moment on an installed release, capture friction, fix, and score again. A storyboard is not evidence of 90% confidence.

## Human-design gate

A feature does not meet this bar because it works. On onboarding, the first-day cockpit, craving reset, paywall, rescue offer, and day close, dogfooders must answer:

- Does this screen feel handcrafted for this moment, or assembled from generic cards and claims?
- Is there one emotional focal point and one clear next action?
- Does the copy sound like a calm person who remembers what the user said, without cheerleading, shame, fake urgency, or vague wellness language?
- Does motion explain a state change or offer company? Remove motion that only decorates or delays.
- Do spacing, type scale, color, illustration, loading, empty, error, and reduced-motion states feel finished on a real phone?
- Are prices, renewals, estimates, permissions, and uncertainty stated plainly?
- After added sugar, a declined offer, or a missed plan, does the product preserve dignity and offer a useful next choice?

A screen fails dogfood if two reviewers call it template-like, AI-looking, crowded, generic, cold, or manipulative. Record the exact screen and phrase, fix it, and retest on an installed build. No screenshot or score can raise experience confidence above 90% until this gate passes.
