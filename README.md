# Trivia Concurrente en Elixir

## Proyecto Final – Programación III

**Universidad:** Universidad del Quindío  
**Programa:** Ingeniería de Sistemas y Computación  
**Asignatura:** Programación III  
**Docente:** Carlos Andrés Flórez Villarraga

### Integrante

- **Nombre:** Jacobo Arboleda Carvajal
- **Integrantes del proyecto:** 1

## 1. Descripción del proyecto

Trivia Concurrente es un juego de preguntas y respuestas desarrollado en Elixir, utilizando programación concurrente y distribuida mediante procesos de Erlang/OTP.

El sistema utiliza una arquitectura cliente-servidor en la que un servidor central administra los jugadores, las partidas, las preguntas, los puntajes y la persistencia de información.

Cada jugador humano puede crear una partida y competir contra dos o tres jugadores automáticos (bots). Las partidas son independientes y pueden ejecutarse simultáneamente.

El juego incluye:

- Registro e inicio de sesión de usuarios.
- Creación de partidas con tema, número de preguntas y tiempo configurable.
- Preguntas clasificadas por dificultad: básico, intermedio y avanzado.
- Selección de preguntas según el nivel histórico del jugador en cada tema.
- Bots con dificultades fácil y difícil.
- Temporizador independiente por pregunta.
- Puntuación según dificultad, respuestas correctas, incorrectas y tiempo de respuesta.
- Clasificación de jugadores y bots.
- Ranking histórico global y por tema.
- Persistencia de usuarios, preguntas e historial.
- Supervisión y reinicio de partidas ante fallos.
- Ejecución de múltiples partidas concurrentes.

## 2. Tecnologías utilizadas

- Elixir.
- Erlang/OTP.
- Mix para administración del proyecto.
- Jason para lectura y escritura de archivos JSON.
- GenServer para procesos con estado.
- DynamicSupervisor para supervisión de partidas.
- ExUnit para pruebas automatizadas.
- Comunicación entre nodos distribuidos de Erlang.

## 3. Requisitos de instalación

Para ejecutar el proyecto se necesita:

- Elixir 1.14 o superior.
- Erlang/OTP compatible.
- Mix.
- Una terminal o consola de comandos.
- Sistema operativo Windows para utilizar los archivos `.bat` incluidos.

Se recomienda verificar la instalación mediante:

```bash
elixir --version
mix --version
```

## 4. Instalación y compilación

Descargar o clonar el repositorio y abrir una terminal en la carpeta raíz del proyecto.

Instalar las dependencias:

```bash
mix deps.get
```

Compilar el proyecto:

```bash
mix compile
```

## 5. Ejecución del servidor

El servidor central debe iniciarse antes que los clientes.

En Windows, ejecutar:

```text
Iniciar_servidor.bat
```

Este archivo configura el nodo con el rol de servidor, utilizando el nombre `servidor` y la cookie `trivia_local`.

También puede iniciarse manualmente desde una terminal de Windows:

```cmd
set TRIVIA_ROLE=servidor
elixir --sname servidor --cookie trivia_local -S mix run --no-halt
```

El servidor permanece activo y administra las conexiones, las partidas y la información persistente.

**Importante:** El servidor debe mantenerse abierto mientras los clientes están jugando.

## 6. Ejecución de los clientes

Cada cliente debe ejecutarse en una consola independiente.

### Primer cliente

Ejecutar:

```text
Iniciar_cliente_pedro.bat
```

O manualmente:

```cmd
set TRIVIA_ROLE=cliente
elixir --sname pedro --cookie trivia_local -S mix run -e "Trivia.Cliente.iniciar()"
```

### Segundo cliente

Abrir otra consola y ejecutar:

```text
Iniciar_cliente_carlos.bat
```

O manualmente:

```cmd
set TRIVIA_ROLE=cliente
elixir --sname carlos --cookie trivia_local -S mix run -e "Trivia.Cliente.iniciar()"
```

Los nombres `pedro` y `carlos` identifican los nodos de ejecución. No obligan a utilizar esos nombres como usuarios del juego.

