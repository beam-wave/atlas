---
name: positioning
title: Positioning
description: Build evidence-cited positioning using the April Dunford sequence from alternatives to market category
version: 1
---

# Positioning

## When to use

Use this skill after competitive alternatives and jobs-to-be-done are drafted, and whenever the next move is `reposition`. Positioning defines how the product is the best choice for a specific customer compared with what they would otherwise use. It drives landing-page copy, smoke tests and interview framing.

Follow April Dunford's sequence in order. Each step depends on the previous one. Every claim cites at least one evidence ID; uncited claims are blocked by the code gate.

## Steps

1. **Competitive alternatives.** Take the dominant alternatives from competitive_alternatives for this segment. Name what customers would really do instead, including CA firms, spreadsheets and doing nothing. Cite evidence.
2. **Unique attributes.** List capabilities or properties the product has that those alternatives lack. Be factual: features, pricing model, delivery, expertise. If the product does not exist yet, mark attributes as `planned` and treat them as untested.
3. **Value.** For each unique attribute, state the value it creates for the customer, in their terms. Attribute → so what → value. Cite `voc` showing customers care about that value. Drop attributes with no value evidence.
4. **Best-fit customer.** Who cares most about that value? Usually a sub-segment of the ICP with a specific trigger. Describe characteristics that make them care, not demographics.
5. **Market category.** Choose the frame of reference that makes the value obvious. Options: an existing category (fast to understand, but you are compared to leaders), a subcategory (existing category + a qualifier for your best-fit customer), or a new category (only if no existing frame works, and expensive to teach). Default to a subcategory.
6. **Optional: relevant trend.** Mention a trend only if it makes the value more urgent and you have evidence for it.
7. **Write the positioning statement** and a one-line headline test. Then list assumptions that need experimental validation, each with the experiment that tests it.

## Output format

```
segment_id: <slug>
alternatives: [<alternative> [E..], ...]
unique_attributes:
  - attribute: <...>
    status: live | planned
value:
  - attribute: <...>
    value: <customer outcome> [E..]
best_fit_customer: <description> [E..]
market_category: <category>
category_type: existing | subcategory | new
statement: For <best-fit customer> who <situation>, <product> is a <category> that <key value>. Unlike <main alternative>, it <key difference>.
headline_draft: <under 12 words>
assumptions_to_test:
  - <assumption> -> <experiment>
```

## Worked example

Product: AI bookkeeping for Indian freelancers. Segment: GST-registered freelance designers.

1. Alternatives: CA firm on retainer [E4, E12]; spreadsheets [E15]; inventory-focused GST apps [E19, E21].
2. Unique attributes: reads bank and UPI statements and matches them to invoices automatically (planned); prepares returns in a format the user or their CA can file (planned); flat monthly price (planned).
3. Value:
   - Auto-matching → no more quarter-end invoice chasing → reclaims the day or two lost each cycle [E5].
   - CA-ready output → keeps the CA for sign-off but cuts their billable work → lower total cost without losing a trusted reviewer [E12, E13].
   - Flat price → predictable cost versus variable CA charges [E4].
4. Best-fit customer: designers billing many small clients through UPI and bank transfer, who already use a CA and resent paying for data entry [E5, E12].
5. Market category: subcategory "GST bookkeeping for service freelancers" rather than "accounting software" (which invites comparison with full suites) or a new category.

Statement: For GST-registered freelance designers who lose days each quarter reconciling payments for their CA, the product is GST bookkeeping for service freelancers that turns bank and UPI statements into filing-ready returns. Unlike a CA retainer alone, it removes the data-entry work so you pay your CA only to review.

Headline draft: "Your GST return, ready before your CA asks."

Assumptions to test: designers will pay a flat fee on top of a reduced CA fee → landing-page pre-order test with deposit; anxiety about filing errors is reduced by CA review framing → A/B headline test.

## Common mistakes

- Starting with the category or tagline. Alternatives come first.
- Listing features as value. Value is what the customer gets, in their words.
- Positioning against another startup when the real alternative is the CA.
- Choosing a new category to sound differentiated. It forces you to educate the market.
- Best-fit customer defined as "everyone who files GST".
- Presenting planned attributes as if they exist.
