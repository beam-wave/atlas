defmodule Atlas.Evidence do
  @moduledoc """
  The evidence ledger: observations and the queries scores are built from.
  """
  import Ecto.Query

  alias Atlas.Evidence.Observation
  alias Atlas.Repo

  def record(attrs) do
    with {:ok, obs} <- %Observation{} |> Observation.changeset(attrs) |> Repo.insert() do
      Atlas.Studies.broadcast(obs.study_id, {:evidence, Observation.ref(obs)})
      {:ok, obs}
    end
  end

  @doc """
  Records many observations atomically. Returns `{:error, {index, changeset}}`
  for the first invalid one; nothing is written in that case.
  """
  def record_many([]), do: {:ok, []}

  def record_many(list) do
    result =
      Repo.transaction(fn ->
        list
        |> Enum.with_index()
        |> Enum.map(fn {attrs, i} ->
          case %Observation{} |> Observation.changeset(attrs) |> Repo.insert() do
            {:ok, obs} -> obs
            {:error, cs} -> Repo.rollback({i, cs})
          end
        end)
      end)

    with {:ok, [first | _] = observations} <- result do
      Atlas.Studies.broadcast(first.study_id, {:evidence, length(observations)})
      {:ok, observations}
    end
  end

  def get!(id), do: Repo.get!(Observation, id)

  @doc """
  Lists a study's observations. Filters: `:segment_id`, `:evidence_type`,
  `:signal_code`, `:loop`, `:include_study_wide` (with segment filter, also
  return observations that have no segment).
  """
  def list(study_id, filters \\ []) do
    Observation
    |> where([o], o.study_id == ^study_id)
    |> filter_segment(filters[:segment_id], filters[:include_study_wide])
    |> maybe_where(:evidence_type, filters[:evidence_type])
    |> maybe_where(:signal_code, filters[:signal_code])
    |> maybe_where(:loop_number, filters[:loop])
    |> order_by(asc: :id)
    |> Repo.all()
  end

  defp filter_segment(q, nil, _), do: q

  defp filter_segment(q, segment_id, true),
    do: where(q, [o], o.segment_id == ^segment_id or is_nil(o.segment_id))

  defp filter_segment(q, segment_id, _), do: where(q, [o], o.segment_id == ^segment_id)

  defp maybe_where(q, _field, nil), do: q

  defp maybe_where(q, field, values) when is_list(values),
    do: where(q, [o], field(o, ^field) in ^values)

  defp maybe_where(q, field, value), do: where(q, [o], field(o, ^field) == ^value)

  @doc "The set of evidence ids that exist for a study."
  def ids(study_id) do
    Observation
    |> where([o], o.study_id == ^study_id)
    |> select([o], o.id)
    |> Repo.all()
    |> MapSet.new()
  end

  def count(study_id) do
    Observation |> where([o], o.study_id == ^study_id) |> Repo.aggregate(:count)
  end

  def counts_by_type(study_id) do
    Observation
    |> where([o], o.study_id == ^study_id)
    |> group_by([o], o.evidence_type)
    |> select([o], {o.evidence_type, count(o.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Compact, prompt-friendly rows for a set of observations."
  def digest(observations) do
    Enum.map(observations, fn o ->
      %{
        "ref" => Observation.ref(o),
        "segment_id" => o.segment_id,
        "signal_code" => o.signal_code,
        "value" => o.value_num || o.value_text,
        "detail" => if(o.value_num, do: o.value_text),
        "evidence_type" => o.evidence_type,
        "confidence" => o.confidence,
        "source" => o.source_url || o.source_note
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) end)
    end)
  end

  @doc "Deletes all observations of a study (per-study deletion for privacy)."
  def delete_for_study(study_id) do
    Observation |> where([o], o.study_id == ^study_id) |> Repo.delete_all()
  end
end
