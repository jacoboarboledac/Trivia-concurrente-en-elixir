defmodule Trivia.ServidorTest do
  use ExUnit.Case, async: false

  alias Trivia.GestorJugadores
  alias Trivia.Servidor

  setup do
    carpeta =
      Path.join(
        System.tmp_dir!(),
        "servidor_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(carpeta)

    nombre_gestor =
      String.to_atom("gestor_servidor_#{System.unique_integer([:positive])}")

    nombre_servidor =
      String.to_atom("servidor_#{System.unique_integer([:positive])}")

    gestor =
      start_supervised!(
        {Trivia.GestorJugadores,
         [
           name: nombre_gestor,
           ruta_usuarios: Path.join(carpeta, "users.json"),
           ruta_historial: Path.join(carpeta, "results.log")
         ]}
      )

    nombre_supervisor_partidas =
      String.to_atom("supervisor_servidor_#{System.unique_integer([:positive])}")

    nombre_gestor_partidas =
      String.to_atom("gestor_partidas_servidor_#{System.unique_integer([:positive])}")

    ruta_preguntas = Path.join(carpeta, "questions.json")

    File.cp!("data/questions.json", ruta_preguntas)

    start_supervised!({
      Trivia.SupervisorPartidas,
      name: nombre_supervisor_partidas
    })

    start_supervised!({
      Trivia.GestorPartidas,
      [
        name: nombre_gestor_partidas,
        supervisor: nombre_supervisor_partidas,
        ruta_preguntas: ruta_preguntas,
        ruta_historial: Path.join(carpeta, "results.log")
      ]
    })

    servidor =
      start_supervised!(
        {Trivia.Servidor,
         [
           name: nombre_servidor,
           gestor_jugadores: nombre_gestor,
           gestor_partidas: nombre_gestor_partidas
         ]}
      )

    on_exit(fn ->
      File.rm_rf!(carpeta)
    end)

    %{
      gestor: nombre_gestor,
      servidor: nombre_servidor,
      pid_servidor: servidor,
      pid_gestor: gestor,
      gestor_partidas: nombre_gestor_partidas
    }
  end

  test "registra al cliente y no al servidor", context do
    assert {:ok, "pedro"} =
             Servidor.connect(
               "pedro",
               "12345",
               context.servidor
             )

    assert {:ok, "pedro"} =
             GestorJugadores.usuario_por_pid(
               self(),
               context.gestor
             )

    assert {:error, :no_autenticado} =
             GestorJugadores.usuario_por_pid(
               context.pid_servidor,
               context.gestor
             )
  end

  test "rechaza una conexion con datos invalidos", context do
    assert {:error, :datos_invalidos} =
             Servidor.connect(
               "",
               "",
               context.servidor
             )
  end

  test "score y ranking funcionan con una sesión activa", context do
    assert {:ok, "pedro"} =
             Servidor.connect(
               "pedro",
               "12345",
               context.servidor
             )

    # Estadísticas iniciales
    assert {:ok, estadisticas} =
             Servidor.score(context.servidor)

    assert estadisticas.usuario == "pedro"
    assert estadisticas.puntaje == 0
    assert estadisticas.partidas == 0
    assert estadisticas.temas == []

    # Ranking global
    assert {:ok, []} =
             Servidor.ranking(nil, context.servidor)

    # Ranking por tema
    assert {:ok, []} =
             Servidor.ranking("ciencia", context.servidor)
  end

  test "rechaza consultas de clientes sin sesión", context do
    assert {:error, :no_autenticado} =
             Servidor.score(context.servidor)

    assert {:error, :no_autenticado} =
             Servidor.ranking(nil, context.servidor)

    assert {:error, :no_autenticado} =
             Servidor.ranking("ciencia", context.servidor)
  end

  test "un jugador conectado puede crear partida y agregar bots",
       context do
    assert {:ok, "pedro"} =
             Servidor.connect(
               "pedro",
               "12345",
               context.servidor
             )

    assert {:ok, "P-1001", :basico} =
             Servidor.create_game(
               "ciencia",
               1,
               10,
               context.servidor
             )

    assert {:ok, "bot_1", _pid_1} =
             Servidor.add_bot(
               :facil,
               context.servidor
             )

    assert {:ok, "bot_2", _pid_2} =
             Servidor.add_bot(
               :dificil,
               context.servidor
             )

    assert {:error, :jugador_en_partida} =
             Servidor.create_game(
               "ciencia",
               1,
               10,
               context.servidor
             )

    partida =
      Trivia.GestorPartidas.buscar_por_creador(
        "pedro",
        context.gestor_partidas
      )

    estado = Trivia.Partida.consultar_estado(partida.pid)

    assert length(estado.jugadores) == 3
    assert estado.estado == :esperando
    assert estado.nivel == :basico
  end

  test "no permite crear partidas sin iniciar sesion",
       context do
    assert {:error, :no_autenticado} =
             Servidor.create_game(
               "ciencia",
               1,
               10,
               context.servidor
             )

    assert {:error, :no_autenticado} =
             Servidor.add_bot(
               :facil,
               context.servidor
             )
  end

  test "iniciar partida y responder desde el servidor",
       context do
    # Conectar jugador
    assert {:ok, "pedro"} =
             Servidor.connect(
               "pedro",
               "12345",
               context.servidor
             )

    # Crear partida con una pregunta
    assert {:ok, _id, :basico} =
             Servidor.create_game(
               "ciencia",
               1,
               10,
               context.servidor
             )

    # No puede iniciar sin dos bots
    assert {:error, :jugadores_insuficientes} =
             Servidor.start_game(context.servidor)

    # Agregar los dos bots
    assert {:ok, "bot_1", _} =
             Servidor.add_bot(:facil, context.servidor)

    assert {:ok, "bot_2", _} =
             Servidor.add_bot(:dificil, context.servidor)

    # Iniciar partida
    assert {:ok, :basico} =
             Servidor.start_game(context.servidor)

    # Debe llegar la pregunta al cliente
    assert_receive {
                     :nueva_pregunta,
                     _id,
                     1,
                     1,
                     pregunta,
                     10
                   },
                   1000

    # El cliente no debe conocer la respuesta
    refute Map.has_key?(
             pregunta,
             "respuesta_correcta"
           )

    # Responder correctamente
    assert {:ok, puntos} =
             Servidor.answer("B", context.servidor)

    assert puntos == -5 or puntos in 10..15

    # No se permite responder dos veces
    assert {:error, :respuesta_duplicada} =
             Servidor.answer("A", context.servidor)
  end

  test "abandonar antes de iniciar libera al jugador",
       context do
    assert {:ok, "pedro"} =
             Servidor.connect(
               "pedro",
               "12345",
               context.servidor
             )

    assert {:ok, id, :basico} =
             Servidor.create_game(
               "ciencia",
               1,
               10,
               context.servidor
             )

    assert :ok = Servidor.leave_game(context.servidor)

    assert_receive {:partida_cancelada, ^id}, 1000

    assert {:error, :partida_no_encontrada} =
             Trivia.GestorPartidas.buscar_por_creador(
               "pedro",
               context.gestor_partidas
             )

    # Puede crear otra partida
    assert {:ok, nuevo_id, :basico} =
             Servidor.create_game(
               "ciencia",
               1,
               10,
               context.servidor
             )

    assert nuevo_id != id
  end

  test "abandonar durante el juego registra el resultado",
       context do
    assert {:ok, "pedro"} =
             Servidor.connect(
               "pedro",
               "12345",
               context.servidor
             )

    assert {:ok, _id, :basico} =
             Servidor.create_game(
               "ciencia",
               1,
               10,
               context.servidor
             )

    assert {:ok, "bot_1", _} =
             Servidor.add_bot(:facil, context.servidor)

    assert {:ok, "bot_2", _} =
             Servidor.add_bot(:dificil, context.servidor)

    assert {:ok, :basico} =
             Servidor.start_game(context.servidor)

    assert_receive {:nueva_pregunta, _, 1, 1, _, 10}, 1000

    assert :ok = Servidor.leave_game(context.servidor)

    # La partida abandonada debe contar en el historial
    assert {:ok, estadisticas} =
             Servidor.score(context.servidor)

    assert estadisticas.partidas == 1

    # Ya puede crear otra partida
    assert {:ok, _, :basico} =
             Servidor.create_game(
               "ciencia",
               1,
               10,
               context.servidor
             )
  end

  test "disconnect cierra la sesion y cancela la partida",
       context do
    assert {:ok, "pedro"} =
             Servidor.connect(
               "pedro",
               "12345",
               context.servidor
             )

    assert {:ok, _, :basico} =
             Servidor.create_game(
               "ciencia",
               1,
               10,
               context.servidor
             )

    assert :ok = Servidor.disconnect(context.servidor)

    assert {:error, :no_autenticado} =
             Servidor.score(context.servidor)

    assert {:error, :partida_no_encontrada} =
             Trivia.GestorPartidas.buscar_por_creador(
               "pedro",
               context.gestor_partidas
             )

    # Puede volver a iniciar sesión
    assert {:ok, "pedro"} =
             Servidor.connect(
               "pedro",
               "12345",
               context.servidor
             )
  end
end
