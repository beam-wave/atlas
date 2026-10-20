System.delete_env("ATLAS_LLM_ADAPTER")
File.rm_rf!(Path.expand("../tmp/test_uploads", __DIR__))

# Tests edit skills; give them a scratch copy so priv/skills is never touched.
skills_copy = Path.expand("../tmp/test_skills", __DIR__)
File.rm_rf!(skills_copy)
File.mkdir_p!(skills_copy)
File.cp_r!(Path.expand("../priv/skills", __DIR__), skills_copy)
Application.put_env(:atlas, :skills_dir, skills_copy)
:ok = Supervisor.terminate_child(Atlas.Supervisor, Atlas.Skills.Library)
{:ok, _} = Supervisor.restart_child(Atlas.Supervisor, Atlas.Skills.Library)

ExUnit.start(exclude: [:live])
Ecto.Adapters.SQL.Sandbox.mode(Atlas.Repo, :manual)
