---
name: jobs_to_be_done
title: Jobs to Be Done
description: Map functional, emotional and social jobs and run switch analysis with push, pull, anxiety and habit forces
version: 1
---

# Jobs to Be Done

## When to use

Use this skill to understand why a customer would hire a product, and what it would take to make them fire their current solution. Use it after the ICP is drafted and before positioning. Apply it to `voc` evidence (reviews, forum posts, interview notes) and to switch interviews with people who recently changed solutions.

A job is the progress a person is trying to make in a specific circumstance. It is stable over time; solutions change.

## Steps

1. **Write the core job statement** in the form: "When <situation>, I want to <motivation>, so I can <outcome>." One per segment. No product names.
2. **Break the job into three layers:**
   - **Functional** — the practical task. "File GST return on time with correct figures."
   - **Emotional** — how they want to feel or avoid feeling. "Stop worrying about notices." "Not feel stupid about money."
   - **Social** — how they want to be seen. "Look like a professional business to clients." "Not look disorganised to my CA."
3. **Find the switch moments.** Search `voc` for posts or reviews where someone describes moving from one solution to another ("I finally ditched my CA", "went back to Excel"). These are the richest evidence.
4. **Map the four forces** for each switch:
   - **Push** — pain with the current situation driving change.
   - **Pull** — attraction of the new solution.
   - **Anxiety** — fears about the new solution that block switching.
   - **Habit** — comfort with the current way that resists change.
   A switch happens only when push + pull exceed anxiety + habit.
5. **Run switch interviews** when you have access to recent switchers (last 90 days). Reconstruct the timeline: first thought, passive looking, active looking, deciding, first use. Ask what happened, not what they think. See interview_guide.
6. **Cite every force** with evidence IDs. Mark forces you infer without evidence as `hypothesis`.
7. **Derive implications.** For each strong anxiety or habit, name what the product or messaging must do to reduce it.

## Output format

```
segment_id: <slug>
job_statement: When ..., I want to ..., so I can ...
functional: [<job>, ...]
emotional: [<job>, ...]
social: [<job>, ...]
forces:
  push: [<force> [E..], ...]
  pull: [<force> [E..], ...]
  anxiety: [<force> [E..], ...]
  habit: [<force> [E..], ...]
balance: <which side is stronger and why, one or two sentences>
implications:
  - <force> -> <product or messaging response>
```

## Worked example

Segment: GST-registered freelance designers.

Job statement: When a quarter ends and client payments are scattered across UPI, bank transfers and PayPal, I want my GST return prepared from what I already have, so I can file on time without losing a working day.

- Functional: reconcile invoices with bank credits; compute output GST; file GSTR-1 and GSTR-3B.
- Emotional: avoid dread before deadlines; stop feeling dependent on a CA for simple questions.
- Social: send clients proper GST invoices; appear established.

Forces:

- Push: CA retainer feels high for routine filings [E5]; delays waiting on the CA to respond [E12].
- Pull: auto-import of bank statements; fixed monthly price [hypothesis, no evidence yet].
- Anxiety: "what if the app files wrong and I get a notice" [E13]; data privacy of bank statements [E14].
- Habit: CA has done it for years and knows their history [E12]; spreadsheet already set up [E15].

Balance: push is real but anxiety about filing errors is the strongest force in the evidence. Implication: offer CA review of the first filing, or position the product as preparing returns for the CA, not replacing the CA.

## Common mistakes

- Writing the job as a feature ("I want AI categorisation"). Jobs never name solutions.
- Ignoring emotional and social jobs, which often decide the purchase.
- Listing only push and pull. Anxiety and habit explain why people who complain never switch.
- Asking people why they would switch in future. Ask what happened the last time they switched.
- Treating one dramatic post as the job for the whole segment.
- Inventing pull forces from the founder's pitch. Pull needs evidence or a `hypothesis` label.
