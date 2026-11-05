
defmodule Trivia.PartidaTest do
  use ExUnit.Case, async: true

  alias Trivia.Partida

  setup do
    {:ok, pid} =
      Partida.start_link(
        id: "P-TEST",
        creador: "pedro",
        cliente: self(),
        tema: "ciencia",
        numero_preguntas: 5,
        tiempo_por_pregunta: 15
      )

    %{partida: pid}
  end

  test "inicia en estado de espera", context do
    estado = Partida.consultar_estado(context.partida)

    assert estado.id == "P-TEST"
    assert estado.estado == :esperando
    assert estado.pregunta_actual == 0
  end

  test "registra al creador como primer jugador", context do
    estado = Partida.consultar_estado(context.partida)

    assert length(estado.jugadores) == 1

    assert hd(estado.jugadores).usuario == "pedro"
    assert hd(estado.jugadores).tipo == :humano
    assert estado.puntajes["pedro"] == 0
  end

  test "conserva la configuración de la partida", context do
    estado = Partida.consultar_estado(context.partida)

    assert estado.tema == "ciencia"
    assert estado.numero_preguntas == 5
    assert estado.tiempo_por_pregunta == 15
  end


  test "agrega un bot fácil a la partida", context do
    assert {:ok, "bot_1", pid_bot} =
             Partida.agregar_bot(context.partida, :facil)

    assert Process.alive?(pid_bot)

    estado = Partida.consultar_estado(context.partida)

    assert length(estado.jugadores) == 2
    assert estado.puntajes["bot_1"] == 0

    bot = Trivia.Bot.consultar(pid_bot)

    assert bot.nombre == "bot_1"
    assert bot.dificultad == :facil
  end

  test "rechaza una dificultad inválida", context do
    assert {:error, :dificultad_invalida} =
             Partida.agregar_bot(context.partida, :media)
  end

  test "no permite más de cuatro jugadores", context do
    assert {:ok, "bot_1", _} =
             Partida.agregar_bot(context.partida)

    assert {:ok, "bot_2", _} =
             Partida.agregar_bot(context.partida)

    assert {:ok, "bot_3", _} =
             Partida.agregar_bot(context.partida)

    assert {:error, :partida_llena} =
             Partida.agregar_bot(context.partida)
  end

end
