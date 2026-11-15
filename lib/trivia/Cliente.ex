defmodule Trivia.Cliente do
  @moduledoc """
  Menús interactivos de la Trivia. No requiere introducir comandos de juego.
  La entrada se lee en este proceso; Trivia.Receptor recibe los avisos en otro.
  """
  alias Trivia.Receptor

  @temas [
    {"1", "ciencia", "Ciencia"},
    {"2", "historia", "Historia"},
    {"3", "geografia", "Geografía"},
    {"4", "tecnologia", "Tecnología"}
  ]

  # Mantiene compatibilidad con Trivia.Cliente.iniciar() en los nodos existentes.
  def iniciar(nodo_servidor \\ nodo_local_servidor()) do
    cond do
      not Node.alive?() ->
        {:error, :nodo_no_distribuido}

      is_nil(nodo_servidor) or Node.connect(nodo_servidor) != true ->
        {:error, :servidor_no_disponible}

      true ->
        case Receptor.start_link(servidor: {Trivia.Servidor, nodo_servidor}) do
          {:ok, receptor} ->
            try do
              encabezado("BIENVENIDO A TRIVIA CONCURRENTE")
              bucle(receptor)
            after
              if Process.alive?(receptor), do: GenServer.stop(receptor, :normal)
            end

          {:error, motivo} ->
            {:error, motivo}
        end
    end
  end

  # Deducir el nombre del servidor usando el host del nodo local.
  defp nodo_local_servidor do
    case String.split(Atom.to_string(Node.self()), "@", parts: 2) do
      [_, host] -> String.to_atom("servidor@" <> host)
      _ -> nil
    end
  end

  defp bucle(receptor) do
    estado = Receptor.estado_cliente(receptor)

    cond do
      estado.pregunta != nil -> menu_respuesta(receptor, estado.pregunta)
      estado.usuario == nil -> menu_bienvenida(receptor)
      estado.fase == :esperando -> menu_preparacion(receptor, estado)
      estado.fase == :en_curso -> menu_juego(receptor, estado)
      true -> menu_principal(receptor, estado)
    end
  end

  # INICIO DE SESIÓN (connect también registra usuarios nuevos).

  defp menu_bienvenida(receptor) do
    encabezado("ACCESO AL JUEGO")
    IO.puts("1) Iniciar sesión o registrarme")
    IO.puts("0) Salir")

    case leer("Selecciona una opción: ") do
      "1" ->
        usuario = leer("Nombre de usuario: ")
        clave = leer("Contraseña: ")

        if is_binary(usuario) and is_binary(clave) and usuario != "" and clave != "" do
          respuesta = Receptor.solicitar(receptor, {:connect, usuario, clave})
          mostrar_resultado(respuesta)
        else
          IO.puts("Debes introducir un usuario y una contraseña.")
        end

        bucle(receptor)

      "0" ->
        IO.puts("Hasta pronto.")
        :ok

      :eof ->
        :ok

      _ ->
        opcion_invalida()
        bucle(receptor)
    end
  end

  # MENÚ DEL JUGADOR CONECTADO

  defp menu_principal(receptor, estado) do
    encabezado("MENÚ PRINCIPAL | #{estado.usuario}")
    IO.puts("1) Crear nueva partida")
    IO.puts("2) Ver mis estadísticas")
    IO.puts("3) Ver ranking global")
    IO.puts("4) Ver ranking por tema")
    IO.puts("5) Cerrar sesión")
    IO.puts("0) Salir del juego")
    ejecutar_menu(receptor, :principal, leer("Elige una opción: "))
  end

  # MENÚ DE PARTIDA EN PREPARACIÓN

  defp menu_preparacion(receptor, estado) do
    encabezado("PREPARAR PARTIDA #{estado.partida_id}")
    IO.puts("1) Agregar bot fácil")
    IO.puts("2) Agregar bot difícil")
    IO.puts("3) Iniciar la partida")
    IO.puts("4) Cancelar la partida")
    IO.puts("5) Ver mis estadísticas")
    IO.puts("6) Ver ranking global")
    IO.puts("7) Cerrar sesión")
    IO.puts("0) Salir")
    ejecutar_menu(receptor, :preparacion, leer("Elige una opción: "))
  end

  # MENÚ DURANTE LAS PAUSAS ENTRE RONDAS

  defp menu_juego(receptor, _estado) do
    IO.puts("\nEsperando las respuestas de los demás jugadores...")
    esperar_siguiente_ronda(receptor)
  end

  defp esperar_siguiente_ronda(receptor) do
    estado = Receptor.estado_cliente(receptor)

    cond do
      # Llegó una nueva pregunta
      estado.pregunta != nil ->
        menu_respuesta(receptor, estado.pregunta)

      # La partida sigue esperando a los demás
      estado.fase == :en_curso ->
        Process.sleep(100)
        esperar_siguiente_ronda(receptor)

      # La partida terminó o fue cancelada
      true ->
        bucle(receptor)
    end
  end

  # CUANDO LLEGA UNA PREGUNTA, 1..4 CORRESPONDEN A A..D.

  defp menu_respuesta(receptor, pregunta) do
    IO.puts("\nPregunta #{pregunta.numero}/#{pregunta.total}")
    IO.puts("1) Responder A")
    IO.puts("2) Responder B")
    IO.puts("3) Responder C")
    IO.puts("4) Responder D")
    IO.puts("5) No responder (esperar a que termine el tiempo)")
    IO.puts("0) Salir del juego")

    opcion = leer("Tu respuesta (1-4): ")
    actual = Receptor.estado_cliente(receptor)

    cond do
      opcion in [:eof, "0"] ->
        salir(receptor)

      not misma_pregunta?(actual.pregunta, pregunta) ->
        IO.puts("La pregunta ya se cerró; no se enviará una respuesta tardía.")
        bucle(receptor)

      opcion in ["1", "2", "3", "4"] ->
        responder_numero(receptor, opcion)
        bucle(receptor)

      opcion == "5" ->
        :ok = Receptor.omitir_pregunta(receptor)
        IO.puts("No se enviará respuesta en esta ronda; al vencer el tiempo obtendrás 0 puntos.")
        bucle(receptor)

      true ->
        opcion_invalida()
        bucle(receptor)
    end
  end

  defp misma_pregunta?(nil, _), do: false
  defp misma_pregunta?(a, b), do: a.id == b.id and a.numero == b.numero

  # Si llega una pregunta mientras se elegía una opción de otro menú,
  # damos prioridad a la pregunta para evitar respuestas accidentales.
  defp ejecutar_menu(receptor, fase, opcion) do
    actual = Receptor.estado_cliente(receptor)

    cond do
      opcion in [:eof, "0"] ->
        salir(receptor)

      actual.pregunta != nil ->
        IO.puts("Llegó una pregunta mientras elegías. Selecciona ahora su respuesta.")
        bucle(receptor)

      # Cambió la fase de la partida antes de que se eligiera la opción.
      actual.usuario != nil and actual.fase != fase_a_estado(fase) ->
        IO.puts("El estado de la partida cambió. Se actualizó el menú.")
        bucle(receptor)

      true ->
        realizar_accion(receptor, fase, opcion)
        bucle(receptor)
    end
  end

  defp fase_a_estado(:principal), do: :sin_partida
  defp fase_a_estado(:preparacion), do: :esperando
  defp fase_a_estado(:juego), do: :en_curso

  defp realizar_accion(receptor, :principal, "1"), do: crear_partida(receptor)
  defp realizar_accion(receptor, :principal, "2"), do: solicitar_y_mostrar(receptor, :score)

  defp realizar_accion(receptor, :principal, "3"),
    do: solicitar_y_mostrar(receptor, {:ranking, nil})

  defp realizar_accion(receptor, :principal, "4"), do: ranking_tema(receptor)
  defp realizar_accion(receptor, :principal, "5"), do: solicitar_y_mostrar(receptor, :disconnect)

  defp realizar_accion(receptor, :preparacion, "1"),
    do: solicitar_y_mostrar(receptor, {:add_bot, :facil})

  defp realizar_accion(receptor, :preparacion, "2"),
    do: solicitar_y_mostrar(receptor, {:add_bot, :dificil})

  defp realizar_accion(receptor, :preparacion, "3"),
    do: solicitar_y_mostrar(receptor, :start_game)

  defp realizar_accion(receptor, :preparacion, "4"),
    do: solicitar_y_mostrar(receptor, :leave_game)

  defp realizar_accion(receptor, :preparacion, "5"), do: solicitar_y_mostrar(receptor, :score)

  defp realizar_accion(receptor, :preparacion, "6"),
    do: solicitar_y_mostrar(receptor, {:ranking, nil})

  defp realizar_accion(receptor, :preparacion, "7"),
    do: solicitar_y_mostrar(receptor, :disconnect)

  defp realizar_accion(receptor, :juego, "1"), do: solicitar_y_mostrar(receptor, :score)
  defp realizar_accion(receptor, :juego, "2"), do: solicitar_y_mostrar(receptor, {:ranking, nil})
  defp realizar_accion(receptor, :juego, "3"), do: abandonar_con_confirmacion(receptor)
  defp realizar_accion(receptor, :juego, "4"), do: solicitar_y_mostrar(receptor, :disconnect)

  defp realizar_accion(_receptor, _fase, _opcion), do: opcion_invalida()

  defp crear_partida(receptor) do
    encabezado("CREAR PARTIDA")

    with {:ok, tema} <- elegir_tema(),
         {:ok, cantidad} <- pedir_entero("Número de preguntas (1-10, 0 para volver): ", 1, 10),
         {:ok, tiempo} <- pedir_entero("Segundos por pregunta (1-3600, 0 para volver): ", 1, 3600) do
      solicitar_y_mostrar(receptor, {:create_game, tema, cantidad, tiempo})
    else
      :cancelado -> IO.puts("Creación cancelada.")
    end
  end

  defp elegir_tema do
    IO.puts("Selecciona el tema:")

    Enum.each(@temas, fn {numero, _tema, titulo} ->
      IO.puts("#{numero}) #{titulo}")
    end)

    IO.puts("5) Escribir otro tema")
    IO.puts("0) Volver")

    case leer("Tema: ") do
      :eof ->
        :cancelado

      "0" ->
        :cancelado

      "5" ->
        tema = leer("Identificador del tema (minúsculas, sin espacios): ")

        if is_binary(tema) and Regex.match?(~r/^[a-z0-9_]+$/, tema) do
          {:ok, tema}
        else
          IO.puts("Tema inválido.")
          elegir_tema()
        end

      opcion ->
        case Enum.find(@temas, fn {numero, _, _} -> numero == opcion end) do
          {_, tema, _} ->
            {:ok, tema}

          nil ->
            opcion_invalida()
            elegir_tema()
        end
    end
  end

  defp ranking_tema(receptor) do
    case elegir_tema() do
      {:ok, tema} -> solicitar_y_mostrar(receptor, {:ranking, tema})
      :cancelado -> :ok
    end
  end

  defp pedir_entero(mensaje, minimo, maximo) do
    case leer(mensaje) do
      :eof ->
        :cancelado

      "0" ->
        :cancelado

      valor ->
        case Integer.parse(valor) do
          {numero, ""} when numero >= minimo and numero <= maximo ->
            {:ok, numero}

          _ ->
            IO.puts("Escribe un número entre #{minimo} y #{maximo}, o 0 para volver.")
            pedir_entero(mensaje, minimo, maximo)
        end
    end
  end

  defp abandonar_con_confirmacion(receptor) do
    IO.puts("Si abandonas, se conservará el puntaje obtenido hasta ahora.")

    if leer("¿Seguro que quieres abandonar? (s/n): ") in ["s", "S"] do
      solicitar_y_mostrar(receptor, :leave_game)
    else
      IO.puts("Sigues en tu partida.")
    end
  end

  defp responder_numero(receptor, numero) do
    letra = Enum.at(["A", "B", "C", "D"], String.to_integer(numero) - 1)
    solicitar_y_mostrar(receptor, {:answer, letra})
  end

  defp solicitar_y_mostrar(receptor, peticion) do
    Receptor.solicitar(receptor, peticion)
    |> mostrar_resultado()
  end

  defp mostrar_resultado({:ok, usuario}) when is_binary(usuario) do
    IO.puts("Sesión iniciada: #{usuario}.")
  end

  defp mostrar_resultado({:ok, nombre, pid})
       when is_binary(nombre) and is_pid(pid) do
    IO.puts("Se agregó #{nombre} correctamente.")
  end

  defp mostrar_resultado({:ok, id, nivel})
       when is_binary(id) and is_atom(nivel) do
    IO.puts("Partida #{id} creada. Tu nivel es #{nivel}.")
    IO.puts("Agrega por lo menos dos bots para comenzar.")
  end

  defp mostrar_resultado({:ok, nivel}) when is_atom(nivel) do
    IO.puts("¡Partida iniciada! Nivel: #{nivel}. Espera la pregunta.")
  end

  defp mostrar_resultado({:ok, puntos}) when is_integer(puntos) do
    IO.puts("Respuesta enviada. Puntaje de la respuesta: #{puntos}.")
  end

  defp mostrar_resultado(
         {:ok, %{usuario: usuario, puntaje: puntos, partidas: partidas, temas: temas}}
       ) do
    encabezado("ESTADÍSTICAS DE #{usuario}")
    IO.puts("Puntaje acumulado: #{puntos}")
    IO.puts("Partidas jugadas: #{partidas}")

    Enum.each(temas, fn tema ->
      IO.puts("- #{tema.tema}: #{tema.puntaje} puntos | nivel #{tema.nivel}")
    end)
  end

  defp mostrar_resultado({:ok, ranking}) when is_list(ranking) do
    encabezado("RANKING HISTÓRICO")

    if ranking == [] do
      IO.puts("Todavía no hay resultados.")
    else
      ranking
      |> Enum.with_index(1)
      |> Enum.each(fn {jugador, posicion} ->
        IO.puts(
          "#{posicion}. #{jugador.usuario} | #{jugador.puntaje} puntos | #{jugador.partidas} partidas"
        )
      end)
    end
  end

  defp mostrar_resultado(:ok), do: IO.puts("Operación realizada correctamente.")

  defp mostrar_resultado({:error, motivo}) do
    IO.puts("No se pudo realizar la operación: #{texto_error(motivo)}")
  end

  defp mostrar_resultado(otro), do: IO.puts("Resultado: #{inspect(otro)}")

  defp texto_error(:no_autenticado), do: "debes iniciar sesión"
  defp texto_error(:servidor_no_disponible), do: "servidor no disponible"
  defp texto_error(:clave_incorrecta), do: "contraseña incorrecta"
  defp texto_error(:sesion_activa), do: "el usuario ya inició sesión en otro cliente"
  defp texto_error(:prefijo_reservado), do: "ese nombre está reservado para bots"
  defp texto_error(:jugador_en_partida), do: "ya tienes una partida"
  defp texto_error(:sin_partida), do: "no estás en una partida"
  defp texto_error(:jugadores_insuficientes), do: "necesitas al menos dos bots"
  defp texto_error(:partida_llena), do: "la partida ya tiene cuatro jugadores"
  defp texto_error(:partida_iniciada), do: "la partida ya comenzó"
  defp texto_error(:partida_ya_iniciada), do: "la partida ya comenzó"
  defp texto_error(:ronda_no_abierta), do: "la ronda ya terminó o todavía no inició"
  defp texto_error(:respuesta_duplicada), do: "ya respondiste esta pregunta"
  defp texto_error(:respuesta_invalida), do: "debes seleccionar una opción válida"
  defp texto_error(:tema_inexistente), do: "ese tema no está en el banco de preguntas"
  defp texto_error(:partida_no_encontrada), do: "la partida ya no existe"

  defp texto_error({:preguntas_insuficientes, _, _, _}),
    do: "no hay preguntas suficientes en ese tema"

  defp texto_error(motivo), do: inspect(motivo)

  defp encabezado(texto) do
    IO.puts("\n" <> String.duplicate("=", 52))
    IO.puts("  #{texto}")
    IO.puts(String.duplicate("=", 52))
  end

  defp opcion_invalida do
    IO.puts("Opción inválida. Selecciona uno de los números del menú.")
  end

  defp leer(mensaje) do
    case IO.gets(mensaje) do
      valor when is_binary(valor) -> String.trim(valor)
      _ -> :eof
    end
  end

  defp salir(receptor) do
    if Receptor.estado_cliente(receptor).usuario != nil do
      Receptor.solicitar(receptor, :disconnect)
    end

    IO.puts("Gracias por jugar. ¡Hasta luego!")
    :ok
  end
end
