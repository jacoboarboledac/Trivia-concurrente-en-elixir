
defmodule Trivia.BancoPreguntasTest do
  use ExUnit.Case

  alias Trivia.BancoPreguntas

  # Construye un banco pequeño para las pruebas.
  defp banco_de_prueba do
    for nivel <- [:basico, :intermedio, :avanzado],
        numero <- 1..8 do
      %{
        "id" => "#{nivel}_#{numero}",
        "tema" => "ciencia",
        "nivel" => nivel,
        "enunciado" => "Pregunta #{numero} de #{nivel}",
        "opciones" => ["Opción A", "Opción B", "Opción C", "Opción D"],
        "respuesta_correcta" => "A"
      }
    end
  end

  test "sortear devuelve la cantidad solicitada de preguntas" do
    {:ok, preguntas} =
      BancoPreguntas.sortear(banco_de_prueba(), "ciencia", 5, :basico)

    assert length(preguntas) == 5
  end

  test "todas las preguntas pertenecen al tema solicitado" do
    {:ok, preguntas} =
      BancoPreguntas.sortear(banco_de_prueba(), "ciencia", 5, :basico)

    assert Enum.all?(preguntas, fn pregunta ->
             pregunta["tema"] == "ciencia"
           end)
  end

  test "el sorteo no repite preguntas" do
    {:ok, preguntas} =
      BancoPreguntas.sortear(banco_de_prueba(), "ciencia", 10, :intermedio)

    ids = Enum.map(preguntas, & &1["id"])

    assert length(ids) == length(Enum.uniq(ids))
  end

  test "respeta las cantidades del reparto por nivel" do
    {:ok, preguntas} =
      BancoPreguntas.sortear(banco_de_prueba(), "ciencia", 10, :intermedio)

    cantidades =
      Enum.frequencies_by(preguntas, & &1["nivel"])

    assert cantidades[:basico] == 2
    assert cantidades[:intermedio] == 6
    assert cantidades[:avanzado] == 2
  end

  test "ordena las preguntas de básico a avanzado" do
    {:ok, preguntas} =
      BancoPreguntas.sortear(banco_de_prueba(), "ciencia", 10, :intermedio)

    niveles = Enum.map(preguntas, & &1["nivel"])

    posiciones = Enum.map(niveles, fn nivel ->
      case nivel do
        :basico -> 1
        :intermedio -> 2
        :avanzado -> 3
      end
    end)

    assert posiciones == Enum.sort(posiciones)
  end

  test "devuelve error cuando no hay suficientes preguntas" do
    banco = Enum.take(banco_de_prueba(), 2)

    assert {:error, {:preguntas_insuficientes, :basico, 4, 2}} =
             BancoPreguntas.sortear(banco, "ciencia", 5, :basico)
  end

  test "devuelve error cuando el tema no existe" do
    assert {:error, {:preguntas_insuficientes, :basico, 4, 0}} =
             BancoPreguntas.sortear(
               banco_de_prueba(),
               "historia",
               5,
               :basico
             )
  end
end
