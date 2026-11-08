defmodule Trivia.GestorPartidas do
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
    supervisor =
      Keyword.get(
        opciones,
        :supervisor,
        Trivia.SupervisorPartidas
      )

    {:ok,
     %{
       partidas: %{},
       partidas_por_creador: %{},
       siguiente_id: 1001,
       supervisor: supervisor,
       ruta_preguntas:
         Keyword.get(
           opciones,
           :ruta_preguntas,
           "data/questions.json"
         ),
       ruta_historial:
         Keyword.get(
           opciones,
           :ruta_historial,
           "data/results.log"
         )
     }}
  end

  def listar_partidas(gestor \\ __MODULE__) do
    GenServer.call(gestor, :listar_partidas)
  end

  def crear_partida(opciones, gestor \\ __MODULE__) do
    GenServer.call(
      gestor,
      {:crear_partida, opciones}
    )
  end

  def iniciar_partida(id, usuario, gestor \\ __MODULE__) do
    GenServer.call(
      gestor,
      {:iniciar_partida, id, usuario}
    )
  end

  # -------------------------
  # CONSULTAS
  # -------------------------

  def buscar_por_creador(creador, gestor \\ __MODULE__) do
    GenServer.call(
      gestor,
      {:buscar_por_creador, creador}
    )
  end

  # -------------------------
  # REGISTRO DE PARTIDAS
  # -------------------------

  @impl true
  def handle_call(
        {:buscar_por_creador, creador},
        _from,
        estado
      ) do
    respuesta =
      case Map.get(estado.partidas_por_creador, creador) do
        nil ->
          {:error, :partida_no_encontrada}

        id ->
          Map.get(estado.partidas, id)
      end

    {:reply, respuesta, estado}
  end

  @impl true
  def handle_call(:listar_partidas, _from, estado) do
    {:reply, estado.partidas, estado}
  end

  @impl true
  def handle_call(
        {:crear_partida, opciones},
        _from,
        estado
      ) do
    id = "P-#{estado.siguiente_id}"

    opciones_partida =
      Keyword.merge(
        opciones,
        id: id,
        gestor: self(),
        ruta_historial: estado.ruta_historial
      )

    case DynamicSupervisor.start_child(
           estado.supervisor,
           {Trivia.Partida, opciones_partida}
         ) do
      {:ok, pid} ->
        creador = Keyword.fetch!(opciones, :creador)
        cliente = Keyword.fetch!(opciones, :cliente)

        nueva_partida = %{
          id: id,
          pid: pid,
          creador: creador,
          cliente: cliente
        }

        nuevo_estado = %{
          estado
          | siguiente_id: estado.siguiente_id + 1,
            partidas: Map.put(estado.partidas, id, nueva_partida),
            partidas_por_creador:
              Map.put(
                estado.partidas_por_creador,
                creador,
                id
              )
        }

        {:reply, {:ok, id, pid}, nuevo_estado}

      {:error, motivo} ->
        {:reply, {:error, motivo}, estado}
    end
  end

  @impl true
  def handle_call(
        {:iniciar_partida, id, usuario},
        _from,
        estado
      ) do
    case Map.get(estado.partidas, id) do
      nil ->
        {:reply, {:error, :partida_no_encontrada}, estado}

      %{creador: creador} when creador != usuario ->
        {:reply, {:error, :no_es_el_creador}, estado}

      %{pid: pid} ->
        resultado =
          with {:ok, preguntas} <-
                 Trivia.BancoPreguntas.cargar(estado.ruta_preguntas),
               {:ok, historial} <-
                 Trivia.Persistencia.leer_historial(estado.ruta_historial),
               nivel =
                 Trivia.Nivel.nivel_jugador(
                   historial,
                   usuario,
                   estado_partida(pid).tema
                 ),
               {:ok, preguntas_sorteadas} <-
                 Trivia.BancoPreguntas.sortear(
                   preguntas,
                   estado_partida(pid).tema,
                   estado_partida(pid).numero_preguntas,
                   nivel
                 ),
               :ok <-
                 Trivia.Partida.iniciar(
                   pid,
                   preguntas_sorteadas,
                   nivel
                 ) do
            {:ok, nivel}
          else
            {:error, motivo} ->
              {:error, motivo}
          end

        {:reply, resultado, estado}
    end
  end

  # -------------------------
  # ACTUALIZACIÓN DE PROCESOS
  # -------------------------

  @impl true
  def handle_cast(
        {:registrar_partida, id, pid, creador, cliente},
        estado
      ) do
    partida_anterior =
      Map.get(estado.partidas, id)

    nueva_partida = %{
      id: id,
      pid: pid,
      creador: creador,
      cliente: cliente
    }

    nuevo_estado = %{
      estado
      | partidas: Map.put(estado.partidas, id, nueva_partida),
        partidas_por_creador: Map.put(estado.partidas_por_creador, creador, id)
    }

    if partida_anterior != nil and
         partida_anterior.pid != pid do
      send(
        cliente,
        {:partida_reiniciada, id}
      )
    end

    {:noreply, nuevo_estado}
  end

  defp estado_partida(pid) do
    Trivia.Partida.consultar_estado(pid)
  end
end
