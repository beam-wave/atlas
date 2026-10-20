---
name: clear_writing
title: Clear Writing
description: Plain-language rules and banned filler phrases for every agent output a founder will read
version: 1
---

# Clear Writing

## When to use

Use this skill for any text a founder will read: summaries, recommendations, scorecard rationales, survey questions, landing-page copy drafts, interview guides. The reader is a busy founder deciding where to spend the next month. Every sentence should either state a finding, cite it, or tell them what to do.

## Steps

1. **Lead with the answer.** First sentence states the conclusion. Supporting detail follows.
2. **One idea per sentence.** Aim for under 20 words. Split anything over 30.
3. **Use concrete nouns and numbers.** "Freelance designers filing quarterly GST" beats "small business owners". "12 of 40 respondents" beats "a significant portion".
4. **Prefer the active voice.** "Tutors rarely register for GST [E8]" not "It was found that GST registration is rare among tutors".
5. **Match certainty to evidence.** Use "suggests" or "some" for confidence under 0.5. Use "shows" only for experimental evidence or multiple Tier 1 sources.
6. **Cut hedging stacks.** One qualifier per claim. Not "it may potentially be possible that".
7. **Use the customer's words** when describing pain. Quote verbatim from `voc` evidence rather than paraphrasing into marketing language.
8. **Remove every banned phrase** (list below). If a sentence only works with one, the sentence has no content. Delete it.
9. **Use lists for parallel items,** prose for reasoning. Do not bullet an argument.
10. **Read it once as the founder.** Delete anything they would skim past.

### Banned phrases

- game-changer
- game-changing
- revolutionize
- revolutionary
- seamless
- seamlessly
- cutting-edge
- state-of-the-art
- unlock the power
- unlock
- unleash
- in today's fast-paced world
- in today's digital age
- leverage synergies
- synergy
- delve
- dive deep
- deep dive
- robust
- holistic
- empower
- transformative
- next-generation
- best-in-class
- world-class
- paradigm shift
- move the needle
- low-hanging fruit
- at the end of the day
- it's worth noting that
- it is important to note
- navigate the landscape
- ever-evolving landscape
- tapestry
- elevate
- supercharge
- streamline
- one-stop shop
- harness

## Output format

There is no separate output. Apply these rules to whatever format the calling skill specifies. Before returning, scan for banned phrases and sentences over 30 words, and fix both.

## Worked example

Before:

> In today's fast-paced world, Indian freelancers face an ever-evolving landscape of tax compliance. Our cutting-edge AI solution seamlessly empowers them to unlock the power of automated bookkeeping, a true game-changer for the gig economy.

After:

> Freelance designers registered for GST file returns every quarter and often pay a CA a monthly fee to do it [E4, E5]. Several describe the fee as high for what they see as data entry [E5, E11]. An app that prepares GST returns from bank statements could replace that fee. We have not yet tested whether they will pay for it.

The rewrite names the segment, cites evidence, uses the customer's framing, and states what is unknown.

## Common mistakes

- Swapping one banned phrase for a synonym ("frictionless" for "seamless"). Remove the idea, not the word.
- Writing an introduction. Start with the finding.
- Ending with a summary that repeats the opening.
- Using "users" or "customers" when you mean a specific segment.
- Rounding "3 of 11" into "many".
- Bold text on every other phrase. Bold at most one thing per section.
- Explaining what you are about to say instead of saying it.
