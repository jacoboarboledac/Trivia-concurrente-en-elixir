defmodule Trivia.NivelTest do
  use ExUnit.Case

  alias Trivia.Nivel

  # Crea una línea de historial en formato JSON.
  defp crear_linea(tema, jugadores) do
    Jason.encode!(%{
      tema: tema,
      jugadores: jugadores
    })
  end

  test "determina el nivel básico con 59 puntos" do
    assert Nivel.determinar_nivel(59) == :basico
  end

  test "determina el nivel intermedio desde 60 hasta 179 puntos" do
    assert Nivel.determinar_nivel(60) == :intermedio
    assert Nivel.determinar_nivel(179) == :intermedio
  end

  test "determina el nivel avanzado desde 180 puntos" do
    assert Nivel.determinar_nivel(180) == :avanzado
    assert Nivel.determinar_nivel(250) == :avanzado
  end

  test "los puntajes negativos corresponden al nivel básico" do
    assert Nivel.determinar_nivel(-10) == :basico
  end

  test "suma los puntos del jugador solamente en el tema solicitado" do
    historial = [
      crear_linea("ciencia", [
        %{usuario: "pedro", puntaje: 40},
        %{usuario: "bot_1", puntaje: 30}
      ]),
      crear_linea("historia", [
        %{usuario: "pedro", puntaje: 100}
      ]),
      crear_linea("ciencia", [
        %{usuario: "pedro", puntaje: 25}
      ])
    ]

    assert Nivel.puntaje_por_tema(historial, "pedro", "ciencia") == 65
  end

  test "ignora los bots y las líneas JSON inválidas" do
    historial = [
      crear_linea("ciencia", [
        %{usuario: "bot_1", puntaje: 100},
        %{usuario: "pedro", puntaje: 30}
      ]),
      "esta no es una línea JSON válida"
    ]

    assert Nivel.puntaje_por_tema(historial, "pedro", "ciencia") == 30
    assert Nivel.puntaje_por_tema(historial, "bot_1", "ciencia") == 0
  end

  test "un tema nunca jugado comienza en nivel básico" do
    historial = []

    assert Nivel.nivel_jugador(historial, "pedro", "ciencia") == :basico
  end

  test "reparte las preguntas según el nivel del jugador" do
    assert Nivel.reparto_preguntas(5, :basico) == %{
             basico: 4,
             intermedio: 1,
             avanzado: 0
           }

    assert Nivel.reparto_preguntas(10, :intermedio) == %{
             basico: 2,
             intermedio: 6,
             avanzado: 2
           }

    assert Nivel.reparto_preguntas(10, :avanzado) == %{
             basico: 0,
             intermedio: 3,
             avanzado: 7
           }
  end

  test "un puntaje negativo en el historial puede bajar el nivel" do
    historial = [
      crear_linea("ciencia", [
        %{usuario: "pedro", puntaje: 75}
      ]),
      crear_linea("ciencia", [
        %{usuario: "pedro", puntaje: -90}
      ])
    ]

    assert Nivel.puntaje_por_tema(historial, "pedro", "ciencia") == -15
    assert Nivel.nivel_jugador(historial, "pedro", "ciencia") == :basico
  end
end
