
defmodule Trivia.PersistenciaTest do
  use ExUnit.Case, async: true

  alias Trivia.Persistencia

  setup do
    ruta =
      Path.join(
        System.tmp_dir!(),
        "trivia_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(ruta)

    on_exit(fn ->
      File.rm_rf!(ruta)
    end)

    %{
      ruta_usuarios: Path.join(ruta, "users.json"),
      ruta_historial: Path.join(ruta, "results.log")
    }
  end

  test "cargar usuarios devuelve lista vacía si el archivo no existe", context do
    assert {:ok, []} =
             Persistencia.cargar_usuarios(context.ruta_usuarios)
  end

  test "registrar usuario crea el archivo y guarda sus datos", context do
    assert {:ok, usuario} =
             Persistencia.registrar_usuario(
               "pedro",
               "12345",
               context.ruta_usuarios
             )

    assert usuario["usuario"] == "pedro"
    assert usuario["clave"] == "12345"

    assert {:ok, [guardado]} =
             Persistencia.cargar_usuarios(context.ruta_usuarios)

    assert guardado["usuario"] == "pedro"
  end

  test "no permite registrar dos veces el mismo usuario", context do
    assert {:ok, _usuario} =
             Persistencia.registrar_usuario(
               "pedro",
               "12345",
               context.ruta_usuarios
             )

    assert {:error, :usuario_existente} =
             Persistencia.registrar_usuario(
               "pedro",
               "otra_clave",
               context.ruta_usuarios
             )
  end

  test "rechaza usuarios con el prefijo reservado bot_", context do
    assert {:error, :prefijo_reservado} =
             Persistencia.registrar_usuario(
               "bot_pedro",
               "12345",
               context.ruta_usuarios
             )
  end

  test "rechaza datos vacíos al registrar un usuario", context do
    assert {:error, :datos_invalidos} =
             Persistencia.registrar_usuario(
               "",
               "12345",
               context.ruta_usuarios
             )
  end

  test "leer historial devuelve lista vacía si no existe el archivo", context do
    assert {:ok, []} =
             Persistencia.leer_historial(context.ruta_historial)
  end

  test "guardar resultado agrega una línea al historial", context do
    resultado = %{
      "fecha" => "2026-10-29T21:00:00Z",
      "id" => "P-1001",
      "tema" => "ciencia",
      "nivel" => "basico",
      "ganador" => "pedro",
      "jugadores" => [
        %{"usuario" => "pedro", "puntaje" => 48},
        %{"usuario" => "bot_1", "puntaje" => 22},
        %{"usuario" => "bot_2", "puntaje" => -11}
      ]
    }

    assert :ok =
             Persistencia.guardar_resultado(
               resultado,
               context.ruta_historial
             )

    assert {:ok, [linea]} =
             Persistencia.leer_historial(context.ruta_historial)

    assert {:ok, datos} = Jason.decode(linea)
    assert datos["id"] == "P-1001"
    assert datos["tema"] == "ciencia"
    assert length(datos["jugadores"]) == 3
  end

  test "guardar varios resultados conserva las líneas anteriores", context do
    resultado = %{
      "fecha" => "2026-10-29T21:00:00Z",
      "id" => "P-1001",
      "tema" => "ciencia",
      "nivel" => "basico",
      "ganador" => "pedro",
      "jugadores" => [
        %{"usuario" => "pedro", "puntaje" => 48}
      ]
    }

    assert :ok =
             Persistencia.guardar_resultado(
               resultado,
               context.ruta_historial
             )

    segundo_resultado = Map.put(resultado, "id", "P-1002")

    assert :ok =
             Persistencia.guardar_resultado(
               segundo_resultado,
               context.ruta_historial
             )

    assert {:ok, lineas} =
             Persistencia.leer_historial(context.ruta_historial)

    assert length(lineas) == 2
  end

  test "rechaza resultados sin los campos obligatorios", context do
    assert {:error, :resultado_invalido} =
             Persistencia.guardar_resultado(
               %{"tema" => "ciencia"},
               context.ruta_historial
             )
  end
end
