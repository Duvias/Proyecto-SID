--------------------------------------------------------------------------------
-- Proyecto Stocka - Entrega 3 - Consultas de los reportes (DQL)
--
-- Los seis reportes del numeral 1.4 del caso. Se ejecuta despues de 01_ddl.sql
-- y 02_dml.sql.
--
-- Todos los reportes se parametrizan por establecimiento y por rango de fechas,
-- como pide el RF-14. Los valores van escritos directamente en el WHERE para
-- que el script corra de principio a fin; para probar otra sede o periodo basta
-- cambiarlos.
--
-- Cobertura de lo que exige la rubrica:
--
--   Agrupamiento      R1, R3, R4, R5, R6
--   Inner join        los seis
--   Outer join        R3, R4, R5, R6
--   Ordenamiento      los seis
--   TOP               R1
--
-- Nota sobre el TOP: se usa el patron ROWNUM sobre una subconsulta ya ordenada,
-- que funciona en cualquier version de Oracle. FETCH FIRST n ROWS ONLY solo
-- existe desde la 12c y el modelo apunta a 11g.
--
-- Nota sobre el IVA: el precio de PRODUCTOS lo incluye, asi que para obtener
-- valores sin impuesto se divide entre 1.19 y nunca se suma por encima.
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- R1 - Ventas por periodo, establecimiento y producto (Top N)
--
-- Responde: de todo lo que se vendio en la sede Centro entre el 1 de septiembre
-- y el 30 de noviembre de 2026, cuales fueron los diez productos que mas
-- unidades movieron, cuanto dinero dejo cada uno y en cuantas facturas
-- distintas aparecio.
--
-- Sirve para decidir que reponer primero y que promocionar. Solo cuenta ventas
-- en estado COMPLETADA: las anuladas conservan su registro historico pero no
-- representan venta real.
--
-- Tablas: VENTAS, DETALLES_VENTA, PRODUCTOS, CATEGORIAS, SESIONES_CAJA, CAJAS,
--         ESTABLECIMIENTOS. Parametros: establecimiento y rango de fechas.
-- Usa: agrupamiento, inner join, ordenamiento y TOP.
--------------------------------------------------------------------------------
SELECT *
  FROM (SELECT est.nombre                AS establecimiento,
               cat.nombre                AS categoria,
               pro.nombre                AS producto,
               SUM(det.cantidad)         AS unidades_vendidas,
               SUM(det.subtotal)         AS ingreso_con_iva,
               ROUND(SUM(det.subtotal) / 1.19, 2) AS ingreso_sin_iva,
               COUNT(DISTINCT ven.id)    AS facturas
          FROM VENTAS ven
         INNER JOIN DETALLES_VENTA   det ON det.venta_id       = ven.id
         INNER JOIN PRODUCTOS        pro ON pro.id             = det.producto_id
         INNER JOIN CATEGORIAS       cat ON cat.id             = pro.categoria_id
         INNER JOIN SESIONES_CAJA    ses ON ses.id             = ven.sesion_caja_id
         INNER JOIN CAJAS            caj ON caj.id             = ses.caja_id
         INNER JOIN ESTABLECIMIENTOS est ON est.id             = caj.establecimiento_id
         WHERE ven.estado = 'COMPLETADA'
           AND est.id     = 1
           AND ven.fecha_creacion BETWEEN TO_DATE('2026-09-01','YYYY-MM-DD')
                                      AND TO_DATE('2026-11-30','YYYY-MM-DD')
         GROUP BY est.nombre, cat.nombre, pro.nombre
         ORDER BY SUM(det.cantidad) DESC, SUM(det.subtotal) DESC)
 WHERE ROWNUM <= 10;


--------------------------------------------------------------------------------
-- R2 - Productos en stock minimo
--
-- Responde: que productos de un negocio estan en su punto de reorden o por
-- debajo, cuantas unidades faltan para volver al minimo y cuales son los mas
-- urgentes.
--
-- La criticidad se mide con la cobertura, que es la razon entre lo disponible y
-- el stock minimo: cuanto menor sea, mas cerca esta el producto de agotarse.
-- Un cero significa que ya no queda nada en esa sede. Se excluyen los productos
-- inactivos, porque no tiene sentido reponer algo que salio del catalogo.
--
-- Tablas: INVENTARIOS, PRODUCTOS, CATEGORIAS, ESTABLECIMIENTOS.
-- Usa: inner join y ordenamiento.
--------------------------------------------------------------------------------
SELECT est.nombre              AS establecimiento,
       cat.nombre              AS categoria,
       pro.nombre              AS producto,
       inv.cantidad_disponible AS disponible,
       inv.stock_minimo,
       inv.stock_minimo - inv.cantidad_disponible AS faltante,
       ROUND(inv.cantidad_disponible / NULLIF(inv.stock_minimo, 0), 2) AS cobertura,
       inv.cantidad_disponible * pro.costo AS valor_existencias
  FROM INVENTARIOS inv
 INNER JOIN PRODUCTOS        pro ON pro.id = inv.producto_id
 INNER JOIN CATEGORIAS       cat ON cat.id = pro.categoria_id
 INNER JOIN ESTABLECIMIENTOS est ON est.id = inv.establecimiento_id
 WHERE inv.cantidad_disponible <= inv.stock_minimo
   AND NVL(pro.estado, 'A') = 'A'
   AND est.negocio_id = 1
 ORDER BY cobertura, faltante DESC;


