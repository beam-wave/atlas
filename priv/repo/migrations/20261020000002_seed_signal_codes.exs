defmodule Atlas.Repo.Migrations.SeedSignalCodes do
  use Ecto.Migration

  # The vocabulary lives in Atlas.Evidence.SignalCodes. Adding a code means
  # editing that module and adding a migration that calls sync!/1 again.
  def up do
    flush()
    Atlas.Evidence.SignalCodes.sync!(repo())
  end

  def down do
    execute "DELETE FROM signal_codes"
  end
end
