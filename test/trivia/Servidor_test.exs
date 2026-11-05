
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

    servidor =
      start_supervised!(
        {Trivia.Servidor,
         [
           name: nombre_servidor,
           gestor_jugadores: nombre_gestor
         ]}
      )

    on_exit(fn ->
      File.rm_rf!(carpeta)
    end)

    %{
      gestor: nombre_gestor,
      servidor: nombre_servidor,
      pid_servidor: servidor,
      pid_gestor: gestor
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
end
