defmodule Atlas.Studies.Product do
  @moduledoc "The thing being evaluated for product-market fit."
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :name, :string
    field :description, :string
    field :url, :string
    field :price, :string
    field :owner, :string

    has_many :studies, Atlas.Studies.Study
    timestamps(type: :utc_datetime)
  end

  def changeset(product, attrs) do
    product
    |> cast(attrs, [:name, :description, :url, :price, :owner])
    |> validate_required([:name, :description])
    |> validate_length(:name, max: 200)
    |> validate_length(:description, min: 10, max: 20_000)
    |> validate_format(:url, ~r{^https?://}, message: "must start with http:// or https://")
  end
end
