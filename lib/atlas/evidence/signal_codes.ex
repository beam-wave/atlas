defmodule Atlas.Evidence.SignalCodes do
  @moduledoc """
  The governed vocabulary of signals an observation may record.

  Each code belongs to a scorecard dimension (or `market` / `general` for
  context that informs but does not score). Observations reference
  `signal_codes.code` through a foreign key, so an unknown code is rejected by
  the database. To add a code: append it here and add a migration that calls
  `sync!/1`.
  """

  @codes [
    # problem_intensity
    {"pain_frequency", "problem_intensity", "How often the problem occurs (0-5)"},
    {"pain_severity", "problem_intensity", "How bad the problem is when it occurs (0-5)"},
    {"current_spend", "problem_intensity", "Money or time currently spent on the problem"},
    {"workaround_seeking", "problem_intensity", "Evidence people actively hunt for workarounds"},
    {"pain_mention_volume", "problem_intensity",
     "Volume of forum or review mentions of the pain"},
    {"pain_quote", "problem_intensity", "Verbatim pain language from a public source"},
    {"interview_pain_confirmed", "problem_intensity",
     "Share of interviews confirming the pain (%)"},
    {"interview_past_spend", "problem_intensity", "Interviewees who already paid to solve it"},
    # willingness_to_pay
    {"competitor_price", "willingness_to_pay", "Published price of an alternative"},
    {"price_anchor", "willingness_to_pay", "Reference price customers compare against"},
    {"vw_too_cheap", "willingness_to_pay", "Van Westendorp median: too cheap"},
    {"vw_bargain", "willingness_to_pay", "Van Westendorp median: bargain"},
    {"vw_expensive", "willingness_to_pay", "Van Westendorp median: getting expensive"},
    {"vw_too_expensive", "willingness_to_pay", "Van Westendorp median: too expensive"},
    {"preorder_count", "willingness_to_pay", "Pre-orders or deposits received"},
    {"paid_pilot_count", "willingness_to_pay", "Paid pilots signed"},
    # reachability
    {"community_size", "reachability", "Size of a community where the segment gathers"},
    {"channel_cost_estimate", "reachability", "Estimated cost to reach one prospect"},
    {"signup_cost_per_channel", "reachability", "Measured cost per signup on a channel"},
    {"signup_conversion_pct", "reachability", "Smoke-test visitor to signup conversion (%)"},
    {"visits", "reachability", "Smoke-test page visits"},
    {"signups", "reachability", "Smoke-test signups"},
    # competitive_gap
    {"competitor_present", "competitive_gap", "An alternative the segment uses today"},
    {"positioning_gap", "competitive_gap", "An unmet need alternatives do not address"},
    {"feature_gap", "competitive_gap", "A capability alternatives lack"},
    {"switching_intent", "competitive_gap",
     "Share of interviewees describing a switch moment (%)"},
    # sean_ellis
    {"sean_ellis_very_disappointed_pct", "sean_ellis", "Share answering 'very disappointed' (%)"},
    {"sean_ellis_responses", "sean_ellis", "Number of qualifying Sean Ellis responses"},
    # retention
    {"retention_pct", "retention", "Share of a cohort still active at a period (%)"},
    {"retention_flattening", "retention", "1 when the cohort curve flattens, 0 when it decays"},
    # market context
    {"market_size", "market", "Market size estimate"},
    {"market_trend", "market", "Direction or growth of the market"},
    {"regulation", "market", "Regulation that shapes the segment"},
    # general
    {"interview_count", "general", "Interviews completed"},
    {"experiment_outcome", "general", "1 passed, 0 failed, 0.5 inconclusive"},
    {"note", "general", "Free-form observation"}
  ]

  @dimensions ~w(problem_intensity willingness_to_pay reachability competitive_gap sean_ellis retention)

  def all, do: @codes
  def codes, do: Enum.map(@codes, &elem(&1, 0))
  def scoring_dimensions, do: @dimensions

  def dimension(code) do
    case List.keyfind(@codes, code, 0) do
      {_, dimension, _} -> dimension
      nil -> nil
    end
  end

  def codes_for(dimension), do: for({code, ^dimension, _} <- @codes, do: code)

  @doc "Upserts the vocabulary. Safe to run repeatedly."
  def sync!(repo \\ Atlas.Repo) do
    rows = for {code, dim, desc} <- @codes, do: %{code: code, dimension: dim, description: desc}

    repo.insert_all("signal_codes", rows,
      on_conflict: {:replace, [:dimension, :description]},
      conflict_target: :code
    )
  end
end
