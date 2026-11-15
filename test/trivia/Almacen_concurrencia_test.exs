defmodule Trivia.AlmacenConcurrenciaTest do
  use ExUnit.Case, async: false

  alias Trivia.Almacen

  setup do
    sufijo = System.unique_integer([:positive])
    carpeta = Path.join(System.tmp_dir!(), "trivia_almacen_#{sufijo}")
    File.mkdir_p!(carpeta)

    nombre = String.to_atom("almacen_test_#{sufijo}")
    start_supervised!({Almacen, name: nombre})

    on_exit(fn -> File.rm_rf!(carpeta) end)

    %{
      almacen: nombre,
      usuarios: Path.join(carpeta, "users.json"),
      historial: Path.join(carpeta, "results.log")
    }
  end

  test "30 resultados simultaneos se guardan en 30 lineas validas", contexto do
    respuestas =
      1..30
      |> Task.async_stream(
        fn numero ->
          resultado = %{
            "fecha" => "2026-11-08T00:00:00Z",
            "id" => "P-#{numero}",
            "tema" => "ciencia",
            "nivel" => "basico",
            "ganador" => "jugador_#{numero}",
            "jugadores" => [
              %{"usuario" => "jugador_#{numero}", "puntaje" => numero}
            ]
          }

          Almacen.guardar_resultado(resultado, contexto.historial, contexto.almacen)
        end,
        max_concurrency: 10,
        timeout: 10_000
      )
      |> Enum.to_list()

    assert Enum.all?(respuestas, &(&1 == {:ok, :ok}))
    assert {:ok, lineas} = Almacen.leer_historial(contexto.historial, contexto.almacen)
    assert length(lineas) == 30

    ids =
      Enum.map(lineas, fn linea ->
        assert {:ok, resultado} = Jason.decode(linea)
        resultado["id"]
      end)

    assert length(Enum.uniq(ids)) == 30
  end

  test "20 registros simultaneos conservan todos los usuarios", contexto do
    respuestas =
      1..20
      |> Task.async_stream(
        fn numero ->
          Almacen.registrar_usuario(
            "jugador_#{numero}", "clave", contexto.usuarios, contexto.almacen
          )
        end,
        max_concurrency: 10,
        timeout: 10_000
      )
      |> Enum.to_list()

    assert Enum.all?(respuestas, fn
      {:ok, {:ok, %{"usuario" => _usuario}}} -> true
      _ -> false
    end)

    assert {:ok, usuarios} = Almacen.cargar_usuarios(contexto.usuarios, contexto.almacen)
    assert length(usuarios) == 20
    assert length(Enum.uniq(Enum.map(usuarios, & &1["usuario"]))) == 20
  end
end
