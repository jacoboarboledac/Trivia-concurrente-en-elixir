defmodule Trivia.GestorPartidas do
  use GenServer

  @moduledoc """
  Crea, localiza y supervisa partidas, y calcula el nivel requerido
  para comenzar cada juego.

  En el servidor real, las lecturas del historial pasan por Trivia.Almacen.
  Las pruebas antiguas pueden seguir utilizando Trivia.Persistencia.
  """

  # INICIO

  def start_link(opciones \\ []) do
    nombre = Keyword.get(opciones, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opciones, name: nombre)
  end

  @impl true
  def init(opciones) do
    ruta_preguntas =
      Keyword.get(
        opciones,
        :ruta_preguntas,
        "data/questions.json"
      )

    case Trivia.BancoPreguntas.cargar(ruta_preguntas) do
      {:ok, preguntas} ->
        {:ok,
         %{
           partidas: %{},
           partidas_por_creador: %{},
           siguiente_id: 1001,
           supervisor:
             Keyword.get(
               opciones,
               :supervisor,
               Trivia.SupervisorPartidas
             ),
           ruta_preguntas: ruta_preguntas,
           preguntas: preguntas,
           ruta_historial:
             Keyword.get(
               opciones,
               :ruta_historial,
               "data/results.log"
             ),
           almacen:
             Keyword.get(
               opciones,
               :almacen,
               Trivia.Persistencia
             )
         }}

      {:error, motivo} ->
        {:stop, {:banco_preguntas_invalido, motivo}}
    end
  end

  # API PÚBLICA

  def listar_partidas(gestor \\ __MODULE__) do
    GenServer.call(gestor, :listar_partidas)
  end

  def crear_partida(opciones, gestor \\ __MODULE__) do
    GenServer.call(gestor, {:crear_partida, opciones})
  end

  def iniciar_partida(id, usuario, gestor \\ __MODULE__) do
    GenServer.call(gestor, {:iniciar_partida, id, usuario})
  end

  def buscar_por_creador(creador, gestor \\ __MODULE__) do
    GenServer.call(gestor, {:buscar_por_creador, creador})
  end

  def preparar_creacion(
        usuario,
        tema,
        cantidad,
        tiempo,
        gestor \\ __MODULE__
      ) do
    GenServer.call(
      gestor,
      {:preparar_creacion, usuario, tema, cantidad, tiempo}
    )
  end

  def liberar_partida(id, pid, gestor \\ __MODULE__) do
    GenServer.call(gestor, {:liberar_partida, id, pid})
  end

  # CONSULTAS

  @impl true
  def handle_call({:buscar_por_creador, creador}, _from, estado) do
    respuesta =
      case Map.get(estado.partidas_por_creador, creador) do
        nil -> {:error, :partida_no_encontrada}
        id -> Map.get(estado.partidas, id) || {:error, :partida_no_encontrada}
      end

    {:reply, respuesta, estado}
  end

  @impl true
  def handle_call(:listar_partidas, _from, estado) do
    {:reply, estado.partidas, estado}
  end

  # VALIDAR CONFIGURACIÓN Y NIVEL ANTES DE CREAR

  @impl true
  def handle_call(
        {:preparar_creacion, usuario, tema, cantidad, tiempo},
        _from,
        estado
      ) do
    almacen = estado.almacen

    respuesta =
      cond do
        Map.has_key?(estado.partidas_por_creador, usuario) ->
          {:error, :jugador_en_partida}

        not is_binary(tema) or String.trim(tema) == "" ->
          {:error, :tema_invalido}

        not is_integer(cantidad) or cantidad < 1 or cantidad > 10 ->
          {:error, :cantidad_invalida}

        not is_integer(tiempo) or tiempo <= 0 ->
          {:error, :tiempo_invalido}

        true ->
          with true <-
                 Enum.any?(
                   estado.preguntas,
                   &(&1["tema"] == tema)
                 ),
               {:ok, historial} <-
                 almacen.leer_historial(estado.ruta_historial),
               nivel =
                 Trivia.Nivel.nivel_jugador(
                   historial,
                   usuario,
                   tema
                 ),
               {:ok, _sorteo} <-
                 Trivia.BancoPreguntas.sortear(
                   estado.preguntas,
                   tema,
                   cantidad,
                   nivel
                 ) do
            {:ok, nivel}
          else
            false -> {:error, :tema_inexistente}
            {:error, motivo} -> {:error, motivo}
          end
      end

    {:reply, respuesta, estado}
  end

  # CREAR PARTIDA

  @impl true
  def handle_call({:crear_partida, opciones}, _from, estado) do
    creador = Keyword.fetch!(opciones, :creador)

    if Map.has_key?(estado.partidas_por_creador, creador) do
      {:reply, {:error, :jugador_en_partida}, estado}
    else
      id = "P-#{estado.siguiente_id}"

      opciones_partida =
        Keyword.merge(
          opciones,
          id: id,
          gestor: self(),
          ruta_historial: estado.ruta_historial,
          almacen: estado.almacen
        )

      case DynamicSupervisor.start_child(
             estado.supervisor,
             {Trivia.Partida, opciones_partida}
           ) do
        {:ok, pid} ->
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
              partidas_por_creador: Map.put(estado.partidas_por_creador, creador, id)
          }

          {:reply, {:ok, id, pid}, nuevo_estado}

        {:error, motivo} ->
          {:reply, {:error, motivo}, estado}
      end
    end
  end

  # INICIAR PARTIDA

  @impl true
  def handle_call({:iniciar_partida, id, usuario}, _from, estado) do
    case Map.get(estado.partidas, id) do
      nil ->
        {:reply, {:error, :partida_no_encontrada}, estado}

      %{creador: creador} when creador != usuario ->
        {:reply, {:error, :no_es_el_creador}, estado}

      %{pid: pid} ->
        datos_partida = Trivia.Partida.consultar_estado(pid)

        # Conservar el nivel establecido al crear la partida.
        nivel = datos_partida.nivel

        resultado =
          with {:ok, preguntas_sorteadas} <-
                 Trivia.BancoPreguntas.sortear(
                   estado.preguntas,
                   datos_partida.tema,
                   datos_partida.numero_preguntas,
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
            {:error, motivo} -> {:error, motivo}
          end

        {:reply, resultado, estado}
    end
  end

  # LIBERAR UNA PARTIDA AL TERMINAR O CANCELARSE

  @impl true
  def handle_call({:liberar_partida, id, pid}, _from, estado) do
    {:reply, :ok, quitar_partida(estado, id, pid)}
  end

  @impl true
  def handle_cast({:partida_cerrada, id, pid}, estado) do
    {:noreply, quitar_partida(estado, id, pid)}
  end

  # REGISTRAR EL PID NUEVO CUANDO UNA PARTIDA SE REINICIA

  @impl true
  def handle_cast(
        {:registrar_partida, id, pid, creador, cliente},
        estado
      ) do
    case Map.get(estado.partidas, id) do
      nil ->
        # Evita que una notificación tardía vuelva a registrar
        # una partida que ya fue liberada.
        {:noreply, estado}

      partida_anterior ->
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

        if partida_anterior.pid != pid do
          send(cliente, {:partida_reiniciada, id})
        end

        {:noreply, nuevo_estado}
    end
  end

  # ELIMINAR SOLO SI EL PID TODAVÍA CORRESPONDE A ESA PARTIDA

  defp quitar_partida(estado, id, pid) do
    case Map.get(estado.partidas, id) do
      %{pid: ^pid, creador: creador} ->
        partidas = Map.delete(estado.partidas, id)

        por_creador =
          if Map.get(estado.partidas_por_creador, creador) == id do
            Map.delete(estado.partidas_por_creador, creador)
          else
            estado.partidas_por_creador
          end

        %{
          estado
          | partidas: partidas,
            partidas_por_creador: por_creador
        }

      _ ->
        estado
    end
  end
end
