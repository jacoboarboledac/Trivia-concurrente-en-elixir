
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
       supervisor: supervisor
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
        gestor: self()
      )

    case DynamicSupervisor.start_child(
           estado.supervisor,
           {Trivia.Partida, opciones_partida}
         ) do
      {:ok, pid} ->
        nuevo_estado = %{
          estado
          | siguiente_id: estado.siguiente_id + 1
        }

        {:reply, {:ok, id, pid}, nuevo_estado}

      {:error, motivo} ->
        {:reply, {:error, motivo}, estado}
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
        partidas_por_creador:
          Map.put(estado.partidas_por_creador, creador, id)
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
end
