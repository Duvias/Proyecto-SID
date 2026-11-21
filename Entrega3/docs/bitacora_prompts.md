# Bitácora de prompts — Entrega 3

**Proyecto Stocka** · Sistemas Intensivos en Datos, Universidad Icesi
**Herramienta:** Claude (Anthropic) · **Nivel de uso de IAG autorizado:** 4 — IAG completa
**Periodo:** 20 y 21 de noviembre de 2026

---

## Nota sobre esta bitácora

Las entradas cubren la Entrega 3 y las correcciones de la Entrega 2 que se aplicaron en la misma sesión de trabajo. Las entregas anteriores se desarrollaron bajo nivel 2 de uso de IAG y sus registros están en las bitácoras correspondientes.

Los prompts se transcriben con corrección de redacción —frases completas y ortografía— manteniendo el contenido y la intención originales.

La columna de verificación es la que importa: registra qué hizo el equipo con lo que la herramienta devolvió. En tres entradas la salida tuvo que corregirse, y esos casos están desarrollados en la sección 3.

---

## 1. Correcciones de la Entrega 2

| # | Fecha | Objetivo | Prompt | Verificación y resultado |
|---|---|---|---|---|
| 1 | 20/11 | Entender las nueve correcciones de la monitora antes de aplicarlas | Adjunto el PDF con las correcciones de la monitora sobre la Entrega 2. Necesito revisarlas una por una antes de aplicarlas en el modelo. | Se extrajeron las nueve anotaciones del PDF y se ordenaron por tipo. El equipo decidió el orden de aplicación: primero las estructurales, la de nomenclatura al final. |
| 2 | 20/11 | Corrección 3: tipos de datos en VENTAS y unicidad del ticket | Necesito el paso a paso para aplicar la corrección de los tipos de datos de VENTAS en Oracle SQL Developer Data Modeler. | Se aplicó en el modelo. La herramienta propuso dos alternativas para la unicidad del ticket; se escogió la clave única por sesión de caja porque la alternativa introducía una dependencia transitiva que rompe la 3FN. |
| 3 | 20/11 | Corrección 4: relación VENTA–CLIENTE opcional | Aplicar la corrección de la relación entre VENTA y CLIENTE. | Verificado en el DDL exportado: la columna quedó sin `NOT NULL`. Se registró como límite conocido que el modelo no impide asociar una venta a un cliente de otro negocio. |
| 4 | 20/11 | Corrección 7: clave única de existencias por sede | Aplicar la restricción única compuesta sobre INVENTARIO. | Aplicada. Se documentó como clave alterna de la tabla, manteniendo la clave primaria sustituta. |
| 5 | 20/11 | Corrección 8: negocio propietario del producto | Aplicar la corrección del negocio propietario en PRODUCTO y la unicidad del código de barras. | Aplicada. La herramienta señaló que CATEGORIA tiene el mismo problema; el equipo decidió dejar las categorías como globales del sistema y documentarlo. |
| 6 | 20/11 | Corrección 9: columna sin función clara | Revisar qué es la columna `id_detalle_venta1` y si debe eliminarse. | Diagnóstico: residuo de la ingeniería del modelo lógico al relacional. El equipo confirmó que no existía en el modelo lógico y la eliminó. |
| 7 | 20/11 | Corrección 5: tipos y ciclo de vida de la sesión de caja | Aplicar la corrección de los tipos de la sesión de caja y la restricción de una sola sesión abierta. | Se corrigieron los tipos y se agregó `fecha_cierre`, que faltaba. La restricción de sesión única se aplazó a la Entrega 3 por requerir un índice funcional. |
| 8 | 20/11 | Corrección 6: vincular los ajustes de una transferencia | Resolver cómo identificar que dos ajustes de inventario pertenecen a la misma transferencia. | Se pidieron alternativas antes de decidir. De las tres evaluadas se escogió crear la entidad TRANSFERENCIA, por argumento de normalización: los atributos del traslado dependen de él y no de cada ajuste. |
| 9 | 20/11 | Correcciones 1 y 2: nomenclatura | El profesor confirmó que no es necesario pasar el modelo a inglés. Solo se pluralizaron las tablas. Necesito el resto de la unificación de nombres en español. | Se replanteó el alcance. Se produjo el mapa de renombramiento de columnas, claves y restricciones. |
| 10 | 21/11 | Organizar la carpeta `model` del repositorio | Necesito organizar la carpeta model con el MER, el modelo relacional y el enlace a las fuentes. | Se definió la estructura. La herramienta advirtió que el `.dmd` no sirve sin su carpeta; se verificó el contenido del zip con `unzip -l` antes de subirlo. |

---

## 2. Entrega 3

