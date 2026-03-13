# Interaction Intelligence And Operations

Use this file when the task touches adaptive behavior, lifecycle-aware UX,
engagement systems, notifications, analytics, or operational truth between the
UI and the underlying services.

## Scope

In COOL, "intelligence" should mean trustworthy product behavior, not vague AI.
Most adaptive behavior is deterministic and service-backed.

Relevant areas include:

- home ordering and contextual summaries
- engagement systems such as missions, quests, status, and seasons
- notification and deep-link re-entry
- lifecycle-aware refresh and resume behavior
- pending versus confirmed operational states
- analytics, crash, and performance observability
- rollout gates and unavailable-state handling

## Product Intelligence Rules

- Prefer deterministic rules over opaque personalization.
- Never invent a recommendation or status the backend cannot support.
- Use adaptive ordering only when it improves clarity or urgency.
- If a module is unavailable because of config, deployment, or permission state,
  say that directly.
- AI is not the primary UX engine. The app's notable AI-backed path today is
  SMS parsing in the MoMo pipeline.

## Home Intelligence

The home surface can adapt, but only within clear trust rules:

- recent activity must come from real backend-backed or reconciled data
- quick actions should stay compact and limited
- missions and engagement modules are secondary to trust summary and useful actions
- the home screen should not become a second dashboard for every feature

## Lifecycle-Aware UX

Important lifecycle-sensitive flows include:

- returning from USSD after initiating a payment
- resuming after permission changes
- re-entering after scanner flows
- auth/session changes
- trip and payment refresh on app resume

Design and QA implication:

- if a flow depends on resume behavior, test it on device
- show pending or refreshing states while the app rehydrates
- do not assume background sync has already completed

## Notifications And Re-entry

Re-entry can happen through:

- FCM notifications
- deep links
- invite links
- basket or partner links
- scanner or verification callbacks

Rules:

- notification copy should be concise and action-oriented
- deep links should land on a meaningful surface, not a broken intermediate state
- if the target screen depends on auth or missing data, the app should recover gracefully

## Engagement Systems

The app already contains engagement and status systems such as:

- `cool_status`
- `cool_events`
- `cool_missions`
- `cool_mission_progress`
- `cool_seasons`
- referral attribution and activation flows

Design rules:

- engagement should amplify useful behavior, not distract from money and mobility tasks
- financial and identity-sensitive actions should not be over-gamified
- missions belong below primary task surfaces unless the task itself is engagement-driven

## Operational Truth UX

The UI should expose real operational states for:

- payment pending versus confirmed
- draft or unreconciled SMS rows
- function or config unavailability
- missing map capability
- disabled rollout or kill-switch state
- permission-blocked and service-disabled conditions

Never collapse these into generic copy like "Something went wrong" when the app
actually knows the specific failure mode.

## Analytics And Observability

Meaningful telemetry should exist for:

- auth start and completion
- quick-action launches
- USSD initiation
- SMS reconciliation outcomes
- trip creation and trip state changes
- partner purchase attempts and confirmations
- permission-request and denial outcomes
- route entry for high-risk transactional screens

Rules:

- log meaningful intent, not every tap
- avoid leaking sensitive amounts or private identifiers unnecessarily
- keep analytics naming aligned with the repo taxonomy
- use Crashlytics and performance signals to confirm operational health, not just UI render success

## Review Questions

Use these when critiquing an interaction or operational design:

- Does the app explain what state it is in right now?
- Can the user tell whether work is pending, failed, blocked, or complete?
- If the app resumes from USSD or Settings, is the next screen obvious?
- If a backend function is missing, does the UI say so clearly?
- Is engagement helping the task, or competing with it?
