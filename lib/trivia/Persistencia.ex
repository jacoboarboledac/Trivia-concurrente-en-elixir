defmodule Trivia.Persistencia do
  @moduledoc """
  Maneja la lectura y escritura de usuarios e historial de partidas.
  """

  @ruta_usuarios "data/users.json"
  @ruta_historial "data/results.log"

  # -------------------------
  # USUARIOS
  # -------------------------

  def cargar_usuarios(ruta \\ @ruta_usuarios) do
    case File.read(ruta) do
      {:ok, contenido} ->
        case Jason.decode(contenido) do
          {:ok, usuarios} when is_list(usuarios) ->
            if Enum.all?(usuarios, &usuario_valido?/1) do
              {:ok, usuarios}
            else
              {:error, :formato_usuarios_invalido}
            end

          {:ok, _otro_formato} ->
            {:error, :formato_usuarios_invalido}

          {:error, _motivo} ->
            {:error, :json_invalido}
        end

      {:error, :enoent} ->
        {:ok, []}

      {:error, motivo} ->
        {:error, motivo}
    end
  end

  def guardar_usuarios(usuarios, ruta \\ @ruta_usuarios)

  def guardar_usuarios(usuarios, ruta) when is_list(usuarios) do
    if Enum.all?(usuarios, &usuario_valido?/1) do
      with {:ok, contenido} <- Jason.encode(usuarios, pretty: true),
           :ok <- crear_directorio(ruta),
           :ok <- File.write(ruta, contenido) do
        :ok
      end
    else
      {:error, :formato_usuarios_invalido}
    end
  end

  def guardar_usuarios(_usuarios, _ruta) do
    {:error, :formato_usuarios_invalido}
  end

  def registrar_usuario(usuario, clave, ruta \\ @ruta_usuarios)

  def registrar_usuario(usuario, clave, ruta)
      when is_binary(usuario) and is_binary(clave) do
    cond do
      String.trim(usuario) == "" or String.trim(clave) == "" ->
        {:error, :datos_invalidos}

      String.starts_with?(usuario, "bot_") ->
        {:error, :prefijo_reservado}

      true ->
        case cargar_usuarios(ruta) do
          {:ok, usuarios} ->
            existe =
              Enum.any?(usuarios, fn registrado ->
                registrado["usuario"] == usuario
              end)

            if existe do
              {:error, :usuario_existente}
            else
              nuevo_usuario = %{
                "usuario" => usuario,
                "clave" => clave
              }

              case guardar_usuarios(usuarios ++ [nuevo_usuario], ruta) do
                :ok -> {:ok, nuevo_usuario}
                error -> error
              end
            end

          error ->
            error
        end
    end
  end

  def registrar_usuario(_usuario, _clave, _ruta) do
    {:error, :datos_invalidos}
  end

  # -------------------------
  # HISTORIAL DE PARTIDAS
  # -------------------------

  def leer_historial(ruta \\ @ruta_historial) do
    case File.stat(ruta) do
      {:ok, _informacion} ->
        lineas =
          ruta
          |> File.stream!()
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        {:ok, lineas}

      {:error, :enoent} ->
        {:ok, []}

      {:error, motivo} ->
        {:error, motivo}
    end
  end

  def guardar_resultado(resultado, ruta \\ @ruta_historial)

  def guardar_resultado(resultado, ruta) when is_map(resultado) do
    with :ok <- validar_resultado(resultado),
         {:ok, contenido} <- Jason.encode(resultado),
         :ok <- crear_directorio(ruta),
         :ok <- File.write(ruta, contenido <> "\n", [:append]) do
      :ok
    end
  end

  def guardar_resultado(_resultado, _ruta) do
    {:error, :resultado_invalido}
  end

  # -------------------------
  # FUNCIONES AUXILIARES
  # -------------------------

  defp usuario_valido?(usuario) when is_map(usuario) do
    is_binary(usuario["usuario"]) and
      is_binary(usuario["clave"])
  end

  defp usuario_valido?(_usuario), do: false

  defp validar_resultado(resultado) do
    campos_obligatorios = [
      "fecha",
      "id",
      "tema",
      "nivel",
      "ganador",
      "jugadores"
    ]

    campos_presentes =
      Enum.all?(campos_obligatorios, fn campo ->
        Map.has_key?(resultado, campo)
      end)

    jugadores_validos =
      case resultado["jugadores"] do
        jugadores when is_list(jugadores) ->
          Enum.all?(jugadores, fn jugador ->
            is_map(jugador) and
              is_binary(jugador["usuario"]) and
              is_integer(jugador["puntaje"])
          end)

        _ ->
          false
      end

    if campos_presentes and jugadores_validos do
      :ok
    else
      {:error, :resultado_invalido}
    end
  end

  defp crear_directorio(ruta) do
    ruta
    |> Path.dirname()
    |> File.mkdir_p()
  end
end
