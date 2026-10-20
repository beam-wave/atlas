defmodule Atlas.LLM.Request do
  @moduledoc """
  One model call. `system` carries skills and the output contract; `prompt`
  the task. `metadata` is passed through to adapters (the mock adapter reads
  `:agent` and `:input` from it).
  """
  @enforce_keys [:prompt]
  defstruct system: "",
            prompt: nil,
            study_id: nil,
            agent: nil,
            model: nil,
            allow_web: false,
            timeout: nil,
            metadata: %{}

  @type t :: %__MODULE__{
          system: String.t(),
          prompt: String.t(),
          study_id: integer() | nil,
          agent: String.t() | nil,
          model: String.t() | nil,
          allow_web: boolean(),
          timeout: pos_integer() | nil,
          metadata: map()
        }

  @doc "System and task joined into one prompt, for adapters with no system field."
  def combined(%__MODULE__{system: system, prompt: prompt}) when system in [nil, ""], do: prompt

  def combined(%__MODULE__{system: system, prompt: prompt}) do
    system <> "\n\n=== TASK ===\n\n" <> prompt
  end
end

defmodule Atlas.LLM.Response do
  @moduledoc "What an adapter returns: the text plus whatever usage it can report."
  defstruct text: "", tokens_in: nil, tokens_out: nil, cost_usd: nil, model: nil, raw: nil

  @type t :: %__MODULE__{
          text: String.t(),
          tokens_in: non_neg_integer() | nil,
          tokens_out: non_neg_integer() | nil,
          cost_usd: float() | nil,
          model: String.t() | nil,
          raw: term()
        }
end

defmodule Atlas.LLM.Adapter do
  @moduledoc """
  Behaviour every model backend implements.

  `opts` is the adapter's keyword config from `config :atlas, Atlas.LLM,
  adapters: %{...}` merged with per-call overrides.
  """
  @callback complete(Atlas.LLM.Request.t(), keyword()) ::
              {:ok, Atlas.LLM.Response.t()} | {:error, term()}

  @doc "Reports whether the backend is usable on this machine, and how."
  @callback check(keyword()) :: {:ok, String.t()} | {:error, String.t()}
end
