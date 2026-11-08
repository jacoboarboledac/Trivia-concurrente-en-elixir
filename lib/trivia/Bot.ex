
defmodule Trivia.Bot do
  use GenServer

  @moduledoc """
  Representa un jugador automático.
  Cada bot funciona en su propio proceso GenServer.
  """

  # INICIO DEL PROCESO

  def start_link(opciones) do
    GenServer.start_link(__MODULE__, opciones)
  end

  # CONSULTAS

  def consultar(pid) do
    GenServer.call(pid, :consultar)
  end

  # RECIBIR PREGUNTAS

  def pregunta(pid, pregunta, referencia, tiempo) do
    GenServer.cast(
      pid,
      {:pregunta, pregunta, referencia, tiempo}
    )
  end

  # DECIDIR RESPUESTA

  def decidir(dificultad, nivel, respuesta_correcta, tiempo_pregunta)
      when dificultad in [:facil, :dificil] and
             nivel in [:basico, :intermedio, :avanzado] and
             is_binary(respuesta_correcta) and
             is_number(tiempo_pregunta) and tiempo_pregunta > 0 do

    probabilidades = %{
      facil: %{
        basico: 0.40,
        intermedio: 0.30,
        avanzado: 0.20
      },
      dificil: %{
        basico: 0.80,
        intermedio: 0.70,
        avanzado: 0.60
      }
    }

    probabilidad = probabilidades[dificultad][nivel]

    respuesta =
      if :rand.uniform() <= probabilidad do
        respuesta_correcta
      else
        ["A", "B", "C", "D"]
        |> Enum.reject(&(&1 == respuesta_correcta))
        |> Enum.random()
      end

    {minimo, maximo} =
      case dificultad do
        :facil -> {0.40, 0.90}
        :dificil -> {0.10, 0.40}
      end

    retardo =
      minimo + :rand.uniform() * (maximo - minimo)

    {
      respuesta,
      round(retardo * tiempo_pregunta * 1000)
    }
  end

  def decidir(_, _, _, _) do
    {:error, :parametros_invalidos}
  end

  # INICIALIZACIÓN

  @impl true
  def init(opciones) do
    estado = %{
      nombre: Keyword.fetch!(opciones, :nombre),
      dificultad: Keyword.fetch!(opciones, :dificultad),
      partida: Keyword.fetch!(opciones, :partida)
    }

    {:ok, estado}
  end

  # CONSULTAS AL PROCESO

  @impl true
  def handle_call(:consultar, _from, estado) do
    {:reply, estado, estado}
  end

  # RECEPCIÓN DE PREGUNTAS

  @impl true
  def handle_cast(
        {:pregunta, pregunta, referencia, tiempo},
        estado
      ) do

    nivel = pregunta["nivel"]
    respuesta_correcta = pregunta["respuesta_correcta"]

    {respuesta, retardo} =
      decidir(
        estado.dificultad,
        nivel,
        respuesta_correcta,
        tiempo
      )

    Process.send_after(
      self(),
      {:enviar_respuesta, respuesta, referencia},
      retardo
    )

    {:noreply, estado}
  end

  # ENVÍO DE RESPUESTAS A LA PARTIDA

  @impl true
  def handle_info(
        {:enviar_respuesta, respuesta, referencia},
        estado
      ) do

    send(
      estado.partida,
      {
        :respuesta_bot,
        estado.nombre,
        respuesta,
        referencia
      }
    )

    {:noreply, estado}
  end
end
