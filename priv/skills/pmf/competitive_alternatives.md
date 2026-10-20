---
name: competitive_alternatives
title: Competitive Alternatives
description: Map direct, indirect, do-nothing, spreadsheet and agency alternatives and judge the real competitive gap
version: 1
---

# Competitive Alternatives

## When to use

Use this skill to find what the ICP does today instead of using the product. Its output feeds the `competitive_gap` dimension of the scorecard and is the first input to positioning. The real competitor is whatever the customer would do if your product did not exist, and that is usually not another startup.

## Steps

1. **Start from behaviour, not from a competitor list.** Search `voc` for how the segment currently handles the job ("how do you file GST as a freelancer"). Log each method mentioned.
2. **Sort alternatives into five buckets:**
   - **Direct** — products built for the same job and segment.
   - **Indirect** — products built for a different primary job that people bend to this one (general accounting suites, invoicing apps, banking apps with tax features).
   - **Non-consumption / do-nothing** — ignore the problem, file late, stay below a threshold, pay penalties.
   - **Spreadsheets and DIY** — Excel, Google Sheets, templates, manual portal entry.
   - **Agencies and professionals** — CA firms, bookkeepers, tax consultants, family members.
3. **For each alternative record:** price (from the vendor's own page where possible), what it does well, where it fails for this segment, switching cost, and evidence IDs.
4. **Estimate share of use** qualitatively: dominant / common / niche, with evidence. Do not invent percentages.
5. **Find the gap.** The gap is a specific failure of the dominant alternatives that matters to this segment and that the product could fix. Cite `voc` showing customers feel that failure.
6. **Score competitive_gap 0–5:**
   - 0: alternatives solve it well and cheaply; no complaints.
   - 1: minor annoyances only.
   - 2: real complaints, but alternatives are good enough and cheap.
   - 3: clear, repeated complaints about a specific failure.
   - 4: dominant alternative fails on something important, and people are paying to work around it.
   - 5: no adequate alternative; people hack together solutions at real cost.
7. **Flag threats:** incumbents who could add the feature quickly, or free government tools.

## Output format

```
segment_id: <slug>
alternatives:
  - name: <name or description>
    bucket: direct | indirect | do_nothing | spreadsheet | agency
    price: <amount and unit or unknown> [E..]
    strengths: [<...>]
    failures_for_segment: [<...> [E..]]
    switching_cost: low | medium | high
    prevalence: dominant | common | niche [E..]
gap: <one or two sentences> [E..]
competitive_gap: <0-5>
threats: [<...>]
confidence: <0.0-1.0>
```

## Worked example

Segment: GST-registered freelance designers.

- CA firms (agency) — monthly retainer per pricing pages and posts [E4, E12]. Strengths: trusted, handles notices. Failures: slow responses near deadlines [E12], designers must still collect and send invoices [E5]. Switching cost high (relationship, history). Prevalence dominant [E5, E12, E18].
- Spreadsheets (spreadsheet) — free. Strengths: flexible. Failures: error-prone reconciliation [E15]. Switching cost low. Common.
- Existing GST and invoicing apps (direct and indirect) — subscription pricing from vendor pages [E19, E20]. Strengths: GST invoice formats. Failures: built for traders with inventory; confusing for service freelancers [E21]. Switching cost medium. Common.
- Do nothing / file late (do_nothing) — late fees [E16]. Niche among registered filers.

Gap: the dominant alternative (CA) still leaves the designer doing invoice collection and reconciliation, and apps assume inventory businesses [E5, E21]. competitive_gap 3. Threat: existing apps could add a freelancer mode; CA firms could adopt the same AI tools.

## Common mistakes

- Listing only funded startups as competitors and missing the CA and the spreadsheet.
- Claiming "no competitors". There is always do-nothing.
- Scoring a big gap from feature comparison tables instead of customer complaints.
- Using third-party listicles for pricing instead of the vendor's own pricing page.
- Ignoring switching cost. A relationship with a trusted CA is a strong habit force.
- Inventing market share numbers.
