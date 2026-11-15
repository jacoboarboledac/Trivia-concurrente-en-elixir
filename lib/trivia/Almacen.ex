defmodule Trivia.Almacen do
  @moduledoc """
  Proceso central de acceso a los archivos persistentes del servidor.
  Serializa las escrituras y permite consultas consistentes.
  """
  use GenServer

  alias Trivia.Persistencia

  def start_link(opciones \\ []) do
    nombre = Keyword.get(opciones, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, name: nombre)
  end

  @impl true
  def init(:ok), do: {:ok, %{}}

  def cargar_usuarios(ruta \\ "data/users.json", servidor \\ __MODULE__) do
    GenServer.call(servidor, {:cargar_usuarios, ruta})
  end

  def registrar_usuario(usuario, clave, ruta \\ "data/users.json", servidor \\ __MODULE__) do
    GenServer.call(servidor, {:registrar_usuario, usuario, clave, ruta})
  end

  def leer_historial(ruta \\ "data/results.log", servidor \\ __MODULE__) do
    GenServer.call(servidor, {:leer_historial, ruta})
  end

  def guardar_resultado(resultado, ruta \\ "data/results.log", servidor \\ __MODULE__) do
    GenServer.call(servidor, {:guardar_resultado, resultado, ruta})
  end

  @impl true
  def handle_call({:cargar_usuarios, ruta}, _from, estado) do
    {:reply, Persistencia.cargar_usuarios(ruta), estado}
  end

  def handle_call({:registrar_usuario, usuario, clave, ruta}, _from, estado) do
    {:reply, Persistencia.registrar_usuario(usuario, clave, ruta), estado}
  end

  def handle_call({:leer_historial, ruta}, _from, estado) do
    {:reply, Persistencia.leer_historial(ruta), estado}
  end

  def handle_call({:guardar_resultado, resultado, ruta}, _from, estado) do
    {:reply, Persistencia.guardar_resultado(resultado, ruta), estado}
  end
end
