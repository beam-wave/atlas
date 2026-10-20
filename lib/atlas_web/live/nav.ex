defmodule AtlasWeb.Nav do
  @moduledoc """
  `on_mount` hook for every page: keeps the approval-queue count and the kill
  switch in the nav current via PubSub.
  """
  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      Atlas.Artifacts.subscribe_queue()
      Atlas.Settings.subscribe()
    end

    socket =
      socket
      |> assign(
        pending_count: Atlas.Artifacts.pending_count(),
        kill_switch: Atlas.Settings.kill_switch?()
      )
      |> attach_hook(:nav, :handle_info, &handle_info/2)

    {:cont, socket}
  end

  defp handle_info(:approvals_changed, socket) do
    {:cont, assign(socket, pending_count: Atlas.Artifacts.pending_count())}
  end

  defp handle_info({:setting, "kill_switch", value}, socket) do
    {:cont, assign(socket, kill_switch: value == true)}
  end

  defp handle_info(_msg, socket), do: {:cont, socket}
end
