defmodule Trivia.PartidaIntegracionTest do
  use ExUnit.Case, async: false

  alias Trivia.Partida
  alias Trivia.Persistencia

  test "una partida completa con dos bots guarda el resultado" do
    id = "P-INTEGRACION"

    ruta =
      Path.join(
        System.tmp_dir!(),
        "trivia_#{System.unique_integer([:positive])}.log"
      )

    on_exit(fn -> File.rm(ruta) end)

    partida =
      start_supervised!({
        Partida,
        [
          id: id,
          creador: "pedro",
          cliente: self(),
          tema: "ciencia",
          numero_preguntas: 1,
          tiempo_por_pregunta: 3,
          ruta_historial: ruta
        ]
      })

      monitor_partida = Process.monitor(partida)

    # Agregamos los dos bots
    assert {:ok, "bot_1", _} =
             Partida.agregar_bot(partida, :facil)

    assert {:ok, "bot_2", _} =
             Partida.agregar_bot(partida, :dificil)

    # Pregunta de prueba
    pregunta = %{
      "tema" => "ciencia",
      "nivel" => :basico,
      "enunciado" => "¿Cuánto es 2 + 2?",
      "opciones" => ["2", "4", "6", "8"],
      "respuesta_correcta" => "B"
    }

    # Iniciamos la partida
    assert :ok =
             Partida.iniciar(partida, [pregunta], :basico)

    # Verificamos que el humano recibe la pregunta
    assert_receive {
                     :nueva_pregunta,
                     ^id,
                     1,
                     1,
                     pregunta_cliente,
                     3
                   },
                   1000

    # No debe enviarse la respuesta correcta al cliente
    refute Map.has_key?(
             pregunta_cliente,
             "respuesta_correcta"
           )

    # El humano responde
    assert {:ok, _puntos} =
             Partida.responder(partida, "pedro", "B")

    # Esperamos el cierre de la ronda
    assert_receive {
                     :fin_ronda,
                     ^id,
                     "B",
                     _puntos_ronda,
                     _puntaje_total
                   },
                   5000

    # Esperamos el ranking final
    assert_receive {
                     :partida_finalizada,
                     ^id,
                     ranking,
                     _ganadores
                   },
                   1000

    nombres = Enum.map(ranking, & &1.usuario)

    assert Enum.sort(nombres) ==
             ["bot_1", "bot_2", "pedro"]

    # Verificamos que se guardó el resultado
    assert_receive {:resultado_guardado, ^id}, 1000

    assert {:ok, [linea]} =
             Persistencia.leer_historial(ruta)

    assert {:ok, resultado} = Jason.decode(linea)

    assert resultado["tema"] == "ciencia"
    assert resultado["nivel"] == "basico"

    assert length(resultado["jugadores"]) == 3

    # Verificamos el estado final

    assert_receive {
    :DOWN,
    ^monitor_partida,
    :process,
    ^partida,
    :normal
   }, 2000


    refute Process.alive?(partida)
  end
end
