defmodule Atlas.Experiments.Evaluator do
  @moduledoc """
  Deterministic comparison of measured metrics against locked thresholds.

  * every criterion met → `"passed"`
  * any criterion missed → `"failed"`
  * a metric is missing, or the sample is below `min_sample` → `"inconclusive"`
  """

  @spec evaluate(map(), map()) :: {String.t(), [map()]}
  def evaluate(thresholds, metrics) do
    criteria = thresholds["criteria"] || []
    min_sample = thresholds["min_sample"]
    sample = metrics["sample_size"]

    checks = Enum.map(criteria, &check(&1, metrics))

    outcome =
      cond do
        is_number(min_sample) and (not is_number(sample) or sample < min_sample) -> "inconclusive"
        Enum.any?(checks, &(&1["result"] == "missing")) -> "inconclusive"
        Enum.all?(checks, &(&1["result"] == "met")) -> "passed"
        true -> "failed"
      end

    {outcome, checks}
  end

  defp check(%{"metric" => metric, "operator" => op, "value" => target}, metrics) do
    case Map.fetch(metrics, metric) do
      {:ok, actual} when is_number(actual) ->
        %{
          "metric" => metric,
          "operator" => op,
          "target" => target,
          "actual" => actual,
          "result" => if(compare(actual, op, target), do: "met", else: "missed")
        }

      _ ->
        %{"metric" => metric, "operator" => op, "target" => target, "result" => "missing"}
    end
  end

  defp compare(a, ">=", b), do: a >= b
  defp compare(a, ">", b), do: a > b
  defp compare(a, "<=", b), do: a <= b
  defp compare(a, "<", b), do: a < b
  defp compare(a, "==", b), do: a == b
end
