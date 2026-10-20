# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :atlas,
  ecto_repos: [Atlas.Repo],
  generators: [timestamp_type: :utc_datetime]

# Durable jobs on SQLite: re-score, re-observation, reminders, analyst.
config :atlas, Oban,
  engine: Oban.Engines.Lite,
  repo: Atlas.Repo,
  notifier: Oban.Notifiers.PG,
  peer: Oban.Peers.Global,
  queues: [default: 5, agents: 2],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 3600},
    {Oban.Plugins.Cron, crontab: [{"0 9 * * *", Atlas.Workers.Reminder}]}
  ]

# Model backends. Pick the default here, per study in the dashboard, or with
# ATLAS_LLM_ADAPTER. Subscription CLIs must be installed and logged in once.
config :atlas, Atlas.LLM,
  default_adapter: "claude_cli",
  max_concurrency: 3,
  queue_timeout: 600_000,
  adapters: %{
    "claude_cli" => [executable: "claude", timeout: 600_000],
    "codex_cli" => [executable: "codex", timeout: 600_000],
    "cursor_cli" => [timeout: 600_000],
    "gemini_cli" => [executable: "gemini", timeout: 600_000],
    "anthropic_api" => [model: "claude-opus-5-5", max_tokens: 16_000],
    "mock" => []
  }

config :atlas,
  top_segments: 2,
  step_retries: 1,
  reminder_after_days: 7,
  skills_poll_ms: 2000

# Configures the endpoint
config :atlas, AtlasWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AtlasWeb.ErrorHTML, json: AtlasWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Atlas.PubSub,
  live_view: [signing_salt: "xjf0VsNL"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  atlas: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  atlas: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
