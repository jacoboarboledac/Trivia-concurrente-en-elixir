
defmodule Trivia.BancoPreguntas do
  @moduledoc """
  Carga el banco de preguntas desde un archivo JSON
  y realiza sorteos por tema y nivel.
  """

  @niveles [:basico, :intermedio, :avanzado]

  @doc """
  Lee y valida las preguntas de un archivo JSON.

  Devuelve {:ok, preguntas} o {:error, motivo}.
  """
  def cargar(ruta \\ "data/questions.json") do
    with {:ok, contenido} <- File.read(ruta),
         {:ok, datos} <- Jason.decode(contenido),
         true <- is_list(datos),
         {:ok, preguntas} <- normalizar_preguntas(datos) do
      {:ok, preguntas}
    else
      false ->
        {:error, :formato_invalido}

      {:error, %Jason.DecodeError{}} ->
        {:error, :json_invalido}

      {:error, motivo} ->
        {:error, motivo}
    end
  end

  @doc """
  Sortea las preguntas de una partida.

  Recibe:
  - La lista de preguntas cargadas.
  - El tema solicitado.
  - La cantidad total de preguntas.
  - El nivel del jugador creador.

  Devuelve las preguntas ordenadas de básico a avanzado.
  """
  def sortear(preguntas, tema, total_preguntas, nivel_jugador)
      when is_list(preguntas) and is_binary(tema) and
             is_integer(total_preguntas) and total_preguntas > 0 do
    if nivel_jugador not in @niveles do
      {:error, :nivel_invalido}
    else
      reparto = Trivia.Nivel.reparto_preguntas(
        total_preguntas,
        nivel_jugador
      )

      preguntas_tema =
        Enum.filter(preguntas, fn pregunta ->
          pregunta["tema"] == tema
        end)

      cantidades_disponibles =
        Map.new(@niveles, fn nivel ->
          cantidad =
            Enum.count(preguntas_tema, fn pregunta ->
              pregunta["nivel"] == nivel
            end)

          {nivel, cantidad}
        end)

      case verificar_cantidades(reparto, cantidades_disponibles) do
        :ok ->
          preguntas_sorteadas =
            Enum.flat_map(@niveles, fn nivel ->
              cantidad = Map.fetch!(reparto, nivel)

              preguntas_tema
              |> Enum.filter(&(&1["nivel"] == nivel))
              |> Enum.take_random(cantidad)
            end)

          {:ok, preguntas_sorteadas}

        {:error, motivo} ->
          {:error, motivo}
      end
    end
  end

  def sortear(_preguntas, _tema, _total, _nivel) do
    {:error, :parametros_invalidos}
  end

  # Normaliza todas las preguntas del archivo.
  defp normalizar_preguntas(datos) do
    resultado =
      Enum.reduce_while(datos, {:ok, []}, fn pregunta, {:ok, acumuladas} ->
        case normalizar_pregunta(pregunta) do
          {:ok, pregunta_normalizada} ->
            {:cont, {:ok, [pregunta_normalizada | acumuladas]}}

          {:error, motivo} ->
            {:halt, {:error, motivo}}
        end
      end)

    case resultado do
      {:ok, preguntas} ->
        preguntas = Enum.reverse(preguntas)

        if ids_unicos?(preguntas) do
          {:ok, preguntas}
        else
          {:error, :ids_duplicados}
        end

      error ->
        error
    end
  end

  # Comprueba que una pregunta tenga todos sus campos correctos.
  defp normalizar_pregunta(pregunta) when is_map(pregunta) do
    id = pregunta["id"]
    tema = pregunta["tema"]
    nivel = convertir_nivel(pregunta["nivel"])
    enunciado = pregunta["enunciado"]
    opciones = pregunta["opciones"]
    respuesta = pregunta["respuesta_correcta"]

    cond do
      is_nil(id) ->
        {:error, :pregunta_sin_id}

      not is_binary(tema) ->
        {:error, :tema_invalido}

      is_nil(nivel) ->
        {:error, :nivel_invalido}

      not is_binary(enunciado) ->
        {:error, :enunciado_invalido}

      not (is_list(opciones) and length(opciones) == 4 and
             Enum.all?(opciones, &is_binary/1)) ->
        {:error, :opciones_invalidas}

      respuesta not in ["A", "B", "C", "D"] ->
        {:error, :respuesta_invalida}

      true ->
        pregunta_normalizada =
          Map.put(pregunta, "nivel", nivel)

        {:ok, pregunta_normalizada}
    end
  end

  defp normalizar_pregunta(_pregunta) do
    {:error, :pregunta_invalida}
  end

  # Convierte el texto del JSON en un átomo conocido.
  defp convertir_nivel("basico"), do: :basico
  defp convertir_nivel("intermedio"), do: :intermedio
  defp convertir_nivel("avanzado"), do: :avanzado
  defp convertir_nivel(_nivel), do: nil

  # Verifica que no existan identificadores repetidos.
  defp ids_unicos?(preguntas) do
    ids = Enum.map(preguntas, & &1["id"])
    length(ids) == length(Enum.uniq(ids))
  end

  # Comprueba que haya suficientes preguntas para cada nivel.
  defp verificar_cantidades(reparto, disponibles) do
    insuficientes =
      Enum.find(@niveles, fn nivel ->
        Map.fetch!(disponibles, nivel) < Map.fetch!(reparto, nivel)
      end)

    case insuficientes do
      nil ->
        :ok

      nivel ->
        {:error,
         {:preguntas_insuficientes,
          nivel,
          Map.fetch!(reparto, nivel),
          Map.fetch!(disponibles, nivel)}}
    end
  end
end
