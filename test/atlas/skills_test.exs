defmodule Atlas.SkillsTest do
  use ExUnit.Case, async: false

  alias Atlas.Skills.{Library, Skill}

  @valid """
  ---
  name: demo_skill
  title: Demo
  description: A demo skill
  version: 2
  ---

  # Demo

  ## When to use
  Always.
  ## Steps
  1. Do it.
  ### Banned phrases
  - synergy
  - * bad bullet
  ## Output format
  JSON.
  ## Worked example
  Example.
  ## Common mistakes
  None.
  """

  describe "Skill.parse/2" do
    test "parses frontmatter, body and a stable hash" do
      assert {:ok, %Skill{} = s} = Skill.parse(@valid, "/x/demo_skill.md")
      assert s.name == "demo_skill"
      assert s.title == "Demo"
      assert s.version == 2
      assert s.body =~ "## Steps"
      assert byte_size(s.hash) == 12
      assert {:ok, %{hash: same}} = Skill.parse(@valid)
      assert same == s.hash
    end

    test "reports what is wrong" do
      assert {:error, ["file must start with a --- frontmatter block"]} =
               Skill.parse("# no frontmatter")

      assert {:error, ["frontmatter is not closed with ---"]} = Skill.parse("---\nname: x\n")

      broken = String.replace(@valid, "## Worked example", "## Example")
      assert {:error, [msg]} = Skill.parse(broken)
      assert msg =~ "missing sections: Worked example"

      assert {:error, errors} =
               Skill.parse(String.replace(@valid, "version: 2", "version: two"), "/x/other.md")

      assert "version must be an integer" in errors
      assert "name must match the file name" in errors
    end

    test "bullets_under/2 reads a list under a heading" do
      {:ok, s} = Skill.parse(@valid)
      assert Skill.bullets_under(s, "Banned phrases") == ["synergy", "* bad bullet"]
      assert Skill.bullets_under(s, "Missing") == []
    end
  end

  describe "the shipped skills library" do
    test "tests run against a scratch copy, never priv/skills" do
      assert Library.dir() =~ "tmp/test_skills"
    end

    test "every skill file is valid and every mapped skill exists" do
      assert Library.errors() == %{}
      names = Enum.map(Library.all(), & &1.name)
      assert length(names) == 18

      for {agent, skills} <- Library.skill_map(), skill <- skills do
        assert skill in names, "#{agent} maps unknown skill #{skill}"
      end
    end

    test "every agent has a skill map entry" do
      agents = [
        Atlas.Agents.Intake,
        Atlas.Agents.SegmentStrategist,
        Atlas.Agents.MarketResearcher,
        Atlas.Agents.CompetitorAnalyst,
        Atlas.Agents.VoCMiner,
        Atlas.Agents.PositioningWriter,
        Atlas.Agents.ExperimentDesigner,
        Atlas.Agents.EvidenceSynthesizer,
        Atlas.Agents.Skeptic,
        Atlas.Agents.PMFScorer,
        Atlas.Agents.Analyst
      ]

      for agent <- agents do
        assert Map.has_key?(Library.skill_map(), agent.name()),
               "no skill_map entry for #{agent.name()}"

        assert Library.for_agent(agent.name()) != []
      end
    end
  end

  describe "write/2 and hot reload" do
    setup do
      {:ok, skill} = Library.get("clear_writing")
      original = File.read!(skill.path)

      on_exit(fn ->
        File.write!(skill.path, original)
        Library.reload()
      end)

      %{skill: skill, original: original}
    end

    test "write validates before saving", %{original: original} do
      assert {:error, [_ | _]} = Library.write("clear_writing", "not a skill")
      assert {:error, :not_found} = Library.write("nope", original)

      updated = String.replace(original, "version: 1", "version: 9")
      assert :ok = Library.write("clear_writing", updated)
      assert {:ok, %{version: 9}} = Library.get("clear_writing")
    end

    test "the poll notices edits made in an editor", %{skill: skill, original: original} do
      # mtime resolution is one second; make sure the change is visible.
      Process.sleep(1100)
      File.write!(skill.path, String.replace(original, "version: 1", "version: 7"))
      send(Library, :poll)
      _ = Library.dir()
      assert {:ok, %{version: 7}} = Library.get("clear_writing")
    end

    test "reload picks up edits made on disk and keeps the last good version of a broken file", %{
      skill: skill,
      original: original
    } do
      File.write!(skill.path, String.replace(original, "version: 1", "version: 5"))
      :ok = Library.reload()
      assert {:ok, %{version: 5}} = Library.get("clear_writing")

      File.write!(skill.path, "broken")
      :ok = Library.reload()
      assert {:ok, %{version: 5}} = Library.get("clear_writing")
      assert Map.has_key?(Library.errors(), "core/clear_writing.md")
    end
  end
end
