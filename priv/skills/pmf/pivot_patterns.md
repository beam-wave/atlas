---
name: pivot_patterns
title: Pivot Patterns
description: Choose among zoom-in, zoom-out, customer-segment, customer-need, platform and channel pivots based on evidence
version: 1
---

# Pivot Patterns

## When to use

Use this skill when decision_frameworks returns `pivot`, or when `narrow` or `reposition` has been tried and the scorecard has not improved. A pivot changes one fundamental element of the thesis while keeping what the evidence says is working. Changing everything at once is starting over, not pivoting, and throws away validated learning.

Pivots are usually reversible at the research stage and expensive after building. Prefer the pivot that reuses the most validated evidence.

## Steps

1. **List what is validated and what failed.** Go dimension by dimension through the scorecard. Mark each as keep (score 4+ with voc or experimental evidence), weak, or failed.
2. **Identify the failed element:** segment, need, solution scope, delivery model or channel.
3. **Match it to a pivot pattern** below. Each pattern keeps something and changes one thing.
4. **Check the evidence for the new direction.** A pivot needs at least some `voc` evidence pointing to it, not just the founder's intuition. If none exists, the first step is research, not building.
5. **Restate the thesis** in one sentence and list which earlier evidence IDs still apply.
6. **Reset the scorecard** for the new thesis. Carry forward only evidence that applies to the new segment and need.
7. **Define the first experiment** with thresholds before any build work.

### Pivot types

- **Zoom-in** — one feature becomes the whole product. Applies when usage data or voc shows customers value one part and ignore the rest. Example: users only use invoice-to-bank matching; drop full bookkeeping.
- **Zoom-out** — the product becomes one feature of a larger product. Applies when the product solves a real problem but is too narrow to pay for alone (low willingness_to_pay despite high problem_intensity), and adjacent jobs share the same users and data.
- **Customer-segment** — same problem and solution, different customer. Applies when a non-target segment shows stronger signal than the ICP (higher Sean Ellis share, better retention, more urgent voc).
- **Customer-need** — same customer, different problem. Applies when interviews reveal the target customer has a more intense problem than the one being solved, and you have the trust and access to address it.
- **Platform** — switch between application and platform (or the reverse). Applies when other builders or professionals want to use your capability inside their own workflow, or when a platform has no anchor use case and needs one application to prove value.
- **Channel** — same product, different route to customers. Applies when problem and retention are fine but reachability or acquisition cost fails: direct-to-user is too expensive, but a partner or intermediary already has the customers.

Related variants exist (business model, value capture, technology pivots); treat them as changes to willingness_to_pay or delivery and state which element changes.

## Output format

```
current_thesis: <one sentence>
validated: [<element> [E..]]
failed: [<element> [E..]]
pivot_type: zoom_in | zoom_out | customer_segment | customer_need | platform | channel
new_thesis: <one sentence>
evidence_for_new_direction: [E..]
evidence_carried_forward: [E..]
what_is_discarded: [<...>]
first_experiment: <metric, operator, value, min sample>
risks: [<...>]
```

## Worked example

Current thesis: AI bookkeeping app sold directly to Indian freelancers.

Validated: designers have intense quarterly reconciliation pain [E5, E12, E13]; designers who use it retain well [E41]. Failed: reachability through direct outreach (cost per deposit too high) [E36]; tutors show no signal [E42]; willingness to pay alongside an existing CA fee is weak [E35].

voc shows CA firms complain about chasing clients for invoices and bank statements every quarter [E50, E51].

```
pivot_type: channel
new_thesis: Sell the reconciliation engine to small CA firms who serve freelance designers, so they prepare clients' GST returns faster.
evidence_for_new_direction: [E50, E51]
evidence_carried_forward: [E5, E12, E13, E41]
what_is_discarded: direct-to-freelancer acquisition, tutor segment
first_experiment: 15 problem interviews with CA firms serving freelancers; then a pilot pass if paid_pilot_signups >= 3 of 15 firms
risks: CA firms may see automation as a threat to billable hours; requires a new ICP and positioning
```

This could also be framed as a platform pivot (engine used by professionals). Choose channel when the end user and job stay the same and only the route to them changes.

## Common mistakes

- Pivoting on desk evidence alone.
- Changing segment, need and channel at once.
- Throwing away evidence that still applies to the new thesis.
- Pivoting after one weak experiment that never reached minimum sample.
- Calling a cosmetic rebrand a pivot.
- Choosing the pivot the founder finds exciting instead of the one the evidence points to.
