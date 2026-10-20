import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :atlas, Atlas.Repo,
  database: Path.expand("../atlas_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :atlas, AtlasWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "0WiHgXbtULoQ/TV5xzdzcdVFMQihPZ+ZkYgh2ncy8pWoAYuoH90S/JU528qzEt1w",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :atlas, Oban, testing: :manual

config :atlas, Atlas.LLM,
  default_adapter: "mock",
  max_concurrency: 4,
  queue_timeout: 5_000,
  adapters: %{
    "claude_cli" => [executable: "claude"],
    "codex_cli" => [executable: "codex"],
    "cursor_cli" => [executable: "cursor-agent"],
    "gemini_cli" => [executable: "gemini"],
    "anthropic_api" => [
      api_key: "test-key",
      req_options: [plug: {Req.Test, Atlas.LLM.Adapters.AnthropicAPI}, retry: false]
    ],
    "mock" => []
  }

config :atlas,
  resume_studies: false,
  skills_poll_ms: 0,
  step_retries: 1,
  uploads_dir: Path.expand("../tmp/test_uploads", __DIR__)
