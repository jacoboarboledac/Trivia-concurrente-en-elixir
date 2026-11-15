defmodule Trivia.Receptor do
  @moduledoc """
  Proceso del cliente que habla con Trivia.Servidor y recibe notificaciones.
  El PID del receptor es siempre el que el servidor asocia a la sesión.
  """
  use GenServer

  def start_link(opciones) do
    GenServer.start_link(__MODULE__, opciones)
  end

  def solicitar(receptor, peticion) do
    GenServer.call(receptor, {:solicitar, peticion}, 15_000)
  end

  def estado_cliente(receptor) do
    GenServer.call(receptor, :estado_cliente)
  end

  # Omitir una respuesta no envía nada al servidor. Cuando expire la ronda,
  # se aplicarán los 0 puntos correspondientes a "sin responder".
  def omitir_pregunta(receptor) do
    GenServer.call(receptor, :omitir_pregunta)
  end

  @impl true
  def init(opciones) do
    {:ok,
     %{
       servidor: Keyword.fetch!(opciones, :servidor),
       usuario: nil,
       partida_id: nil,
       fase: :sin_partida,
       pregunta: nil
     }}
  end

  @impl true
  def handle_call(:estado_cliente, _from, estado) do
    vista = Map.take(estado, [:usuario, :partida_id, :fase, :pregunta])
    {:reply, vista, estado}
  end

  def handle_call(:omitir_pregunta, _from, estado) do
    {:reply, :ok, %{estado | pregunta: nil}}
  end

  def handle_call({:solicitar, peticion}, _from, estado) do
    respuesta =
      try do
        GenServer.call(estado.servidor, peticion, 10_000)
      catch
        :exit, _motivo -> {:error, :servidor_no_disponible}
      end

    nuevo_estado = actualizar_peticion(estado, peticion, respuesta)
    {:reply, respuesta, nuevo_estado}
  end

  defp actualizar_peticion(estado, {:connect, usuario, _clave}, {:ok, _}) do
    %{estado | usuario: usuario}
  end

  defp actualizar_peticion(estado, :disconnect, :ok) do
    %{estado | usuario: nil, partida_id: nil, fase: :sin_partida, pregunta: nil}
  end

  defp actualizar_peticion(estado, {:create_game, _tema, _n, _tiempo}, {:ok, id, _nivel}) do
    %{estado | partida_id: id, fase: :esperando, pregunta: nil}
  end

  defp actualizar_peticion(estado, :start_game, {:ok, _nivel}) do
    %{estado | fase: :en_curso}
  end

  defp actualizar_peticion(estado, {:answer, _letra}, {:ok, _puntos}) do
    %{estado | pregunta: nil}
  end

  defp actualizar_peticion(estado, :leave_game, :ok) do
    %{estado | partida_id: nil, fase: :sin_partida, pregunta: nil}
  end

  defp actualizar_peticion(estado, _peticion, _respuesta), do: estado

  @impl true
  def handle_info({:nueva_pregunta, id, numero, total, pregunta, tiempo}, estado) do
    IO.puts("\n" <> String.duplicate("=", 52))
    IO.puts(" PARTIDA #{id} | PREGUNTA #{numero} DE #{total}")
    IO.puts(String.duplicate("=", 52))
    IO.puts("Nivel: #{pregunta["nivel"]}")
    IO.puts("\n#{pregunta["enunciado"]}\n")

    pregunta["opciones"]
    |> Enum.with_index(1)
    |> Enum.each(fn {opcion, indice} ->
      letra = Enum.at(["A", "B", "C", "D"], indice - 1)
      IO.puts("  #{indice}) #{letra}. #{opcion}")
    end)

    IO.puts("\nTienes #{tiempo} segundos. Responde con 1, 2, 3 o 4.")

    datos = %{id: id, numero: numero, total: total, tiempo: tiempo}

    {:noreply,
     %{estado | partida_id: id, fase: :en_curso, pregunta: datos}}
  end

  def handle_info({:fin_ronda, id, correcta, puntos, total}, estado) do
    IO.puts("\n--- Ronda terminada (#{id}) ---")
    IO.puts("Respuesta correcta: #{correcta}")
    IO.puts("Puntos de esta ronda: #{puntos}")
    IO.puts("Puntaje acumulado: #{total}")
    IO.puts("La siguiente ronda llegará automáticamente, si quedan preguntas.")
    {:noreply, %{estado | pregunta: nil}}
  end

  def handle_info({:partida_finalizada, id, ranking, ganadores}, estado) do
    IO.puts("\n" <> String.duplicate("=", 52))
    IO.puts(" RESULTADO FINAL - #{id}")
    IO.puts(String.duplicate("=", 52))

    ranking
    |> Enum.with_index(1)
    |> Enum.each(fn {jugador, posicion} ->
      IO.puts("#{posicion}. #{jugador.usuario}: #{jugador.puntaje} puntos")
    end)

    IO.puts("Ganador(es): #{Enum.join(ganadores, ", ")}")
    {:noreply, %{estado | partida_id: nil, fase: :sin_partida, pregunta: nil}}
  end

  def handle_info({:respuesta_recibida, _id, _usuario}, estado) do
    IO.puts("\nRespuesta registrada.")
    {:noreply, estado}
  end

  def handle_info({:respuesta_ignorada, _id, _usuario, motivo}, estado) do
    IO.puts("\nLa respuesta no contó: #{inspect(motivo)}")
    {:noreply, estado}
  end

  def handle_info({:partida_cancelada, id}, estado) do
    IO.puts("\nPartida #{id} cancelada.")
    {:noreply, %{estado | partida_id: nil, fase: :sin_partida, pregunta: nil}}
  end

  def handle_info({:partida_reiniciada, id}, estado) do
    IO.puts("\nLa partida #{id} se reinició sin su progreso.")
    IO.puts("Vuelve a agregar dos bots e inicia la partida.")
    {:noreply, %{estado | partida_id: id, fase: :esperando, pregunta: nil}}
  end

  def handle_info({:resultado_guardado, id}, estado) do
    IO.puts("\nResultado de #{id} guardado en el historial.")
    {:noreply, estado}
  end

  def handle_info({:error_persistencia, id, motivo}, estado) do
    IO.puts("\nNo se pudo guardar #{id}: #{inspect(motivo)}")
    {:noreply, estado}
  end

  def handle_info(mensaje, estado) do
    IO.puts("\nAviso del servidor: #{inspect(mensaje)}")
    {:noreply, estado}
  end
end