### Comunicación entre nodos

El servidor y los clientes utilizan nodos distribuidos de Erlang.

Todos deben:

- Tener nombres de nodo diferentes.
- Utilizar la misma cookie de Erlang.
- Tener acceso al nodo del servidor.
- Ejecutarse con el rol correspondiente.

El cliente se comunica con el servidor mediante peticiones y recibe las notificaciones de las partidas de forma independiente.

Los archivos de datos y el estado del juego se administran desde el servidor.

## 7. Registro e inicio de sesión

Al iniciar el cliente aparece un menú de acceso.

```text
1) Iniciar sesión o registrarme
0) Salir
```

Al seleccionar la primera opción, el sistema solicita el usuario y la contraseña.

Si el usuario no existe, se registra automáticamente. Si ya existe, se verifica la contraseña.

Un usuario no puede mantener dos sesiones abiertas simultáneamente.

## 8. Menú principal

Después de iniciar sesión, el jugador dispone de las siguientes opciones:

```text
1) Crear nueva partida
2) Ver mis estadísticas
3) Ver ranking global
4) Ver ranking por tema
5) Cerrar sesión
0) Salir del juego
```

Las estadísticas muestran los puntos acumulados, las partidas jugadas y el nivel del usuario en los temas en los que ha participado.

## 9. Creación de partidas

Para crear una partida, seleccionar la opción correspondiente del menú principal.

El sistema permite elegir uno de los temas disponibles:

```text
1) Ciencia
2) Historia
3) Geografía
4) Tecnología
0) Volver
```

Después se solicita el número de preguntas y el tiempo disponible por pregunta.

El sistema crea la partida y determina el nivel del jugador a partir de su puntaje histórico en el tema seleccionado.

### Configuración de los bots

Una vez creada la partida, se presenta el menú de preparación:

```text
1) Agregar bot fácil
2) Agregar bot difícil
3) Iniciar la partida
4) Cancelar la partida
5) Ver mis estadísticas
6) Ver ranking global
7) Cerrar sesión
0) Salir
```

Para iniciar una partida se deben agregar al menos dos bots. Se permite un máximo de tres bots por partida.

## 10. Niveles de dificultad

El nivel del jugador depende de los puntos acumulados históricamente en el tema.

| Puntaje acumulado | Nivel |
|---|---|
| Menos de 60 | Básico |
| 60 a 179 | Intermedio |
| 180 o más | Avanzado |

El nivel se determina cuando se crea la partida y permanece fijo durante ella.

Las preguntas se distribuyen de acuerdo con los siguientes porcentajes:

| Nivel del jugador | Básico | Intermedio | Avanzado |
|---|---:|---:|---:|
| Básico | 70 % | 30 % | 0 % |
| Intermedio | 20 % | 60 % | 20 % |
| Avanzado | 0 % | 30 % | 70 % |

Las preguntas se seleccionan aleatoriamente, sin repetirse dentro de una misma partida, y se presentan de menor a mayor dificultad.

## 11. Funcionamiento de las rondas

Al iniciar la partida, todos los participantes reciben la misma pregunta.

Cada pregunta tiene cuatro opciones de respuesta: A, B, C y D.

El jugador puede responder seleccionando la opción correspondiente del menú.

Cada ronda termina cuando todos los participantes han respondido o cuando vence el temporizador.

Al terminar, el sistema informa la respuesta correcta y los puntos obtenidos. Entre rondas se realiza una pausa de tres segundos.

Cuando termina la partida, se muestra el ranking final y se guarda el resultado en el historial.

## 12. Sistema de puntuación

Los puntos dependen de la dificultad de la pregunta.

| Resultado | Básico | Intermedio | Avanzado |
|---|---:|---:|---:|
| Respuesta correcta | +10 | +15 | +20 |
| Respuesta incorrecta | -5 | -8 | -10 |
| Sin responder | 0 | 0 | 0 |

### Bonificación por rapidez

Las respuestas correctas reciben una bonificación adicional de 0 a 5 puntos, calculada mediante:

```text
bonificacion = trunc(5 * segundos_restantes / tiempo_pregunta)
```

