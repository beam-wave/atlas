defmodule Atlas.Skills.Skill do
  @moduledoc """
  A Markdown skill: frontmatter (`name`, `title`, `description`, `version`)
  and a body with five required sections.

  `hash` is a short content hash; it is stored with every artifact so scores
  from different loops can be traced to the exact skill text that produced
  them.
  """
  defstruct [:name, :title, :description, :version, :body, :path, :hash, :mtime, :group]

  @required_sections [
    "When to use",
    "Steps",
    "Output format",
    "Worked example",
    "Common mistakes"
  ]

  def required_sections, do: @required_sections

  @doc "Parses a skill file's content. Returns `{:ok, skill}` or `{:error, [reason]}`."
  def parse(content, path \\ nil) do
    with {:ok, meta, body} <- split_frontmatter(content),
         :ok <- validate(meta, body, path) do
      {:ok,
       %__MODULE__{
         name: meta["name"],
         title: meta["title"] || meta["name"],
         description: meta["description"] || "",
         version: parse_version(meta["version"]),
         body: String.trim(body),
         path: path,
         hash: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower) |> binary_part(0, 12)
       }}
    end
  end

  defp split_frontmatter(content) do
    case String.split(content, ~r/\r?\n/, parts: 2) do
      ["---", rest] ->
        case String.split(rest, ~r/\r?\n---\s*(\r?\n|$)/, parts: 2) do
          [front, body] -> {:ok, parse_front(front), body}
          _ -> {:error, ["frontmatter is not closed with ---"]}
        end

      _ ->
        {:error, ["file must start with a --- frontmatter block"]}
    end
  end

  defp parse_front(front) do
    front
    |> String.split(~r/\r?\n/, trim: true)
    |> Enum.flat_map(fn line ->
      case String.split(line, ":", parts: 2) do
        [k, v] -> [{String.trim(k), String.trim(v)}]
        _ -> []
      end
    end)
    |> Map.new()
  end

  defp validate(meta, body, path) do
    errors =
      []
      |> check(
        is_binary(meta["name"]) and meta["name"] =~ ~r/^[a-z0-9_]+$/,
        "name must be snake_case"
      )
      |> check(
        path == nil or meta["name"] == Path.basename(path, ".md"),
        "name must match the file name"
      )
      |> check(parse_version(meta["version"]) != nil, "version must be an integer")
      |> then(fn errs ->
        missing = Enum.reject(@required_sections, &String.contains?(body, "## " <> &1))
        if missing == [], do: errs, else: ["missing sections: #{Enum.join(missing, ", ")}" | errs]
      end)

    if errors == [], do: :ok, else: {:error, Enum.reverse(errors)}
  end

  defp check(errors, true, _msg), do: errors
  defp check(errors, false, msg), do: [msg | errors]

  defp parse_version(nil), do: nil

  defp parse_version(v) do
    case Integer.parse(to_string(v)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  @doc "Bullet items under a `### heading` in the body (used for banned phrases)."
  def bullets_under(%__MODULE__{body: body}, heading) do
    case String.split(body, "### " <> heading, parts: 2) do
      [_, rest] ->
        rest
        |> String.split(~r/\n#+ /, parts: 2)
        |> hd()
        |> String.split("\n")
        |> Enum.flat_map(fn line ->
          case Regex.run(~r/^\s*[-*]\s+(.+?)\s*$/, line) do
            [_, item] -> [item]
            nil -> []
          end
        end)

      _ ->
        []
    end
  end
end
