import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/atlas start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :atlas, AtlasWeb.Endpoint, server: true
end

# Point an adapter at a different binary or model without editing config:
#   ATLAS_CLAUDE_BIN, ATLAS_CODEX_BIN, ATLAS_CURSOR_BIN, ATLAS_GEMINI_BIN
#   ATLAS_CLAUDE_MODEL, ATLAS_CODEX_MODEL, ATLAS_CURSOR_MODEL, ATLAS_GEMINI_MODEL, ATLAS_ANTHROPIC_MODEL
if config_env() != :test do
  llm = Application.get_env(:atlas, Atlas.LLM, [])

  overrides = %{
    "claude_cli" => {"ATLAS_CLAUDE_BIN", "ATLAS_CLAUDE_MODEL"},
    "codex_cli" => {"ATLAS_CODEX_BIN", "ATLAS_CODEX_MODEL"},
    "cursor_cli" => {"ATLAS_CURSOR_BIN", "ATLAS_CURSOR_MODEL"},
    "gemini_cli" => {"ATLAS_GEMINI_BIN", "ATLAS_GEMINI_MODEL"},
    "anthropic_api" => {nil, "ATLAS_ANTHROPIC_MODEL"}
  }

  adapters =
    Enum.reduce(overrides, llm[:adapters] || %{}, fn {name, {bin_var, model_var}}, acc ->
      opts = Map.get(acc, name, [])

      opts =
        if bin_var && System.get_env(bin_var),
          do: Keyword.put(opts, :executable, System.get_env(bin_var)),
          else: opts

      opts =
        if System.get_env(model_var),
          do: Keyword.put(opts, :model, System.get_env(model_var)),
          else: opts

      Map.put(acc, name, opts)
    end)

  llm = Keyword.put(llm, :adapters, adapters)

  llm =
    case System.get_env("ATLAS_MAX_CONCURRENCY") do
      nil -> llm
      n -> Keyword.put(llm, :max_concurrency, String.to_integer(n))
    end

  config :atlas, Atlas.LLM, llm
end

# Where uploaded experiment results are stored (Docker points this at /data).
if uploads = System.get_env("ATLAS_UPLOADS_DIR") do
  config :atlas, uploads_dir: uploads
end

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/atlas/atlas.db
      """

  config :atlas, Atlas.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")
  # Public URL. Defaults suit a host behind HTTPS; the Docker setup runs on
  # plain http://localhost:4000 and sets these accordingly.
  url_scheme = System.get_env("PHX_URL_SCHEME") || "https"
  url_port = String.to_integer(System.get_env("PHX_URL_PORT") || "443")

  config :atlas, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :atlas, AtlasWeb.Endpoint,
    url: [host: host, port: url_port, scheme: url_scheme],
    # Local Docker installs are reached as localhost or 127.0.0.1; allow both.
    check_origin: System.get_env("PHX_CHECK_ORIGIN", "true") != "false",
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :atlas, AtlasWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :atlas, AtlasWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
