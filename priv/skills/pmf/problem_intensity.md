---
name: problem_intensity
title: Problem Intensity
description: Score a problem on frequency, severity, current spend and workaround-seeking using a 0 to 5 scale per factor
version: 1
---

# Problem Intensity

## When to use

Use this skill to rate how badly an ICP segment needs the problem solved. Its output feeds the `problem_intensity` dimension of the PMF scorecard, which carries the highest weight (0.25). Score each segment separately. A problem that is mildly annoying for everyone is worse than one that is acute for a few.

## Steps

1. **State the problem in the customer's words,** scoped to one segment. Use a verbatim `voc` quote if available.
2. **Score four factors, each 0–5,** citing evidence IDs for every score.
3. **Combine** into a single 0–5 problem_intensity rating (method below).
4. **Record the evidence type mix.** Scores supported only by `desk` evidence carry a 0.6 multiplier in the scorecard; `voc` 0.8; `experimental` 1.0. Note which type dominates.
5. **List what would raise or lower the score** and the cheapest way to check it.

### Factor scales

**Frequency** — how often the problem occurs.
- 0: never or hypothetical. 1: once a year or less. 2: a few times a year. 3: monthly. 4: weekly. 5: daily or continuous.

**Severity** — cost when it occurs (money, time, risk, stress).
- 0: no cost. 1: minor irritation. 2: an hour or two lost, small cost. 3: a day lost or noticeable money. 4: penalties, lost clients, or serious stress. 5: threatens income, legal standing or the business.

**Current spend** — what they already pay in money or time to deal with it.
- 0: nothing. 1: occasional free effort. 2: regular unpaid time. 3: pays for a tool or service, low amount. 4: pays a meaningful recurring amount (e.g. professional retainer). 5: pays heavily and visibly, budget line item.

**Workaround-seeking** — active effort to find a better solution.
- 0: no awareness. 1: aware, not looking. 2: complains but does nothing. 3: has tried a workaround (spreadsheet, template, asking friends). 4: has tried and abandoned paid tools, or built a custom process. 5: actively searching or asking for recommendations now.

### Combining

- Compute the mean of the four factors.
- If severity is 1 or less, cap the combined score at 2. Frequent but harmless problems do not create demand.
- If current spend and workaround-seeking are both 1 or less, cap at 3. People who do nothing about a problem rarely pay to fix it.
- Round to the nearest integer (halves round up) for the scorecard rating; report the unrounded value too.

## Output format

```
segment_id: <slug>
problem: <one sentence, customer's words where possible>
factors:
  frequency: <0-5> [E..]
  severity: <0-5> [E..]
  current_spend: <0-5> [E..]
  workaround_seeking: <0-5> [E..]
mean: <x.xx>
caps_applied: <none | severity_cap | inaction_cap>
problem_intensity: <0-5>
dominant_evidence_type: desk | voc | experimental
confidence: <0.0-1.0>
to_raise_confidence: <cheapest next check>
```

## Worked example

Segment: GST-registered freelance designers. Problem: "Every quarter I lose two days chasing invoices for my CA and still pay them for it."

- Frequency 3 — returns are monthly or quarterly under QRMP [E3]; reconciliation pain recurs each cycle [E5].
- Severity 4 — late fees and mismatch notices reported [E13, E16].
- Current spend 4 — recurring CA retainers reported in several posts [E4, E5, E12].
- Workaround-seeking 3 — spreadsheets and invoicing apps tried [E15, E17]; few active "recommend me" posts found.

Mean 3.5, no caps, problem_intensity 4 (rounded from 3.5, round half up). Dominant evidence type `voc`. Confidence 0.55.

Same problem for tutors: frequency 1, severity 1, spend 0, workaround 1 — mean 0.75, severity cap applies, problem_intensity 1. Most tutors are below the GST threshold [E8].

To raise confidence: 10 problem interviews with designers asking about their last filing.

## Common mistakes

- Scoring the problem for "freelancers" in general instead of one segment.
- Taking loud complaints as high severity. Look for actual consequences (fees, notices, lost clients).
- Scoring current spend from what the founder thinks they should pay instead of what they pay.
- Giving a factor a score without a citation.
- Ignoring the caps and reporting a 4 for a frequent but trivial annoyance.