| # | Fecha | Objetivo | Prompt | Verificación y resultado |
|---|---|---|---|---|
| 11 | 20/11 | Diagnóstico del DDL exportado del Data Modeler | Adjunto el DDL exportado del modelo. Necesito saber si está correcto antes de usarlo. | La herramienta identificó 26 errores del exportador: cuatro nombres de más de 30 caracteres y veinte columnas `VARCHAR2` sin tamaño. El equipo confirmó cada uno contra el archivo. |
| 12 | 20/11 | Script DDL documentado | Transformar el modelo en el script DDL de la base de datos, debidamente documentado. | Se revisó tabla por tabla contra el modelo. Se verificó que el script corriera con cero errores en Oracle antes de darlo por bueno. |
| 13 | 20/11 | Definición de los reportes | Adjunto el documento del caso de la Entrega 0 con los reportes R1 a R6. | Se detectó que la herramienta había inferido cinco reportes de fuentes indirectas cuando el caso define seis. Se corrigió a partir del documento original. |
| 14 | 20/11 | Script DML con datos para los seis reportes | Generar el script de inserciones con las tuplas necesarias para que cada reporte devuelva al menos diez registros. | 706 inserciones. El equipo ejecutó en Oracle y comprobó: cero errores, totales de venta iguales a la suma de sus detalles, IVA extraído del precio y no sumado, y ninguna existencia negativa. |
| 15 | 20/11 | Corrección del DDL tras fallo en Oracle | Ejecuté el DML y la salida arrojó tres tipos de error. Adjunto el registro completo. | Ver sección 3.1. El equipo detectó el fallo ejecutando; la herramienta no lo había previsto. |
| 16 | 21/11 | Organización de los commits | Necesito dividir en commits lo que está pendiente de subir. Adjunto la salida de `git status`. | Se detectó que el índice contenía dos copias del diseño ya borradas del disco. Se limpió antes de hacer commit, evitando 290 archivos de ruido en el historial. |
| 17 | 21/11 | Consultas de los seis reportes | Escribir las consultas DQL de los reportes definidos, con agrupamiento, uniones interna y externa, ordenamiento y al menos un TOP, con descripción en lenguaje natural. | Se ejecutaron las seis en Oracle. Conteos obtenidos: 10, 22, 24, 12, 58 y 12 filas, todos por encima del mínimo exigido. Se verificó que el desglose por método de pago de R4 sumara el total de cada sesión. |
| 18 | 21/11 | Objetos PL/SQL | Escribir el script PL/SQL con al menos un procedimiento almacenado, una función y un disparador, documentados. | Ver sección 3.2. Un objeto quedó inválido en la primera compilación. |
| 19 | 21/11 | Corrección del PL/SQL por restricción de privilegios | El `CREATE TYPE` falla con `ORA-01031`. Adjunto la salida de la compilación. | Reescrito con tipos en paquete. Segunda ejecución: cinco objetos `VALID` y las seis pruebas superadas. |
| 20 | 21/11 | Documento de riesgos y esta bitácora | Elaborar el documento de riesgos del uso de IA generativa y la bitácora de prompts. | En borrador. El equipo aportó los casos reales ocurridos durante el desarrollo. |

---

## 3. Incidentes que exigieron corrección

Estos tres casos se registran aparte porque son la evidencia concreta de los riesgos descritos en `riesgos_ia_generativa.md`.

### 3.1 Clave única compuesta con columna opcional

**Entrada 15.** El DDL generado declaraba `UNIQUE (transferencia_id, tipo_ajuste)` sobre AJUSTES_INVENTARIO. La herramienta la verificó contra un motor de prueba y la dio por correcta.

Al ejecutar el DML en Oracle fallaron 83 de 93 inserciones con `ORA-00001`. Oracle documenta que en una clave única compuesta parcialmente nula no admite valores repetidos en las columnas con valor, de modo que la tabla solo aceptaba un ajuste de cada tipo en todo el sistema. El conteo de inserciones exitosas lo confirmó: exactamente cuatro con transferencia nula —una por tipo— más las seis de las transferencias.

**Corrección.** Índice único funcional que deja la clave completamente nula en los ajustes sin transferencia. Se aplicó la misma corrección preventiva al código de barras de PRODUCTOS, que tenía el mismo defecto latente y aún no había fallado porque todos los productos de prueba tienen código.

### 3.2 Privilegio no disponible en el esquema

**Entrada 18.** El procedimiento de registro de venta usaba `CREATE TYPE` para la colección de líneas. El esquema del curso respondió `ORA-01031: privilegios insuficientes` y el procedimiento quedó `INVALID`.

**Corrección.** Los tipos se declararon en la especificación de un paquete, que solo requiere `CREATE PROCEDURE`. Los otros tres objetos habían compilado bien en el primer intento.

### 3.3 Reportes inferidos de fuente indirecta

**Entrada 13.** Antes de recibir el documento del caso, la herramienta reconstruyó los reportes a partir de actas de reunión del repositorio. Esas actas describían un esquema con entidades COMPRA, PROVEEDOR y DEVOLUCION que el modelo no tiene, y los reportes inferidos eran cinco en lugar de seis.

**Corrección.** Se entregó el documento original de la Entrega 0 y se rehízo el trabajo sobre los seis reportes del numeral 1.4. El equipo tomó nota de la inconsistencia entre las actas y el modelo entregado.

---

## 4. Balance del uso de la herramienta

**Dónde aportó.** En el trabajo mecánico de volumen: generar 706 inserciones aritméticamente consistentes entre sí, con totales que cuadran, IVA extraído correctamente y saldos de inventario que nunca quedan negativos. Hacerlo a mano habría tomado días y habría sido más propenso a error. También en el diagnóstico rápido de salidas largas de error.

**Dónde falló.** En los dos puntos donde el conocimiento específico del entorno era decisivo: la semántica de nulos de Oracle y los privilegios reales del esquema. En ambos casos el código parecía correcto y compilaba.

**Qué nos deja.** Los dos fallos los encontró el equipo ejecutando contra la base, no revisando el código a ojo. Esa es la práctica que vale la pena conservar.
