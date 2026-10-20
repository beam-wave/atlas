defmodule Atlas.Audit do
  @moduledoc "Append-only log of decisions, refusals and gate failures."
  import Ecto.Query
  require Logger

  alias Atlas.Repo

  defmodule Event do
    @moduledoc false
    use Ecto.Schema

    schema "audit_events" do
      field :kind, :string
      field :payload, :map, default: %{}
      belongs_to :study, Atlas.Studies.Study
      timestamps(type: :utc_datetime, updated_at: false)
    end
  end

  def log(study_id, kind, payload \\ %{}) do
    Logger.info("audit #{kind} study=#{inspect(study_id)} #{inspect(payload)}")

    %Event{study_id: study_id, kind: to_string(kind), payload: jsonable(payload)}
    |> Repo.insert()
  end

  def list(study_id, opts \\ []) do
    Event
    |> where([e], e.study_id == ^study_id)
    |> then(fn q -> if k = opts[:kind], do: where(q, [e], e.kind == ^k), else: q end)
    |> order_by(desc: :id)
    |> limit(^(opts[:limit] || 100))
    |> Repo.all()
  end

  defp jsonable(payload) do
    payload |> Jason.encode!() |> Jason.decode!()
  rescue
    _ -> %{"inspect" => inspect(payload)}
  end
end
