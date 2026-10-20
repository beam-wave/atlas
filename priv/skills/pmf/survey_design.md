---
name: survey_design
title: Survey Design
description: Write unbiased surveys including the Sean Ellis PMF question and Van Westendorp price questions
version: 1
---

# Survey Design

## When to use

Use this skill to draft surveys the founder will send. Surveys produce `experimental` evidence only after real responses are uploaded and processed by code. You draft; a human approves and sends. Two standard instruments matter for the scorecard: the Sean Ellis question (feeds `sean_ellis`) and Van Westendorp price sensitivity (informs `willingness_to_pay`).

Send the Sean Ellis survey only to people who have actually used the product, ideally at least twice in the last two weeks. Asking non-users is meaningless.

## Steps

1. **State the decision the survey informs** and the threshold that decides it (see experiment_thresholds). If no decision depends on the answer, cut the question.
2. **Define the sample:** who receives it, how they are reached, target number of responses. Minimum 40 responses for Sean Ellis; aim for 100.
3. **Write screening questions first** (role, GST status, current method) so responses can be segmented. Ask the minimum needed; no names, emails or phone numbers unless the human explicitly needs follow-up consent.
4. **Write each question against the rules:**
   - **Not leading.** No adjectives that suggest an answer. Bad: "How frustrating is GST filing?" Good: "How would you describe your last GST filing?"
   - **Not double-barrelled.** One thing per question. Bad: "Is the app fast and accurate?" Split it.
   - **No hypothetical future.** Never "Would you use…", "Would you pay…", "How likely are you to…" for behaviour prediction. Ask about past behaviour: "In the last quarter, how did you file your GST return?"
   - **Specific time frame.** "In the last 3 months" not "usually".
   - **Balanced scales** with a neutral or "not applicable" option.
   - **Plain words** the segment uses.
5. **Order:** screening → past behaviour → Sean Ellis (if users) → price (if relevant) → one open text question → optional consent for follow-up.
6. **Keep it short.** Under 10 questions, under 3 minutes.
7. **Pilot** with 3–5 people from the segment and fix confusing items.

### Sean Ellis question (exact wording, do not edit)

"How would you feel if you could no longer use <product>?"

- Very disappointed
- Somewhat disappointed
- Not disappointed

Optional follow-ups (keep wording neutral): "What is the main benefit you get from <product>?" and "What type of person do you think would benefit most from <product>?"

The PMF benchmark is 40% or more answering "Very disappointed". The share is computed by code from uploaded responses, never estimated.

### Van Westendorp price questions (all four, in this order)

1. "At what price would you consider <product> to be so cheap that you would question its quality?" (too cheap)
2. "At what price would you consider <product> to be a bargain, a great buy for the money?" (cheap / bargain)
3. "At what price would you consider <product> to be getting expensive, but you would still consider buying it?" (expensive)
4. "At what price would you consider <product> to be too expensive to consider buying?" (too expensive)

Use open numeric answers with a stated currency and period (e.g. INR per month). Ask only people who understand the product.

## Output format

```
survey_id: <slug>
decision: <what this informs>
threshold_ref: <experiment id>
audience: <segment and inclusion criteria>
channel: <how it reaches them, pending approval>
target_responses: <n>
questions:
  - id: Q1
    text: <exact text>
    type: single_choice | multi_choice | scale | numeric | open
    options: [<...>]
    purpose: <screening | behaviour | sean_ellis | price | open>
status: awaiting_approval
```

## Worked example

Survey for beta users of the AI bookkeeping app (designers, tutors, consultants), target 80 responses.

- Q1 "What is your main type of freelance work?" Design / Tutoring / Consulting / Other.
- Q2 "Are you registered for GST?" Yes / No / Not sure.
- Q3 "Before using <product>, how did you prepare your last GST return?" CA / Self with spreadsheet / Another app / Did not file / Not registered.
- Q4 Sean Ellis question, exact wording.
- Q5 "What is the main benefit you get from <product>?" (open)
- Q6–Q9 Van Westendorp four questions, INR per month.
- Q10 "Anything else you want to tell us?" (open)

Rejected draft: "Wouldn't automated GST filing save you a lot of stress?" — leading and hypothetical.

## Common mistakes

- Rewording the Sean Ellis question or adding a fourth option.
- Sending Sean Ellis to a waitlist of non-users.
- "Would you pay 499 per month?" — hypothetical; people overstate. Use Van Westendorp or a real payment test.
- Collecting emails by default.
- Reporting results before the minimum sample is reached.
- Analysing the blended score without segmenting by Q1 and Q2.
