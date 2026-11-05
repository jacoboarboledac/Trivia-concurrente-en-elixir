
defmodule Trivia.Servidor do
  use GenServer

  # -------------------------
  # INICIO DEL SERVIDOR
  # -------------------------

  def start_link(opciones \\ []) do
    nombre = Keyword.get(opciones, :name, __MODULE__)

    GenServer.start_link(
      __MODULE__,
      opciones,
      name: nombre
    )
  end

  @impl true
  def init(opciones) do
    gestor_jugadores =
      Keyword.get(
        opciones,
        :gestor_jugadores,
        Trivia.GestorJugadores
      )

    {:ok,
     %{
       gestor_jugadores: gestor_jugadores
     }}
  end

  # -------------------------
  # PETICIONES DEL CLIENTE
  # -------------------------

  def connect(usuario, clave, servidor \\ __MODULE__) do
    GenServer.call(
      servidor,
      {:connect, usuario, clave}
    )
  end

  # -------------------------
  # PROCESAMIENTO DE PETICIONES
  # -------------------------

  @impl true
  def handle_call(
        {:connect, usuario, clave},
        {pid_cliente, _referencia},
        estado
      ) do
    respuesta =
      Trivia.GestorJugadores.connect(
        usuario,
        clave,
        pid_cliente,
        estado.gestor_jugadores
      )

    {:reply, respuesta, estado}
  end
end
