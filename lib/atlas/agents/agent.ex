defmodule Atlas.Agents.Agent do
  @moduledoc """
  Behaviour and defaults for an agent: a role, a skill list, a prompt builder
  and an Ecto embedded schema that its JSON output must satisfy.

      use Atlas.Agents.Agent,
        name: "segment_strategist",
        skills: ~w(guardrails icp_definition),
        allow_web: false

  The skill list is a default; `priv/skills/skill_map.json` overrides it.
  """

  @callback name() :: String.t()
  @callback default_skills() :: [String.t()]
  @callback allow_web?() :: boolean()
  @callback role() :: String.t()
  @callback build_prompt(map()) :: String.t()
  @callback output_example() :: map()
  @callback changeset(struct(), map()) :: Ecto.Changeset.t()
  @callback validate(struct(), map()) :: :ok | {:error, [String.t()]}
  @callback mock_output(map()) :: map()

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Atlas.Agents.Agent
      use Ecto.Schema
      import Ecto.Changeset
      import Atlas.Agents.Agent, only: [json: 1, section: 2, feedback: 1]

      @primary_key false

      @impl true
      def name, do: unquote(opts[:name])
      @impl true
      def default_skills, do: unquote(opts[:skills] || [])
      @impl true
      def allow_web?, do: unquote(opts[:allow_web] || false)
      @impl true
      def validate(_output, _input), do: :ok

      defoverridable validate: 2
    end
  end

  @doc """
  Like `validate_length/3` for list fields, but also checks values that equal
  the default (an omitted list), which `validate_length` skips.
  """
  def validate_count(changeset, field, min, max) do
    n = changeset |> Ecto.Changeset.get_field(field) |> List.wrap() |> length()

    cond do
      n < min -> Ecto.Changeset.add_error(changeset, field, "needs at least #{min} item(s)")
      n > max -> Ecto.Changeset.add_error(changeset, field, "allows at most #{max} item(s)")
      true -> changeset
    end
  end

  @doc "Pretty JSON for prompts."
  def json(term), do: Jason.encode!(term, pretty: true)

  @doc "Issues from a previous attempt (gates or Skeptic) the agent must fix."
  def feedback(input) do
    case input[:revision_feedback] do
      list when is_list(list) and list != [] ->
        "## Fix these issues from review\n\nYour previous version was sent back. Address every point:\n\n" <>
          Enum.map_join(list, "\n", &"- #{&1}") <> "\n\n"

      _ ->
        ""
    end
  end

  @doc "A titled prompt section; skipped when the content is empty."
  def section(_title, content) when content in [nil, "", [], %{}], do: ""
  def section(title, content) when is_binary(content), do: "## #{title}\n\n#{content}\n\n"
  def section(title, content), do: "## #{title}\n\n```json\n#{json(content)}\n```\n\n"
end

defmodule Atlas.Agents.Schemas do
  @moduledoc "Embedded schemas shared by several agents."

  defmodule Claim do
    @moduledoc "A sentence the output asserts, with the evidence behind it."
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :text, :string
      field :evidence_ids, {:array, :string}, default: []
    end

    def changeset(claim, attrs) do
      claim
      |> cast(attrs, [:text, :evidence_ids])
      |> validate_required([:text])
    end
  end

  defmodule ObservationDraft do
    @moduledoc """
    An observation an agent proposes. The runner stamps study, evidence type,
    run id and agent before storing it. `segment` names the segment it is
    about (null for study-wide facts).
    """
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :segment, :string
      field :signal_code, :string
      field :value_num, :float
      field :value_text, :string
      field :confidence, :float
      field :source_url, :string
      field :source_note, :string
    end

    def changeset(obs, attrs) do
      obs
      |> cast(attrs, [
        :segment,
        :signal_code,
        :value_num,
        :value_text,
        :confidence,
        :source_url,
        :source_note
      ])
      |> validate_required([:signal_code, :confidence])
      |> validate_inclusion(:signal_code, Atlas.Evidence.SignalCodes.codes())
      |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
      |> then(fn cs ->
        if get_field(cs, :value_num) == nil and (get_field(cs, :value_text) || "") == "",
          do: add_error(cs, :value_text, "value_num or value_text is required"),
          else: cs
      end)
    end
  end

  @doc "Checks drafts only use the signal codes an agent is allowed to emit."
  def check_codes(drafts, allowed) do
    bad = drafts |> Enum.map(& &1.signal_code) |> Enum.reject(&(&1 in allowed)) |> Enum.uniq()

    if bad == [],
      do: :ok,
      else: {:error, ["signal codes not allowed for this agent: #{Enum.join(bad, ", ")}"]}
  end

  @doc "Checks drafts carry a source when the evidence type requires one."
  def check_sources(drafts) do
    missing = Enum.count(drafts, &(blank?(&1.source_url) and blank?(&1.source_note)))

    if missing == 0,
      do: :ok,
      else: {:error, ["#{missing} observation(s) have no source_url or source_note"]}
  end

  defp blank?(v), do: v in [nil, ""]
end
