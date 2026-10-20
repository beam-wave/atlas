---
name: decision_frameworks
title: Decision Frameworks
description: Logic for choosing double down, narrow, reposition or pivot and for weighing reversible against irreversible decisions
version: 1
---

# Decision Frameworks

## When to use

Use this skill when recommending what the founder should do next after a scorecard, an experiment readout or a research cycle. Atlas recommends exactly one of four next moves: `double_down`, `narrow`, `reposition`, `pivot`. You also use it to judge how much evidence a decision needs before acting.

## Steps

1. **Classify the decision as reversible or irreversible.**
   - Reversible (two-way door): changing landing-page copy, running a new survey, testing a price, targeting a new subreddit. Decide fast with moderate evidence. Bias to action.
   - Irreversible or expensive (one-way door): quitting a job, hiring, raising money on a thesis, signing annual contracts, building a large integration, shutting down a product with paying users. Require experimental evidence and a pre-registered threshold.
   - Most PMF decisions are reversible. Say so explicitly to stop the founder over-analysing.
2. **Read the scorecard by dimension, not just the composite.** Identify the strongest and weakest dimensions and which have only `desk` evidence.
3. **Apply the move logic** below. Pick the first rule that matches.
4. **Name the single experiment** that would most change the decision, with a pre-set threshold (see experiment_thresholds).
5. **State the kill condition.** What result would make you recommend a different move.

### Move logic

- **double_down** — The current segment, problem and positioning are working. Use when composite is 60 or above with experimental evidence in at least two dimensions, or problem_intensity and willingness_to_pay are both 4+ and the main gap is simply more data. Action: keep the thesis, increase sample size, tighten the funnel, start charging if not already.
- **narrow** — Signal exists but is diluted across segments. Use when one sub-segment scores clearly higher than the blend (for example, Sean Ellis "very disappointed" share of 45% among designers versus 18% overall), or when reachability is low because the ICP is too broad. Action: cut to the best sub-segment, rewrite ICP and messaging for them only.
- **reposition** — Problem is real and intense, but the competitive_gap or willingness_to_pay is weak because customers compare you to the wrong alternative. Use when problem_intensity is 4+ and competitive_gap is 2 or less, or voc shows people misunderstand what the product replaces. Action: rerun positioning; change the reference alternative and category, not the product.
- **pivot** — The core problem is weak or no segment shows signal. Use when problem_intensity is 2 or less across segments after reasonable research, or after two cycles of narrow and reposition without the composite rising. Action: choose a pivot type from pivot_patterns and restart evidence collection.

### Tie-breakers

- Prefer the smaller move. Narrow before reposition, reposition before pivot.
- Never recommend pivot from `desk` evidence alone unless the problem is demonstrably absent (e.g. regulation removed the need).
- If evidence is too thin for any move, the recommendation is still one of the four; pick `double_down` on research and say the next experiment is the decision.

## Output format

```
next_move: double_down | narrow | reposition | pivot
door_type: reversible | irreversible
rationale: <2-4 sentences citing evidence IDs>
next_experiment: <one experiment with metric, operator, value, sample size>
kill_condition: <result that would change this recommendation>
```

## Worked example

Scorecard for "AI bookkeeping for Indian freelancers": composite 52, verdict `promising`. problem_intensity 4 (voc), willingness_to_pay 2 (desk), reachability 3 (desk), competitive_gap 3 (desk). A Sean Ellis survey of 60 users shows 22% very disappointed overall, but 41% among the 17 freelance designers filing GST, and 9% among tutors.

```
next_move: narrow
door_type: reversible
rationale: Designers filing GST show much stronger attachment than the blend [E31]; tutors mostly are not GST-registered and have little filing pain [E8, E14]. Blended messaging is diluting the signal.
next_experiment: Landing page aimed only at GST-registered freelance designers. Pass if pre-order deposit rate >= 3% of unique visitors with n >= 400 visitors.
kill_condition: Deposit rate below 1% at n >= 400, or designer Sean Ellis share falls below 30% at n >= 40.
```

## Common mistakes

- Recommending pivot because the composite is low when the weak score is driven by missing data, not bad data.
- Treating a reversible test as a one-way door and asking for months of research first.
- Treating fundraising or hiring as reversible.
- Giving two moves ("narrow and reposition"). Pick one; the other can follow.
- Omitting the kill condition, which turns the recommendation into an opinion.
- Recommending double_down on vanity metrics like waitlist size.
