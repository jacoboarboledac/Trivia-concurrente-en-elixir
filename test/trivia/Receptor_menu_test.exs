defmodule Trivia.ReceptorMenuTest do
  use ExUnit.Case, async: false

  alias Trivia.Receptor

  defmodule ServidorFalso do
    use GenServer

    def start_link(_opciones), do: GenServer.start_link(__MODULE__, %{})

    @impl true
    def init(estado), do: {:ok, estado}

    @impl true
    def handle_call({:connect, nombre, _clave}, _from, estado) do
      {:reply, {:ok, nombre}, estado}
    end

    def handle_call({:create_game, _tema, _cantidad, _tiempo}, _from, estado) do
      {:reply, {:ok, "P-PRUEBA", :basico}, estado}
    end

    def handle_call(:start_game, _from, estado) do
      {:reply, {:ok, :basico}, estado}
    end

    def handle_call({:answer, "B"}, _from, estado) do
      {:reply, {:ok, 15}, estado}
    end

    def handle_call(:disconnect, _from, estado) do
      {:reply, :ok, estado}
    end
  end

  test "una pregunta se puede responder por el receptor y queda cerrada" do
    servidor = start_supervised!(ServidorFalso)
    receptor = start_supervised!({Receptor, [servidor: servidor]})

    assert {:ok, "pedro"} = Receptor.solicitar(receptor, {:connect, "pedro", "1234"})
    assert {:ok, "P-PRUEBA", :basico} =
             Receptor.solicitar(receptor, {:create_game, "ciencia", 1, 15})

    assert {:ok, :basico} = Receptor.solicitar(receptor, :start_game)

    pregunta = %{
      "enunciado" => "¿Cuánto es 2 + 2?",
      "opciones" => ["2", "4", "6", "8"],
      "nivel" => :basico
    }

    send(receptor, {:nueva_pregunta, "P-PRUEBA", 1, 1, pregunta, 15})
    vista = Receptor.estado_cliente(receptor)
    assert vista.usuario == "pedro"
    assert vista.pregunta.numero == 1
    assert vista.fase == :en_curso

    assert {:ok, 15} = Receptor.solicitar(receptor, {:answer, "B"})
    assert Receptor.estado_cliente(receptor).pregunta == nil

    send(receptor, {:partida_finalizada, "P-PRUEBA", [%{usuario: "pedro", puntaje: 15}], ["pedro"]})
    assert Receptor.estado_cliente(receptor).fase == :sin_partida
    assert Receptor.estado_cliente(receptor).partida_id == nil
  end

  test "omitir una pregunta no envía ninguna respuesta" do
    servidor = start_supervised!(ServidorFalso)
    receptor = start_supervised!({Receptor, [servidor: servidor]})

    pregunta = %{
      "enunciado" => "Pregunta de prueba",
      "opciones" => ["Uno", "Dos", "Tres", "Cuatro"],
      "nivel" => :basico
    }

    send(receptor, {:nueva_pregunta, "P-1", 1, 1, pregunta, 5})
    assert Receptor.estado_cliente(receptor).pregunta.numero == 1
    assert :ok = Receptor.omitir_pregunta(receptor)
    assert Receptor.estado_cliente(receptor).pregunta == nil
    assert Process.alive?(receptor)
  end
end
