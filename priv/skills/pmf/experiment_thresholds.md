---
name: experiment_thresholds
title: Experiment Thresholds
description: Fix pass and fail criteria before any test with metric, operator, value, minimum sample and an inconclusive band
version: 1
---

# Experiment Thresholds

## When to use

Use this skill before any experiment launches: surveys, smoke tests, fake doors, pricing tests, pilots, retention checks. Criteria are fixed BEFORE the test and stored with the experiment. After results arrive, code compares data with the stored thresholds. Nobody, including you, edits thresholds after launch.

Pre-registering criteria is what makes `experimental` evidence trustworthy. Without it, any result can be narrated as success.

## Steps

1. **Write the hypothesis** as a falsifiable sentence naming segment, behaviour and expected size.
2. **Choose one primary metric** that measures behaviour, not opinion. Examples: deposit rate, paid conversion, Sean Ellis very-disappointed share, week-4 retention, qualified-call booking rate. Secondary metrics are allowed but do not decide the outcome.
3. **Define the metric exactly:** numerator, denominator, counting window, deduplication rule. "Deposits / unique visitors from tracked ICP sources, over 14 days."
4. **Set the pass criterion** as `metric operator value`, using operators `>=`, `>`, `<=`, `<`.
5. **Set the fail criterion** the same way. Pass and fail must not overlap.
6. **Define the inconclusive band** as everything between pass and fail. An inconclusive result means "run longer or redesign", never "pass".
7. **Set minimum sample size.** Results below it are reported as `insufficient_sample` regardless of the rate. Rules of thumb:
   - Rate metrics with expected rates of 2–5%: at least 300–500 unique visitors.
   - Sean Ellis surveys: at least 40 responses from qualified users; 100 preferred.
   - Retention cohorts: at least 30 users per cohort, at least 3 cohorts.
   - Interviews: at least 8 per segment before treating patterns as findings.
   If the expected effect is small, the sample must be larger. Say so rather than shrinking the bar.
8. **Set the time box:** maximum duration. If the minimum sample is not reached in time, the result is inconclusive.
9. **Write the decision mapping:** what you will do on pass, fail and inconclusive. Link to decision_frameworks moves.
10. **Choose threshold values with a reason.** Cite benchmarks or economics (e.g. the conversion rate needed for paid acquisition to break even). Do not pick numbers because they are likely to pass.

## Output format

```
experiment_id: X<n>
hypothesis: <...>
segment_id: <slug>
primary_metric:
  name: <slug>
  definition: <numerator / denominator, window, dedup>
pass: <metric> <operator> <value>
fail: <metric> <operator> <value>
inconclusive: <value range between fail and pass>
min_sample: <n> <unit>
time_box_days: <n>
rationale: <why these values> [E..]
on_pass: <next move>
on_fail: <next move>
on_inconclusive: <next move>
locked_at: <YYYY-MM-DD>
```

## Worked example

```
experiment_id: X3
hypothesis: GST-registered freelance designers reaching the landing page will place a refundable INR 99 deposit at a rate of at least 3%.
segment_id: gst_freelance_designers
primary_metric:
  name: deposit_rate
  definition: deposits / unique visitors with ICP UTM tags, 14-day window, one deposit per email
pass: deposit_rate >= 0.03
fail: deposit_rate < 0.01
inconclusive: 0.01 <= deposit_rate < 0.03
min_sample: 400 unique visitors
time_box_days: 21
rationale: Strong-commitment smoke tests in comparable B2B and prosumer tools often land in low single digits; 3% is the level at which paid acquisition is plausible given expected prices [E24, E25].
on_pass: double_down; build the reconciliation prototype for depositors.
on_fail: reposition; test the CA-review framing before considering pivot.
on_inconclusive: extend by 14 days or add one new ICP traffic source; do not change thresholds.
locked_at: 2026-10-20
```

Sean Ellis example: pass `very_disappointed_share >= 0.40`, fail `very_disappointed_share < 0.25`, min_sample 40 qualified users.

## Common mistakes

- Writing thresholds after seeing the data, or "adjusting" them mid-test.
- Using opinion metrics ("% who said they'd use it") as the primary metric.
- No fail criterion, so every result is "promising".
- Calling 4 deposits from 60 visitors a 6.7% pass. It is below min_sample.
- Treating inconclusive as a soft pass.
- Mixing segments in the denominator.
- Choosing a threshold to match what the founder hopes for.
