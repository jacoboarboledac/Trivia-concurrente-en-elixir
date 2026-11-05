
defmodule Trivia.BotTest do
  use ExUnit.Case

  test "el bot fácil responde dentro del tiempo establecido" do
    for _ <- 1..100 do
      {respuesta, retardo} =
        Trivia.Bot.decidir(
          :facil,
          :basico,
          "B",
          15
        )

      assert respuesta in ["A", "B", "C", "D"]
      assert retardo >= 6000
      assert retardo <= 13500
    end
  end

  test "el bot difícil responde dentro del tiempo establecido" do
    for _ <- 1..100 do
      {respuesta, retardo} =
        Trivia.Bot.decidir(
          :dificil,
          :avanzado,
          "C",
          15
        )

      assert respuesta in ["A", "B", "C", "D"]
      assert retardo >= 1500
      assert retardo <= 6000
    end
  end

  test "rechaza parámetros inválidos" do
    assert Trivia.Bot.decidir(
             :experto,
             :basico,
             "A",
             15
           ) == {:error, :parametros_invalidos}
  end
end
