defmodule UtilTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  test "leer/2 obtiene una cadena y elimina espacios exteriores" do
    capture_io("  Hola, mundo  \n", fn ->
      assert Util.leer("Texto: ", :string) == "Hola, mundo"
    end)
  end

  test "leer/2 convierte una entrada a entero" do
    capture_io("42\n", fn ->
      assert Util.leer("Número: ", :integer) == 42
    end)
  end

  test "leer/2 convierte una entrada a decimal" do
    capture_io("3.5\n", fn ->
      assert Util.leer("Decimal: ", :float) == 3.5
    end)
  end

  test "imprimir_mensaje/1 escribe en la salida estándar" do
    salida = capture_io(fn -> Util.imprimir_mensaje("Mensaje de prueba") end)
    assert salida == "Mensaje de prueba\n"
  end

  test "imprimir_error/1 escribe en la salida de error" do
    salida = capture_io(:stderr, fn -> Util.imprimir_error("Error de prueba") end)
    assert salida == "Error de prueba\n"
  end
end
