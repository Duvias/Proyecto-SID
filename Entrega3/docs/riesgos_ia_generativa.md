# Riesgos del uso de herramientas de IA generativa en el desarrollo de bases de datos

**Proyecto Stocka — Entrega 3**
Sistemas Intensivos en Datos, Universidad Icesi

---

## 1. Por qué este documento

La Entrega 3 se desarrolló bajo el nivel 4 de uso de IA generativa, que permite emplearla estratégicamente en cualquier etapa siempre que el uso sea crítico, esté justificado y el contenido generado quede citado. Este documento recoge los riesgos que identificamos de usar estas herramientas en trabajo de bases de datos, no en abstracto sino a partir de lo que nos pasó construyendo el DDL, el DML, las consultas y el PL/SQL de este proyecto.

Dos de los riesgos que se describen abajo no son hipotéticos: ocurrieron, los detectamos y están documentados con el error exacto que arrojó Oracle.

---

## 2. Riesgos identificados

### 2.1 Código correcto en apariencia que falla en el motor real

Es el riesgo principal y el más difícil de detectar, porque el código generado compila, se lee bien y resiste una revisión visual.

**Lo que nos pasó.** El modelo necesitaba una restricción que impidiera que una transferencia entre sedes registrara dos salidas o dos entradas. Se generó como `UNIQUE (transferencia_id, tipo_ajuste)`, con la transferencia opcional porque la mayoría de los ajustes no vienen de un traslado. La restricción se verificó contra un motor de prueba y pasó.

Al ejecutarla en Oracle fallaron 83 de 93 inserciones con `ORA-00001`. La causa es una diferencia de semántica entre motores: Oracle documenta que en una clave única compuesta parcialmente nula no se pueden repetir los valores de las columnas que sí tienen valor. Con la transferencia en nulo, Oracle comparaba solo el tipo de ajuste, y la tabla admitía un único ajuste de cada tipo en todo el sistema. En PostgreSQL o SQLite la misma restricción se comporta distinto y el error no aparece.

**Por qué importa en lo profesional.** Una herramienta de IA generaliza a partir del patrón más frecuente, y el patrón más frecuente no es necesariamente el del motor de producción. El error solo se manifestó al ejecutar contra Oracle con volumen real de datos; una prueba con tres filas lo habría dejado pasar.

**Cómo lo mitigamos.** Ningún script se dio por bueno sin ejecutarse contra la base del curso. La corrección final usó un índice único funcional, que es el modismo correcto de Oracle para este caso, y quedó documentada en el propio DDL explicando por qué no sirve la restricción convencional.

---

### 2.2 Suposiciones sobre el entorno de ejecución

**Lo que nos pasó.** El procedimiento de registro de venta se generó usando `CREATE TYPE` para declarar una colección de líneas. Es la solución estándar y habría funcionado en una instancia propia. El esquema del curso respondió `ORA-01031: privilegios insuficientes`, y el procedimiento quedó inválido por depender de un tipo que nunca se creó.

**Por qué importa en lo profesional.** La herramienta propone sobre un entorno idealizado: privilegios completos, versión reciente, esquema propio. En la realidad hay permisos restringidos, versiones antiguas, esquemas compartidos y políticas de seguridad. En este proyecto el obstáculo fue un privilegio; en un entorno corporativo puede ser una política que prohíbe ciertos objetos, una versión que no soporta la sintaxis o un esquema donde no se puede crear nada.

**Cómo lo mitigamos.** Se reescribió declarando los tipos dentro de la especificación de un paquete, que solo requiere el privilegio `CREATE PROCEDURE` que el esquema sí tiene. La restricción del entorno quedó anotada en el script, de modo que quien lo retome entienda por qué no se usó la vía habitual.

---

### 2.3 Pérdida de trazabilidad de las decisiones de diseño

Cuando una herramienta propone una solución y el equipo la adopta sin registrar por qué, el modelo termina conteniendo decisiones que nadie puede explicar. El problema aparece meses después, cuando hay que modificar algo y nadie recuerda qué restricción protegía qué regla.

**Cómo lo mitigamos.** Cada decisión no obvia quedó documentada en el propio código, no en un documento aparte: por qué el índice de la sesión de caja es funcional y no una restricción única, por qué el precio unitario se congela en el detalle de la venta en lugar de leerse del catálogo, por qué el número de ticket se numera por caja y no por sesión. La bitácora de prompts complementa eso registrando qué se pidió y qué se verificó en cada paso.

