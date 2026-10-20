---
name: icp_definition
title: ICP Definition
description: Define an ideal customer profile with firmographic and psychographic criteria and explicit disqualifiers
version: 1
---

# ICP Definition

## When to use

Use this skill at the start of a PMF cycle, and again whenever the scorecard suggests `narrow`. An ideal customer profile (ICP) is the segment where the problem is most intense, the buyer can pay, and you can reach them cheaply. A good ICP is narrow enough that you could list 100 real people who fit it from public sources.

Every downstream skill (problem intensity, positioning, surveys, smoke tests) is scoped to one ICP segment. If segments overlap, evidence is double-counted and the scorecard lies.

## Steps

1. **List candidate segments.** Start from the founder's idea and brainstorm 3–6 segments. Each segment is a who + a situation, not a demographic alone. "Freelance designers registered for GST" not "millennials".
2. **Write firmographic criteria** (observable facts you can filter on):
   - Role or profession.
   - Business form (sole proprietor, LLP, company) and size (revenue band, team size).
   - Geography and regulatory status (e.g. GST-registered, turnover above threshold).
   - Tools already used (accounting app, spreadsheets, CA firm).
   - Where they gather (platforms, communities, associations).
3. **Write psychographic criteria** (attitudes and behaviours you infer from evidence):
   - Trigger events that create the need (first GST notice, crossing a turnover threshold, client asking for invoices with GSTIN).
   - Attitude to the problem (anxious, indifferent, actively shopping).
   - Buying behaviour (pays for tools, prefers free, delegates to a professional).
   - Self-identity that affects adoption (sees themselves as a business versus a hobbyist).
4. **Write disqualifiers.** Explicit conditions that remove someone even if they match the rest. Disqualifiers prevent you counting enthusiastic non-buyers.
5. **Check mutual exclusivity.** For each pair of segments, ask: can one person be in both? If yes, tighten criteria until they cannot, or merge them.
6. **Score each segment quickly** on problem intensity, ability to pay and reachability using available evidence, citing IDs. Pick one primary ICP and at most one secondary.
7. **Write the reachability plan.** Name three concrete channels where you can find 100 of them.

## Output format

```
segment_id: <slug>
name: <one line>
firmographic:
  - <criterion>
psychographic:
  - <criterion>
trigger_events:
  - <event>
disqualifiers:
  - <condition>
channels:
  - <specific community, platform or list>
evidence: [E.., E..]
confidence: <0.0-1.0>
priority: primary | secondary | deprioritised
```

Follow with a one-paragraph rationale for the primary pick and a list of overlap checks performed.

## Worked example

Idea: AI bookkeeping for Indian freelancers.

Candidate segments: freelance designers, tutors, independent consultants, freelance developers billing foreign clients.

```
segment_id: gst_freelance_designers
name: Freelance graphic and UI designers in India registered for GST
firmographic:
  - Sole proprietor, annual billing roughly 20 lakh to 1 crore INR
  - GST-registered, filing quarterly or monthly
  - Invoices domestic agency and startup clients
  - Uses a CA, spreadsheets or a basic invoicing app
psychographic:
  - Sees bookkeeping as unpaid admin that steals billable hours
  - Already pays for tools (Figma, Adobe), so software spend is normal
  - Anxious about notices and late fees more than about the filing itself
trigger_events:
  - First client requiring a GST invoice
  - Receiving a mismatch notice
disqualifiers:
  - Not GST-registered and below threshold
  - Employed full time with occasional side gigs
  - Has an in-house accountant or a family member who does the books
channels:
  - Behance and Dribbble India profiles
  - Design community Slack and Discord groups in India
  - r/IndiaTax and r/developersIndia threads about GST
evidence: [E3, E5, E11]
confidence: 0.55
priority: primary
```

Tutors are deprioritised: most fall below the GST threshold [E8], so filing pain is low. Consultants are secondary. Overlap check: a designer who also tutors is classed by majority income.

## Common mistakes

- Defining the ICP by demographics (age, gender) instead of situation and behaviour.
- Making "freelancers" one segment. Designers, tutors and consultants have different tax status and pain.
- Skipping disqualifiers, then counting enthusiastic students as demand.
- Picking the largest segment instead of the one with the most intense, reachable pain.
- Psychographic criteria with no evidence behind them. Cite or mark as hypothesis.
- Listing channels like "social media". Name the actual community.