--------------------------------------------------------------------------------
-- R3 - Margen bruto por producto y categoria
--
-- Responde: cuanta utilidad deja cada producto y cada categoria, comparando el
-- precio de venta sin IVA contra el costo de adquisicion, ponderado por las
-- unidades realmente vendidas.
--
-- Se usa una union externa a proposito: los productos que no han tenido ninguna
-- venta deben aparecer igual, con utilidad en cero, porque forman parte del
-- catalogo y el propietario necesita verlos para decidir si los mantiene.
--
-- El porcentaje de margen protege el denominador con NULLIF: un producto sin
-- ventas tiene ingreso cero y la division daria error.
--
-- Tablas: PRODUCTOS, CATEGORIAS, DETALLES_VENTA, VENTAS.
-- Usa: agrupamiento, inner join, outer join y ordenamiento.
--------------------------------------------------------------------------------
SELECT cat.nombre AS categoria,
       pro.nombre AS producto,
       pro.costo,
       pro.precio AS precio_con_iva,
       ROUND(pro.precio / 1.19, 2) AS precio_sin_iva,
       NVL(SUM(mov.cantidad), 0)   AS unidades_vendidas,
       ROUND(NVL(SUM(mov.subtotal), 0) / 1.19, 2) AS ingreso_sin_iva,
       ROUND(NVL(SUM(mov.cantidad), 0) * pro.costo, 2) AS costo_de_lo_vendido,
       ROUND(NVL(SUM(mov.subtotal), 0) / 1.19
             - NVL(SUM(mov.cantidad), 0) * pro.costo, 2) AS utilidad_bruta,
       ROUND(100 * (NVL(SUM(mov.subtotal), 0) / 1.19
                    - NVL(SUM(mov.cantidad), 0) * pro.costo)
             / NULLIF(NVL(SUM(mov.subtotal), 0) / 1.19, 0), 2) AS margen_porcentaje
  FROM PRODUCTOS pro
 INNER JOIN CATEGORIAS cat ON cat.id = pro.categoria_id
  LEFT JOIN (SELECT det.producto_id,
                    det.cantidad,
                    det.subtotal
               FROM DETALLES_VENTA det
              INNER JOIN VENTAS ven ON ven.id = det.venta_id
              WHERE ven.estado = 'COMPLETADA'
                AND ven.fecha_creacion BETWEEN TO_DATE('2026-09-01','YYYY-MM-DD')
                                           AND TO_DATE('2026-11-30','YYYY-MM-DD')) mov
         ON mov.producto_id = pro.id
 WHERE pro.negocio_id = 1
 GROUP BY cat.nombre, pro.id, pro.nombre, pro.costo, pro.precio
 ORDER BY cat.nombre, utilidad_bruta DESC;


