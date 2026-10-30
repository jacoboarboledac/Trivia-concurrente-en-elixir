
defmodule Trivia.GestorPartidasTest do
  use ExUnit.Case, async: false

  alias Trivia.GestorPartidas


  setup do
    sufijo = System.unique_integer([:positive])

    nombre_supervisor =
      String.to_atom("supervisor_partidas_#{sufijo}")

    nombre_gestor =
      String.to_atom("gestor_partidas_#{sufijo}")

    supervisor =
      start_supervised!(
        {Trivia.SupervisorPartidas,
         name: nombre_supervisor}
      )

      start_supervised!(
        {Trivia.GestorPartidas,
         [
           name: nombre_gestor,
           supervisor: nombre_supervisor
         ]}
      )

    %{
      supervisor: supervisor,
      gestor: nombre_gestor
    }
  end


  test "crea una partida correctamente", context do
    opciones = [
      creador: "pedro",
      cliente: self(),
      tema: "ciencia",
      numero_preguntas: 5,
      tiempo_por_pregunta: 20
    ]

    assert {:ok, "P-1001", pid} =
             GestorPartidas.crear_partida(
               opciones,
               context.gestor
             )

    assert Process.alive?(pid)
  end

  test "asigna identificadores diferentes a varias partidas", context do
    opciones_1 = [
      creador: "pedro",
      cliente: self(),
      tema: "ciencia",
      numero_preguntas: 5,
      tiempo_por_pregunta: 20
    ]

    opciones_2 = [
      creador: "ana",
      cliente: self(),
      tema: "historia",
      numero_preguntas: 10,
      tiempo_por_pregunta: 30
    ]

    assert {:ok, "P-1001", pid_1} =
             GestorPartidas.crear_partida(
               opciones_1,
               context.gestor
             )

    assert {:ok, "P-1002", pid_2} =
             GestorPartidas.crear_partida(
               opciones_2,
               context.gestor
             )

    assert pid_1 != pid_2
    assert Process.alive?(pid_1)
    assert Process.alive?(pid_2)
  end

  test "cada partida mantiene su propio estado", context do
    opciones_1 = [
      creador: "pedro",
      cliente: self(),
      tema: "ciencia",
      numero_preguntas: 5,
      tiempo_por_pregunta: 20
    ]

    opciones_2 = [
      creador: "ana",
      cliente: self(),
      tema: "historia",
      numero_preguntas: 10,
      tiempo_por_pregunta: 30
    ]

    assert {:ok, _id_1, pid_1} =
             GestorPartidas.crear_partida(
               opciones_1,
               context.gestor
             )

    assert {:ok, _id_2, pid_2} =
             GestorPartidas.crear_partida(
               opciones_2,
               context.gestor
             )

    estado_1 = :sys.get_state(pid_1)
    estado_2 = :sys.get_state(pid_2)

    assert estado_1.tema == "ciencia"
    assert estado_2.tema == "historia"

    assert estado_1.numero_preguntas == 5
    assert estado_2.numero_preguntas == 10
  end


  test "reinicia una partida sin afectar las demas", context do
    opciones_pedro = [
      creador: "pedro",
      cliente: self(),
      tema: "ciencia",
      numero_preguntas: 5,
      tiempo_por_pregunta: 20
    ]

    opciones_ana = [
      creador: "ana",
      cliente: self(),
      tema: "historia",
      numero_preguntas: 10,
      tiempo_por_pregunta: 30
    ]

    assert {:ok, id_pedro, pid_pedro} =
             GestorPartidas.crear_partida(
               opciones_pedro,
               context.gestor
             )

    assert {:ok, _id_ana, pid_ana} =
             GestorPartidas.crear_partida(
               opciones_ana,
               context.gestor
             )

    # Esperamos a que ambas partidas estén registradas.
    assert_eventualmente_registrada(
      id_pedro,
      pid_pedro,
      context.gestor
    )

    # Provocamos una caída anormal.
    Process.exit(pid_pedro, :kill)

    # Esperamos el registro del nuevo proceso.
    nueva_partida =
      esperar_reinicio(
        id_pedro,
        pid_pedro,
        context.gestor,
        30
      )

    assert is_pid(nueva_partida)
    assert nueva_partida != pid_pedro
    assert Process.alive?(nueva_partida)

    # Ana debe continuar en su partida original.
    assert Process.alive?(pid_ana)

    assert_receive {:partida_reiniciada, ^id_pedro}, 2000
  end

  defp assert_eventualmente_registrada(id, pid, gestor) do
    assert esperar_reinicio(id, nil, gestor, 30) == pid
  end

  defp esperar_reinicio(_id, _pid_anterior, _gestor, 0) do
    flunk("La partida no se registro o reinicio a tiempo")
  end

  defp esperar_reinicio(id, pid_anterior, gestor, intentos) do
    partidas = GestorPartidas.listar_partidas(gestor)

    case Map.get(partidas, id) do
      %{pid: pid}
      when is_pid(pid) and pid != pid_anterior ->
        pid

      _ ->
        Process.sleep(100)

        esperar_reinicio(
          id,
          pid_anterior,
          gestor,
          intentos - 1
        )
    end
  end

end
