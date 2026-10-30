**Contexto del proyecto — Trivia concurrente en Elixir**  
**1. Identificación**  
- **Curso:** Programación III — Universidad del Quindío.  
- **Proyecto:** Proyecto final: Trivia Concurrente.  
- **Repositorio:**jacoboarboledac/Trivia-concurrente-en-elixir.  
- **Rama de trabajo:**main.  
- **Estado actual:** se creó la estructura inicial de Mix en main; aún no se ha ejecutado la compilación ni las pruebas.  
**2. Objetivo**  
Construir una trivia por consola en Elixir donde cada jugador humano compite contra al menos dos bots. Las preguntas se organizan por tema y dificultad; el nivel del jugador en cada tema depende de su historial. Las partidas deben ser independientes y ejecutarse concurrentemente.  
**3. Alcance obligatorio según la guía**  
- Registro e inicio de sesión de jugadores.  
- Creación y ejecución de partidas con tema, cantidad de preguntas y tiempo por pregunta.  
- Un humano juega contra dos o tres bots; los bots participan como jugadores normales en la partida.  
- Preguntas sorteadas por tema y nivel, sin repetirse dentro de una partida y ordenadas de menor a mayor dificultad.  
- Envío de cada pregunta a todos los jugadores al mismo tiempo; la ronda termina cuando todos responden o vence el temporizador.  
- Puntaje por respuesta según dificultad, con penalización por respuesta incorrecta y bonificación por rapidez.  
- Ranking al finalizar la partida e historial/estadísticas persistentes de los humanos.  
- Varias partidas simultáneas sin interferencia; un fallo de una partida no debe tumbar el servidor ni afectar las demás.  
- Manejo de errores propios y pruebas automatizadas con ExUnit.  
**4. Arquitectura requerida/recomendada**  
- **Servidor central:** conserva el estado del juego, sesiones, banco de preguntas y persistencia. Es el único componente que accede a los archivos de datos.  
- **Clientes:** procesos/nodos separados que envían peticiones y reciben notificaciones; no contienen lógica de juego ni acceden a los archivos de datos.  
- **Partidas:** cada partida vive en un GenServer independiente, administrado por un DynamicSupervisor.  
- **Bots:** jugadores automáticos con procesos propios.  
- La comunicación entre nodos se realiza mediante las capacidades distribuidas de Erlang/Elixir.  
**5. Módulos sugeridos por la guía**  
Ubicación sugerida: lib/trivia/.  
- servidor.ex: recibe y enruta peticiones.  
- gestor_jugadores.ex: registro, sesiones, puntajes y ranking.  
- gestor_partidas.ex: creación, ubicación y aviso de reinicio de partidas.  
- partida.ex: GenServer que controla una partida.  
- supervisor_partidas.ex: DynamicSupervisor de partidas.  
- bot.ex: jugador automático.  
- banco_preguntas.ex: carga y sorteo de preguntas por tema y nivel.  
- nivel.ex: cálculo del nivel del jugador y reparto de preguntas.  
- persistencia.ex: lectura y escritura de archivos.  
- cliente.ex: consola del jugador y envío de peticiones.  
- receptor.ex: recepción de notificaciones de la partida.  
Esta es la arquitectura recomendada por la guía, no una afirmación de que esos módulos ya estén implementados.  
**6. Datos y dependencias**  
- Dependencia indicada: jason para trabajar con JSON.  
- data/questions.json: banco semilla que debe crear el equipo; mínimo 4 temas y 8 preguntas por cada nivel en cada tema (24 por tema).  
- data/users.json: se genera/actualiza al registrar jugadores.  
- data/results.log: historial de resultados.  
- El servidor es el único que debe leer o escribir estos archivos.  
**7. Pruebas y entrega**  
- Implementar al menos 5 de las 7 pruebas propuestas en la sección 12 de la guía y ejecutarlas con mix test.  
- Entregar el repositorio con el proyecto Mix completo y el banco semilla data/questions.json.  
- El README.md debe explicar integrantes, compilación, arranque del nodo servidor y de los nodos cliente, conexión y comandos.  
- Incluir documentación del uso de inteligencia artificial.  
- La sustentación debe demostrar al menos dos clientes con partidas distintas ejecutándose simultáneamente, además de los bots.  
**8. Archivos y avances comprobados**  
- mix.exs: proyecto :trivia_concurrente, versión 0.1.0, requisito Elixir >= 1.14.0 y dependencia jason ~> 1.4.  
- lib/trivia_concurrente.ex: módulo principal con documentación inicial.  
- lib/trivia/util.ex: módulo Util incorporado desde el archivo compartido.  
- test/test_helper.exs y test/trivia/util_test.exs: configuración ExUnit y cinco pruebas iniciales para Util.  
- .gitignore: excluye compilados, dependencias y archivos locales de usuarios/resultados.  
- data/.gitkeep: conserva el directorio de datos en Git.  
- El README.md todavía conserva su descripción breve original.  
- El módulo Util contiene:  
- leer(mensaje, :string): lee texto y elimina espacios/salto de línea exterior.  
- leer(mensaje, :integer) y leer(mensaje, :float): convierten la entrada; si no es válida, muestran un error y retornan 0 o 0.0.  
- imprimir_error/1: escribe en :standard_error.  
- imprimir_mensaje/1: escribe en la salida estándar.  
- Todavía no se han creado los módulos de lógica del juego (Nivel, BancoPreguntas, servidor, partidas, bots, clientes ni persistencia).  
- La compilación y las cinco pruebas todavía están pendientes de ejecución; el entorno disponible en esta sesión no tiene instalados elixir ni mix.  
**9. Decisiones y límites conocidos**  
- La extensión opcional de varios humanos en una misma partida no forma parte del mínimo obligatorio; primero se debe completar el alcance de las secciones 1 a 14 de la guía.  
- No asumir que un requisito está implementado hasta revisar el código y/o ejecutar pruebas.  
- Mantener separados los conceptos de **requisito**,  **diseño propuesto** e  **implementación comprobada**.  
**10. Próximos pasos sugeridos**  
1. Ejecutar mix deps.get y mix test en un equipo con Elixir instalado; corregir cualquier fallo encontrado.  
2. Implementar y probar módulos pequeños y deterministas: Nivel, BancoPreguntas y reglas de puntaje.  
3. Construir la persistencia y el gestor de jugadores.  
4. Implementar el supervisor y el GenServer de cada partida.  
5. Añadir bots, servidor, cliente y comunicación distribuida.  
6. Completar banco de preguntas, README y demostración de concurrencia.  
**11. Cómo mantener este documento**  
Actualizar este archivo al cerrar cada etapa: módulos creados, funciones principales, pruebas ejecutadas y resultado, decisiones tomadas, problemas pendientes y siguiente tarea. No marcar como terminado nada que no se haya probado.  
![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANklEQVR4nO3OQQmAABRAsSfYxZo/jzlMYQLPJrCCNxG2BFtmZquOAAD4i3Ot7mr/egIAwGvXA4q7Bc870TqdAAAAAElFTkSuQmCC)  
Documento inicial elaborado a partir de la guía del proyecto y los archivos disponibles al momento de su creación. Debe actualizarse a medida que avance la implementación.  
### Gestor de jugadores  
   
Se implementó el módulo `Trivia.GestorJugadores` utilizando GenServer.  
   
Sus funcionalidades son:  
- Registro automático de usuarios e inicio de sesión.  
- Validación de credenciales.  
- Control de sesiones activas.  
- Detección de desconexiones mediante monitoreo de procesos.  
- Consulta del puntaje e historial por tema.  
- Consulta del ranking general y por tema.  
   
También se implementaron pruebas automatizadas para verificar estas funcionalidades.  
   
