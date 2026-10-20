---
name: pmf_scorecard
title: PMF Scorecard
description: Rate six PMF dimensions, compute the weighted composite, assign a gated verdict and name the next move
version: 1
---

# PMF Scorecard

## When to use

Use this skill to produce the PMF verdict for one ICP segment. The code computes the composite and applies the verdict gates; your job is to propose dimension ratings with cited evidence, explain them, and choose the next move and next experiment. Your ratings must follow this rubric exactly or the code will reject or override them.

Score one segment per scorecard. A blended "all freelancers" scorecard hides the signal.

## Steps

1. **Rate each dimension 0–5** where evidence exists. Leave a dimension unrated rather than guessing. Every rating cites evidence IDs (e.g. `E12`); an uncited rating is blocked by the code gate.
2. **Record the evidence type** each rating rests on: `desk`, `voc` or `experimental`. Do not label a rating `experimental` unless it is computed from uploaded test data.
3. **Let code compute the composite** with the formula below. You may show the arithmetic, but the code value wins.
4. **Apply the verdict rules** in order, highest first. Apply the gate.
5. **Choose one next move** with decision_frameworks.
6. **Name the single experiment** that would most change the verdict, with thresholds from experiment_thresholds.

### Dimensions and weights

| dimension | weight | source skill | evidence allowed |
|---|---|---|---|
| problem_intensity | 0.25 | problem_intensity | desk, voc, experimental |
| willingness_to_pay | 0.20 | survey_design, smoke_test_design | desk, voc, experimental |
| reachability | 0.15 | icp_definition | desk, voc, experimental |
| competitive_gap | 0.15 | competitive_alternatives | desk, voc, experimental |
| sean_ellis | 0.15 | survey_design | experimental only |
| retention | 0.10 | retention_signals | experimental only |

Weights are renormalised over the dimensions that have a rating.

### Evidence multipliers

- desk: 0.6
- voc: 0.8
- experimental: 1.0

### Composite (0–100)

composite = Σ(weight × score/5 × multiplier) / Σ(weight) × 100, summed over rated dimensions only.

Consequence: a scorecard built only on `desk` evidence cannot exceed 60; one built only on `voc` cannot exceed 80.

### Sean Ellis mapping (very disappointed share, computed by code)

- 40% or more → 5
- 30–39% → 4
- 20–29% → 3
- 10–19% → 2
- 1–9% → 1
- 0% → 0

### Verdicts

- `no_signal` — composite < 40.
- `promising` — composite ≥ 40.
- `approaching_fit` — composite ≥ 60 AND experimental evidence in at least 2 dimensions.
- `fit` — composite ≥ 70 AND experimental evidence AND Sean Ellis very disappointed share ≥ 40% AND retention score ≥ 4.

Gate: `approaching_fit` and `fit` are impossible from desk and voc evidence alone. The code caps such a scorecard at `promising` regardless of composite. If a higher verdict's conditions are not all met, fall to the next verdict down.

### Next moves

`double_down`, `narrow`, `reposition`, `pivot`. Pick exactly one.

## Output format

```
segment_id: <slug>
ratings:
  - dimension: <name>
    score: <0-5>
    evidence_type: desk | voc | experimental
    evidence: [E..]
    rationale: <one sentence>
unrated: [<dimension>, ...]
composite: <0-100, one decimal>
verdict: no_signal | promising | approaching_fit | fit
gate_applied: <none | capped_at_promising>
next_move: double_down | narrow | reposition | pivot
next_experiment: <one experiment with metric, operator, value, min sample>
why_this_experiment: <which dimension or gate it would move>
```

## Worked example

Segment: GST-registered freelance designers. Round 1, research only.

- problem_intensity 4, voc [E5, E12, E13] → 0.25 × 0.8 × 0.8 = 0.160
- willingness_to_pay 2, desk [E4] → 0.20 × 0.4 × 0.6 = 0.048
- reachability 3, desk [E26] → 0.15 × 0.6 × 0.6 = 0.054
- competitive_gap 3, desk [E19, E21] → 0.15 × 0.6 × 0.6 = 0.054
- sean_ellis, retention: unrated.

Sum 0.316 / Σweight 0.75 × 100 = 42.1 → `promising`. Next move `double_down` on evidence. Next experiment: refundable-deposit landing page, pass deposit_rate >= 0.03 at n >= 400, because willingness_to_pay is the weakest heavy dimension and would add experimental evidence.

Round 2, after experiments: willingness_to_pay 3 experimental (deposit rate 3.4%, n 450) [E35]; reachability 4 experimental (channel test) [E36]; sean_ellis 41% very disappointed, n 46 → 5 experimental [E37]; retention 3 experimental [E40]; problem_intensity and competitive_gap unchanged.

0.160 + 0.120 + 0.120 + 0.054 + 0.150 + 0.060 = 0.664 / 1.0 × 100 = 66.4. Experimental in 4 dimensions → `approaching_fit`. Not `fit`: retention 3 < 4 and composite < 70. Next move `double_down`. Next experiment: month-3 paid retention for designers, pass retention >= 0.45 with n >= 30 per cohort over 3 cohorts, because retention is the binding gate for `fit`.

## Common mistakes

- Rating sean_ellis or retention from voc or desk evidence.
- Estimating a Sean Ellis percentage instead of using the computed value.
- Filling every dimension to make the composite look complete. Unrated is honest.
- Calling a desk-only scorecard `approaching_fit` because the composite looks high.
- Blending segments in one scorecard.
- Naming three next experiments. Name the one that moves the verdict most.
