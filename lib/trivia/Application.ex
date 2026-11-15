defmodule Trivia.Application do
  use Application

  @impl true
  def start(_tipo, _argumentos) do
    rol = System.get_env("TRIVIA_ROLE", "cliente")

    hijos =
      case rol do
        "servidor" ->
          IO.puts("Iniciando servidor central de Trivia...")

          [
            {Trivia.Almacen, []},
            {Trivia.GestorJugadores, [almacen: Trivia.Almacen]},
            {Trivia.SupervisorPartidas, []},
            {Trivia.GestorPartidas,
             [
               supervisor: Trivia.SupervisorPartidas,
               almacen: Trivia.Almacen
             ]},
            {Trivia.Servidor,
             [
               gestor_jugadores: Trivia.GestorJugadores,
               gestor_partidas: Trivia.GestorPartidas
             ]}
          ]

        "cliente" ->
          IO.puts("Nodo cliente preparado.")
          []

        otro ->
          raise "Rol de nodo desconocido: #{otro}"
      end

    Supervisor.start_link(
      hijos,
      strategy: :one_for_one,
      name: Trivia.Supervisor
    )
  end
end
