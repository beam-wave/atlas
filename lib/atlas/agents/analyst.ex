defmodule Atlas.Agents.Analyst do
  @moduledoc """
  Reads the reasons people gave when rejecting artifacts and proposes skill
  edits. Proposals go to the approval queue; nothing changes until approved.
  """
  use Atlas.Agents.Agent,
    name: "analyst",
    skills: ~w(guardrails clear_writing critical_review)

  defmodule Proposal do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field :skill, :string
      field :rationale, :string
      field :addition, :string
    end

    def changeset(p, attrs),
      do:
        p
        |> cast(attrs, [:skill, :rationale, :addition])
        |> validate_required([:skill, :rationale, :addition])
  end

  embedded_schema do
    embeds_many :proposals, Proposal
  end

  @impl true
  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [])
    |> cast_embed(:proposals)
    |> validate_length(:proposals, max: 5)
  end

  @impl true
  def validate(%{proposals: proposals}, %{skills: skills}) do
    known = Enum.map(skills, & &1["name"])
    unknown = proposals |> Enum.map(& &1.skill) |> Enum.reject(&(&1 in known))
    if unknown == [], do: :ok, else: {:error, ["unknown skills: #{Enum.join(unknown, ", ")}"]}
  end

  def validate(_, _), do: :ok

  @impl true
  def role do
    "You turn reviewers' rejection notes into small, specific edits to the Markdown skills agents follow. " <>
      "Propose only edits a recurring note supports; one note is an anecdote."
  end

  @impl true
  def build_prompt(input) do
    """
    Here are recent rejection notes and the skills that produced the rejected work. Propose up to
    five edits. Each edit is a short Markdown passage to append to one skill under a
    "Lessons from reviews" heading. Return an empty list if no pattern is clear.

    #{section("Rejection notes", input[:rejections])}#{section("Skills", input[:skills])}
    """
  end

  @impl true
  def output_example do
    %{
      "proposals" => [
        %{
          "skill" => "survey_design",
          "rationale" => "Three rejections cite questions about future intent",
          "addition" => "- Rewrite any \"would you\" question as \"when did you last…\"."
        }
      ]
    }
  end

  @impl true
  def mock_output(%{rejections: rejections})
      when is_list(rejections) and length(rejections) >= 2 do
    %{
      "proposals" => [
        %{
          "skill" => "clear_writing",
          "rationale" => "Mock: recurring rejection notes",
          "addition" => "- Mock lesson: #{hd(rejections)["note"]}"
        }
      ]
    }
  end

  def mock_output(_), do: %{"proposals" => []}
end
