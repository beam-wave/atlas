defmodule Atlas.Studies do
  @moduledoc """
  Products, studies, segments and hypotheses.

  State changes are broadcast on `"studies"` and `"study:<id>"` so LiveViews
  update without polling.
  """
  import Ecto.Query

  alias Atlas.Repo
  alias Atlas.Studies.{Hypothesis, Product, Segment, Study}

  @pubsub Atlas.PubSub

  ## PubSub

  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, "studies")
  def subscribe(study_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(study_id))

  def broadcast(study_id, event) do
    Phoenix.PubSub.broadcast(@pubsub, topic(study_id), {:study_event, study_id, event})
    Phoenix.PubSub.broadcast(@pubsub, "studies", {:study_event, study_id, event})
    :ok
  end

  defp topic(study_id), do: "study:#{study_id}"

  ## Products and studies

  def create_product(attrs) do
    %Product{} |> Product.changeset(attrs) |> Repo.insert()
  end

  @doc """
  Creates a product and a study for it in one transaction.

  `attrs` holds the product fields plus optional `"budget"` and `"adapter"`.
  """
  def create_study(attrs) do
    attrs = stringify(attrs)

    Repo.transaction(fn ->
      with {:ok, product} <- create_product(attrs),
           {:ok, study} <-
             %Study{}
             |> Study.create_changeset(Map.put(attrs, "product_id", product.id))
             |> Repo.insert() do
        %{study | product: product}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def get_study!(id), do: Study |> Repo.get!(id) |> Repo.preload(:product)
  def get_study(id), do: Study |> Repo.get(id) |> then(&(&1 && Repo.preload(&1, :product)))

  def list_studies do
    Study |> order_by(desc: :updated_at, desc: :id) |> preload(:product) |> Repo.all()
  end

  @doc "Studies a coordinator should be running for (not closed)."
  def list_active_study_ids do
    Study |> where([s], s.state != "closed") |> select([s], s.id) |> Repo.all()
  end

  def update_study(%Study{} = study, attrs) do
    with {:ok, updated} <- study |> Study.update_changeset(attrs) |> Repo.update() do
      broadcast(updated.id, {:updated, Map.take(updated, [:state, :verdict, :loop_number])})
      {:ok, updated}
    end
  end

  @doc """
  Atomically spends one model call from the study's budget.
  Returns `{:error, :budget_exhausted}` once the cap is reached.
  """
  def consume_call(nil), do: :ok

  def consume_call(study_id) do
    {count, _} =
      Study
      |> where([s], s.id == ^study_id and s.calls_used < s.budget)
      |> Repo.update_all(inc: [calls_used: 1])

    if count == 1, do: :ok, else: {:error, :budget_exhausted}
  end

  ## Segments

  def create_segment(attrs), do: %Segment{} |> Segment.changeset(attrs) |> Repo.insert()

  def get_segment!(id), do: Repo.get!(Segment, id)

  def list_segments(study_id, opts \\ []) do
    Segment
    |> where([s], s.study_id == ^study_id)
    |> filter_status(opts[:status])
    |> filter_loop(opts[:loop])
    |> order_by([s], asc_nulls_last: s.rank, asc: s.id)
    |> Repo.all()
  end

  defp filter_status(query, nil), do: query

  defp filter_status(query, statuses) when is_list(statuses),
    do: where(query, [s], s.status in ^statuses)

  defp filter_status(query, status), do: where(query, [s], s.status == ^status)

  defp filter_loop(query, nil), do: query
  defp filter_loop(query, loop), do: where(query, [s], s.loop_number == ^loop)

  @doc """
  Human pruning step: keeps the given proposed segments and prunes the other
  proposed ones. Returns `{:error, :nothing_kept}` if no id matches.
  """
  def prune_segments(study_id, keep_ids) do
    keep_ids = Enum.map(keep_ids, &to_int/1)
    proposed = list_segments(study_id, status: "proposed")
    kept = Enum.filter(proposed, &(&1.id in keep_ids))

    if kept == [] do
      {:error, :nothing_kept}
    else
      Repo.transaction(fn ->
        for segment <- proposed do
          status = if segment.id in keep_ids, do: "kept", else: "pruned"
          segment |> Segment.changeset(%{status: status}) |> Repo.update!()
        end

        length(kept)
      end)
    end
  end

  def rank_segments(ranked_ids) do
    ranked_ids
    |> Enum.with_index(1)
    |> Enum.each(fn {id, rank} ->
      Segment |> where([s], s.id == ^id) |> Repo.update_all(set: [rank: rank])
    end)
  end

  ## Hypotheses

  def create_hypothesis(attrs), do: %Hypothesis{} |> Hypothesis.changeset(attrs) |> Repo.insert()

  def get_hypothesis!(id), do: Repo.get!(Hypothesis, id)

  def list_hypotheses(study_id, segment_ids \\ nil) do
    Hypothesis
    |> where([h], h.study_id == ^study_id)
    |> then(fn q -> if segment_ids, do: where(q, [h], h.segment_id in ^segment_ids), else: q end)
    |> order_by(asc: :id)
    |> Repo.all()
  end

  def update_hypothesis(%Hypothesis{} = h, attrs),
    do: h |> Hypothesis.changeset(attrs) |> Repo.update()

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)

  defp stringify(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
end
