defmodule Trivia.Partida do
  use GenServer

  @moduledoc """
  Administra el estado y la dinámica de una partida.
  Cada partida funciona en su propio proceso GenServer.
  """

  @niveles [:basico, :intermedio, :avanzado]
  @opciones ["A", "B", "C", "D"]
  @pausa_entre_rondas 3000

  # INICIO DEL PROCESO

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

  # CONSULTAS Y OPERACIONES

  def consultar_estado(partida) do
    GenServer.call(partida, :consultar_estado)
  end

  def agregar_bot(partida, dificultad \\ :facil) do
    GenServer.call(partida, {:agregar_bot, dificultad})
  end

  def iniciar(partida, preguntas, nivel) do
    GenServer.call(
      partida,
      {:iniciar, preguntas, nivel}
    )
  end

  def responder(partida, usuario, respuesta) do
    GenServer.call(partida, {:responder, usuario, respuesta})
  end

  def abandonar(partida) do
    GenServer.call(partida, :abandonar)
  end

  # INICIALIZACIÓN

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

    ruta_historial =
      Keyword.get(
        opciones,
        :ruta_historial,
        "data/results.log"
      )

    jugador = %{
      usuario: creador,
      pid: cliente,
      tipo: :humano,
      puntaje: 0
    }

    monitor = Process.monitor(cliente)

    estado = %{
      id: id,
      creador: creador,
      cliente: cliente,
      gestor: gestor,
      tema: Keyword.fetch!(opciones, :tema),
      nivel: Keyword.get(opciones, :nivel),
      numero_preguntas: Keyword.fetch!(opciones, :numero_preguntas),
      tiempo_por_pregunta: Keyword.fetch!(opciones, :tiempo_por_pregunta),
      preguntas: [],
      ruta_historial: ruta_historial,
      almacen: Keyword.get(opciones, :almacen, Trivia.Persistencia),
      jugadores: [jugador],
      puntajes: %{creador => 0},
      estado: :esperando,
      pregunta_actual: 0,
      respuestas: %{},
      puntos_ronda: %{},
      inicio_ronda: nil,
      temporizador: nil,
      referencia_ronda: nil,
      monitores: %{monitor => {:humano, creador}}
    }

    GenServer.cast(
      gestor,
      {:registrar_partida, id, self(), creador, cliente}
    )

    {:ok, estado}
  end

  # CONSULTAR ESTADO

  @impl true
  def handle_call(:consultar_estado, _from, estado) do
    {:reply, estado, estado}
  end

  # AGREGAR BOTS

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
        numero =
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

        nombre = "bot_#{numero}"

        opciones = [
          nombre: nombre,
          dificultad: dificultad,
          partida: self()
        ]

        case Trivia.Bot.start_link(opciones) do
          {:ok, pid_bot} ->
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
                  Map.put(
                    estado.monitores,
                    monitor,
                    {:bot, nombre}
                  )
            }

            {:reply, {:ok, nombre, pid_bot}, nuevo_estado}

          {:error, motivo} ->
            {:reply, {:error, motivo}, estado}
        end
    end
  end

  # INICIAR PARTIDA

  def handle_call(
        {:iniciar, preguntas, nivel},
        _from,
        estado
      ) do
    cond do
      estado.estado != :esperando ->
        {:reply, {:error, :partida_ya_iniciada}, estado}

      length(estado.jugadores) < 3 ->
        {:reply, {:error, :jugadores_insuficientes}, estado}

      length(estado.jugadores) > 4 ->
        {:reply, {:error, :partida_llena}, estado}

      not is_list(preguntas) ->
        {:reply, {:error, :preguntas_invalidas}, estado}

      length(preguntas) != estado.numero_preguntas ->
        {:reply, {:error, :cantidad_preguntas_invalida}, estado}

      not Enum.all?(preguntas, &pregunta_valida?/1) ->
        {:reply, {:error, :preguntas_invalidas}, estado}

      true ->
        nuevo_estado = %{
          estado
          | preguntas: preguntas,
            nivel: nivel,
            estado: :en_curso
        }

        {:reply, :ok, abrir_ronda(nuevo_estado)}
    end
  end

  # RECIBIR RESPUESTAS HUMANAS

  def handle_call(
        {:responder, usuario, respuesta},
        _from,
        estado
      ) do
    case registrar_respuesta(estado, usuario, respuesta) do
      {:ok, nuevo_estado, puntos} ->
        {:reply, {:ok, puntos}, cerrar_si_completa(nuevo_estado)}

      {:error, motivo} ->
        {:reply, {:error, motivo}, estado}
    end
  end

  # ABANDONAR PARTIDA

  def handle_call(:abandonar, _from, estado) do
    case estado.estado do
      :esperando ->
        nuevo_estado = %{
          estado
          | estado: :cancelada
        }

        enviar(
          estado.cliente,
          {:partida_cancelada, estado.id}
        )

        GenServer.cast(
          estado.gestor,
          {:partida_cerrada, estado.id, self()}
        )

        {:reply, :ok,
         nuevo_estado
         |> detener_bots()
         |> programar_cierre()}

      :en_curso ->
        nuevo_estado = finalizar_partida(estado)

        {:reply, :ok, nuevo_estado}

      :pausa ->
        nuevo_estado = finalizar_partida(estado)

        {:reply, :ok, nuevo_estado}

      _ ->
        {:reply, {:error, :partida_finalizada}, estado}
    end
  end

  # RECEPCIÓN DE MENSAJES ASÍNCRONOS

  @impl true
  def handle_info(
        {:fin_tiempo, referencia},
        %{referencia_ronda: referencia, estado: :en_curso} = estado
      ) do
    {:noreply, cerrar_ronda(estado)}
  end

  def handle_info(
        {:fin_tiempo, _referencia},
        estado
      ) do
    {:noreply, estado}
  end

  # RESPUESTAS DE LOS BOTS

  def handle_info(
        {:respuesta_bot, nombre, respuesta, referencia},
        %{referencia_ronda: referencia, estado: :en_curso} = estado
      ) do
    case registrar_respuesta(estado, nombre, respuesta) do
      {:ok, nuevo_estado, _puntos} ->
        {:noreply, cerrar_si_completa(nuevo_estado)}

      {:error, _motivo} ->
        {:noreply, estado}
    end
  end

  def handle_info(
        {:respuesta_bot, _nombre, _respuesta, _referencia},
        estado
      ) do
    {:noreply, estado}
  end

  # SIGUIENTE RONDA

  def handle_info(
        :siguiente_ronda,
        %{estado: :pausa} = estado
      ) do
    if estado.pregunta_actual >= length(estado.preguntas) do
      {:noreply, finalizar_partida(estado)}
    else
      {:noreply, abrir_ronda(%{estado | estado: :en_curso})}
    end
  end

  # DETECTAR PROCESOS DESCONECTADOS

  # Ignorar cambios de jugadores tras finalizar o cancelar

  def handle_info(
        {:DOWN, monitor, :process, _pid, _motivo},
        %{estado: estado_partida} = estado
      )
      when estado_partida in [:finalizada, :cancelada] do
    nuevos_monitores =
      Map.delete(estado.monitores, monitor)

    {:noreply, %{estado | monitores: nuevos_monitores}}
  end

  def handle_info(
        {:DOWN, monitor, :process, _pid, _motivo},
        estado
      ) do
    case Map.pop(estado.monitores, monitor) do
      {nil, _monitores} ->
        {:noreply, estado}

      {{:humano, _nombre}, monitores} ->
        nuevo_estado = %{
          estado
          | monitores: monitores
        }

        GenServer.cast(
          nuevo_estado.gestor,
          {:partida_cerrada, nuevo_estado.id, self()}
        )

        if estado.estado in [:en_curso, :pausa] do
          {:noreply, finalizar_partida(nuevo_estado)}
        else
          cancelado = %{nuevo_estado | estado: :cancelada}

          GenServer.cast(
            cancelado.gestor,
            {:partida_cerrada, cancelado.id, self()}
          )

          {:noreply,
           cancelado
           |> detener_bots()
           |> programar_cierre()}
        end

      {{:bot, nombre}, monitores} ->
        jugadores =
          Enum.reject(
            estado.jugadores,
            &(&1.usuario == nombre)
          )

        nuevo_estado = %{
          estado
          | jugadores: jugadores,
            monitores: monitores,
            puntajes: Map.delete(estado.puntajes, nombre),
            respuestas: Map.delete(estado.respuestas, nombre)
        }

        {:noreply, cerrar_si_completa(nuevo_estado)}
    end
  end

  # TERMINAR EL PROCESO DE UNA PARTIDA CERRADA

  @impl true
  def handle_info(
        :cerrar_proceso,
        %{estado: estado_partida} = estado
      )
      when estado_partida in [:finalizada, :cancelada] do
    {:stop, :normal, estado}
  end

  # FINALIZACIÓN DEL PROCESO

  @impl true
  def terminate(_motivo, estado) do
    if estado.temporizador do
      Process.cancel_timer(estado.temporizador)
    end

    Enum.each(estado.jugadores, fn jugador ->
      if jugador.tipo == :bot and is_pid(jugador.pid) do
        Process.exit(jugador.pid, :shutdown)
      end
    end)

    :ok
  end

  # ABRIR UNA RONDA

  defp abrir_ronda(estado) do
    indice = estado.pregunta_actual
    pregunta = Enum.at(estado.preguntas, indice)

    referencia = make_ref()

    temporizador =
      Process.send_after(
        self(),
        {:fin_tiempo, referencia},
        estado.tiempo_por_pregunta * 1000
      )

    inicio = System.monotonic_time(:millisecond)

    Enum.each(estado.jugadores, fn jugador ->
      pregunta_para_jugador =
        if jugador.tipo == :bot do
          Map.put(pregunta, "referencia_ronda", referencia)
        else
          Map.drop(pregunta, ["respuesta_correcta"])
        end

      enviar(
        jugador.pid,
        {
          :nueva_pregunta,
          estado.id,
          indice + 1,
          estado.numero_preguntas,
          pregunta_para_jugador,
          estado.tiempo_por_pregunta
        }
      )
    end)

    %{
      estado
      | pregunta_actual: indice + 1,
        respuestas: %{},
        puntos_ronda: %{},
        inicio_ronda: inicio,
        temporizador: temporizador,
        referencia_ronda: referencia
    }
  end

  # REGISTRAR RESPUESTAS

  defp registrar_respuesta(estado, usuario, respuesta) do
    jugador =
      Enum.find(
        estado.jugadores,
        &(&1.usuario == usuario)
      )

    cond do
      estado.estado != :en_curso ->
        {:error, :ronda_no_abierta}

      is_nil(jugador) ->
        {:error, :jugador_no_encontrado}

      Map.has_key?(estado.respuestas, usuario) ->
        enviar(
          jugador.pid,
          {
            :respuesta_ignorada,
            estado.id,
            usuario,
            :respuesta_duplicada
          }
        )

        {:error, :respuesta_duplicada}

      respuesta not in @opciones ->
        {:error, :respuesta_invalida}

      true ->
        pregunta =
          Enum.at(
            estado.preguntas,
            estado.pregunta_actual - 1
          )

        transcurrido =
          System.monotonic_time(:millisecond) -
            estado.inicio_ronda

        segundos_restantes =
          max(
            estado.tiempo_por_pregunta -
              transcurrido / 1000,
            0
          )

        puntos =
          calcular_puntos(
            pregunta["nivel"],
            respuesta,
            pregunta["respuesta_correcta"],
            segundos_restantes,
            estado.tiempo_por_pregunta
          )

        respuestas =
          Map.put(
            estado.respuestas,
            usuario,
            respuesta
          )

        puntos_ronda =
          Map.put(
            estado.puntos_ronda,
            usuario,
            puntos
          )

        puntajes =
          Map.update!(
            estado.puntajes,
            usuario,
            &(&1 + puntos)
          )

        jugadores =
          Enum.map(estado.jugadores, fn j ->
            if j.usuario == usuario do
              %{j | puntaje: Map.fetch!(puntajes, usuario)}
            else
              j
            end
          end)

        nuevo_estado = %{
          estado
          | respuestas: respuestas,
            puntos_ronda: puntos_ronda,
            puntajes: puntajes,
            jugadores: jugadores
        }

        enviar(
          jugador.pid,
          {:respuesta_recibida, estado.id, usuario}
        )

        {:ok, nuevo_estado, puntos}
    end
  end

  # CALCULAR PUNTAJE

  defp calcular_puntos(
         nivel,
         respuesta,
         correcta,
         segundos_restantes,
         tiempo_total
       ) do
    puntos_correcta = %{
      basico: 10,
      intermedio: 15,
      avanzado: 20
    }

    puntos_incorrecta = %{
      basico: -5,
      intermedio: -8,
      avanzado: -10
    }

    cond do
      respuesta == nil ->
        0

      respuesta == correcta ->
        bonificacion =
          trunc(5 * segundos_restantes / tiempo_total)

        Map.fetch!(puntos_correcta, nivel) + bonificacion

      true ->
        Map.fetch!(puntos_incorrecta, nivel)
    end
  end

  # CERRAR LA RONDA CUANDO TODOS RESPONDAN

  defp cerrar_si_completa(%{estado: :en_curso} = estado) do
    if map_size(estado.respuestas) == length(estado.jugadores) do
      cerrar_ronda(estado)
    else
      estado
    end
  end

  defp cerrar_si_completa(estado), do: estado

  # CERRAR RONDA

  defp cerrar_ronda(estado) do
    if estado.temporizador do
      Process.cancel_timer(estado.temporizador)
    end

    pregunta =
      Enum.at(
        estado.preguntas,
        estado.pregunta_actual - 1
      )

    Enum.each(estado.jugadores, fn jugador ->
      puntos =
        Map.get(
          estado.puntos_ronda,
          jugador.usuario,
          0
        )

      enviar(
        jugador.pid,
        {
          :fin_ronda,
          estado.id,
          pregunta["respuesta_correcta"],
          puntos,
          Map.get(estado.puntajes, jugador.usuario, 0)
        }
      )
    end)

    # Construir el ranking de la ronda
    ranking_ronda =
      estado.jugadores
      |> Enum.map(fn jugador ->
        %{
          usuario: jugador.usuario,
          puntos_ronda: Map.get(estado.puntos_ronda, jugador.usuario, 0),
          puntaje: Map.get(estado.puntajes, jugador.usuario, 0)
        }
      end)
      |> Enum.sort_by(fn jugador ->
        {-jugador.puntaje, jugador.usuario}
      end)

    # Enviar la clasificación al cliente humano
    enviar(
      estado.cliente,
      {:ranking_ronda, estado.id, ranking_ronda}
    )

    nuevo_estado = %{
      estado
      | estado: :pausa,
        temporizador: nil,
        inicio_ronda: nil,
        referencia_ronda: nil
    }

    if estado.pregunta_actual >= length(estado.preguntas) do
      finalizar_partida(nuevo_estado)
    else
      Process.send_after(
        self(),
        :siguiente_ronda,
        @pausa_entre_rondas
      )

      nuevo_estado
    end
  end

  # FINALIZAR PARTIDA Y GENERAR RANKING

  defp finalizar_partida(estado) do
    if estado.temporizador do
      Process.cancel_timer(estado.temporizador)
    end

    ranking =
      estado.puntajes
      |> Enum.map(fn {usuario, puntaje} ->
        %{
          usuario: usuario,
          puntaje: puntaje
        }
      end)
      |> Enum.sort_by(fn jugador ->
        {-jugador.puntaje, jugador.usuario}
      end)

    mayor_puntaje =
      ranking
      |> Enum.map(& &1.puntaje)
      |> Enum.max(fn -> 0 end)

    ganadores =
      Enum.filter(
        ranking,
        &(&1.puntaje == mayor_puntaje)
      )
      |> Enum.map(& &1.usuario)

    ganador =
      Enum.join(ganadores, ", ")

    jugadores_resultado =
      Enum.map(ranking, fn jugador ->
        %{
          "usuario" => jugador.usuario,
          "puntaje" => jugador.puntaje
        }
      end)

    resultado = %{
      "fecha" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "id" => estado.id,
      "tema" => estado.tema,
      "nivel" => Atom.to_string(estado.nivel),
      "ganador" => ganador,
      "jugadores" => jugadores_resultado
    }

    resultado_persistencia =
      estado.almacen.guardar_resultado(
        resultado,
        estado.ruta_historial
      )

    enviar(
      estado.cliente,
      {
        :partida_finalizada,
        estado.id,
        ranking,
        ganadores
      }
    )

    case resultado_persistencia do
      :ok ->
        enviar(
          estado.cliente,
          {:resultado_guardado, estado.id}
        )

      {:error, motivo} ->
        enviar(
          estado.cliente,
          {:error_persistencia, estado.id, motivo}
        )
    end

    GenServer.cast(
      estado.gestor,
      {:partida_cerrada, estado.id, self()}
    )

    detener_bots(%{
      estado
      | estado: :finalizada,
        temporizador: nil,
        referencia_ronda: nil
    })
    |> programar_cierre()
  end

  # PROGRAMAR LA TERMINACIÓN DEL PROCESO

  defp programar_cierre(estado) do
    send(self(), :cerrar_proceso)
    estado
  end

  # DETENER BOTS

  defp detener_bots(estado) do
    Enum.each(estado.jugadores, fn jugador ->
      if jugador.tipo == :bot and is_pid(jugador.pid) do
        if Process.alive?(jugador.pid) do
          GenServer.stop(jugador.pid, :normal)
        end
      end
    end)

    estado
  end

  # VALIDAR PREGUNTAS

  defp pregunta_valida?(pregunta) when is_map(pregunta) do
    pregunta["nivel"] in @niveles and
      is_binary(pregunta["enunciado"]) and
      is_list(pregunta["opciones"]) and
      length(pregunta["opciones"]) == 4 and
      pregunta["respuesta_correcta"] in @opciones
  end

  defp pregunta_valida?(_pregunta), do: false

  # ENVIAR MENSAJES

  defp enviar(pid, mensaje) when is_pid(pid) do
    send(pid, mensaje)
  end

  defp enviar(_pid, _mensaje) do
    :ok
  end
end
