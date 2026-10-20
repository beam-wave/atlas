defmodule AtlasWeb.ExportController do
  @moduledoc """
  Downloads an artifact as Markdown. Approval-kind artifacts (surveys,
  interview guides, smoke tests, positioning) leave only once approved.
  """
  use AtlasWeb, :controller

  alias Atlas.Artifacts
  alias Atlas.Gates.Outbound

  def show(conn, %{"id" => id}) do
    artifact = Artifacts.get!(id)

    case Outbound.authorize(artifact) do
      :ok ->
        conn
        |> put_resp_content_type("text/markdown")
        |> put_resp_header(
          "content-disposition",
          ~s(attachment; filename="#{artifact.kind}-#{artifact.id}.md")
        )
        |> send_resp(200, to_markdown(artifact))

      {:error, :not_approved} ->
        conn
        |> put_status(:forbidden)
        |> text("This #{artifact.kind} has not been approved, so it cannot leave Atlas yet.")
    end
  end

  @doc false
  def to_markdown(artifact) do
    "# #{artifact.kind |> String.replace("_", " ") |> String.capitalize()}\n\n" <>
      md(artifact.body, 2)
  end

  defp md(map, level) when is_map(map) do
    map
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map_join("\n", fn {k, v} ->
      heading =
        String.duplicate("#", min(level, 6)) <>
          " " <> (k |> to_string() |> String.replace("_", " ") |> String.capitalize())

      heading <> "\n\n" <> md(v, level + 1)
    end)
  end

  defp md(list, _level) when is_list(list) do
    Enum.map_join(list, "", fn
      v when is_map(v) ->
        "- " <>
          (v
           |> Enum.sort_by(&elem(&1, 0))
           |> Enum.map_join("; ", fn {k, x} -> "#{k}: #{inline(x)}" end)) <> "\n"

      v ->
        "- #{inline(v)}\n"
    end) <> "\n"
  end

  defp md(nil, _), do: "—\n\n"
  defp md(v, _), do: "#{v}\n\n"

  defp inline(v) when is_binary(v), do: v
  defp inline(v) when is_list(v), do: Enum.map_join(v, ", ", &inline/1)
  defp inline(v) when is_map(v), do: Jason.encode!(v)
  defp inline(nil), do: "—"
  defp inline(v), do: to_string(v)
end