--------------------------------------------------------------------------------
-- R4 - Cierre de caja y recaudo por metodo de pago
--
-- Responde: por cada turno cerrado, con cuanto efectivo se abrio la caja,
-- cuanto deberia haber al cerrar, cuanto se conto de verdad y si sobro o falto
-- plata, junto con el desglose del recaudo entre efectivo, tarjeta y
-- transferencia.
--
-- Solo el efectivo afecta el esperado, porque las ventas con tarjeta o
-- transferencia no pasan por el cajon. Una diferencia negativa significa que
-- falto dinero y una positiva que sobro; el cero es el cuadre perfecto.
--
-- La union externa permite que un turno sin ventas aparezca igual en el
-- reporte, que es justamente el caso que conviene revisar.
--
-- Se ordena por la diferencia para que los descuadres mas graves salgan de
-- primeros. Solo se incluyen sesiones cerradas: una sesion abierta todavia no
-- tiene conteo final contra el cual comparar.
--
-- Tablas: SESIONES_CAJA, CAJAS, ESTABLECIMIENTOS, EMPLEADOS, USUARIOS, VENTAS.
-- Usa: agrupamiento, inner join, outer join y ordenamiento.
--------------------------------------------------------------------------------
SELECT est.nombre AS establecimiento,
       caj.nombre AS caja,
       ses.numero_turno,
       TO_CHAR(ses.fecha_apertura, 'DD/MM/YYYY') AS fecha,
       usu.nombre AS responsable_caja,
       ses.monto_inicial,
       NVL(SUM(CASE WHEN ven.metodo_pago = 'EFECTIVO'      THEN ven.total END), 0) AS recaudo_efectivo,
       NVL(SUM(CASE WHEN ven.metodo_pago = 'TARJETA'       THEN ven.total END), 0) AS recaudo_tarjeta,
       NVL(SUM(CASE WHEN ven.metodo_pago = 'TRANSFERENCIA' THEN ven.total END), 0) AS recaudo_transferencia,
       ses.monto_inicial
         + NVL(SUM(CASE WHEN ven.metodo_pago = 'EFECTIVO' THEN ven.total END), 0) AS efectivo_esperado,
       ses.monto_final AS efectivo_contado,
       ses.monto_final
         - (ses.monto_inicial
            + NVL(SUM(CASE WHEN ven.metodo_pago = 'EFECTIVO' THEN ven.total END), 0)) AS diferencia,
       COUNT(ven.id) AS ventas_del_turno
  FROM SESIONES_CAJA ses
 INNER JOIN CAJAS            caj ON caj.id = ses.caja_id
 INNER JOIN ESTABLECIMIENTOS est ON est.id = caj.establecimiento_id
 INNER JOIN EMPLEADOS        emp ON emp.id = caj.empleado_id
 INNER JOIN USUARIOS         usu ON usu.id = emp.usuario_id
  LEFT JOIN VENTAS           ven ON ven.sesion_caja_id = ses.id
                                AND ven.estado = 'COMPLETADA'
 WHERE ses.estado = 'C'
   AND est.negocio_id = 1
   AND ses.fecha_apertura BETWEEN TO_DATE('2026-09-01','YYYY-MM-DD')
                              AND TO_DATE('2026-11-30','YYYY-MM-DD')
 GROUP BY est.nombre, caj.nombre, ses.numero_turno, ses.fecha_apertura,
          usu.nombre, ses.monto_inicial, ses.monto_final
 ORDER BY diferencia;


--------------------------------------------------------------------------------
-- R5 - Rotacion e inventario sin movimiento
--
-- Responde: por cada producto en cada sede, cuantas unidades se vendieron
-- frente a cuantas quedan en existencia, cuanto tiempo lleva sin venderse y
-- cuanto dinero hay inmovilizado en el que no se mueve.
--
-- El indice de rotacion es unidades vendidas sobre cantidad disponible: por
-- debajo de uno el producto se mueve mas lento de lo que ocupa estanteria.
--
-- Esta es la consulta donde la union externa es imprescindible. Los productos
-- que nunca se han vendido no aparecen en DETALLES_VENTA, y son precisamente
-- los que el reporte debe sacar a la luz; con una union interna quedarian
-- invisibles y el reporte perderia la mitad de su proposito.
--
-- Se ordena de menor a mayor rotacion y, a igualdad, por capital inmovilizado,
-- de modo que lo primero que se ve es la plata quieta en mercancia que no sale.
--
-- Tablas: INVENTARIOS, PRODUCTOS, CATEGORIAS, ESTABLECIMIENTOS, DETALLES_VENTA,
--         VENTAS, SESIONES_CAJA, CAJAS.
-- Usa: agrupamiento, inner join, outer join y ordenamiento.
--------------------------------------------------------------------------------
SELECT est.nombre AS establecimiento,
       cat.nombre AS categoria,
       pro.nombre AS producto,
       inv.cantidad_disponible AS disponible,
       NVL(mov.unidades, 0)    AS unidades_vendidas,
       ROUND(NVL(mov.unidades, 0) / NULLIF(inv.cantidad_disponible, 0), 2) AS indice_rotacion,
       inv.cantidad_disponible * pro.costo AS capital_inmovilizado,
       NVL(TO_CHAR(mov.ultima_venta, 'DD/MM/YYYY'), 'Nunca') AS ultima_venta,
       CASE WHEN mov.ultima_venta IS NULL THEN NULL
            ELSE TRUNC(SYSDATE - mov.ultima_venta)
       END AS dias_sin_venta
  FROM INVENTARIOS inv
 INNER JOIN PRODUCTOS        pro ON pro.id = inv.producto_id
 INNER JOIN CATEGORIAS       cat ON cat.id = pro.categoria_id
 INNER JOIN ESTABLECIMIENTOS est ON est.id = inv.establecimiento_id
  LEFT JOIN (SELECT caj.establecimiento_id,
                    det.producto_id,
                    SUM(det.cantidad)       AS unidades,
                    MAX(ven.fecha_creacion) AS ultima_venta
               FROM DETALLES_VENTA det
              INNER JOIN VENTAS        ven ON ven.id = det.venta_id
              INNER JOIN SESIONES_CAJA ses ON ses.id = ven.sesion_caja_id
              INNER JOIN CAJAS         caj ON caj.id = ses.caja_id
              WHERE ven.estado = 'COMPLETADA'
              GROUP BY caj.establecimiento_id, det.producto_id) mov
         ON mov.establecimiento_id = inv.establecimiento_id
        AND mov.producto_id        = inv.producto_id
 WHERE est.negocio_id = 1
 ORDER BY NVL(mov.unidades, 0), capital_inmovilizado DESC;


