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

    gestor_partidas =
      Keyword.get(
        opciones,
        :gestor_partidas,
        Trivia.GestorPartidas
      )

    {:ok,
     %{
       gestor_jugadores: gestor_jugadores,
       gestor_partidas: gestor_partidas
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

  # Consultar puntaje del jugador conectado
  def score(servidor \\ __MODULE__) do
    GenServer.call(servidor, :score)
  end

  # Consultar ranking global o por tema
  def ranking(tema \\ nil, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:ranking, tema})
  end

  # CREAR PARTIDA

  def create_game(
        tema,
        cantidad,
        tiempo,
        servidor \\ __MODULE__
      ) do
    GenServer.call(
      servidor,
      {:create_game, tema, cantidad, tiempo}
    )
  end

  # AGREGAR BOT

  def add_bot(dificultad, servidor \\ __MODULE__) do
    GenServer.call(
      servidor,
      {:add_bot, dificultad}
    )
  end

  # INICIAR PARTIDA

  def start_game(servidor \\ __MODULE__) do
    GenServer.call(servidor, :start_game)
  end

  # RESPONDER PREGUNTA

  def answer(letra, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:answer, letra})
  end

  # ABANDONAR PARTIDA

  def leave_game(servidor \\ __MODULE__) do
    GenServer.call(servidor, :leave_game)
  end

  # CERRAR SESIÓN

  def disconnect(servidor \\ __MODULE__) do
    GenServer.call(servidor, :disconnect)
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

  # CONSULTAR PUNTAJE

  @impl true
  def handle_call(
        :score,
        {pid_cliente, _referencia},
        estado
      ) do
    respuesta =
      Trivia.GestorJugadores.score(
        pid_cliente,
        estado.gestor_jugadores
      )

    {:reply, respuesta, estado}
  end

  # CONSULTAR RANKING

  @impl true
  def handle_call(
        {:ranking, tema},
        {pid_cliente, _referencia},
        estado
      ) do
    respuesta =
      Trivia.GestorJugadores.ranking(
        tema,
        pid_cliente,
        estado.gestor_jugadores
      )

    {:reply, respuesta, estado}
  end

  # CREAR PARTIDA

  @impl true
  def handle_call(
        {:create_game, tema, cantidad, tiempo},
        {pid_cliente, _referencia},
        estado
      ) do
    resultado =
      with {:ok, usuario} <-
             Trivia.GestorJugadores.usuario_por_pid(
               pid_cliente,
               estado.gestor_jugadores
             ),
           {:ok, nivel} <-
             Trivia.GestorPartidas.preparar_creacion(
               usuario,
               tema,
               cantidad,
               tiempo,
               estado.gestor_partidas
             ),
           {:ok, id, _pid} <-
             Trivia.GestorPartidas.crear_partida(
               [
                 creador: usuario,
                 cliente: pid_cliente,
                 tema: tema,
                 numero_preguntas: cantidad,
                 tiempo_por_pregunta: tiempo,
                 nivel: nivel
               ],
               estado.gestor_partidas
             ) do
        {:ok, id, nivel}
      end

    {:reply, resultado, estado}
  end

  # AGREGAR BOT A LA PARTIDA DEL JUGADOR

  @impl true
  def handle_call(
        {:add_bot, dificultad},
        {pid_cliente, _referencia},
        estado
      ) do
    resultado =
      with {:ok, usuario} <-
             Trivia.GestorJugadores.usuario_por_pid(
               pid_cliente,
               estado.gestor_jugadores
             ),
           %{pid: pid_partida} <-
             Trivia.GestorPartidas.buscar_por_creador(
               usuario,
               estado.gestor_partidas
             ) do
        Trivia.Partida.agregar_bot(
          pid_partida,
          dificultad
        )
      else
        {:error, :partida_no_encontrada} ->
          {:error, :sin_partida}

        {:error, motivo} ->
          {:error, motivo}
      end

    {:reply, resultado, estado}
  end

  # INICIAR PARTIDA DEL JUGADOR

  @impl true
  def handle_call(
        :start_game,
        {pid_cliente, _referencia},
        estado
      ) do
    resultado =
      with {:ok, usuario} <-
             Trivia.GestorJugadores.usuario_por_pid(
               pid_cliente,
               estado.gestor_jugadores
             ),
           %{id: id} <-
             Trivia.GestorPartidas.buscar_por_creador(
               usuario,
               estado.gestor_partidas
             ) do
        Trivia.GestorPartidas.iniciar_partida(
          id,
          usuario,
          estado.gestor_partidas
        )
      else
        {:error, :partida_no_encontrada} ->
          {:error, :sin_partida}

        {:error, motivo} ->
          {:error, motivo}
      end

    {:reply, resultado, estado}
  end

  # RESPONDER UNA PREGUNTA

  @impl true
  def handle_call(
        {:answer, letra},
        {pid_cliente, _referencia},
        estado
      ) do
    resultado =
      with {:ok, usuario} <-
             Trivia.GestorJugadores.usuario_por_pid(
               pid_cliente,
               estado.gestor_jugadores
             ),
           %{pid: pid_partida} <-
             Trivia.GestorPartidas.buscar_por_creador(
               usuario,
               estado.gestor_partidas
             ) do
        Trivia.Partida.responder(
          pid_partida,
          usuario,
          letra
        )
      else
        {:error, :partida_no_encontrada} ->
          {:error, :sin_partida}

        {:error, motivo} ->
          {:error, motivo}
      end

    {:reply, resultado, estado}
  end

  @impl true
  def handle_call(
        :leave_game,
        {pid_cliente, _referencia},
        estado
      ) do
    resultado =
      with {:ok, usuario} <-
             Trivia.GestorJugadores.usuario_por_pid(
               pid_cliente,
               estado.gestor_jugadores
             ) do
        case abandonar_si_existe(usuario, estado) do
          :sin_partida -> {:error, :sin_partida}
          respuesta -> respuesta
        end
      end

    {:reply, resultado, estado}
  end

  @impl true
  def handle_call(
        :disconnect,
        {pid_cliente, _referencia},
        estado
      ) do
    resultado =
      with {:ok, usuario} <-
             Trivia.GestorJugadores.usuario_por_pid(
               pid_cliente,
               estado.gestor_jugadores
             ) do
        case abandonar_si_existe(usuario, estado) do
          resultado when resultado in [:ok, :sin_partida] ->
            Trivia.GestorJugadores.disconnect(
              pid_cliente,
              estado.gestor_jugadores
            )

          {:error, motivo} ->
            {:error, motivo}
        end
      end

    {:reply, resultado, estado}
  end

  defp abandonar_si_existe(usuario, estado) do
    alias Trivia.GestorPartidas
    alias Trivia.Partida

    case GestorPartidas.buscar_por_creador(
           usuario,
           estado.gestor_partidas
         ) do
      %{id: id, pid: pid} ->
        case Partida.abandonar(pid) do
          :ok ->
            GestorPartidas.liberar_partida(
              id,
              pid,
              estado.gestor_partidas
            )

          {:error, :partida_finalizada} ->
            GestorPartidas.liberar_partida(
              id,
              pid,
              estado.gestor_partidas
            )

          {:error, motivo} ->
            {:error, motivo}
        end

      {:error, :partida_no_encontrada} ->
        :sin_partida

      {:error, motivo} ->
        {:error, motivo}
    end
  end
end
