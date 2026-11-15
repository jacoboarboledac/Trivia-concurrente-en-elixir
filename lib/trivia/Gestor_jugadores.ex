defmodule Trivia.GestorJugadores do
  use GenServer

  @moduledoc """
  Administra los usuarios, las sesiones y las consultas
  de estadísticas y ranking.
  """

  alias Trivia.Persistencia
  alias Trivia.Nivel

  # -------------------------
  # INICIO DEL SERVIDOR
  # -------------------------

  def start_link(opciones \\ []) do
    nombre = Keyword.get(opciones, :name, __MODULE__)

    GenServer.start_link(
      __MODULE__,
      opciones,
      name: nombre
    )
  end

  @impl true
  def init(opciones) do
    ruta_usuarios =
      Keyword.get(opciones, :ruta_usuarios, "data/users.json")

    ruta_historial =
      Keyword.get(opciones, :ruta_historial, "data/results.log")

    almacen = Keyword.get(opciones, :almacen, Persistencia)

    case almacen.cargar_usuarios(ruta_usuarios) do
      {:ok, usuarios} ->
        {:ok,
         %{
           usuarios: usuarios,
           sesiones: %{},
           monitores: %{},
           ruta_usuarios: ruta_usuarios,
           ruta_historial: ruta_historial,
           almacen: almacen
         }}

      {:error, motivo} ->
        {:stop, motivo}
    end
  end

  # -------------------------
  # FUNCIONES PARA LOS CLIENTES
  # -------------------------

  def connect(usuario, clave, servidor \\ __MODULE__) do
    GenServer.call(
      servidor,
      {:connect, usuario, clave, self()}
    )
  end


  def connect(usuario, clave, pid_cliente, servidor) do
    GenServer.call(servidor, {:connect, usuario, clave, pid_cliente})
  end


  def disconnect(servidor \\ __MODULE__) do
    GenServer.call(
      servidor,
      {:disconnect, self()}
    )
  end

  def score(servidor \\ __MODULE__) do
    GenServer.call(
      servidor,
      {:score, self()}
    )
  end

  def ranking(tema \\ nil, servidor \\ __MODULE__) do
    GenServer.call(
      servidor,
      {:ranking, tema, self()}
    )
  end


  # Versiones para peticiones enviadas por Trivia.Servidor.
  # Usan el PID real del cliente/receptor, no el del servidor.

  def disconnect(pid_cliente, servidor) when is_pid(pid_cliente) do
    GenServer.call(servidor, {:disconnect, pid_cliente})
  end

  def score(pid_cliente, servidor) when is_pid(pid_cliente) do
    GenServer.call(servidor, {:score, pid_cliente})
  end

  def ranking(tema, pid_cliente, servidor) when is_pid(pid_cliente) do
    GenServer.call(servidor, {:ranking, tema, pid_cliente})
  end

  def usuario_por_pid(pid_cliente, servidor \\ __MODULE__) do
    GenServer.call(
      servidor,
      {:usuario_por_pid, pid_cliente}
    )
  end


  # -------------------------
  # CONEXIÓN Y SESIONES
  # -------------------------

  @impl true
  def handle_call(
        {:connect, usuario, clave, pid},
        _from,
        estado
      ) do
    cond do
      not datos_validos?(usuario, clave) ->
        {:reply, {:error, :datos_invalidos}, estado}

      String.starts_with?(usuario, "bot_") ->
        {:reply, {:error, :prefijo_reservado}, estado}

      true ->
        conectar_usuario(usuario, clave, pid, estado)
    end
  end

  def handle_call(
        {:disconnect, pid},
        _from,
        estado
      ) do
    case buscar_sesion(pid, estado.sesiones) do
      nil ->
        {:reply, {:error, :sesion_no_encontrada}, estado}

      usuario ->
        ref =
          Enum.find_value(estado.monitores, fn {referencia, nombre} ->
            if nombre == usuario, do: referencia
          end)

        if ref do
          Process.demonitor(ref, [:flush])
        end

        nuevo_estado = %{
          estado
          | sesiones: Map.delete(estado.sesiones, usuario),
            monitores: Map.delete(estado.monitores, ref)
        }

        {:reply, :ok, nuevo_estado}
    end
  end

  def handle_call(
        {:score, pid},
        _from,
        estado
      ) do
    case buscar_sesion(pid, estado.sesiones) do
      nil ->
        {:reply, {:error, :no_autenticado}, estado}

      usuario ->
        respuesta =
          calcular_score(
            usuario,
            estado.ruta_historial,
            estado.almacen
          )

        {:reply, respuesta, estado}
    end
  end

  def handle_call(
        {:ranking, tema, pid},
        _from,
        estado
      ) do
    cond do
      is_nil(buscar_sesion(pid, estado.sesiones)) ->
        {:reply, {:error, :no_autenticado}, estado}

      not (is_nil(tema) or is_binary(tema)) ->
        {:reply, {:error, :tema_invalido}, estado}

      true ->
        respuesta =
          calcular_ranking(tema, estado.ruta_historial, estado.almacen)

        {:reply, respuesta, estado}
    end
  end


  def handle_call(
        {:usuario_por_pid, pid_cliente},
        _from,
        estado
      ) do
    respuesta =
      case buscar_sesion(pid_cliente, estado.sesiones) do
        nil ->
          {:error, :no_autenticado}

        usuario ->
          {:ok, usuario}
      end

    {:reply, respuesta, estado}
  end


  # -------------------------
  # DETECTAR CLIENTES DESCONECTADOS
  # -------------------------

  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, _motivo},
        estado
      ) do
    case Map.pop(estado.monitores, ref) do
      {nil, _monitores} ->
        {:noreply, estado}

      {usuario, monitores} ->
        nuevo_estado = %{
          estado
          | sesiones: Map.delete(estado.sesiones, usuario),
            monitores: monitores
        }

        {:noreply, nuevo_estado}
    end
  end

  # -------------------------
  # REGISTRAR O CONECTAR USUARIO
  # -------------------------

  defp conectar_usuario(usuario, clave, pid, estado) do
    usuario_guardado =
      Enum.find(estado.usuarios, fn registrado ->
        registrado["usuario"] == usuario
      end)

    case usuario_guardado do
      nil ->
        registrar_y_conectar(usuario, clave, pid, estado)

      registrado ->
        cond do
          registrado["clave"] != clave ->
            {:reply, {:error, :clave_incorrecta}, estado}

          Map.has_key?(estado.sesiones, usuario) ->
            {:reply, {:error, :sesion_activa}, estado}

          true ->
            abrir_sesion(usuario, pid, estado)
        end
    end
  end

  defp registrar_y_conectar(usuario, clave, pid, estado) do
    almacen = estado.almacen

    case almacen.registrar_usuario(
           usuario,
           clave,
           estado.ruta_usuarios
         ) do
      {:ok, nuevo_usuario} ->
        nuevo_estado = %{
          estado
          | usuarios: estado.usuarios ++ [nuevo_usuario]
        }

        abrir_sesion(usuario, pid, nuevo_estado)

      {:error, motivo} ->
        {:reply, {:error, motivo}, estado}
    end
  end

  defp abrir_sesion(usuario, pid, estado) do
    ref = Process.monitor(pid)

    nuevo_estado = %{
      estado
      | sesiones: Map.put(estado.sesiones, usuario, pid),
        monitores: Map.put(estado.monitores, ref, usuario)
    }

    {:reply, {:ok, usuario}, nuevo_estado}
  end

  # -------------------------
  # ESTADÍSTICAS DEL JUGADOR
  # -------------------------

  defp calcular_score(usuario, ruta_historial, almacen) do
    case almacen.leer_historial(ruta_historial) do
      {:ok, lineas} ->
        temas = puntajes_por_tema(lineas, usuario)

        puntaje_total =
          Enum.reduce(temas, 0, fn {_tema, datos}, total ->
            total + datos.puntaje
          end)

        partidas_total =
          Enum.reduce(temas, 0, fn {_tema, datos}, total ->
            total + datos.partidas
          end)

        detalle_temas =
          temas
          |> Enum.map(fn {tema, datos} ->
            %{
              tema: tema,
              puntaje: datos.puntaje,
              partidas: datos.partidas,
              nivel: Nivel.determinar_nivel(datos.puntaje)
            }
          end)
          |> Enum.sort_by(& &1.tema)

        {:ok,
         %{
           usuario: usuario,
           puntaje: puntaje_total,
           partidas: partidas_total,
           temas: detalle_temas
         }}

      {:error, motivo} ->
        {:error, motivo}
    end
  end

  defp puntajes_por_tema(lineas, usuario) do
    Enum.reduce(lineas, %{}, fn linea, acumulado ->
      case Jason.decode(linea) do
        {:ok, partida} ->
          tema = partida["tema"]

          jugador =
            Enum.find(
              partida["jugadores"] || [],
              fn jugador ->
                jugador["usuario"] == usuario
              end
            )

          if is_binary(tema) and is_map(jugador) and
               is_integer(jugador["puntaje"]) do
            datos_actuales =
              Map.get(
                acumulado,
                tema,
                %{puntaje: 0, partidas: 0}
              )

            nuevos_datos = %{
              puntaje: datos_actuales.puntaje + jugador["puntaje"],
              partidas: datos_actuales.partidas + 1
            }

            Map.put(acumulado, tema, nuevos_datos)
          else
            acumulado
          end

        {:error, _motivo} ->
          acumulado
      end
    end)
  end

  # -------------------------
  # RANKING HISTÓRICO
  # -------------------------

  defp calcular_ranking(tema, ruta_historial, almacen) do
    case almacen.leer_historial(ruta_historial) do
      {:ok, lineas} ->
        resultados =
          Enum.reduce(lineas, %{}, fn linea, acumulado ->
            case Jason.decode(linea) do
              {:ok, partida} ->
                if is_nil(tema) or partida["tema"] == tema do
                  acumular_jugadores(
                    partida["jugadores"] || [],
                    acumulado
                  )
                else
                  acumulado
                end

              {:error, _motivo} ->
                acumulado
            end
          end)

        ranking =
          resultados
          |> Enum.map(fn {usuario, datos} ->
            %{
              usuario: usuario,
              puntaje: datos.puntaje,
              partidas: datos.partidas
            }
          end)
          |> Enum.sort_by(fn jugador ->
            {-jugador.puntaje, jugador.usuario}
          end)

        {:ok, ranking}

      {:error, motivo} ->
        {:error, motivo}
    end
  end

  defp acumular_jugadores(jugadores, acumulado) do
    Enum.reduce(jugadores, acumulado, fn jugador, resultado ->
      usuario = jugador["usuario"]
      puntaje = jugador["puntaje"]

      if is_binary(usuario) and
           not String.starts_with?(usuario, "bot_") and
           is_integer(puntaje) do
        datos_actuales =
          Map.get(
            resultado,
            usuario,
            %{puntaje: 0, partidas: 0}
          )

        nuevos_datos = %{
          puntaje: datos_actuales.puntaje + puntaje,
          partidas: datos_actuales.partidas + 1
        }

        Map.put(resultado, usuario, nuevos_datos)
      else
        resultado
      end
    end)
  end

  # -------------------------
  # FUNCIONES AUXILIARES
  # -------------------------

  defp datos_validos?(usuario, clave) do
    is_binary(usuario) and
      is_binary(clave) and
      String.trim(usuario) != "" and
      String.trim(clave) != "" and
      not Regex.match?(~r/\s/, usuario)
  end

  defp buscar_sesion(pid, sesiones) do
    Enum.find_value(sesiones, fn {usuario, pid_sesion} ->
      if pid_sesion == pid, do: usuario
    end)
  end
end
