defmodule Atlas.Usage do
  @moduledoc "Model-call accounting: per agent, per study, against budget."
  import Ecto.Query

  alias Atlas.Repo

  defmodule Call do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    schema "llm_calls" do
      field :agent, :string
      field :adapter, :string
      field :model, :string
      field :tokens_in, :integer
      field :tokens_out, :integer
      field :cost_usd, :float
      field :duration_ms, :integer
      field :outcome, :string
      field :error, :string
      belongs_to :study, Atlas.Studies.Study
      timestamps(type: :utc_datetime, updated_at: false)
    end

    def changeset(call, attrs) do
      call
      |> cast(attrs, [
        :study_id,
        :agent,
        :adapter,
        :model,
        :tokens_in,
        :tokens_out,
        :cost_usd,
        :duration_ms,
        :outcome,
        :error
      ])
      |> validate_required([:adapter, :duration_ms, :outcome])
      |> validate_inclusion(:outcome, ~w(ok error))
    end
  end

  def record(attrs) do
    with {:ok, call} <- %Call{} |> Call.changeset(attrs) |> Repo.insert() do
      Phoenix.PubSub.broadcast(Atlas.PubSub, "usage", {:llm_call, call})
      {:ok, call}
    end
  end

  def subscribe, do: Phoenix.PubSub.subscribe(Atlas.PubSub, "usage")

  def by_agent(study_id \\ nil) do
    Call
    |> scope(study_id)
    |> group_by([c], c.agent)
    |> select([c], %{
      agent: c.agent,
      calls: count(c.id),
      errors: filter(count(c.id), c.outcome == "error"),
      tokens_in: coalesce(sum(c.tokens_in), 0),
      tokens_out: coalesce(sum(c.tokens_out), 0),
      cost_usd: coalesce(sum(c.cost_usd), 0.0),
      avg_ms: avg(c.duration_ms)
    })
    |> order_by([c], desc: count(c.id))
    |> Repo.all()
  end

  def by_adapter do
    Call
    |> group_by([c], c.adapter)
    |> select([c], %{
      adapter: c.adapter,
      calls: count(c.id),
      cost_usd: coalesce(sum(c.cost_usd), 0.0)
    })
    |> Repo.all()
  end

  def by_study do
    from(s in Atlas.Studies.Study,
      join: p in assoc(s, :product),
      left_join: c in Call,
      on: c.study_id == s.id,
      group_by: [s.id, p.name, s.budget, s.calls_used],
      select: %{
        study_id: s.id,
        product: p.name,
        budget: s.budget,
        calls_used: s.calls_used,
        recorded: count(c.id),
        cost_usd: coalesce(sum(c.cost_usd), 0.0)
      },
      order_by: [desc: s.id]
    )
    |> Repo.all()
  end

  def recent(limit \\ 25) do
    Call |> order_by(desc: :id) |> limit(^limit) |> Repo.all()
  end

  defp scope(q, nil), do: q
  defp scope(q, study_id), do: where(q, [c], c.study_id == ^study_id)
end
