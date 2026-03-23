# BioPay Liveness Manual QA

Date: 2026-03-23

Scope:

- verifies the challenge-based PAD scaffold in the BioPay scanner
- covers both enrollment and pay matching flows
- does not replace a dedicated spoof-lab or calibrated PAD evaluation

## Preconditions

- build includes the real BioPay model asset and generated contract
- BioPay feature flag enabled for the test account
- device auth and backend match throttling already enabled
- test on at least one Android device and one iPhone

## Enrollment Happy Path

1. Open BioPay enrollment and grant camera access.
2. Confirm the scanner first asks for alignment, then arms a blink challenge.
3. Blink once and verify the prompt advances to a head-turn challenge.
4. Turn the head slightly to either side and verify the prompt advances to recenter.
5. Recenter the face and verify BioPay resumes capture and completes the five-frame enrollment.
6. Confirm enrollment succeeds and the profile is created.

## Pay Happy Path

1. Open BioPay pay scan.
2. Confirm the scanner asks for a blink challenge before matching.
3. Blink once and verify the prompt advances to a head-turn challenge.
4. Turn the head slightly to either side and verify BioPay proceeds to matching only after the face is centered again.
5. Confirm the payee confirmation screen appears only after liveness plus match threshold are both satisfied.

## Negative Checks

1. Present a static printed face and confirm BioPay never reaches match or enrollment submission.
2. Present a second face in frame and confirm the liveness sequence resets to alignment.
3. Keep the face still without blinking until the challenge timeout and confirm the scanner reports a restart.
4. Obscure one eye and confirm the blink challenge does not complete.
5. Move into very dark or very bright conditions and confirm the liveness sequence falls back to generic capture guidance instead of progressing.

## Logging Review

1. Inspect BioPay enrollment operational-health events and confirm liveness metadata is attached.
2. Inspect BioPay match-event metadata and confirm liveness metadata is attached.
3. Confirm rate-limit and lockout events still work when liveness metadata is present.

## Exit Criteria

- enrollment and pay flows both require the live challenge
- printed or replayed faces do not advance without the required movement
- liveness metadata reaches backend telemetry for both enrollment and match requests
- no new analyzer, widget-test, or Deno-check regressions are introduced
