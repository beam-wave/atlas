# Atlas PMF

Atlas PMF takes a product and returns an evidence-backed product-market-fit
scorecard, segment by segment, plus the cheapest experiments that would prove
or disprove fit.

It is a loop, not a report. Agents propose segments and experiments, you run
the experiments, results flow back in, and agents re-score. Every score
carries its evidence type (desk, voice-of-customer or experimental), so the
system never claims fit from desk research alone.

- **Runs on the AI subscription you already pay for.** Claude Code, OpenAI
  Codex, Cursor and Gemini CLIs are supported as model backends; an Anthropic
  API key works too. An offline mock backend runs the whole loop with no model
  at all.
- **One command to run.** `make up` builds and starts everything in Docker,
  CLIs included. Prefer no Docker? `make install` sets up Erlang and Elixir
  through asdf. Data lives in one SQLite file; there is no database server.
- **Knowledge is Markdown.** The PMF methods agents follow are editable files
  in `priv/skills/`. Change a skill, and the next agent call uses it.

## Quick start

### Option 1: Docker (one command, nothing else to install)

You need [Docker](https://docs.docker.com/get-docker/) only.

```bash
make up
```

No `make`? Use `docker compose up --build -d`. Then open <http://localhost:4000>.
Port 4000 taken? `make up PORT=4001` (or set `ATLAS_PORT` in `.env`). The
first build takes a few minutes; later starts take seconds.

The image includes Erlang/Elixir, the app, and the Claude Code, Codex, Gemini
and Cursor CLIs. Your data (SQLite database, editable skills, uploads) lives
in the `atlas-data` volume and survives rebuilds.

Connect your AI subscription once, either way:

- **Token in `.env`** (created by `make up` from `.env.example`). For Claude,
  run `claude setup-token` on your machine and set `CLAUDE_CODE_OAUTH_TOKEN`.
  Cursor and Gemini take `CURSOR_API_KEY` / `GEMINI_API_KEY`. Then `make restart`.
- **Log in inside the container:** `make docker-login`, pick a CLI and follow
  its prompts. Logins persist in the `atlas-home` volume.

`make docker-doctor` shows which CLIs are installed inside the container (it
does not check that you are logged in; a study's first step will tell you). Choose
`mock` when creating a study to try everything offline.

Other commands: `make logs`, `make down`, `make rebuild`, `make docker-shell`.
Run `make` to list them all.

### Option 2: install locally (asdf)

```bash
make install
```

This installs [asdf](https://asdf-vm.com) if needed, then the Erlang and
Elixir versions pinned in `.tool-versions`, then runs `mix setup`. It supports
macOS (Homebrew) and Debian/Ubuntu (apt). Erlang compiles from source the
first time, which takes 5–15 minutes. If Elixir is already installed at the
right version it skips straight to setup.

```bash
make server
```

Open <http://localhost:4000>, describe a product, and pick a model backend.
`make clis` installs the Claude Code, Codex and Gemini CLIs with npm.

To run a study from the terminal instead:

```bash
mix atlas.study "AI bookkeeping for Indian freelancers" --name LedgerLite --keep-all
```

## Choosing a model backend

| Backend         | What it runs                         | Billing                  | One-time setup                               |
|-----------------|--------------------------------------|--------------------------|----------------------------------------------|
| `claude_cli`    | `claude -p` (Claude Code)            | Claude Pro/Max plan      | install Claude Code, run `claude` and log in |
| `codex_cli`     | `codex exec` (OpenAI Codex CLI)      | ChatGPT plan             | install Codex, run `codex login`             |
| `cursor_cli`    | `cursor-agent -p` or `agent -p`      | Cursor plan              | install Cursor CLI, run `cursor-agent login` |
| `gemini_cli`    | `gemini -p` (Gemini CLI)             | Google account           | install Gemini CLI, run `gemini` and log in  |
| `anthropic_api` | Claude Messages API                  | API key                  | set `ANTHROPIC_API_KEY`                      |
| `mock`          | canned outputs                       | free                     | none                                         |

In Docker all four CLIs are already installed; only the login is left. Without
Docker, `make clis` installs the Claude Code, Codex and Gemini CLIs with npm,
and Cursor's installer is `curl https://cursor.com/install -fsS | bash`.

Check what is ready (`make docker-doctor` inside Docker):

```bash
make doctor
```

To send one tiny prompt through a backend and see the reply:

```bash
mix atlas.doctor --ping claude_cli
```

The backend for a study is, in order: the one chosen when the study was
created, the default set on the Studies page, `ATLAS_LLM_ADAPTER`, then
`default_adapter` in `config/config.exs` (`claude_cli`).

CLIs run in print mode inside an empty scratch directory, read-only where the
CLI supports it, with the prompt passed on stdin. Research agents may use the
CLI's web search when it offers one (Claude Code: `WebSearch`/`WebFetch`).
Override the binary or model per backend with environment variables, for
example `ATLAS_CLAUDE_BIN`, `ATLAS_CODEX_MODEL`, `ATLAS_CURSOR_BIN`,
`ATLAS_GEMINI_MODEL` or `ATLAS_ANTHROPIC_MODEL`. `ATLAS_MAX_CONCURRENCY`
(default 3) caps parallel model calls so a subscription is not flooded.

## How a study runs

Each study moves through eight states. Two of them wait for you.

1. **Intake** — structure the product brief.
2. **Hypothesize** — the Segment Strategist proposes 4–8 segments, each with a
   job to be done and a falsifiable hypothesis. *You keep the ones worth
   testing.*
3. **Desk research** — Market Researcher and Voice-of-Customer Miner run in
   parallel per segment; the Competitor Analyst maps alternatives, including
   spreadsheets, agencies and doing nothing.
4. **Desk score** — the scorer rates each segment; positioning is drafted for
   the top segments.
5. **Design tests** — the Experiment Designer writes the cheapest test per
   hypothesis (survey, interview guide or smoke test) with success thresholds.
6. **Await data** — *you approve designs (which locks their thresholds), run
   them, and upload survey CSVs, interview transcripts, analytics or retention
   exports.*
7. **Ingest results** — code computes the numbers (Sean Ellis share, Van
   Westendorp, conversion, cohort retention); the Evidence Synthesizer reads
   transcripts and open text; each experiment is scored against its locked
   thresholds.
8. **Verdict** — a scorecard per segment and one next move: double down,
   narrow, reposition or pivot. You start the next loop: back to re-segmenting,
   or on to the next experiments.

The Skeptic reviews producer outputs and sends weak work back once with fixes.

### Scorecard

Six dimensions scored 0–5: problem intensity, willingness to pay,
reachability, competitive gap, Sean Ellis score and retention. Evidence counts
less when it is weaker (desk ×0.6, voice-of-customer ×0.8, experimental ×1.0).
Verdicts are *No signal yet*, *Promising*, *Approaching fit* and *Fit*; the
last two are reachable only with experimental evidence. The rubric lives in
`Atlas.Scoring` and is described to the agents in
`priv/skills/pmf/pmf_scorecard.md`.

### Gates (code, not model)

- Every claim cites an evidence ID that exists; uncited claims block the output.
- Experiment thresholds lock on approval; later edits are refused and logged.
- Survey lint rejects leading, double-barrelled and hypothetical-future questions.
- The verdict guard caps desk-only evidence at *Promising*.
- Nothing is exported before it is approved.
- Each study has a model-call budget, and a global kill switch halts every agent.

## Dashboard

- **Studies** — list, new study, default backend.
- **Study** — lifecycle, what it needs from you now, scorecard with history,
  experiments and uploads, documents with Skeptic notes, audit log, budget.
- **Evidence ledger** — every observation with source, type and confidence.
- **Approvals** — one item at a time; a rejection needs a reason, and the
  Analyst turns recurring reasons into proposed skill edits.
- **Skills** — view and edit the Markdown skills.
- **Usage** — calls per agent and per study against budget, backend health,
  kill switch.

## Skills

Skills are Markdown files with a short frontmatter and five sections (When to
use, Steps, Output format, Worked example, Common mistakes):

```
priv/skills/core/   research_method, critical_review, clear_writing, decision_frameworks, guardrails
priv/skills/pmf/    icp_definition, jobs_to_be_done, problem_intensity, ... pmf_scorecard, pivot_patterns
priv/skills/skill_map.json   which agent loads which skills
```

They reload on change. Each artifact records the hash of every skill that
produced it, so scores from different loops can be traced to the rubric text
used at the time.

## Project layout

```
lib/atlas/study/coordinator.ex   gen_statem per study; deterministic routing
lib/atlas/study/steps.ex         the work done in each state
lib/atlas/agents/                one module per agent, with its output schema
lib/atlas/llm/                   backend behaviour, CLI/API/mock adapters, rate limiter
lib/atlas/gates.ex               claim check, survey lint, threshold lock, verdict guard
lib/atlas/scoring.ex             the rubric
lib/atlas/ingest.ex              survey, analytics, retention and transcript parsing
lib/atlas/workers.ex             Oban jobs: re-score, re-observe, reminders, analyst
lib/atlas_web/live/              dashboard pages
priv/skills/                     the Markdown skills
Dockerfile, docker-compose.yml   the Docker setup (rel/docker-entrypoint.sh prepares /data)
Makefile, scripts/install.sh     one-command tasks and the asdf installer
```

Each study runs in its own supervised subtree. A crashed agent is contained,
the step retries once, and the study then stops in `failed` with the error and
a Retry button. State lives in SQLite, so restarting the app resumes studies
where they were.

## Tests

```bash
make test
```

The suite (about 190 tests) runs the full loop on the mock backend, exercises
each CLI adapter against fake executables, and covers the API adapter with
stubbed HTTP. No model is called and nothing is billed.

To spend a little of your real subscription and check the CLIs installed on
this machine (each test skips itself when its CLI is missing):

```bash
make test-live
```

## Privacy

Transcripts are redacted (emails, phone numbers, card numbers, ID numbers)
before they are stored or shown to a model. Uploads live in `uploads/`
(git-ignored) locally, or in the `atlas-data` volume in Docker. Deleting a
study deletes its evidence and uploads. `.env` holds your tokens and is
git-ignored and kept out of the Docker image.

## Troubleshooting

| Problem | Fix |
|---|---|
| `Port 4000 is already in use` | `make up PORT=4001` |
| `Docker is not running` | start Docker Desktop (or the docker service), then `make up` again |
| Docker build fails while downloading | network hiccup; run `make up` again (downloads retry, finished layers are cached) |
| A study fails with a login or auth error | log the CLI in: `make docker-login` (Docker) or run the CLI once in a terminal; then press **Retry** on the study |
| A study fails with "budget exhausted" | raise the call budget at the bottom of the study page, then **Retry** |
| Every study stops at once | the kill switch is on; release it on the Usage page |
| `elixir: command not found` after `make install` | open a new terminal (the installer added asdf to your shell profile) |
| Start over in Docker | `make docker-reset` deletes the container, data and CLI logins (asks first) |

## Updating

Docker:

```bash
git pull && make up
```

Without Docker:

```bash
git pull && make setup
```

In Docker, database migrations run automatically when the app starts;
`make setup` runs them locally. Your skills in
Docker are a copy in the data volume, so local edits survive updates; delete
`/data/skills` inside the container (`make docker-shell`) to take the new
defaults.

## Configuration

| Variable                 | Default                  | Purpose                              |
|--------------------------|--------------------------|--------------------------------------|
| `ATLAS_LLM_ADAPTER`      | `claude_cli`             | default backend                      |
| `ATLAS_MAX_CONCURRENCY`  | `3`                      | parallel model calls                 |
| `ATLAS_PORT`             | `4000`                   | host port for Docker                 |
| `ATLAS_SKILLS_DIR`       | `priv/skills`            | where skills are read from           |
| `ATLAS_UPLOADS_DIR`      | `uploads/`               | where result files are stored        |
| `CLAUDE_CODE_OAUTH_TOKEN`| —                        | Claude subscription token (`claude setup-token`) |
| `CURSOR_API_KEY`         | —                        | Cursor subscription key              |
| `GEMINI_API_KEY`         | —                        | Gemini key                           |
| `OPENAI_API_KEY`         | —                        | Codex with an API key instead of login |
| `ANTHROPIC_API_KEY`      | —                        | for `anthropic_api`                  |
| `DATABASE_PATH`          | `atlas_dev.db` in dev    | SQLite file (Docker: `/data/atlas.db`) |
| `SECRET_KEY_BASE`        | —                        | required in prod (Docker generates one) |
| `PHX_HOST`, `PHX_URL_SCHEME`, `PHX_URL_PORT` | `example.com`, `https`, `443` | public URL when deployed |

In Docker, put these in `.env` (see `.env.example`) and run `make restart`.
