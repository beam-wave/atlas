---
name: research_method
title: Research Method
description: Desk research process, source quality tiers, evidence logging and confidence calibration
version: 1
---

# Research Method

## When to use

Use this skill whenever you gather facts about a market, segment, competitor, price point or customer pain. It applies to every agent that writes findings into the evidence log. If you are about to state something about the world, you are doing research and this skill governs how.

Evidence in Atlas has exactly three types:

- `desk` — public sources you read (reports, pricing pages, forums, government data, articles).
- `voc` — voice of customer: verbatim statements from real people (reviews, forum posts, interview notes, survey free text).
- `experimental` — data produced by a test the founder ran (survey results, smoke tests, retention exports). Computed by code from uploaded data, never estimated by you.

Every claim in agent output must cite at least one evidence ID such as `E12`. A code gate blocks any uncited claim. No source URL means no evidence entry, which means no claim.

## Steps

1. **Write the question first.** One sentence, answerable, scoped to a segment and geography. Bad: "Is the market big?" Good: "How many freelance designers in India are GST-registered?"
2. **List what would change your mind.** Name the finding that would make the hypothesis false. Search for it as hard as for confirming evidence.
3. **Search in tier order.** Start with the highest tier that could answer the question.
4. **Log each finding as one evidence entry.** One fact per entry. Include source URL, retrieval date, type, a short verbatim excerpt or the exact figure, and confidence.
5. **Triangulate.** A number that matters to the verdict needs two independent sources. If they disagree by more than 2x, log both and report the range.
6. **Calibrate confidence** using the scale below. Do not round up because the finding is convenient.
7. **Write claims that cite entries.** A claim summarises one or more entries and lists their IDs. If you cannot cite, delete the claim or turn it into an open question.
8. **Record gaps.** List the questions you could not answer and the experiment that would answer them.

### Source quality tiers

- **Tier 1** — primary data: government statistics (e.g. GSTN, MCA, census), company filings, the vendor's own pricing page, academic papers with methods. Base confidence 0.7–0.9.
- **Tier 2** — reputable secondary: established industry analysts, major business press quoting named sources, platform-published data (e.g. Upwork reports). Base confidence 0.5–0.7.
- **Tier 3** — community and opinion: Reddit, Quora, X threads, YouTube comments, app store reviews. Strong for `voc`, weak for market size. Base confidence 0.3–0.5.
- **Tier 4** — unverifiable: SEO listicles, undated blogs, AI-generated summaries, numbers with no traceable origin. Base confidence 0.1–0.2. Prefer to discard.

### Confidence calibration (0.0–1.0)

- 0.9 and above — you would bet heavily; primary source, recent, directly answers the question.
- 0.7 — solid; good source, small inference step.
- 0.5 — coin-flip plus; plausible, single secondary source or meaningful inference.
- 0.3 — weak; anecdotal, old, or a different geography or segment.
- 0.1 — placeholder; logged only so the gap is visible.

Subtract 0.1–0.2 when the data is older than three years, from a different country, or about an adjacent segment.

## Output format

Each evidence entry:

```
id: E<n>
type: desk | voc | experimental
source_url: <full URL>
retrieved: <YYYY-MM-DD>
excerpt: <verbatim quote or exact figure>
confidence: <0.0-1.0>
note: <one line on relevance or caveat>
```

Each claim: one sentence, followed by cited IDs in brackets, e.g. `Most GST-registered freelancers file quarterly under QRMP [E4, E7].`

End with `Open questions` — each with the experiment that would close it.

## Worked example

Question: "Do Indian freelance designers pay someone to handle GST filing today?"

- E3, desk, Tier 1, a government GST portal page describing QRMP quarterly filing eligibility. Confidence 0.85.
- E4, desk, Tier 2, a business-press article quoting a CA association on typical small-filer fees. Confidence 0.55.
- E5, voc, Tier 3, a Reddit r/IndiaTax post: a designer says they pay their CA a monthly retainer "just for GST". Confidence 0.4 as a market fact, useful as pain signal.

Claim: `Some freelance designers already pay CAs a recurring fee for GST compliance [E4, E5].` Note the word "some" — two sources do not support "most".

Open question: share of GST-registered designers who use a CA versus self-file. Experiment: 10-question survey to 50 designers sourced from Behance India communities.

## Common mistakes

- Citing a source you did not open. If you did not read it this session, do not cite it.
- Inventing or reconstructing URLs. If you cannot recover the exact URL, the finding is not evidence.
- Treating Tier 3 posts as market-size data. They show pain exists, not how many people have it.
- Merging several facts into one entry, which makes later review impossible.
- Assigning 0.8 confidence to a single blog post.
- Searching only for confirming evidence.
- Presenting estimates of survey or retention results. Those are `experimental` and come only from uploaded data.
