# Stocka — Sistema de inventario y ventas para micronegocios

Proyecto de curso de **Sistemas Intensivos en Datos**
Universidad Icesi · Semestre 2026-2

---

## Sobre el proyecto

Stocka es un sistema de punto de venta e inventario pensado para micronegocios colombianos: tiendas de barrio, minimercados y pequeños comercios que hoy llevan sus ventas y existencias a mano o en una hoja de cálculo.

El sistema es multi-negocio. Cada negocio es un inquilino independiente con su propio catálogo, sus clientes y sus sedes, y la jerarquía operativa va de Negocio a Establecimiento, de ahí a Caja y finalmente a Sesión de caja, que es el turno de trabajo con el que se abre y se cierra el cajón. Las existencias se llevan por producto y establecimiento, de modo que cada sede tiene inventario propio.

El modelo está ajustado al contexto colombiano: los valores van en pesos, los precios de venta incluyen el IVA del 19 % —que se extrae del precio y no se suma encima— y los documentos y teléfonos siguen el formato local.

Este repositorio contiene el diseño completo de la base de datos que soporta el caso: el modelo conceptual, su transformación al modelo relacional normalizado en tercera forma normal, y los scripts de creación, carga, consulta y lógica procedimental.

**Alcance.** El proyecto cubre el núcleo transaccional y de inventario. Quedan fuera, por pertenecer a otras capas del sistema real, las suscripciones y planes SaaS, la pasarela de pagos, la facturación electrónica, el catálogo granular de permisos y el modo sin conexión del punto de venta. Tampoco se modelan proveedores ni compras: la mercancía entra al sistema como un ajuste de inventario de tipo entrada.

---

## Equipo

| Estudiante | Código | Rol | GitHub |
|---|---|---|---|
| Juan Jacobo Sandoval | A00410787 | Líder de proyecto y analista de requerimientos | Jacobo100206 |
| Felipe Cuadros Muñoz | A00410604 | Arquitecto de datos | WertyDeluxe |
| Juan Fernando Devia | A00410871 | Desarrollador de base de datos | Duvias |
| Isabella Sandoval | A00411190 | Gestora de calidad | issa04-sand |

---

## Estructura del repositorio

### Documentación — `Entrega3/docs`

- [Bitácora de prompts](Entrega3/docs/bitacora_prompts.md) — registro de las interacciones con la herramienta de IA generativa durante la entrega, con lo que se pidió, lo que devolvió y lo que el equipo verificó o corrigió en cada caso.
- [Riesgos del uso de IA generativa](Entrega3/docs/riesgos_ia_generativa.md) — ocho riesgos identificados en el uso de estas herramientas para trabajo de bases de datos, documentados a partir de lo que ocurrió en el desarrollo.

### Modelos — `Entrega3/model`

- [Modelo conceptual (MER)](Entrega3/model/logico/Logical.pdf) — modelo entidad-relación del caso, construido en Oracle SQL Developer Data Modeler.
- [Modelo relacional normalizado](Entrega3/model/relacional/Relational.pdf) — resultado de la transformación del MER, en tercera forma normal.
- [Fuentes del modelo](Entrega3/model/fuentes/stocka.zip) — diseño completo de Data Modeler, con el archivo `.dmd` y su carpeta. Los dos modelos viven en el mismo diseño.
- [Notas del modelo](Entrega3/model/README.md)

### Scripts — `Entrega3/src`

- [Stocka_DDL.sql](Entrega3/src/Stocka_DDL.sql) — crea las 15 tablas con sus restricciones, los índices, las 15 secuencias y los comentarios de documentación en el diccionario de datos.
- [Stocka_DML.sql](Entrega3/src/Stocka_DML.sql) — carga 706 registros de prueba, dimensionados para que cada uno de los seis reportes devuelva al menos diez filas.
- [Stocka_DQL.sql](Entrega3/src/Stocka_DQL.sql) — las consultas de los seis reportes del caso, cada una con su descripción en lenguaje natural.
- [04_plsql.sql](Entrega3/src/04_plsql.sql) — una función, dos procedimientos almacenados y un disparador, documentados.
- [05_plsql_pruebas.sql](Entrega3/src/05_plsql_pruebas.sql) — seis pruebas que demuestran el funcionamiento de los objetos PL/SQL.

---

## Cómo ejecutar los scripts

Los scripts deben correrse en este orden sobre un esquema Oracle:

| Orden | Script | Qué hace |
|---|---|---|
| 1 | `Stocka_DDL.sql` | Crea la estructura de la base de datos |
| 2 | `Stocka_DML.sql` | Carga los datos de prueba |
| 3 | `Stocka_DQL.sql` | Ejecuta los seis reportes |
| 4 | `04_plsql.sql` | Crea los objetos PL/SQL |

El `05_plsql_pruebas.sql` se ejecuta al final y es opcional: no hace parte de los entregables, sirve para demostrar que los objetos funcionan. Modifica datos.

**Importante.** El disparador `TRG_VENTAS_SESION_ABIERTA` impide registrar ventas sobre sesiones de caja cerradas, y la mayoría de las ventas del juego de datos pertenecen a turnos ya cerrados. Por eso el PL/SQL va de último. Para volver a cargar los datos hay que eliminar el disparador primero con `DROP TRIGGER TRG_VENTAS_SESION_ABIERTA;` y recrearlo cuando la carga termine.
