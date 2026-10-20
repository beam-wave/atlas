defmodule Atlas.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Atlas.LLM.Adapters.Mock.ensure_table()

    children = [
      AtlasWeb.Telemetry,
      Atlas.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:atlas, :ecto_repos), skip: skip_migrations?()},
      {Task, &Atlas.Settings.load/0},
      {DNSCluster, query: Application.get_env(:atlas, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Atlas.PubSub},
      {Oban, Application.fetch_env!(:atlas, Oban)},
      Atlas.Skills.Library,
      Atlas.LLM.RateLimiter,
      {Registry, keys: :unique, name: Atlas.Study.Registry},
      Atlas.Study.Supervisor,
      resume_child(),
      AtlasWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Atlas.Supervisor]
    Supervisor.start_link(Enum.reject(children, &is_nil/1), opts)
  end

  # Restart coordinators for studies that were running before shutdown.
  defp resume_child do
    if Application.get_env(:atlas, :resume_studies, true) do
      Supervisor.child_spec({Task, fn -> Atlas.Study.resume_all() end}, id: :resume_studies)
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AtlasWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
