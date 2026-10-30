
defmodule Trivia.GestorJugadoresTest do
  use ExUnit.Case, async: false

  alias Trivia.GestorJugadores
  alias Trivia.Persistencia

  setup do
    carpeta =
      Path.join(
        System.tmp_dir!(),
        "gestor_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(carpeta)

    ruta_usuarios = Path.join(carpeta, "users.json")
    ruta_historial = Path.join(carpeta, "results.log")

    nombre =
      String.to_atom(
        "gestor_#{System.unique_integer([:positive])}"
      )

    {:ok, servidor} =
      GestorJugadores.start_link(
        name: nombre,
        ruta_usuarios: ruta_usuarios,
        ruta_historial: ruta_historial
      )

    on_exit(fn ->
      if Process.alive?(servidor) do
        GenServer.stop(servidor)
      end

      File.rm_rf!(carpeta)
    end)

    %{
      servidor: nombre,
      ruta_usuarios: ruta_usuarios,
      ruta_historial: ruta_historial
    }
  end

  test "connect registra automáticamente un usuario nuevo", context do
    assert {:ok, "pedro"} =
             GestorJugadores.connect(
               "pedro",
               "12345",
               context.servidor
             )

    assert {:ok, usuarios} =
             Persistencia.cargar_usuarios(context.ruta_usuarios)

    assert length(usuarios) == 1
    assert hd(usuarios)["usuario"] == "pedro"
  end

  test "rechaza una clave incorrecta", context do
    assert {:ok, "pedro"} =
             GestorJugadores.connect(
               "pedro",
               "12345",
               context.servidor
             )

    assert :ok =
             GestorJugadores.disconnect(context.servidor)

    assert {:error, :clave_incorrecta} =
             GestorJugadores.connect(
               "pedro",
               "clave_incorrecta",
               context.servidor
             )
  end

  test "rechaza usuarios con el prefijo bot_", context do
    assert {:error, :prefijo_reservado} =
             GestorJugadores.connect(
               "bot_pedro",
               "12345",
               context.servidor
             )
  end

  test "rechaza usuarios que ya tienen una sesión activa", context do
    assert {:ok, "pedro"} =
             GestorJugadores.connect(
               "pedro",
               "12345",
               context.servidor
             )

    padre = self()
    servidor = context.servidor

    cliente =
      spawn(fn ->
        resultado =
          GestorJugadores.connect(
            "pedro",
            "12345",
            servidor
          )

        send(padre, {:resultado, resultado})
      end)

    assert_receive {:resultado, {:error, :sesion_activa}}

    refute Process.alive?(cliente)
  end

  test "disconnect permite volver a iniciar sesión", context do
    assert {:ok, "pedro"} =
             GestorJugadores.connect(
               "pedro",
               "12345",
               context.servidor
             )

    assert :ok =
             GestorJugadores.disconnect(context.servidor)

    assert {:ok, "pedro"} =
             GestorJugadores.connect(
               "pedro",
               "12345",
               context.servidor
             )
  end

  test "score calcula puntaje y partidas desde el historial", context do
    assert {:ok, "pedro"} =
             GestorJugadores.connect(
               "pedro",
               "12345",
               context.servidor
             )

    partida_1 = %{
      "fecha" => "2026-10-29T20:00:00Z",
      "id" => "P-1001",
      "tema" => "ciencia",
      "nivel" => "basico",
      "ganador" => "pedro",
      "jugadores" => [
        %{"usuario" => "pedro", "puntaje" => 80},
        %{"usuario" => "bot_1", "puntaje" => 20}
      ]
    }

    partida_2 = %{
      "fecha" => "2026-10-29T21:00:00Z",
      "id" => "P-1002",
      "tema" => "historia",
      "nivel" => "basico",
      "ganador" => "pedro",
      "jugadores" => [
        %{"usuario" => "pedro", "puntaje" => 30},
        %{"usuario" => "bot_1", "puntaje" => 10}
      ]
    }

    assert :ok =
             Persistencia.guardar_resultado(
               partida_1,
               context.ruta_historial
             )

    assert :ok =
             Persistencia.guardar_resultado(
               partida_2,
               context.ruta_historial
             )

    assert {:ok, datos} =
             GestorJugadores.score(context.servidor)

    assert datos.usuario == "pedro"
    assert datos.puntaje == 110
    assert datos.partidas == 2

    assert length(datos.temas) == 2

    ciencia = Enum.find(datos.temas, &(&1.tema == "ciencia"))

    assert ciencia.puntaje == 80
    assert ciencia.partidas == 1
    assert ciencia.nivel == :intermedio
  end

  test "ranking calcula puntajes e ignora los bots", context do
    assert {:ok, "pedro"} =
             GestorJugadores.connect(
               "pedro",
               "12345",
               context.servidor
             )

    resultado = %{
      "fecha" => "2026-10-29T20:00:00Z",
      "id" => "P-1001",
      "tema" => "ciencia",
      "nivel" => "basico",
      "ganador" => "pedro",
      "jugadores" => [
        %{"usuario" => "pedro", "puntaje" => 80},
        %{"usuario" => "ana", "puntaje" => 50},
        %{"usuario" => "bot_1", "puntaje" => 100}
      ]
    }

    assert :ok =
             Persistencia.guardar_resultado(
               resultado,
               context.ruta_historial
             )

    assert {:ok, ranking} =
             GestorJugadores.ranking(
               nil,
               context.servidor
             )

    assert length(ranking) == 2
    assert hd(ranking).usuario == "pedro"
    assert hd(ranking).puntaje == 80

    refute Enum.any?(ranking, &(&1.usuario == "bot_1"))
  end

  test "ranking permite filtrar por tema", context do
    assert {:ok, "pedro"} =
             GestorJugadores.connect(
               "pedro",
               "12345",
               context.servidor
             )

    resultado = %{
      "fecha" => "2026-10-29T20:00:00Z",
      "id" => "P-1001",
      "tema" => "ciencia",
      "nivel" => "basico",
      "ganador" => "pedro",
      "jugadores" => [
        %{"usuario" => "pedro", "puntaje" => 80},
        %{"usuario" => "ana", "puntaje" => 50}
      ]
    }

    assert :ok =
             Persistencia.guardar_resultado(
               resultado,
               context.ruta_historial
             )

    assert {:ok, ranking} =
             GestorJugadores.ranking(
               "ciencia",
               context.servidor
             )

    assert length(ranking) == 2

    assert {:ok, ranking_vacio} =
             GestorJugadores.ranking(
               "historia",
               context.servidor
             )

    assert ranking_vacio == []
  end

  test "no permite consultar estadísticas sin iniciar sesión", context do
    assert {:error, :no_autenticado} =
             GestorJugadores.score(context.servidor)

    assert {:error, :no_autenticado} =
             GestorJugadores.ranking(
               nil,
               context.servidor
             )
  end


  test "identifica el usuario asociado a un PID", context do
    assert {:ok, "pedro"} =
             GestorJugadores.connect(
               "pedro",
               "12345",
               context.servidor
             )

    assert {:ok, "pedro"} =
             GestorJugadores.usuario_por_pid(
               self(),
               context.servidor
             )
  end

  test "rechaza un PID sin sesion autenticada", context do
    pid_inexistente = spawn(fn -> Process.sleep(1000) end)

    assert {:error, :no_autenticado} =
             GestorJugadores.usuario_por_pid(
               pid_inexistente,
               context.servidor
             )

    Process.exit(pid_inexistente, :kill)
  end

end
