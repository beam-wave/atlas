---
name: smoke_test_design
title: Smoke Test Design
description: Design landing-page and fake-door tests with honest disclosure that measure real intent before building
version: 1
---

# Smoke Test Design

## When to use

Use this skill to test demand before or alongside building. A smoke test shows a value proposition to real visitors and measures a behaviour that costs them something: an email with a qualifying question, a booked call, a deposit, a click on a specific paid plan. Results become `experimental` evidence once the founder uploads analytics data.

Two formats:
- **Landing-page test** — a standalone page for a product or feature that does not exist yet.
- **Fake-door test** — a button, menu item or plan inside an existing product or page that leads to a "not available yet" screen.

You draft; a human approves before anything goes live or any ad money is spent.

## Steps

1. **Pick one hypothesis** from positioning, e.g. "GST-registered designers will put down a deposit for automated return preparation".
2. **Fix the threshold before launch** with experiment_thresholds: metric, operator, value, minimum sample, inconclusive band. Write it down; do not change it after seeing data.
3. **Choose the conversion action by cost of commitment:**
   - Weak: page view, click, plain email signup.
   - Medium: email plus answers to two qualifying questions; booking a call.
   - Strong: refundable deposit or pre-order; choosing a priced plan and entering checkout (stopping before payment with disclosure).
   Prefer the strongest action the founder can support. Plain signups are vanity metrics.
4. **Write the page:** headline from positioning, three value points in the customer's words, price if testing price, one call to action. Follow clear_writing.
5. **Write the honest disclosure.** Visitors must be told the product is not live yet, before any payment and immediately after the conversion action. No fake user counts, testimonials, logos or scarcity.
6. **Plan traffic** from the ICP's channels. Name each source and track it with UTM parameters so segments can be separated. Paid ads need human approval and a budget cap.
7. **Plan the analysis:** unique visitors, conversions, rate by source, rate by segment answer.
8. **Plan the follow-up** for converters: thank-you message, refund process for deposits, interview invite.

### Disclosure rules

- Before payment: "We're not live yet. Your deposit is fully refundable at any time and reserves early access."
- After a fake-door click: "This isn't available yet. We're checking interest before we build it. Want us to tell you when it's ready?"
- Never take a non-refundable payment for something that does not exist.
- Never imply the product is live in ads.

## Output format

```
test_id: <slug>
format: landing_page | fake_door
hypothesis: <one sentence> [E..]
segment_id: <slug>
conversion_action: <action> (weak | medium | strong)
threshold_ref: <experiment id>
page:
  headline: <...>
  value_points: [<...>, <...>, <...>]
  price_shown: <amount or none>
  cta: <...>
  disclosure_before: <...>
  disclosure_after: <...>
traffic:
  - source: <channel>
    utm: <campaign tag>
    budget: <amount or organic>
follow_up: <...>
status: awaiting_approval
```

## Worked example

Hypothesis: GST-registered freelance designers will reserve a spot with a refundable deposit [E5, E12].

- Format: landing page. Conversion action: refundable INR 99 deposit (strong).
- Headline: "Your GST return, ready before your CA asks."
- Value points: "Upload your bank and UPI statements. We match them to your invoices." / "Get a return your CA can check in minutes." / "One flat monthly price."
- Disclosure before payment: "We're not live yet. The INR 99 deposit is fully refundable at any time and reserves early access."
- Traffic: two Indian design community groups (organic, posts pending approval), Behance India outreach list (approval required), small paid social test capped at a budget the founder sets.
- Threshold (from experiment_thresholds): deposit rate >= 3% of unique visitors, n >= 400 visitors; inconclusive between 1% and 3%.

## Common mistakes

- Measuring plain email signups and calling it demand.
- Hiding or delaying the "not live" disclosure.
- Driving traffic from friends and the founder's followers instead of the ICP.
- Setting the threshold after seeing results.
- Mixing segments without UTM tags, so you cannot tell designers from tutors.
- Fake testimonials or "1,000 freelancers already joined".
- Taking money without a clear refund path.
