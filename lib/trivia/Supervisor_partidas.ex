
defmodule Trivia.SupervisorPartidas do
  use DynamicSupervisor

  def start_link(opciones \\ []) do
    nombre = Keyword.get(opciones, :name, __MODULE__)

    DynamicSupervisor.start_link(
      __MODULE__,
      :ok,
      name: nombre
    )
  end

  def iniciar_partida(opciones, supervisor \\ __MODULE__) do
    DynamicSupervisor.start_child(
      supervisor,
      {Trivia.Partida, opciones}
    )
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
