
defmodule Trivia.Nivel do
  @moduledoc """
  Calcula el nivel de un jugador por tema y el reparto
  de preguntas que debe recibir en una partida.
  """

  @doc """
  Suma los puntajes de un jugador en un tema específico.

  Recibe una lista de líneas JSON del historial.
  Ignora las líneas inválidas y los jugadores cuyo nombre
  comienza por "bot_".
  """
  def puntaje_por_tema(lineas, usuario, tema) do
    lineas
    |> Enum.map(&decodificar_linea/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn partida ->
      partida["tema"] == tema
    end)
    |> Enum.flat_map(fn partida ->
      partida["jugadores"] || []
    end)
    |> Enum.filter(fn jugador ->
      jugador["usuario"] == usuario and
        not String.starts_with?(jugador["usuario"], "bot_")
    end)
    |> Enum.reduce(0, fn jugador, acumulado ->
      acumulado + puntaje_valido(jugador["puntaje"])
    end)
  end

  @doc """
  Determina el nivel a partir del puntaje acumulado.
  """
  def determinar_nivel(puntaje) when puntaje < 60, do: :basico

  def determinar_nivel(puntaje) when puntaje < 180,
    do: :intermedio

  def determinar_nivel(_puntaje), do: :avanzado

  @doc """
  Calcula el nivel de un jugador en un tema usando su historial.
  """
  def nivel_jugador(lineas, usuario, tema) do
    lineas
    |> puntaje_por_tema(usuario, tema)
    |> determinar_nivel()
  end

  @doc """
  Calcula la cantidad de preguntas de cada nivel.

  Las preguntas que sobran después de calcular los porcentajes
  de los otros dos niveles corresponden al nivel del jugador.
  """
  def reparto_preguntas(total_preguntas, nivel)
      when is_integer(total_preguntas) and total_preguntas >= 0 do
    porcentajes =
      case nivel do
        :basico ->
          %{basico: 0, intermedio: 30, avanzado: 0}

        :intermedio ->
          %{basico: 20, intermedio: 0, avanzado: 20}

        :avanzado ->
          %{basico: 0, intermedio: 30, avanzado: 0}
      end

    nivel_principal =
      case nivel do
        :basico -> :basico
        :intermedio -> :intermedio
        :avanzado -> :avanzado
      end

    cantidades =
      Map.new(porcentajes, fn {nivel_pregunta, porcentaje} ->
        cantidad = trunc(total_preguntas * porcentaje / 100)
        {nivel_pregunta, cantidad}
      end)

    cantidad_asignada =
      cantidades
      |> Map.values()
      |> Enum.sum()

    Map.put(
      cantidades,
      nivel_principal,
      total_preguntas - cantidad_asignada
    )
  end

  # Convierte una línea JSON en un mapa.
  # Si la línea no es válida, devuelve nil.
  defp decodificar_linea(linea) do
    case Jason.decode(linea) do
      {:ok, partida} when is_map(partida) -> partida
      _ -> nil
    end
  end

  # Evita sumar valores que no sean números enteros.
  defp puntaje_valido(puntaje) when is_integer(puntaje), do: puntaje
  defp puntaje_valido(_puntaje), do: 0
end
