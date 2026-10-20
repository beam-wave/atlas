defmodule Atlas.Repo.Migrations.CreateCoreTables do
  use Ecto.Migration

  def change do
    create table(:products) do
      add :name, :string, null: false
      add :description, :text, null: false
      add :url, :string
      add :price, :string
      add :owner, :string
      timestamps(type: :utc_datetime)
    end

    create table(:studies) do
      add :product_id, references(:products, on_delete: :delete_all), null: false
      add :state, :string, null: false, default: "intake"
      add :loop_number, :integer, null: false, default: 1
      add :budget, :integer, null: false, default: 150
      add :calls_used, :integer, null: false, default: 0
      add :verdict, :string
      add :next_move, :string
      add :adapter, :string
      add :last_error, :text
      add :failed_state, :string
      timestamps(type: :utc_datetime)
    end

    create index(:studies, [:product_id])
    create index(:studies, [:state])

    create table(:segments) do
      add :study_id, references(:studies, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :criteria, :map, null: false, default: %{}
      add :job_to_be_done, :map, null: false, default: %{}
      add :rationale, :text
      add :status, :string, null: false, default: "proposed"
      add :rank, :integer
      add :loop_number, :integer, null: false, default: 1
      timestamps(type: :utc_datetime)
    end

    create index(:segments, [:study_id, :status])

    create table(:hypotheses) do
      add :study_id, references(:studies, on_delete: :delete_all), null: false
      add :segment_id, references(:segments, on_delete: :delete_all), null: false
      add :statement, :text, null: false
      add :falsified_if, :text, null: false
      add :status, :string, null: false, default: "open"
      timestamps(type: :utc_datetime)
    end

    create index(:hypotheses, [:segment_id])

    # Governed vocabulary: observations reference it through a foreign key,
    # so an unknown signal code fails at the database, not silently.
    create table(:signal_codes, primary_key: false) do
      add :code, :string, primary_key: true
      add :dimension, :string, null: false
      add :description, :string, null: false
    end

    create table(:experiments) do
      add :study_id, references(:studies, on_delete: :delete_all), null: false
      add :hypothesis_id, references(:hypotheses, on_delete: :nilify_all)
      add :segment_id, references(:segments, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :title, :string, null: false
      add :design, :map, null: false, default: %{}
      add :thresholds, :map, null: false, default: %{}
      add :locked_at, :utc_datetime
      add :status, :string, null: false, default: "draft"
      add :outcome, :string
      add :loop_number, :integer, null: false, default: 1
      timestamps(type: :utc_datetime)
    end

    create index(:experiments, [:study_id, :status])

    create table(:experiment_results) do
      add :experiment_id, references(:experiments, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :raw_upload_ref, :string
      add :summary, :map, null: false, default: %{}
      add :ingested_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:experiment_results, [:experiment_id])

    create table(:observations) do
      add :study_id, references(:studies, on_delete: :delete_all), null: false
      add :segment_id, references(:segments, on_delete: :delete_all)
      add :experiment_id, references(:experiments, on_delete: :nilify_all)

      add :signal_code,
          references(:signal_codes, column: :code, type: :string, on_delete: :restrict),
          null: false

      add :value_num, :float
      add :value_text, :text
      add :evidence_type, :string, null: false
      add :confidence, :float, null: false
      add :source_url, :string
      add :source_note, :string
      add :observed_at, :utc_datetime, null: false
      add :run_id, :string
      add :agent, :string
      add :loop_number, :integer, null: false, default: 1
      timestamps(type: :utc_datetime)
    end

    create index(:observations, [:study_id, :segment_id])
    create index(:observations, [:study_id, :evidence_type])

    create table(:artifacts) do
      add :study_id, references(:studies, on_delete: :delete_all), null: false
      add :segment_id, references(:segments, on_delete: :nilify_all)
      add :experiment_id, references(:experiments, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :agent, :string
      add :loop_number, :integer, null: false, default: 1
      add :body, :map, null: false, default: %{}
      add :review_verdict, :string, null: false, default: "pending"
      add :review_notes, :map, null: false, default: %{}
      add :status, :string, null: false, default: "draft"
      add :skill_versions, :map, null: false, default: %{}
      timestamps(type: :utc_datetime)
    end

    create index(:artifacts, [:study_id, :kind])
    create index(:artifacts, [:status])

    create table(:approvals) do
      add :artifact_id, references(:artifacts, on_delete: :delete_all), null: false
      add :decision, :string, null: false
      add :note, :text
      add :decided_by, :string, null: false
      add :decided_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:approvals, [:artifact_id])

    create table(:llm_calls) do
      add :study_id, references(:studies, on_delete: :delete_all)
      add :agent, :string
      add :adapter, :string, null: false
      add :model, :string
      add :tokens_in, :integer
      add :tokens_out, :integer
      add :cost_usd, :float
      add :duration_ms, :integer, null: false
      add :outcome, :string, null: false
      add :error, :text
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:llm_calls, [:study_id])

    create table(:audit_events) do
      add :study_id, references(:studies, on_delete: :delete_all)
      add :kind, :string, null: false
      add :payload, :map, null: false, default: %{}
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_events, [:study_id, :kind])

    create table(:settings, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :map, null: false
      timestamps(type: :utc_datetime)
    end
  end
end