El puntaje total de una respuesta correcta corresponde a los puntos de la dificultad más la bonificación.

Las respuestas incorrectas no reciben bonificación.

## 13. Jugadores automáticos

El sistema permite agregar bots de dos dificultades:

**Bot fácil:** tiene menores probabilidades de acertar y responde más lentamente.

**Bot difícil:** tiene mayores probabilidades de acertar y responde más rápidamente.

Cada bot se ejecuta en su propio proceso y participa en las rondas como un jugador más.

Los bots aparecen en el ranking final de la partida, pero no se registran como usuarios humanos ni participan en el ranking histórico.

## 14. Concurrencia y supervisión

El proyecto utiliza procesos independientes para ejecutar múltiples partidas simultáneamente.

La arquitectura incluye:

- `Trivia.Servidor`: recibe las peticiones de los clientes.
- `Trivia.GestorJugadores`: administra usuarios, sesiones y estadísticas.
- `Trivia.GestorPartidas`: crea y administra las partidas.
- `Trivia.Partida`: controla las rondas y el estado de cada partida.
- `Trivia.SupervisorPartidas`: supervisa los procesos de las partidas.
- `Trivia.Bot`: implementa los jugadores automáticos.
- `Trivia.BancoPreguntas`: administra el banco de preguntas.
- `Trivia.Nivel`: calcula niveles y distribución de preguntas.
- `Trivia.Almacen`: centraliza operaciones de persistencia.
- `Trivia.Persistencia`: implementa las operaciones sobre archivos.
- `Trivia.Cliente`: administra la interacción por consola.
- `Trivia.Receptor`: recibe notificaciones del servidor.

Si una partida falla, el sistema utiliza supervisión para reiniciarla sin afectar a las demás partidas.

## 15. Persistencia de información

El proyecto utiliza los siguientes archivos:

| Archivo | Función |
|---|---|
| `data/questions.json` | Banco de preguntas por tema y dificultad |
| `data/users.json` | Usuarios registrados |
| `data/results.log` | Historial de resultados de las partidas |

El banco de preguntas contiene cuatro temas, con ocho preguntas por cada nivel de dificultad en cada tema.

Los archivos de usuarios y resultados se generan conforme se utiliza el sistema.

Las estadísticas de los jugadores se reconstruyen a partir del historial de partidas.

## 16. Pruebas automatizadas

El proyecto incluye pruebas unitarias y de integración desarrolladas con ExUnit.

Para ejecutarlas:

```bash
mix test
```

Las pruebas comprueban aspectos como:

- Selección y distribución de preguntas.
- Cálculo del nivel de los jugadores.
- Comportamiento de los bots.
- Creación y administración de partidas.
- Registro y consulta de jugadores.
- Persistencia de información.
- Comunicación entre componentes.
- Concurrencia y reinicio de partidas.

Para comprobar la compilación y ejecución de las pruebas:

```bash
mix deps.get
mix compile
mix test
```

## 17. Ejemplo de uso

1. Ejecutar `Iniciar_servidor.bat`.
2. Ejecutar `Iniciar_cliente_pedro.bat`.
3. Registrar o iniciar sesión con un usuario.
4. Seleccionar la opción de crear una partida.
5. Elegir el tema Ciencia.
6. Configurar cinco preguntas y quince segundos por pregunta.
7. Agregar un bot fácil y uno difícil.
8. Iniciar la partida.
9. Responder las preguntas desde el menú del cliente.
10. Consultar los resultados y el ranking al finalizar.
11. Consultar las estadísticas del jugador.

Para demostrar la concurrencia, abrir también `Iniciar_cliente_carlos.bat` y crear otra partida con un usuario diferente.

Ambas partidas deben poder ejecutarse simultáneamente sin interferirse.

**Herramienta:** ChatGPT (OpenAI).

## 19. Autor

**Desarrollador:** Jacobo Arboleda Carvajal  
**Universidad:** Universidad del Quindío  
**Programa:** Ingeniería de Sistemas y Computación  
**Asignatura:** Programación III  
**Año:** 2026
