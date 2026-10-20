defmodule Atlas.Ingest do
  @moduledoc """
  Turns uploaded files into deterministic metrics. Arithmetic happens here, in
  code; models only interpret open text later.

  `parse/2` returns `{:ok, summary, body_to_store}`. Transcripts are stored
  redacted, so personal data never reaches disk or a model.
  """
  alias Atlas.Ingest.{Analytics, PII, Retention, Survey}

  def parse(kind, path) do
    with {:ok, body} <- read(path) do
      case kind do
        "survey_csv" -> wrap(Survey.parse(body), body)
        "analytics_csv" -> wrap(Analytics.parse(body), body)
        "retention_csv" -> wrap(Retention.parse(body), body)
        "transcript" -> transcript(body)
        other -> {:error, {:unknown_result_kind, other}}
      end
    end
  end

  defp read(path) do
    case File.read(path) do
      {:ok, body} -> if String.valid?(body), do: {:ok, body}, else: {:error, :not_utf8_text}
      {:error, reason} -> {:error, {:unreadable_upload, reason}}
    end
  end

  defp wrap({:ok, summary}, body), do: {:ok, summary, body}
  defp wrap(error, _), do: error

  defp transcript(body) do
    {redacted, counts} = PII.redact(body)
    words = redacted |> String.split(~r/\s+/, trim: true) |> length()

    if words < 20 do
      {:error, :transcript_too_short}
    else
      {:ok, %{"metrics" => %{"words" => words}, "redactions" => counts}, redacted}
    end
  end

  @doc "Parses CSV text into a list of maps keyed by the header row."
  def csv_rows(body) do
    body = String.replace(body, "\r\n", "\n")

    case NimbleCSV.RFC4180.parse_string(body, skip_headers: false) do
      [header | rows] ->
        header = Enum.map(header, &String.trim/1)

        rows =
          rows
          |> Enum.reject(fn row -> Enum.all?(row, &(String.trim(&1) == "")) end)
          |> Enum.map(fn row -> header |> Enum.zip(Enum.map(row, &String.trim/1)) |> Map.new() end)

        {:ok, header, rows}

      [] ->
        {:error, :empty_csv}
    end
  rescue
    e in NimbleCSV.ParseError -> {:error, {:bad_csv, Exception.message(e)}}
  end

  def to_number(nil), do: nil

  def to_number(s) when is_binary(s) do
    s = s |> String.replace(~r/[,\s$₹€£%]/u, "")

    case Float.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end

  def to_number(n) when is_number(n), do: n * 1.0

  def pct(_num, 0), do: nil
  def pct(num, den), do: Float.round(num * 100 / den, 1)

  def median([]), do: nil

  def median(list) do
    sorted = Enum.sort(list)
    n = length(sorted)
    mid = div(n, 2)

    if rem(n, 2) == 1,
      do: Enum.at(sorted, mid),
      else: (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
  end
end

defmodule Atlas.Ingest.PII do
  @moduledoc "Redacts emails, phone numbers, URLs with query strings and card-like numbers."

  @patterns [
    {"email", ~r/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/},
    {"card", ~r/\b(?:\d[ -]?){13,19}\b/},
    {"phone", ~r/(?<![\w])\+?\d[\d\s().-]{8,}\d/},
    {"id_number", ~r/\b[A-Z]{5}\d{4}[A-Z]\b/}
  ]

  @spec redact(String.t()) :: {String.t(), map()}
  def redact(text) do
    Enum.reduce(@patterns, {text, %{}}, fn {label, regex}, {acc, counts} ->
      n = regex |> Regex.scan(acc) |> length()

      {Regex.replace(regex, acc, "[#{String.upcase(label)}]"),
       if(n > 0, do: Map.put(counts, label, n), else: counts)}
    end)
  end
end

defmodule Atlas.Ingest.Survey do
  @moduledoc """
  Survey CSV export (one row per respondent, one column per question).

  Detects the Sean Ellis question ("How would you feel if you could no longer
  use…") and Van Westendorp price columns by header text, and keeps open-text
  answers for the Evidence Synthesizer.
  """
  import Atlas.Ingest, only: [csv_rows: 1, to_number: 1, pct: 2, median: 1]

  @sean_ellis ~r/no longer use|how would you feel if you could no longer/i
  @vw [
    {"vw_too_cheap", ~r/too cheap|so (inexpensive|cheap)|question the quality/i},
    {"vw_too_expensive", ~r/too expensive|so expensive that you would not/i},
    {"vw_bargain", ~r/bargain|good value|great buy/i},
    {"vw_expensive", ~r/getting expensive|(starting|begin) to (seem|be) expensive/i}
  ]

  def parse(body) do
    with {:ok, header, rows} <- csv_rows(body) do
      if rows == [] do
        {:error, :no_responses}
      else
        {:ok, build(header, rows)}
      end
    end
  end

  defp build(header, rows) do
    metrics = %{"responses" => length(rows), "sample_size" => length(rows)}

    {metrics, used} = sean_ellis(header, rows, metrics)
    {metrics, used} = van_westendorp(header, rows, metrics, used)

    open_text =
      for col <- header, col not in used, open_text_column?(rows, col) do
        %{
          "question" => col,
          "answers" =>
            rows |> Enum.map(& &1[col]) |> Enum.reject(&(&1 in [nil, ""])) |> Enum.take(200)
        }
      end

    %{"metrics" => metrics, "open_text" => open_text, "columns" => header}
  end

  defp sean_ellis(header, rows, metrics) do
    case Enum.find(header, &Regex.match?(@sean_ellis, &1)) do
      nil ->
        {metrics, []}

      col ->
        answers = rows |> Enum.map(&String.downcase(&1[col] || "")) |> Enum.reject(&(&1 == ""))
        very = Enum.count(answers, &String.contains?(&1, "very"))
        somewhat = Enum.count(answers, &String.contains?(&1, "somewhat"))
        n = length(answers)

        {Map.merge(metrics, %{
           "sean_ellis_responses" => n,
           "sean_ellis_very_disappointed_pct" => pct(very, n),
           "sean_ellis_somewhat_disappointed_pct" => pct(somewhat, n),
           "sample_size" => n
         }), [col]}
    end
  end

  defp van_westendorp(header, rows, metrics, used) do
    Enum.reduce(@vw, {metrics, used}, fn {key, regex}, {m, u} ->
      case Enum.find(header, &(Regex.match?(regex, &1) and &1 not in u)) do
        nil ->
          {m, u}

        col ->
          values = rows |> Enum.map(&to_number(&1[col])) |> Enum.reject(&is_nil/1)
          {Map.put(m, key, median(values)), [col | u]}
      end
    end)
  end

  defp open_text_column?(rows, col) do
    values = rows |> Enum.map(& &1[col]) |> Enum.reject(&(&1 in [nil, ""]))
    distinct = values |> Enum.uniq() |> length()

    avg_len =
      if values == [], do: 0, else: Enum.sum(Enum.map(values, &String.length/1)) / length(values)

    values != [] and distinct > 5 and avg_len > 15
  end
end

defmodule Atlas.Ingest.Analytics do
  @moduledoc """
  Smoke-test analytics export. Accepts either a `metric,value` table or an
  event log with an `event` column (`visit`/`pageview`, `signup`,
  `preorder`), optionally with a `channel` and `cost` column.
  """
  import Atlas.Ingest, only: [csv_rows: 1, to_number: 1, pct: 2]

  def parse(body) do
    with {:ok, header, rows} <- csv_rows(body) do
      lower = Enum.map(header, &String.downcase/1)

      cond do
        "metric" in lower and "value" in lower ->
          {:ok, from_table(header, rows)}

        "event" in lower ->
          {:ok, from_events(header, rows)}

        true ->
          {:error,
           {:unrecognised_analytics_csv, "expected metric,value columns or an event column"}}
      end
    end
  end

  defp col(header, name), do: Enum.find(header, &(String.downcase(&1) == name))

  defp from_table(header, rows) do
    m = col(header, "metric")
    v = col(header, "value")

    raw =
      for row <- rows, n = to_number(row[v]), into: %{} do
        {row[m] |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_"), n}
      end

    %{"metrics" => derive(raw)}
  end

  defp from_events(header, rows) do
    e = col(header, "event")
    count = fn names -> Enum.count(rows, &(String.downcase(&1[e] || "") in names)) end

    raw = %{
      "visits" => count.(["visit", "pageview", "page_view", "view"]),
      "signups" => count.(["signup", "sign_up", "lead", "waitlist"]),
      "preorders" => count.(["preorder", "pre_order", "deposit", "purchase"])
    }

    raw =
      case col(header, "cost") do
        nil -> raw
        c -> Map.put(raw, "spend", rows |> Enum.map(&(to_number(&1[c]) || 0.0)) |> Enum.sum())
      end

    %{"metrics" => derive(raw)}
  end

  defp derive(raw) do
    visits = raw["visits"]
    signups = raw["signups"]

    raw
    |> Map.put("sample_size", visits)
    |> then(fn m ->
      if visits && signups,
        do: Map.put(m, "signup_conversion_pct", pct(signups, trunc(visits))),
        else: m
    end)
    |> then(fn m ->
      if m["spend"] && signups && signups > 0,
        do: Map.put(m, "cost_per_signup", Float.round(m["spend"] / signups, 2)),
        else: m
    end)
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
  end
end

defmodule Atlas.Ingest.Retention do
  @moduledoc """
  Cohort retention CSV with columns `cohort`, `period` and either
  `retained_pct` or (`active`, `cohort_size`). A curve "flattens" when the
  average period-over-period drop over the last third of periods is under
  2 percentage points while retention is still above 5%.
  """
  import Atlas.Ingest, only: [csv_rows: 1, to_number: 1]

  def parse(body) do
    with {:ok, header, rows} <- csv_rows(body),
         :ok <- require_cols(header) do
      points =
        rows
        |> Enum.map(&point/1)
        |> Enum.reject(&is_nil/1)

      if points == [] do
        {:error, :no_retention_points}
      else
        {:ok, summarise(points)}
      end
    end
  end

  defp require_cols(header) do
    h = Enum.map(header, &String.downcase/1)

    if "period" in h and ("retained_pct" in h or ("active" in h and "cohort_size" in h)),
      do: :ok,
      else:
        {:error,
         {:unrecognised_retention_csv, "need period plus retained_pct, or active and cohort_size"}}
  end

  defp point(row) do
    row = Map.new(row, fn {k, v} -> {String.downcase(k), v} end)
    period = to_number(row["period"])

    pct =
      case to_number(row["retained_pct"]) do
        nil ->
          active = to_number(row["active"])
          size = to_number(row["cohort_size"])
          if active && size && size > 0, do: active * 100 / size

        p ->
          p
      end

    if period && pct, do: {trunc(period), pct}
  end

  defp summarise(points) do
    curve =
      points
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn {p, vals} -> {p, Float.round(Enum.sum(vals) / length(vals), 1)} end)
      |> Enum.sort()

    {_, final} = List.last(curve)
    tail = Enum.take(curve, -max(div(length(curve), 3), 2))

    drops =
      tail
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [{_, a}, {_, b}] -> a - b end)

    avg_drop = if drops == [], do: nil, else: Enum.sum(drops) / length(drops)
    flattening = length(curve) >= 3 and avg_drop != nil and avg_drop < 2.0 and final > 5.0

    %{
      "metrics" => %{
        "retention_final_pct" => final,
        "retention_periods" => length(curve),
        "retention_flattening" => if(flattening, do: 1, else: 0),
        "sample_size" => length(points)
      },
      "curve" => Enum.map(curve, fn {p, v} -> %{"period" => p, "retained_pct" => v} end)
    }
  end
end
