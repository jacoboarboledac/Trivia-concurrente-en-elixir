# Contexto del proyecto — Trivia concurrente en Elixir

## 1. Identificación
- **Curso:** Programación III — Universidad del Quindío.
- **Proyecto:** Proyecto final: Trivia Concurrente.
- **Repositorio:** `jacoboarboledac/Trivia-concurrente-en-elixir`.
- **Rama de trabajo:** `main`.
- **Estado del repositorio al crear este documento:** solo se verificó `README.md`; todavía no se encontró `mix.exs`, código dentro de `lib/` ni este archivo de contexto.

## 2. Objetivo
Construir una trivia por consola en Elixir donde cada jugador humano compite contra al menos dos bots. Las preguntas se organizan por tema y dificultad; el nivel del jugador en cada tema depende de su historial. Las partidas deben ser independientes y ejecutarse concurrentemente.

## 3. Alcance obligatorio según la guía
- Registro e inicio de sesión de jugadores.
- Creación y ejecución de partidas con tema, cantidad de preguntas y tiempo por pregunta.
- Un humano juega contra dos o tres bots; los bots participan como jugadores normales en la partida.
- Preguntas sorteadas por tema y nivel, sin repetirse dentro de una partida y ordenadas de menor a mayor dificultad.
- Envío de cada pregunta a todos los jugadores al mismo tiempo; la ronda termina cuando todos responden o vence el temporizador.
- Puntaje por respuesta según dificultad, con penalización por respuesta incorrecta y bonificación por rapidez.
- Ranking al finalizar la partida e historial/estadísticas persistentes de los humanos.
- Varias partidas simultáneas sin interferencia; un fallo de una partida no debe tumbar el servidor ni afectar las demás.
- Manejo de errores propios y pruebas automatizadas con ExUnit.

## 4. Arquitectura requerida/recomendada
- **Servidor central:** conserva el estado del juego, sesiones, banco de preguntas y persistencia. Es el único componente que accede a los archivos de datos.
- **Clientes:** procesos/nodos separados que envían peticiones y reciben notificaciones; no contienen lógica de juego ni acceden a los archivos de datos.
- **Partidas:** cada partida vive en un `GenServer` independiente, administrado por un `DynamicSupervisor`.
- **Bots:** jugadores automáticos con procesos propios.
- La comunicación entre nodos se realiza mediante las capacidades distribuidas de Erlang/Elixir.

## 5. Módulos sugeridos por la guía
Ubicación sugerida: `lib/trivia/`.
- `servidor.ex`: recibe y enruta peticiones.
- `gestor_jugadores.ex`: registro, sesiones, puntajes y ranking.
- `gestor_partidas.ex`: creación, ubicación y aviso de reinicio de partidas.
- `partida.ex`: `GenServer` que controla una partida.
- `supervisor_partidas.ex`: `DynamicSupervisor` de partidas.
- `bot.ex`: jugador automático.
- `banco_preguntas.ex`: carga y sorteo de preguntas por tema y nivel.
- `nivel.ex`: cálculo del nivel del jugador y reparto de preguntas.
- `persistencia.ex`: lectura y escritura de archivos.
- `cliente.ex`: consola del jugador y envío de peticiones.
- `receptor.ex`: recepción de notificaciones de la partida.

Esta es la arquitectura recomendada por la guía, no una afirmación de que esos módulos ya estén implementados.

## 6. Datos y dependencias
- Dependencia indicada: `jason` para trabajar con JSON.
- `data/questions.json`: banco semilla que debe crear el equipo; mínimo 4 temas y 8 preguntas por cada nivel en cada tema (24 por tema).
- `data/users.json`: se genera/actualiza al registrar jugadores.
- `data/results.log`: historial de resultados.
- El servidor es el único que debe leer o escribir estos archivos.

## 7. Pruebas y entrega
- Implementar al menos 5 de las 7 pruebas propuestas en la sección 12 de la guía y ejecutarlas con `mix test`.
- Entregar el repositorio con el proyecto Mix completo y el banco semilla `data/questions.json`.
- El `README.md` debe explicar integrantes, compilación, arranque del nodo servidor y de los nodos cliente, conexión y comandos.
- Incluir documentación del uso de inteligencia artificial.
- La sustentación debe demostrar al menos dos clientes con partidas distintas ejecutándose simultáneamente, además de los bots.

## 8. Archivos y avances comprobados
- `README.md` existe en GitHub y contiene únicamente una descripción breve del proyecto.
- El archivo `util.ex` fue compartido en el espacio del proyecto, pero no se ha confirmado que esté subido al repositorio.
- El módulo compartido se llama `Util` y contiene:
  - `leer(mensaje, :string)`: lee texto y elimina espacios/salto de línea exterior.
  - `leer(mensaje, :integer)` y `leer(mensaje, :float)`: convierten la entrada; si no es válida, muestran un error y retornan `0` o `0.0`.
  - `imprimir_error/1`: escribe en `:standard_error`.
  - `imprimir_mensaje/1`: escribe en la salida estándar.
- No se ha verificado todavía un proyecto Mix ni otros módulos del juego en el repositorio.

## 9. Decisiones y límites conocidos
- La extensión opcional de varios humanos en una misma partida no forma parte del mínimo obligatorio; primero se debe completar el alcance de las secciones 1 a 14 de la guía.
- No asumir que un requisito está implementado hasta revisar el código y/o ejecutar pruebas.
- Mantener separados los conceptos de **requisito**, **diseño propuesto** e **implementación comprobada**.

## 10. Próximos pasos sugeridos
1. Crear la estructura de proyecto Mix y configurar `jason`.
2. Incorporar `Util` al proyecto si se decide reutilizarlo.
3. Implementar y probar primero módulos pequeños y deterministas: `nivel`, `banco_preguntas` y reglas de puntaje.
4. Construir la persistencia y el gestor de jugadores.
5. Implementar el supervisor y el `GenServer` de cada partida.
6. Añadir bots, servidor, cliente y comunicación distribuida.
7. Completar pruebas, README y demostración de concurrencia.

## 11. Cómo mantener este documento
Actualizar este archivo al cerrar cada etapa: módulos creados, funciones principales, pruebas ejecutadas y resultado, decisiones tomadas, problemas pendientes y siguiente tarea. No marcar como terminado nada que no se haya probado.

---

Documento inicial elaborado a partir de la guía del proyecto y los archivos disponibles al momento de su creación. Debe actualizarse a medida que avance la implementación.