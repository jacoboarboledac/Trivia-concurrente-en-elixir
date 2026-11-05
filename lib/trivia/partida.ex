defmodule Trivia.Partida do
  use GenServer

  @moduledoc """
  Administra el estado y la dinámica de una partida de Trivia.
  Cada partida funciona en su propio proceso GenServer.
  """

  # -------------------------
  # INICIO DEL PROCESO
  # -------------------------

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

  # -------------------------
  # CONSULTAS
  # -------------------------

  @doc """
  Devuelve una copia del estado actual de la partida.
  """
  def consultar_estado(partida) do
    GenServer.call(partida, :consultar_estado)
  end

  def agregar_bot(partida, dificultad \\ :facil) do
    GenServer.call(partida, {:agregar_bot, dificultad})
  end

  # -------------------------
  # INICIALIZACIÓN
  # -------------------------

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

    jugador_creador = %{
      usuario: creador,
      pid: cliente,
      tipo: :humano,
      puntaje: 0
    }

    estado = %{
      # Identificación y configuración
      id: id,
      creador: creador,
      cliente: cliente,
      gestor: gestor,
      tema: Keyword.fetch!(opciones, :tema),
      nivel: Keyword.get(opciones, :nivel),

      # Configuración de las preguntas
      numero_preguntas: Keyword.fetch!(opciones, :numero_preguntas),
      tiempo_por_pregunta: Keyword.fetch!(opciones, :tiempo_por_pregunta),
      preguntas: [],

      # Jugadores y puntajes
      jugadores: [jugador_creador],
      puntajes: %{creador => 0},

      # Progreso de la partida
      estado: :esperando,
      pregunta_actual: 0,
      respuestas: %{},
      inicio_ronda: nil,
      temporizador: nil,
      monitores: %{}
    }

    GenServer.cast(
      gestor,
      {:registrar_partida, id, self(), creador, cliente}
    )

    {:ok, estado}
  end

  # -------------------------
  # MANEJO DE CONSULTAS
  # -------------------------

  @impl true
  def handle_call(
        :consultar_estado,
        _from,
        estado
      ) do
    {:reply, estado, estado}
  end


  # -------------------------
  # AGREGAR BOTS
  # -------------------------

  @impl true
  def handle_call(
        {:agregar_bot, dificultad},
        _from,
        estado
      ) do
    cond do
      estado.estado != :esperando ->
        {:reply, {:error, :partida_iniciada}, estado}

      length(estado.jugadores) >= 4 ->
        {:reply, {:error, :partida_llena}, estado}

      dificultad not in [:facil, :dificil] ->
        {:reply, {:error, :dificultad_invalida}, estado}

      true ->
        numero_bot =
          estado.jugadores
          |> Enum.map(& &1.usuario)
          |> Enum.filter(&String.starts_with?(&1, "bot_"))
          |> Enum.map(fn nombre ->
            nombre
            |> String.replace_prefix("bot_", "")
            |> String.to_integer()
          end)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        nombre = "bot_#{numero_bot}"

        opciones = [
          nombre: nombre,
          dificultad: dificultad,
          partida: self()
        ]

        case Trivia.Bot.start_link(opciones) do
          {:ok, pid_bot} ->
            # El bot no debe tumbar la partida si falla.
            Process.unlink(pid_bot)

            monitor = Process.monitor(pid_bot)

            jugador = %{
              usuario: nombre,
              pid: pid_bot,
              tipo: :bot,
              dificultad: dificultad,
              puntaje: 0
            }

            nuevo_estado = %{
              estado
              | jugadores: estado.jugadores ++ [jugador],
                puntajes: Map.put(estado.puntajes, nombre, 0),
                monitores:
                  Map.put(estado.monitores, monitor, nombre)
            }

            {:reply, {:ok, nombre, pid_bot}, nuevo_estado}

          {:error, motivo} ->
            {:reply, {:error, motivo}, estado}
        end
    end
  end

  @impl true
  def handle_info(
        {:DOWN, monitor, :process, _pid, _motivo},
        estado
      ) do
    case Map.pop(estado.monitores, monitor) do
      {nil, _monitores} ->
        {:noreply, estado}

      {nombre, monitores} ->
        jugadores =
          Enum.reject(estado.jugadores, fn jugador ->
            jugador.usuario == nombre
          end)

        nuevo_estado = %{
          estado
          | jugadores: jugadores,
            monitores: monitores,
            puntajes: Map.delete(estado.puntajes, nombre)
        }

        {:noreply, nuevo_estado}
    end
  end

  @impl true
  def terminate(_motivo, estado) do
    Enum.each(estado.jugadores, fn jugador ->
      if jugador.tipo == :bot and is_pid(jugador.pid) do
        Process.exit(jugador.pid, :shutdown)
      end
    end)

    :ok
  end

end