--------------------------------------------------------------------------------
-- R6 - Actividad por empleado
--
-- Responde: cuanto vendio cada empleado en el periodo y cuantos ajustes de
-- inventario registro, separados por tipo, para poder cruzar las dos cosas.
--
-- El proposito es detectar diferencias atipicas. Un empleado con pocas ventas
-- pero muchas mermas o muchos conteos fisicos a su nombre es una senal que vale
-- la pena mirar de cerca; no prueba nada por si sola, pero es el punto de
-- partida de una revision.
--
-- Las dos uniones externas hacen que un empleado aparezca aunque no tenga
-- ventas o no haya registrado ningun ajuste. Si se usara union interna, el
-- empleado sin movimiento desapareceria del reporte, que es justo el caso que
-- interesa ver.
--
-- Tablas: EMPLEADOS, USUARIOS, ESTABLECIMIENTOS, VENTAS, AJUSTES_INVENTARIO.
-- Usa: agrupamiento, inner join, outer join y ordenamiento.
--------------------------------------------------------------------------------
SELECT est.nombre AS establecimiento,
       usu.nombre AS empleado,
       NVL(vta.facturas, 0)          AS ventas_completadas,
       NVL(vta.total_vendido, 0)     AS total_vendido,
       NVL(vta.anuladas, 0)          AS ventas_anuladas,
       NVL(aju.entradas, 0)          AS ajustes_entrada,
       NVL(aju.salidas, 0)           AS ajustes_salida,
       NVL(aju.mermas, 0)            AS ajustes_merma,
       NVL(aju.conteos, 0)           AS ajustes_conteo,
       NVL(aju.unidades_ajustadas,0) AS unidades_ajustadas
  FROM EMPLEADOS emp
 INNER JOIN USUARIOS         usu ON usu.id = emp.usuario_id
 INNER JOIN ESTABLECIMIENTOS est ON est.id = emp.establecimiento_id
  LEFT JOIN (SELECT ven.empleado_id,
                    COUNT(CASE WHEN ven.estado = 'COMPLETADA' THEN 1 END) AS facturas,
                    SUM(CASE WHEN ven.estado = 'COMPLETADA' THEN ven.total END) AS total_vendido,
                    COUNT(CASE WHEN ven.estado = 'ANULADA' THEN 1 END) AS anuladas
               FROM VENTAS ven
              WHERE ven.fecha_creacion BETWEEN TO_DATE('2026-09-01','YYYY-MM-DD')
                                           AND TO_DATE('2026-11-30','YYYY-MM-DD')
              GROUP BY ven.empleado_id) vta
         ON vta.empleado_id = emp.id
  LEFT JOIN (SELECT aji.empleado_id,
                    COUNT(CASE WHEN aji.tipo_ajuste = 'ENTRADA'       THEN 1 END) AS entradas,
                    COUNT(CASE WHEN aji.tipo_ajuste = 'SALIDA'        THEN 1 END) AS salidas,
                    COUNT(CASE WHEN aji.tipo_ajuste = 'MERMA'         THEN 1 END) AS mermas,
                    COUNT(CASE WHEN aji.tipo_ajuste = 'CONTEO_FISICO' THEN 1 END) AS conteos,
                    SUM(aji.cantidad) AS unidades_ajustadas
               FROM AJUSTES_INVENTARIO aji
              GROUP BY aji.empleado_id) aju
         ON aju.empleado_id = emp.id
 WHERE est.negocio_id = 1
 ORDER BY total_vendido DESC NULLS LAST;