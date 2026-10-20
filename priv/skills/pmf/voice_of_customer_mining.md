---
name: voice_of_customer_mining
title: Voice of Customer Mining
description: Extract real pain signals from public customer conversations with strict verbatim quoting and no PII
version: 1
---

# Voice of Customer Mining

## When to use

Use this skill to collect `voc` evidence: what real people in the ICP say, in their own words, about the problem and current alternatives. Sources include Reddit, Quora, X, LinkedIn posts, app store and G2-style reviews, YouTube comments, community forums and, when uploaded by the founder, interview notes and survey free text.

`voc` evidence carries a 0.8 multiplier in the scorecard. It shows that pain exists and how people describe it. It does not measure how many people have it, and it cannot rate sean_ellis or retention.

## Steps

1. **Build search queries from the job, not the product.** Use the words customers use: "GST filing freelancer", "CA fees too high", "how do designers file GST", "GSTR-3B mismatch notice". Add competitor and alternative names plus "alternative", "review", "problem", "hate", "switched".
2. **Filter to the ICP.** Keep a post only if the author plausibly matches the segment (stated role, context). Log the segment match reason.
3. **Classify each candidate as signal or noise** using the tests below.
4. **Rate intensity** of each signal with the markers below.
5. **Quote under the quoting rules.** One evidence entry per quote.
6. **Cluster** signals into themes (e.g. "reconciliation time", "fear of notices", "CA responsiveness"). Count distinct authors per theme, not posts.
7. **Look for counter-signal.** Search for people who are satisfied with the alternative. Log them too.

### Signal versus noise

Real pain signal:
- Describes a specific past event ("last quarter my CA filed late and I paid a fee").
- Mentions spending money, time or effort on the problem.
- Describes a workaround or a switch.
- Asks for a recommendation with constraints ("need something under 500 a month that handles UPI").

Noise:
- Generic complaints with no situation ("taxes suck").
- Hypothetical enthusiasm ("someone should build an app for this").
- Vendor marketing, affiliate posts, or the founder's own network cheering.
- Posts more than three years old unless the problem is unchanged and you note it.
- Duplicates and reposts.

### Intensity markers (higher to lower)

- **High** — money lost, penalties, lost clients, legal fear, "I'm paying X just for this", already switched or abandoned a tool.
- **Medium** — recurring time cost stated, active workaround, emotional language tied to a concrete event.
- **Low** — mild annoyance, curiosity, general questions.

### Quoting rules

- Verbatim only. Copy the exact words. Use `[...]` for omissions and never change meaning.
- Every quote is attributed to the exact source URL you retrieved this session.
- Never invent, paraphrase into quote marks, or compose a "representative" quote.
- No PII. Strip usernames, real names, emails, phone numbers, client names and city-level location if identifying. Replace with `[redacted]`.
- Translate non-English quotes only if you also keep the original, and mark the translation as yours.

## Output format

```
id: E<n>
type: voc
source_url: <URL>
retrieved: <YYYY-MM-DD>
segment_match: <why this author fits the ICP>
quote: "<verbatim text, PII redacted>"
signal: pain | workaround | switch | satisfaction | request
intensity: high | medium | low
theme: <theme slug>
confidence: <0.0-1.0>
```

Then a theme table: theme, distinct authors, high-intensity count, representative evidence IDs, counter-signal IDs.

## Worked example

Search: "GST freelancer CA fees" on Reddit India communities.

```
id: E5
type: voc
source_url: https://www.reddit.com/r/IndiaTax/comments/<post-id>/...
retrieved: 2026-10-18
segment_match: Author states they are a freelance UI designer, GST-registered
quote: "I pay my CA every month and still spend a full weekend each quarter sending him invoices [...]"
signal: pain
intensity: high
theme: reconciliation_time
confidence: 0.5
```

(The URL placeholder above is illustrative only. A real entry uses the full URL actually retrieved.)

Theme summary: reconciliation_time — 7 distinct authors, 3 high intensity [E5, E12, E15]; counter-signal: 2 authors happy with their CA and unwilling to change [E22, E23].

## Common mistakes

- Counting 20 posts from 4 people as 20 signals.
- Including the founder's friends' LinkedIn comments.
- Cleaning up grammar inside quotes. Verbatim means verbatim.
- Keeping usernames for credibility.
- Reporting only pain and dropping satisfied users.
- Treating "would love an app for this" as demand. It is hypothetical and costs nothing to say.
