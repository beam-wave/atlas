---
name: retention_signals
title: Retention Signals
description: Read cohort retention curves for flattening and compare with rough category benchmarks to rate retention
version: 1
---

# Retention Signals

## When to use

Use this skill when the founder has uploaded usage or billing data and you need to interpret retention. Retention is the most honest PMF signal: people who keep using or paying without being pushed. The `retention` dimension of the scorecard (weight 0.10) can only be rated from `experimental` evidence, meaning cohort numbers computed by code from uploaded data. You interpret the computed curves; you never estimate them.

If no usage data exists, say so and propose the experiment that would produce it. Do not rate retention from reviews, desk benchmarks or founder claims.

## Steps

1. **Confirm the data basis.** Check the computed cohort table: cohort definition (signup week or month), activity definition (what counts as "retained"), number of users per cohort, number of cohorts.
2. **Check the activity definition is meaningful.** "Logged in" is weak. Prefer the core action: "uploaded a statement" or "generated a return". For paid products, revenue retention beats usage.
3. **Check sample adequacy.** At least 30 users per cohort and at least 3 cohorts before drawing conclusions. Otherwise report `insufficient_sample`.
4. **Read the shape of each curve:**
   - **Flattening** — the curve drops early, then levels off to a stable share. This is the PMF signal: a core group keeps getting value.
   - **Declining to zero** — keeps falling with no plateau. No retained core yet.
   - **Smiling** — dips then rises (reactivation, expansion). Strong signal, rare early.
5. **Compare cohorts over time.** Newer cohorts flattening higher than older ones means the product or targeting is improving.
6. **Segment the curves** by ICP segment where the data allows. A blended curve often hides one segment that retains and another that churns.
7. **Match the natural usage frequency.** A product used quarterly (like GST filing) must be measured in quarters, not days. Daily retention for a quarterly job will look like failure.
8. **Compare with rough benchmarks** below, then rate 0–5.

### Rough benchmark heuristics (not standards)

These ranges are rough heuristics compiled from widely shared industry rules of thumb. They vary by product, price and market. Use them for orientation only, and cite a source if you quote a specific figure.

- **Consumer apps (free or low price):** a curve that flattens above roughly 20–30% of a cohort by month 3 is healthy; daily-use apps flattening around 10–20% by day 30 is often considered decent.
- **SMB SaaS:** monthly logo churn around 2–5% is common for healthy products, so roughly 50–75% of customers retained at month 12; net revenue retention near or above 100% is strong.
- **Enterprise SaaS:** gross revenue retention around 90% or higher annually, net revenue retention above 110%.

### Retention rating (0–5)

- 0: no retained users after the first period.
- 1: steady decline, no sign of flattening.
- 2: slowing decline but no plateau yet within the observed window.
- 3: plateau exists but below the category heuristic.
- 4: plateau within the category heuristic, and newer cohorts no worse than older ones.
- 5: plateau above the heuristic, improving across cohorts, or a smiling curve.

## Output format

```
data_basis: <cohort definition, activity definition, period unit>
cohorts: <n> cohorts, <min>-<max> users each
sample_status: adequate | insufficient_sample
shape: flattening | declining | smiling | unclear
plateau_level: <percent at period N or none>
by_segment: [<segment>: <shape, plateau> [E..]]
category: consumer | smb_saas | enterprise
retention_score: <0-5>
evidence: [E..]
caveats: [<...>]
next_experiment: <...>
```

## Worked example

Uploaded data for the AI bookkeeping app: 4 monthly signup cohorts, 35–80 users each. Activity = "uploaded a bank statement in the period". Because GST filing is monthly or quarterly, the period unit is one month.

- Blended: month 1 at 62%, month 2 at 41%, month 3 at 33%, month 4 at 31% [E40]. Flattening around 31%.
- Designers: flattening near 48% by month 3 [E41]. Tutors: declining to 9% with no plateau [E42].
- Category: SMB SaaS, but most users are pre-payment, so usage retention, not revenue retention.

Retention score: 3 blended (plateau, below the heuristic for a paid SMB tool). Designers alone would be a 4. Caveat: only 4 cohorts, free beta. Next experiment: convert beta designers to a paid plan and measure month-3 paid retention, n >= 30.

## Common mistakes

- Rating retention from reviews or "users love it" quotes.
- Using login as the activity definition.
- Measuring daily retention for a monthly or quarterly job.
- Judging from one cohort of 12 users.
- Reporting a blended curve when one segment is clearly different.
- Presenting benchmark ranges as industry standards.
- Ignoring that free-beta retention overstates paid retention.
