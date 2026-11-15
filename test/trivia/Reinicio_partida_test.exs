
defmodule Trivia.ReinicioPartidaTest do
  use ExUnit.Case, async: false

  alias Trivia.Partida
  alias Trivia.GestorPartidas

  test "reinicia la partida cuando falla un bot" do
    sufijo = System.unique_integer([:positive])

    nombre_supervisor =
      String.to_atom("supervisor_reinicio_#{sufijo}")

    nombre_gestor =
      String.to_atom("gestor_reinicio_#{sufijo}")

    ruta =
      Path.join(
        System.tmp_dir!(),
        "reinicio_#{sufijo}.log"
      )

    on_exit(fn -> File.rm(ruta) end)

    start_supervised!({
      Trivia.SupervisorPartidas,
      name: nombre_supervisor
    })

    start_supervised!({
      Trivia.GestorPartidas,
      [
        name: nombre_gestor,
        supervisor: nombre_supervisor,
        ruta_historial: ruta
      ]
    })

    assert {:ok, id, partida} =
      GestorPartidas.crear_partida(
        [
          creador: "pedro",
          cliente: self(),
          tema: "ciencia",
          numero_preguntas: 1,
          tiempo_por_pregunta: 10
        ],
        nombre_gestor
      )

    assert {:ok, "bot_1", bot_1} =
      Partida.agregar_bot(partida, :facil)

    assert {:ok, "bot_2", _bot_2} =
      Partida.agregar_bot(partida, :dificil)

    pregunta = %{
      "nivel" => :basico,
      "enunciado" => "¿Cuánto es 2 + 2?",
      "opciones" => ["2", "4", "6", "8"],
      "respuesta_correcta" => "B"
    }

    assert :ok =
      Partida.iniciar(partida, [pregunta], :basico)

    # Simulamos una falla anormal del primer bot
    Process.exit(bot_1, :kill)

    # El gestor debe avisar que la partida se reinició
    assert_receive {:partida_reiniciada, ^id}, 3000

    nueva_partida =
      GestorPartidas.buscar_por_creador(
        "pedro",
        nombre_gestor
      )

    assert nueva_partida.pid != partida
    assert Process.alive?(nueva_partida.pid)

    estado = Partida.consultar_estado(nueva_partida.pid)

    # Se reinicia sin progreso ni bots
    assert estado.estado == :esperando
    assert length(estado.jugadores) == 1
    assert estado.puntajes == %{"pedro" => 0}

    # La partida fallida no debe guardar resultados
    assert {:ok, []} =
      Trivia.Persistencia.leer_historial(ruta)
  end
end
