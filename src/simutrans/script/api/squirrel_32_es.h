/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

/** @file squirrel_32_es.h Squirrel 3.2 runtime update - Spanish translation
 *
 * Translation status: reviewed.
 * The English page in squirrel_32_en.h is the canonical technical reference.
 * This file is the reviewed Spanish translation of that page.
 */

/**
 * @page squirrel32_es Actualización del runtime de Squirrel 3.2
 *
 * @ref squirrel32_en "English" | <b>Español (traducción)</b>
 *
 * @note Esta es la traducción al español de la documentación de Squirrel 3.2.
 * La documentación en inglés es la referencia técnica canónica.
 *
 * @tableofcontents
 *
 * @section sq32_es_overview Resumen
 *
 * Simutrans integra el lenguaje Squirrel para ejecutar escenarios y jugadores de AI
 * escritos como guiones. El runtime de Squirrel integrado se ha actualizado a la
 * versión v3.2 del proyecto original.
 *
 * Se trata de una actualización del <em>runtime del lenguaje</em>. No es un rediseño
 * de la Script API de Simutrans. No hace falta reescribir los guiones debido a esta
 * actualización.
 *
 * @section sq32_es_changed Qué ha cambiado
 *
 * - Las fuentes de Squirrel incluidas en Simutrans se han actualizado a la v3.2
 *   original.
 * - Squirrel incorpora una sintaxis en línea para vincular un entorno a una función,
 *   además del método @c bindenv que ya existía. Véase @ref sq32_es_bindenv.
 * - Las tablas incorporan un método @c map en la biblioteca estándar de Squirrel.
 *   Véase @ref sq32_es_tablemap.
 * - El proyecto original ha cambiado la función hash de las cadenas. Esto cambia el
 *   orden en que se recorren las entradas de una tabla. Véase @ref sq32_es_order. Para
 *   los guiones existentes que no se modifiquen, este es el principal cambio de
 *   comportamiento que puede resultar observable.
 *
 * @section sq32_es_unchanged Qué no ha cambiado
 *
 * - La Script API de Simutrans (las clases y los métodos documentados en esta
 *   referencia) no ha cambiado. La actualización del runtime no ha añadido, eliminado
 *   ni renombrado ninguna función, y no ha cambiado ninguna lista de parámetros ni el
 *   comportamiento de los argumentos opcionales.
 * - Los puntos de entrada de escenarios y AI no han cambiado.
 * - El formato de las partidas guardadas no ha cambiado.
 * - La forma en que los guiones se cargan, se suspenden y se reanudan no ha cambiado.
 *
 * @section sq32_es_provenance Procedencia del runtime
 *
 * Las fuentes de Squirrel que acompañan a Simutrans son una copia incorporada del
 * proyecto original alojado en
 * <a href="https://github.com/albertodemichelis/squirrel">albertodemichelis/squirrel</a>.
 *
 * <table>
 * <tr><th>Base incorporada anterior<td><tt>23a0620658714b996d20da3d4dd1a0dcf9b0bd98</tt>
 *     <td>una instantánea de la línea de desarrollo 3.1.x, con fecha 2021-09-16
 * <tr><th>Base nueva<td><tt>f92bc298784ceea459b12e2de33bdff672bfeb83</tt>
 *     <td>etiqueta de publicación <tt>v3.2</tt> del proyecto original, con fecha 2022-02-10
 * </table>
 *
 * La instantánea anterior se tomó de la línea de desarrollo posterior a la publicación
 * de la 3.1, así que no era ni una 3.1 exacta ni una 3.2. Describir la actualización
 * simplemente como «de la 3.1 a la 3.2» sería, por tanto, inexacto.
 *
 * @section sq32_es_compat Compatibilidad
 *
 * Los dos jugadores de AI que acompañan a Simutrans, @c sqai y @c sqai_rail, se han
 * ejecutado con el runtime nuevo y siguen siendo compatibles. En la campaña de pruebas
 * conservaron el estado lógico de sus conexiones, continuaron progresando de forma
 * válida y no produjeron errores de guion ni de runtime. Algunas decisiones de
 * planificación y búsqueda de rutas pueden variar debido al orden de iteración de las
 * tablas, como se explica más adelante. También se ha comprobado que se carga
 * correctamente una partida guardada con el runtime anterior.
 *
 * Esto es una afirmación sobre los guiones y las rutas que cubrió esa campaña de
 * pruebas. No es una garantía de que cualquier guion posible quede inalterado. Un guion
 * que dependa del orden de iteración de las tablas puede comportarse de otra manera:
 * véase la sección siguiente.
 *
 * @section sq32_es_order Orden de iteración de las tablas
 *
 * @warning No se debe depender del orden de iteración de las tablas de Squirrel, salvo
 * que la API lo documente explícitamente.
 *
 * Squirrel 3.2 cambia la función hash que se aplica a las claves de tipo cadena. Las
 * tablas son contenedores hash, de modo que esto cambia el orden en que @c foreach
 * recorre sus entradas.
 *
 * La consecuencia para un guion es indirecta, pero real. Si un guion recorre una tabla
 * para elegir la siguiente tarea, el orden nuevo puede cambiar:
 *
 * - qué entrada se examina primero,
 * - el orden en que se planifica el trabajo,
 * - qué candidato gana cuando varios son igual de buenos,
 * - y, por tanto, a cuál de varios resultados igual de válidos llega el guion.
 *
 * Esto no es corrupción ni es aleatoriedad. Con la misma entrada, el runtime se
 * comporta igual siempre, el guion conserva su estado lógico completo y la ejecución
 * sigue siendo válida. Lo que cambia es un desempate basado en un orden que nunca
 * estuvo garantizado.
 *
 * Si un guion necesita un orden definido, tiene que imponerlo él mismo (por ejemplo,
 * recogiendo las claves en un array y ordenándolo) en lugar de confiar en el orden que
 * una tabla produzca por casualidad.
 *
 * Los arrays no se ven afectados: son contenedores ordenados y su orden forma parte de
 * su contrato.
 *
 * @section sq32_es_savegames Compatibilidad de las partidas guardadas
 *
 * Las partidas guardadas con el runtime anterior se cargan correctamente con Squirrel
 * 3.2. Esto se ha comprobado con los jugadores de AI que acompañan a Simutrans. La
 * misma partida del runtime anterior se cargó varias veces para confirmar la
 * reproducibilidad. Un estado cargado con 3.2 también se volvió a guardar y se recargó
 * correctamente. Los guiones se reanudaron con su estado persistente completo.
 *
 * El sentido contrario (cargar una partida guardada por Squirrel 3.2 en una versión
 * anterior de Simutrans) no formó parte de este trabajo y no se afirma.
 *
 * Cuando el estado persistente de un guion se vuelve a escribir, las entradas de una
 * tabla guardada pueden aparecer en un orden distinto al anterior. El estado guardado
 * en sí no se ve afectado: se restaura por nombre, no por posición.
 *
 * @section sq32_es_bindenv bindenv
 *
 * Vincular un entorno a una función es una característica del lenguaje Squirrel, no una
 * clase ni un registro de la API de Simutrans.
 *
 * El método que ya existía no ha cambiado y sigue funcionando:
 *
 * @code
 * local env = { factor = 2 }
 * local scale = function(x) { return x * factor }
 * local bound = scale.bindenv(env)   // 'this' inside scale is now env
 * bound(21)                          // 42
 * @endcode
 *
 * Squirrel 3.2 añade una forma en línea. El entorno se escribe entre corchetes, entre
 * el nombre de la función y la lista de parámetros:
 *
 * @code
 * local env = { factor = 2 }
 * local scale = function [env] (x) { return x * factor }
 * scale(21)                          // 42
 * @endcode
 *
 * La misma forma con corchetes se admite en funciones con nombre, en funciones locales
 * y en miembros de clases y tablas, incluido @c constructor.
 *
 * Las dos formas producen una clausura cuyo entorno es el objeto indicado, ya sea una
 * tabla, una clase o una instancia. La forma en línea es una comodidad; no da acceso a
 * nada que la forma con método no permitiera ya. Los guiones existentes no necesitan
 * ningún cambio.
 *
 * @section sq32_es_tablemap table.map
 *
 * Squirrel 3.2 añade un método @c map a las tablas en la biblioteca estándar. Los
 * arrays ya lo tenían.
 *
 * El callback se llama una vez por entrada y recibe la clave y el valor, con @c this
 * vinculado a la tabla:
 *
 * @code
 * local prices = { coal = 10, oil = 25 }
 * local labels = prices.map(function(key, value) {
 *     return key + "=" + value
 * })
 * @endcode
 *
 * Conviene conocer dos propiedades:
 *
 * - @c table.map devuelve un <b>array</b> con los resultados del callback, no una
 *   tabla. En esto se diferencia de @c table.filter, que devuelve una tabla.
 * - Los resultados aparecen en el orden de iteración de la tabla, así que el orden del
 *   array devuelto está sujeto a @ref sq32_es_order. Conviene ordenarlo si el orden
 *   importa.
 *
 * @section sq32_es_authors Notas para autores de AI y escenarios
 *
 * - No hace falta ningún cambio para que un guion existente siga funcionando.
 * - Revise cualquier punto donde se recorra una tabla para tomar una decisión. Si gana
 *   la primera coincidencia, o la última, determine si ese comportamiento era
 *   intencionado y hágalo explícito.
 * - No compare dos ejecuciones por sus registros. Dos ejecuciones del mismo guion con
 *   versiones distintas de Simutrans pueden tomar decisiones distintas e igualmente
 *   válidas.
 * - Prefiera los arrays cuando el orden tenga significado.
 *
 * @section sq32_es_limits Límites conocidos del alcance
 *
 * - La afirmación de compatibilidad cubre los jugadores de AI que acompañan a Simutrans
 *   y los sentidos de carga de partidas indicados arriba. No se han probado guiones de
 *   terceros.
 * - No se afirma que cargar una partida guardada por Squirrel 3.2 en una versión
 *   anterior funcione.
 * - La forma en línea de @c bindenv es una característica nueva del lenguaje, y
 *   @c table.map es una característica nueva de la biblioteca estándar. Los guiones que
 *   las usen no funcionarán en versiones anteriores de Simutrans.
 *
 * @section sq32_es_further Referencias adicionales
 *
 * - @ref changelog - el registro de cambios de la Script API (en inglés)
 * - @ref pitfalls - errores frecuentes al escribir guiones (en inglés)
 * - @ref page_sqstdlib - las funciones de la biblioteca estándar de Squirrel disponibles
 *   en Simutrans (en inglés)
 */
