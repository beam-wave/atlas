---
name: interview_guide
title: Interview Guide
description: Draft customer interview guides that follow Mom Test rules on past behaviour, specifics, no pitching and no compliments
version: 1
---

# Interview Guide

## When to use

Use this skill to draft a guide for problem interviews, switch interviews or post-use interviews that the founder will run. You draft; the founder conducts. Notes the founder uploads afterwards become `voc` evidence (verbatim lines, PII stripped).

Interviews answer "is this problem real, how do they deal with it now, and what does it cost them". They do not answer "will they buy". Only behaviour (payment, usage) answers that.

## Steps

1. **Set a learning goal.** Write the three things you most need to learn, tied to scorecard dimensions (e.g. problem_intensity factors, current spend, alternatives).
2. **Define who to interview.** ICP criteria plus disqualifiers. Aim for 8–12 interviews per segment before drawing conclusions. Do not mix segments in one batch.
3. **Write questions under the Mom Test rules:**
   - **Ask about past behaviour, not opinions or the future.** "Tell me about the last time you filed GST" not "Would you use an app that…".
   - **Ask for specifics.** Dates, amounts, tools, people involved. "How much did you pay your CA last quarter?" "What did you do when the notice arrived?"
   - **No pitching.** Do not describe the product until the very end, if at all. Once you pitch, answers become polite.
   - **Ignore and deflect compliments.** "That sounds great" is noise. Redirect: "How are you handling it today?"
   - **Dig into emotion and workarounds.** "What was the worst part?" "What have you tried to fix it?"
   - **Ask what else they have tried** and why they stopped.
   - **Ask about money and time already spent.**
4. **Structure the guide:**
   - Context (2 min): role, how they work, GST status.
   - Last occurrence (10 min): walk through the most recent time the problem happened.
   - Current solution and spend (5 min).
   - Past attempts and switches (5 min).
   - Closing (3 min): "Who else should I talk to?" and an optional commitment ask.
5. **Plan a commitment ask** for the end: introduction to a peer, joining a pilot, a deposit. A real commitment is evidence; enthusiasm is not.
6. **Write the note template** so the founder records verbatim lines, facts and commitments separately from their interpretation.
7. **Include the disclosure line:** who is asking, why, how notes are used, and that names will not be stored.

## Output format

```
guide_id: <slug>
segment_id: <slug>
learning_goals: [<...>]
recruit_criteria: [<...>]
disqualifiers: [<...>]
disclosure: <script>
sections:
  - name: <section>
    minutes: <n>
    questions: [<...>]
    probes: [<...>]
commitment_ask: <...>
note_template: [verbatim_quotes, facts, workarounds, spend, commitments, interviewer_interpretation]
red_flags_to_ignore: [compliments, hypotheticals, generic claims]
```

## Worked example

Segment: GST-registered freelance designers. Learning goals: how they prepare returns today, what it costs in time and money, what made them choose their current method.

- Disclosure: "I'm researching how freelancers handle GST. I'm not selling anything today. I'll take notes without your name."
- Last occurrence: "Walk me through the last time you filed GST. When did you start? What did you need to collect?" Probe: "How long did that take?" "Who else was involved?"
- Current spend: "What do you pay for help with tax and compliance? Monthly, per filing?"
- Past attempts: "Have you tried any app or template for this? What happened?"
- Commitment ask: "We're running a small pilot next month. Would you be willing to share last quarter's bank statement with redactions to test it?"

Rewritten bad questions:
- "Do you think filing GST is painful?" → "What happened the last time you filed?"
- "Would you pay 500 a month for automation?" → "What did you pay last quarter to get it done?"

## Common mistakes

- Pitching in the first five minutes, then recording polite agreement as validation.
- Asking "would you" questions.
- Accepting "I usually..." without asking for the last specific time.
- Treating compliments or "let me know when it launches" as a signal.
- Interviewing friends and family.
- Writing interpretation into the verbatim notes field.
- Stopping at three interviews because they agreed with the founder.