---

### 2.4 Dependencia y erosión del criterio propio

El riesgo no es usar la herramienta, es dejar de entender lo que produce. Un profesional que entrega código que no puede explicar ni depurar no puede responder por él, y en el momento en que algo falle en producción no tendrá con qué reaccionar.

Es un riesgo progresivo: no se nota en la primera entrega, se nota cuando aparece el primer error que la herramienta no resuelve.

**Cómo lo mitigamos.** El criterio que aplicamos fue que quien sube código al repositorio tiene que poder sustentarlo. Los dos errores descritos arriba se detectaron porque el equipo ejecutó y leyó la salida, no porque la herramienta los advirtiera.

---

### 2.5 Confidencialidad de la información

Los datos de este proyecto son inventados, así que el riesgo no se materializó. En un contexto profesional sí es serio: pegar en una herramienta externa estructuras de base de datos, consultas con lógica de negocio o, peor, datos reales de clientes, implica enviar información de la empresa a un tercero.

En Colombia la Ley 1581 de 2012 regula el tratamiento de datos personales, y un documento de identidad, un nombre o una dirección de un cliente lo son. Compartirlos con un proveedor externo sin autorización ni contrato de tratamiento expone a la organización a sanciones, además del daño reputacional.

**Cómo lo mitigamos.** Todos los datos del script DML son sintéticos. Los nombres, documentos, teléfonos y correos fueron generados para la prueba y no corresponden a ninguna persona real.

---

### 2.6 Propiedad intelectual y licenciamiento

El código generado puede reproducir fragmentos aprendidos de repositorios con licencias restrictivas, y la propiedad del resultado no siempre está clara según los términos del proveedor. En un desarrollo comercial esto puede significar incorporar código con obligaciones de licencia que la empresa no sabe que adquirió.

**Cómo lo mitigamos.** En este proyecto el alcance es académico y el código son patrones estándar de SQL y PL/SQL, sin componentes de terceros. En un contexto profesional la mitigación pasa por una política explícita de la organización sobre qué herramientas se pueden usar y bajo qué condiciones.

---

### 2.7 Sesgo de anclaje en el diseño

La primera solución que propone la herramienta tiende a convertirse en la solución del equipo. Las alternativas no se evalúan porque ya hay algo que funciona, y el diseño queda condicionado por lo que la herramienta ofreció primero en lugar de por lo que el problema requería.

**Cómo lo mitigamos.** En las decisiones estructurales se pidieron explícitamente alternativas con sus ventajas y desventajas antes de elegir. El caso más claro fue cómo vincular los dos ajustes de una transferencia: se evaluaron tres opciones —entidad nueva, autorreferencia y código compartido— y se escogió la entidad nueva con un argumento de normalización, no porque fuera la primera que apareció.

---

### 2.8 Responsabilidad profesional no transferible

Ninguno de los riesgos anteriores se traslada a la herramienta. Si un script borra datos en producción, la responsabilidad es de quien lo ejecutó y de quien lo aprobó. "Lo generó la IA" no es una defensa técnica ni contractual.

Esto cambia dónde está el trabajo del ingeniero: menos en escribir la primera versión y más en especificar bien, verificar con rigor y saber cuándo lo que recibió está mal.

---

## 3. Prácticas que adoptamos

| Práctica | Qué previene |
|---|---|
| Ejecutar todo script contra la base real antes de aceptarlo | 2.1, 2.2 |
| Documentar en el código las decisiones no obvias | 2.3 |
| Quien sube código debe poder sustentarlo | 2.4 |
| Usar únicamente datos sintéticos | 2.5 |
| Pedir alternativas antes de decidir estructura | 2.7 |
| Registrar en la bitácora qué se pidió y qué se verificó | 2.3, 2.8 |
| Revisión por otro integrante mediante pull request | 2.4, 2.8 |

---

## 4. Conclusión

El balance de la Entrega 3 es que la herramienta aceleró de forma clara la parte mecánica —generar 706 inserciones aritméticamente consistentes a mano habría tomado días— y falló en dos puntos donde el conocimiento específico del entorno era decisivo. Los dos fallos los encontró el equipo ejecutando, no revisando.

Esa es la conclusión que nos llevamos: el valor de estas herramientas depende enteramente de la capacidad de verificar lo que producen. Un equipo que puede verificar gana velocidad; uno que no puede, acumula errores que aparecerán más tarde y le costarán más caro.
