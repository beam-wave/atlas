defmodule Atlas.Artifacts do
  @moduledoc "Agent-produced documents and the approval queue."
  import Ecto.Query

  alias Atlas.Artifacts.{Approval, Artifact}
  alias Atlas.Repo

  def create(attrs) do
    with {:ok, artifact} <- %Artifact{} |> Artifact.changeset(attrs) |> Repo.insert() do
      Atlas.Studies.broadcast(artifact.study_id, {:artifact, artifact.kind, artifact.id})
      if artifact.status == "pending_approval", do: broadcast_queue()
      {:ok, artifact}
    end
  end

  def get!(id), do: Artifact |> Repo.get!(id) |> Repo.preload(:approvals)

  def update(%Artifact{} = artifact, attrs),
    do: artifact |> Artifact.changeset(attrs) |> Repo.update()

  def list(study_id, opts \\ []) do
    Artifact
    |> where([a], a.study_id == ^study_id)
    |> then(fn q -> if k = opts[:kind], do: where(q, [a], a.kind in ^List.wrap(k)), else: q end)
    |> then(fn q -> if l = opts[:loop], do: where(q, [a], a.loop_number == ^l), else: q end)
    |> order_by(asc: :id)
    |> Repo.all()
  end

  def latest(study_id, kind) do
    Artifact
    |> where([a], a.study_id == ^study_id and a.kind == ^kind)
    |> order_by(desc: :id)
    |> limit(1)
    |> Repo.one()
  end

  @doc "Pending approvals, oldest first. Optionally scoped to a study."
  def approval_queue(study_id \\ nil) do
    Artifact
    |> where([a], a.status == "pending_approval")
    |> then(fn q -> if study_id, do: where(q, [a], a.study_id == ^study_id), else: q end)
    |> order_by(asc: :id)
    |> preload(study: :product)
    |> Repo.all()
  end

  def pending_count(study_id \\ nil), do: length(approval_queue(study_id))

  @doc """
  Records a decision on a pending artifact. Returns `{:error, :not_pending}`
  if it was already decided.
  """
  def decide(%Artifact{status: "pending_approval"} = artifact, decision, note, decided_by)
      when decision in ["approved", "rejected"] do
    Repo.transaction(fn ->
      approval =
        %Approval{}
        |> Approval.changeset(%{
          artifact_id: artifact.id,
          decision: decision,
          note: note,
          decided_by: decided_by,
          decided_at: DateTime.utc_now(:second)
        })
        |> Repo.insert()
        |> case do
          {:ok, approval} -> approval
          {:error, cs} -> Repo.rollback(cs)
        end

      updated = artifact |> Artifact.changeset(%{status: decision}) |> Repo.update!()
      {updated, approval}
    end)
    |> tap(fn
      {:ok, {updated, _}} ->
        Atlas.Studies.broadcast(updated.study_id, {:decided, updated.id, decision})
        broadcast_queue()

      _ ->
        :ok
    end)
  end

  def decide(%Artifact{}, _decision, _note, _by), do: {:error, :not_pending}

  def rejection_notes(opts \\ []) do
    Approval
    |> join(:inner, [ap], a in assoc(ap, :artifact))
    |> where([ap], ap.decision == "rejected")
    |> then(fn q -> if k = opts[:kind], do: where(q, [_ap, a], a.kind == ^k), else: q end)
    |> order_by([ap], desc: ap.id)
    |> limit(^(opts[:limit] || 20))
    |> select([ap, a], %{kind: a.kind, agent: a.agent, note: ap.note, artifact_id: a.id})
    |> Repo.all()
  end

  def subscribe_queue, do: Phoenix.PubSub.subscribe(Atlas.PubSub, "approvals")

  defp broadcast_queue,
    do: Phoenix.PubSub.broadcast(Atlas.PubSub, "approvals", :approvals_changed)
end
