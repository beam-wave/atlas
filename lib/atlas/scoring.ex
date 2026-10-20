defmodule Atlas.Scoring do
  @moduledoc """
  The PMF rubric, in code. The `pmf_scorecard` skill describes the same rules
  to the scorer agent; this module is what actually decides.

  * Six dimensions scored 0–5, weighted and renormalised over rated ones.
  * Evidence multipliers: desk 0.6, voc 0.8, experimental 1.0.
  * Composite (0–100) = Σ(weight × score/5 × multiplier) / Σ(weight) × 100.
  * Sean Ellis and retention ratings come only from uploaded data.
  * A rating's evidence type is the strongest type among the observations it
    cites — not what the model says it is.
  """
  alias Atlas.Evidence.Observation
  alias Atlas.Gates.VerdictGuard

  @weights %{
    "problem_intensity" => 0.25,
    "willingness_to_pay" => 0.20,
    "reachability" => 0.15,
    "competitive_gap" => 0.15,
    "sean_ellis" => 0.15,
    "retention" => 0.10
  }

  @multipliers %{"desk" => 0.6, "voc" => 0.8, "experimental" => 1.0}
  @type_rank %{"desk" => 1, "voc" => 2, "experimental" => 3}
  @experimental_only ~w(sean_ellis retention)

  def weights, do: @weights
  def multipliers, do: @multipliers
  def dimensions, do: Map.keys(@weights) |> Enum.sort_by(&(-@weights[&1]))

  @doc "Sean Ellis 'very disappointed' % → 0–5."
  def sean_ellis_score(nil), do: nil
  def sean_ellis_score(pct) when pct >= 40, do: 5
  def sean_ellis_score(pct) when pct >= 30, do: 4
  def sean_ellis_score(pct) when pct >= 20, do: 3
  def sean_ellis_score(pct) when pct >= 10, do: 2
  def sean_ellis_score(pct) when pct > 0, do: 1
  def sean_ellis_score(_), do: 0

  @doc "Final retained % and whether the curve flattens → 0–5."
  def retention_score(nil, _), do: nil
  def retention_score(final, true) when final >= 40, do: 5
  def retention_score(final, true) when final >= 20, do: 4
  def retention_score(_final, true), do: 3
  def retention_score(final, false) when final >= 20, do: 2
  def retention_score(_final, false), do: 1

  @doc """
  Cleans model-proposed ratings against the evidence:

    * drops unknown dimensions, out-of-range scores and uncited ratings;
    * drops model ratings for `sean_ellis` / `retention` (code computes them);
    * sets `evidence_type` to the strongest type actually cited.
  """
  def normalize_ratings(ratings, observations) do
    by_id = Map.new(observations, &{&1.id, &1})

    ratings
    |> Enum.flat_map(fn r ->
      dim = r["dimension"]
      score = r["score"]
      refs = List.wrap(r["evidence_ids"])

      cited =
        refs
        |> Enum.flat_map(fn ref ->
          with {:ok, id} <- Observation.parse_ref(to_string(ref)),
               %Observation{} = o <- by_id[id],
               do: [o],
               else: (_ -> [])
        end)

      cond do
        not Map.has_key?(@weights, dim) ->
          []

        dim in @experimental_only ->
          []

        not (is_number(score) and score >= 0 and score <= 5) ->
          []

        cited == [] ->
          []

        true ->
          [
            Map.merge(r, %{
              "evidence_type" => strongest(cited),
              "evidence_ids" => Enum.map(cited, &Observation.ref/1),
              "score" => score * 1.0
            })
          ]
      end
    end)
    |> Enum.uniq_by(& &1["dimension"])
  end

  defp strongest(observations) do
    observations |> Enum.max_by(&@type_rank[&1.evidence_type]) |> Map.fetch!(:evidence_type)
  end

  @doc """
  Ratings computed from experimental observations of one segment (or of the
  whole study when the observation has no segment).
  """
  def experimental_ratings(observations) do
    exp = Enum.filter(observations, &(&1.evidence_type == "experimental"))

    latest = fn code ->
      exp |> Enum.filter(&(&1.signal_code == code)) |> Enum.max_by(& &1.id, fn -> nil end)
    end

    se = latest.("sean_ellis_very_disappointed_pct")
    ret = latest.("retention_pct")
    flat = latest.("retention_flattening")

    [
      se &&
        %{
          "dimension" => "sean_ellis",
          "score" => sean_ellis_score(se.value_num) * 1.0,
          "evidence_type" => "experimental",
          "evidence_ids" => [Observation.ref(se)],
          "rationale" => "#{se.value_num}% very disappointed"
        },
      ret &&
        %{
          "dimension" => "retention",
          "score" =>
            retention_score(ret.value_num, (flat && flat.value_num == 1.0) || false) * 1.0,
          "evidence_type" => "experimental",
          "evidence_ids" => Enum.map(Enum.reject([ret, flat], &is_nil/1), &Observation.ref/1),
          "rationale" =>
            "#{ret.value_num}% retained, #{if flat && flat.value_num == 1.0, do: "flattening", else: "still decaying"}"
        }
    ]
    |> Enum.reject(&is_nil/1)
  end

  @doc "Composite 0–100 over rated dimensions, or nil when nothing is rated."
  def composite([]), do: nil

  def composite(ratings) do
    {num, den} =
      Enum.reduce(ratings, {0.0, 0.0}, fn r, {n, d} ->
        w = @weights[r["dimension"]]
        {n + w * r["score"] / 5 * @multipliers[r["evidence_type"]], d + w}
      end)

    Float.round(num / den * 100, 1)
  end

  @doc """
  Verdict for one segment from its ratings and the Sean Ellis % (if any).
  Returns `{verdict, guard_note}`.
  """
  def verdict(ratings, sean_ellis_pct) do
    score = composite(ratings) || 0.0
    exp_dims = Enum.count(ratings, &(&1["evidence_type"] == "experimental"))
    retention = Enum.find(ratings, &(&1["dimension"] == "retention"))

    raw =
      cond do
        exp_dims >= 1 and is_number(sean_ellis_pct) and sean_ellis_pct >= 40 and
          retention != nil and retention["score"] >= 4 and score >= 70 ->
          "fit"

        exp_dims >= 2 and score >= 60 ->
          "approaching_fit"

        score >= 40 ->
          "promising"

        true ->
          "no_signal"
      end

    VerdictGuard.apply(raw, Enum.map(ratings, & &1["evidence_type"]))
  end

  @doc """
  Deterministic next move, following the `decision_frameworks` skill:

    1. strong experimental signal, or problem and willingness to pay both 4+ → `double_down`
    2. intense problem (4+) but weak competitive gap (≤ 2) → `reposition`
    3. weak problem (≤ 2) shown by voc or experimental evidence → `pivot`
       (never pivot on desk evidence alone)
    4. `promising` with experimental evidence that did not lift it further → `narrow`
    5. otherwise evidence is too thin to move: `double_down` on research and
       let the next experiment decide.
  """
  def next_move(verdict, ratings) do
    rating = fn dim -> Enum.find(ratings, &(&1["dimension"] == dim)) end
    score = fn dim -> (r = rating.(dim)) && r["score"] end
    problem = score.("problem_intensity")
    wtp = score.("willingness_to_pay")
    gap = score.("competitive_gap")
    exp_dims = Enum.count(ratings, &(&1["evidence_type"] == "experimental"))
    composite = composite(ratings) || 0.0

    cond do
      verdict in ["fit", "approaching_fit"] ->
        "double_down"

      composite >= 60 and exp_dims >= 2 ->
        "double_down"

      gte(problem, 4) and gte(wtp, 4) ->
        "double_down"

      gte(problem, 4) and gap != nil and gap <= 2 ->
        "reposition"

      problem != nil and problem <= 2 and rating.("problem_intensity")["evidence_type"] != "desk" ->
        "pivot"

      verdict == "promising" and exp_dims > 0 ->
        "narrow"

      true ->
        "double_down"
    end
  end

  defp gte(nil, _), do: false
  defp gte(v, min), do: v >= min

  @doc "Where the study goes after a verdict: re-segment, or design the next tests."
  def route(next_move) when next_move in ["pivot", "reposition"], do: "hypothesize"
  def route(_next_move), do: "design_tests"

  @doc """
  Full scorecard for one segment. `proposed` are the scorer agent's ratings;
  `observations` the segment's evidence (including study-wide rows).
  """
  def score_segment(proposed, observations) do
    model = normalize_ratings(proposed, observations)
    computed = experimental_ratings(observations)
    ratings = model ++ computed

    se_pct =
      observations
      |> Enum.filter(
        &(&1.evidence_type == "experimental" and
            &1.signal_code == "sean_ellis_very_disappointed_pct")
      )
      |> Enum.max_by(& &1.id, fn -> nil end)
      |> then(&(&1 && &1.value_num))

    {verdict, guard} = verdict(ratings, se_pct)

    %{
      "ratings" => Enum.sort_by(ratings, &(-@weights[&1["dimension"]])),
      "composite" => composite(ratings),
      "verdict" => verdict,
      "guard_note" => guard,
      "next_move" => next_move(verdict, ratings),
      "evidence_types" =>
        ratings |> Enum.map(& &1["evidence_type"]) |> Enum.uniq() |> Enum.sort(),
      "dropped" => length(proposed) - length(model)
    }
  end
end
