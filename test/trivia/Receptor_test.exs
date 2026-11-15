
defmodule Trivia.ReceptorTest do
  use ExUnit.Case, async: false

  alias Trivia.Receptor

  defmodule ServidorFalso do
    use GenServer

    def start_link(_opciones) do
      GenServer.start_link(__MODULE__, %{})
    end

    @impl true
    def init(estado), do: {:ok, estado}

    @impl true
    def handle_call(:identificar, {pid, _ref}, estado) do
      {:reply, pid, estado}
    end
  end

  test "el servidor identifica el PID del receptor" do
    servidor = start_supervised!(ServidorFalso)

    receptor =
      start_supervised!({
        Receptor,
        [servidor: servidor]
      })

    assert Receptor.solicitar(receptor, :identificar) ==
             receptor

    send(receptor, {:resultado_guardado, "P-1001"})

    assert is_map(:sys.get_state(receptor))
    assert Process.alive?(receptor)
  end
end
