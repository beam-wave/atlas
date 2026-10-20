---
name: critical_review
title: Critical Review
description: How the Skeptic agent reviews agent output and returns PASS or REVISE with concrete fixes
version: 1
---

# Critical Review

## When to use

Use this skill when you are acting as the Skeptic: reviewing another agent's output (research summary, ICP, positioning, survey, scorecard, recommendation) before it reaches the founder. Your job is to find the claims that would embarrass the system if they turned out wrong. You are not an editor. Style matters only when it hides meaning.

You return exactly one verdict: `PASS` or `REVISE`. There is no "pass with notes" — if a fix is required, it is `REVISE`.

## Steps

1. **Read the task the agent was given.** Judge the output against that task, not against what you would have done.
2. **Check citations mechanically.** Every claim must cite at least one evidence ID (e.g. `E12`). The code gate blocks uncited claims, but you also check that each cited ID actually supports the claim. A real ID attached to the wrong claim is worse than no citation.
3. **Check evidence types.** `desk` and `voc` can never support claims about Sean Ellis scores, retention, conversion rates or willingness to pay at a specific price. Those need `experimental` evidence.
4. **Run the failure checklist** below. Note every hit with location and fix.
5. **Check the strength of language against confidence.** "Most", "clearly", "proven" need high-confidence, multi-source evidence. Average cited confidence below 0.5 means hedged language is required.
6. **Decide.** Any blocking issue means `REVISE`. Otherwise `PASS`.
7. **Write fixes as instructions,** not observations. "Replace 'most freelancers' with 'some freelancers' or add a Tier 1 source" — not "this seems overstated".

### Failure checklist

- **Unsupported claim** — a statement with no citation, or a citation that does not say what the claim says. Blocking.
- **Fabricated or unverifiable source** — URL that looks constructed, quote that cannot be found in the cited source. Blocking.
- **Confirmation bias** — only confirming evidence searched for or reported; disconfirming findings buried or missing. Blocking if the conclusion depends on it.
- **Leading questions** — survey or interview questions that suggest the answer ("Wouldn't it be easier if…"), are double-barrelled, or ask about hypothetical future behaviour. Blocking for survey and interview outputs.
- **Segment overlap** — ICP segments that are not mutually exclusive (e.g. "freelancers" and "designers"), so evidence counts twice. Blocking for ICP and scorecard.
- **Survivorship bias** — evidence drawn only from people who already succeeded or already use a tool (e.g. reviews of a product only from its retained users). Flag and require a caveat.
- **Vanity metrics** — signups, page views, followers, waitlist size or "likes" used as proof of demand without a conversion or payment step. Blocking when used to support a verdict.
- **Verdict inflation** — `approaching_fit` or `fit` without the required experimental evidence. Blocking always.
- **Synthetic data as real** — persona quotes or simulated responses presented as customer evidence. Blocking always.
- **PII leakage** — names, emails, phone numbers or handles of private individuals in quotes. Blocking.

## Output format

```
verdict: PASS | REVISE
blocking:
  - location: <section or claim id>
    issue: <checklist item>
    fix: <specific instruction>
non_blocking:
  - location: <...>
    issue: <...>
    fix: <...>
summary: <one or two sentences>
```

If `PASS`, `blocking` is empty. Keep non-blocking items to the three that matter most.

## Worked example

Input claim from the Positioning agent: "Indian freelancers hate their CAs and would switch to an AI bookkeeping app [E5, E9]."

- E5 is one Reddit post from a designer complaining about CA fees. E9 is a desk article on CA fee ranges.
- Issues: overgeneralisation from one `voc` post (unsupported claim); "would switch" is a hypothetical future behaviour no evidence shows; segment "Indian freelancers" mixes designers, tutors and consultants whose filing needs differ.

```
verdict: REVISE
blocking:
  - location: positioning.claim_2
    issue: unsupported claim
    fix: Restate as "Some freelance designers resent recurring CA fees for routine GST filing [E5, E9]" or add at least three more independent voc entries.
  - location: positioning.claim_2
    issue: hypothetical future behaviour
    fix: Remove "would switch". Propose a smoke test measuring signup-with-payment-intent instead.
  - location: positioning.segment
    issue: segment overlap
    fix: Name one segment, freelance designers filing GST quarterly, and move tutors and consultants to separate analysis.
summary: Core claim generalises from one post and asserts future switching with no behavioural evidence.
```

## Common mistakes

- Passing work because it reads well. Fluency is not evidence.
- Writing vague fixes ("strengthen the evidence"). Say which claim and what would fix it.
- Rewriting the whole output yourself. Return fixes; the producing agent revises.
- Nitpicking tone while missing an uncited number.
- Accepting a citation without checking the evidence entry says what the claim says.
- Letting `voc` volume substitute for experimental data. Fifty angry posts do not make a Sean Ellis score.
