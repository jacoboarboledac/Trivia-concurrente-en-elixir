defmodule Trivia.BancoCompletoTest do
  use ExUnit.Case, async: true

  alias Trivia.BancoPreguntas
  alias Trivia.Nivel

  @temas ~w(ciencia historia geografia tecnologia)
  @niveles [:basico, :intermedio, :avanzado]
  @orden_nivel %{basico: 0, intermedio: 1, avanzado: 2}

  test "el banco incluye 4 temas con al menos 8 preguntas por nivel" do
    assert {:ok, preguntas} = BancoPreguntas.cargar("data/questions.json")
    assert length(preguntas) >= 96

    ids = Enum.map(preguntas, & &1["id"])
    assert length(ids) == length(Enum.uniq(ids))

    for tema <- @temas, nivel <- @niveles do
      cantidad =
        Enum.count(preguntas, fn pregunta ->
          pregunta["tema"] == tema and pregunta["nivel"] == nivel
        end)

      assert cantidad >= 8,
             "Faltan preguntas para tema=#{tema}, nivel=#{nivel}; hay #{cantidad}"
    end
  end

  test "cada tema permite sortear 10 preguntas sin repetir y con el reparto correcto" do
    assert {:ok, preguntas} = BancoPreguntas.cargar("data/questions.json")

    for tema <- @temas, nivel_jugador <- @niveles do
      assert {:ok, sorteadas} =
               BancoPreguntas.sortear(preguntas, tema, 10, nivel_jugador)

      assert length(sorteadas) == 10
      assert Enum.all?(sorteadas, &(&1["tema"] == tema))
      assert length(Enum.uniq_by(sorteadas, & &1["id"])) == 10

      niveles_sorteados = Enum.map(sorteadas, & &1["nivel"])
      assert niveles_sorteados ==
               Enum.sort_by(niveles_sorteados, &Map.fetch!(@orden_nivel, &1))

      for {nivel, esperado} <- Nivel.reparto_preguntas(10, nivel_jugador) do
        assert Enum.count(sorteadas, &(&1["nivel"] == nivel)) == esperado
      end
    end
  end
end
