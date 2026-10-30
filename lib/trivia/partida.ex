
defmodule Trivia.Partida do
  use GenServer

  def start_link(opciones) do
    GenServer.start_link(__MODULE__, opciones)
  end

  def child_spec(opciones) do
    %{
      id: {__MODULE__, Keyword.fetch!(opciones, :id)},
      start: {__MODULE__, :start_link, [opciones]},
      restart: :transient,
      type: :worker
    }
  end

  @impl true
  def init(opciones) do
    id = Keyword.fetch!(opciones, :id)
    creador = Keyword.fetch!(opciones, :creador)
    cliente = Keyword.fetch!(opciones, :cliente)

    gestor =
      Keyword.get(
        opciones,
        :gestor,
        Trivia.GestorPartidas
      )

    estado = %{
      id: id,
      creador: creador,
      tema: Keyword.fetch!(opciones, :tema),
      numero_preguntas:
        Keyword.fetch!(opciones, :numero_preguntas),
      tiempo_por_pregunta:
        Keyword.fetch!(opciones, :tiempo_por_pregunta),
      cliente: cliente,
      gestor: gestor,
      jugadores: [],
      estado: :esperando
    }

    GenServer.cast(
      gestor,
      {:registrar_partida, id, self(), creador, cliente}
    )

    {:ok, estado}
  end
end
