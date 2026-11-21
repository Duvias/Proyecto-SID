--------------------------------------------------------------------------------
-- Proyecto Stocka - Entrega 3 - Pruebas de los objetos PL/SQL
--
-- No hace parte de los entregables exigidos: sirve para demostrar en la
-- sustentacion que los cuatro objetos funcionan, y para dejar evidencia de que
-- se probaron contra la base cargada.
--
-- OJO: este script MODIFICA datos. Registra una venta real, descuenta
-- inventario y cierra una sesion de caja. Despues de correrlo, los conteos de
-- los reportes cambian un poco. Al final hay un bloque para dejar todo como
-- estaba si se quieren volver a ejecutar las pruebas.
--
-- Ejecutar con F5 y SERVEROUTPUT activado.
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON;


--------------------------------------------------------------------------------
-- PREPARACION
--
-- Deja la sesion 14 abierta. Es necesario porque la prueba 5 la cierra, y sin
-- esto el script solo se podria ejecutar una vez. Si la sesion ya esta abierta
-- no cambia nada.
--------------------------------------------------------------------------------
UPDATE SESIONES_CAJA
   SET estado              = 'A',
       monto_final         = NULL,
       fecha_cierre        = NULL,
       fecha_actualizacion = SYSDATE
 WHERE id = 14;
COMMIT;


--------------------------------------------------------------------------------
-- Estado de partida: las sesiones abiertas y el inventario que vamos a tocar
--------------------------------------------------------------------------------
SELECT ses.id AS sesion, caj.nombre AS caja, est.nombre AS establecimiento,
       ses.monto_inicial, fn_efectivo_esperado(ses.id) AS efectivo_esperado
  FROM SESIONES_CAJA ses
  JOIN CAJAS            caj ON caj.id = ses.caja_id
  JOIN ESTABLECIMIENTOS est ON est.id = caj.establecimiento_id
 WHERE ses.estado = 'A'
 ORDER BY ses.id;

SELECT pro.id, pro.nombre, inv.cantidad_disponible
  FROM INVENTARIOS inv
  JOIN PRODUCTOS   pro ON pro.id = inv.producto_id
 WHERE inv.establecimiento_id = 1
   AND pro.id IN (1, 19);


--------------------------------------------------------------------------------
-- PRUEBA 1 - Venta valida con dos lineas
--
-- Empleado 1 (Marta Lucia Obando) cobra en la Caja 2 Centro, que tiene la
-- sesion 14 abierta, dos gaseosas y tres paquetes de galletas al cliente 3.
-- Debe crear la venta, su detalle y descontar el inventario.
--------------------------------------------------------------------------------
DECLARE
    v_lineas   pkg_tipos_venta.t_lineas_venta;
    v_venta_id NUMBER;
BEGIN
    v_lineas(1).producto_id := 1;    -- Gaseosa personal 400 ml
    v_lineas(1).cantidad    := 2;
    v_lineas(1).descuento   := 0;

    v_lineas(2).producto_id := 19;   -- Galletas de sal x6
    v_lineas(2).cantidad    := 3;
    v_lineas(2).descuento   := 0;

    sp_registrar_venta(
        p_empleado_id => 1,
        p_caja_id     => 2,
        p_cliente_id  => 3,
        p_metodo_pago => 'EFECTIVO',
        p_lineas      => v_lineas,
        p_venta_id    => v_venta_id);

    DBMS_OUTPUT.PUT_LINE('PRUEBA 1 correcta. Venta registrada con id ' || v_venta_id);
END;
/

-- La venta quedo con el IVA extraido del precio, no sumado encima:
-- total = subtotal + impuesto, y subtotal = total / 1.19
SELECT id, numero_ticket, subtotal, impuesto, total, metodo_pago, estado
  FROM VENTAS
 WHERE id = (SELECT MAX(id) FROM VENTAS);

SELECT producto_id, precio_unitario, cantidad, descuento, subtotal
  FROM DETALLES_VENTA
 WHERE venta_id = (SELECT MAX(id) FROM VENTAS);

-- Y el inventario bajo en las cantidades vendidas
SELECT pro.id, pro.nombre, inv.cantidad_disponible
  FROM INVENTARIOS inv
  JOIN PRODUCTOS   pro ON pro.id = inv.producto_id
 WHERE inv.establecimiento_id = 1
   AND pro.id IN (1, 19);


--------------------------------------------------------------------------------
-- PRUEBA 2 - Venta rechazada por existencias insuficientes
--
-- Se piden 9999 unidades de un producto que no las tiene. El procedimiento debe
-- rechazarla antes de escribir nada: ni venta, ni detalle, ni descuento.
--------------------------------------------------------------------------------
DECLARE
    v_lineas   pkg_tipos_venta.t_lineas_venta;
    v_venta_id NUMBER;
BEGIN
    v_lineas(1).producto_id := 1;
    v_lineas(1).cantidad    := 9999;
    v_lineas(1).descuento   := 0;

    sp_registrar_venta(
        p_empleado_id => 1,
        p_caja_id     => 2,
        p_cliente_id  => NULL,
        p_metodo_pago => 'TARJETA',
        p_lineas      => v_lineas,
        p_venta_id    => v_venta_id);

    DBMS_OUTPUT.PUT_LINE('FALLO DE LA PRUEBA 2: la venta no debio registrarse.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('PRUEBA 2 correcta. El procedimiento rechazo la venta:');
        DBMS_OUTPUT.PUT_LINE('   ' || SQLERRM);
END;
/


--------------------------------------------------------------------------------
-- PRUEBA 3 - Venta rechazada porque la caja no tiene sesion abierta
--
-- La Caja 1 Centro no tiene ningun turno abierto en este momento.
--------------------------------------------------------------------------------
DECLARE
    v_lineas   pkg_tipos_venta.t_lineas_venta;
    v_venta_id NUMBER;
BEGIN
    v_lineas(1).producto_id := 1;
    v_lineas(1).cantidad    := 1;
    v_lineas(1).descuento   := 0;

    sp_registrar_venta(
        p_empleado_id => 1,
        p_caja_id     => 1,
        p_cliente_id  => NULL,
        p_metodo_pago => 'EFECTIVO',
        p_lineas      => v_lineas,
        p_venta_id    => v_venta_id);

    DBMS_OUTPUT.PUT_LINE('FALLO DE LA PRUEBA 3: la venta no debio registrarse.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('PRUEBA 3 correcta. El procedimiento rechazo la venta:');
        DBMS_OUTPUT.PUT_LINE('   ' || SQLERRM);
END;
/


--------------------------------------------------------------------------------
-- PRUEBA 4 - El disparador bloquea un INSERT directo sobre una sesion cerrada
--
-- Esta es la prueba que demuestra para que sirve el disparador: aqui no se
-- pasa por el procedimiento, se escribe directo contra la tabla, que es
-- justamente el camino que la validacion de la aplicacion no cubre.
-- La sesion 1 esta cerrada desde septiembre.
--------------------------------------------------------------------------------
BEGIN
    INSERT INTO VENTAS (id, empleado_id, sesion_caja_id, cliente_id, numero_ticket,
                        subtotal, impuesto, descuento, total, metodo_pago, estado,
                        fecha_creacion, fecha_actualizacion)
    VALUES (SEQ_VENTAS.NEXTVAL, 1, 1, NULL, 9999,
            8403.36, 1596.64, 0, 10000, 'EFECTIVO', 'COMPLETADA', SYSDATE, SYSDATE);

    DBMS_OUTPUT.PUT_LINE('FALLO DE LA PRUEBA 4: el disparador no actuo.');
    ROLLBACK;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('PRUEBA 4 correcta. El disparador rechazo la venta:');
        DBMS_OUTPUT.PUT_LINE('   ' || SQLERRM);
        ROLLBACK;
END;
/


--------------------------------------------------------------------------------
-- PRUEBA 5 - Cierre de caja con la funcion calculando el esperado
--
-- Se cierra la sesion 14 declarando un conteo fisico 5000 pesos por debajo del
-- esperado, para que la diferencia salga negativa y se vea el faltante.
--------------------------------------------------------------------------------
DECLARE
    v_esperado   NUMBER;
    v_diferencia NUMBER;
BEGIN
    v_esperado := fn_efectivo_esperado(14);
    DBMS_OUTPUT.PUT_LINE('Efectivo esperado en la sesion 14: ' || v_esperado);

    sp_cerrar_sesion_caja(
        p_sesion_id     => 14,
        p_monto_contado => v_esperado - 5000,
        p_diferencia    => v_diferencia);

    DBMS_OUTPUT.PUT_LINE('PRUEBA 5 correcta. Sesion cerrada. Diferencia: ' || v_diferencia);
END;
/


--------------------------------------------------------------------------------
-- PRUEBA 6 - No se puede cerrar dos veces la misma sesion
--------------------------------------------------------------------------------
DECLARE
    v_diferencia NUMBER;
BEGIN
    sp_cerrar_sesion_caja(14, 100000, v_diferencia);
    DBMS_OUTPUT.PUT_LINE('FALLO DE LA PRUEBA 6: no debio permitir el segundo cierre.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('PRUEBA 6 correcta. El procedimiento rechazo el cierre:');
        DBMS_OUTPUT.PUT_LINE('   ' || SQLERRM);
END;
/

SELECT id, estado, monto_inicial, monto_final,
       TO_CHAR(fecha_cierre, 'DD/MM/YYYY HH24:MI') AS cerrada_el
  FROM SESIONES_CAJA
 WHERE id = 14;


--------------------------------------------------------------------------------
-- DEVOLVER LOS DATOS AL ESTADO DE LA CARGA
--
-- El script se puede repetir tal cual, porque el bloque de preparacion vuelve a
-- abrir la sesion 14. Pero cada ejecucion deja una venta nueva y descuenta
-- inventario, asi que si se quiere volver exactamente a los numeros que dan los
-- reportes del 03_dql, hay que descomentar esto y ejecutarlo.
--
-- Las ventas del juego de datos llegan hasta el id 112; las de las pruebas usan
-- la secuencia, que arranca en 1000.
--------------------------------------------------------------------------------
-- DELETE FROM DETALLES_VENTA WHERE venta_id IN (SELECT id FROM VENTAS WHERE id > 112);
-- DELETE FROM VENTAS WHERE id > 112;
-- UPDATE INVENTARIOS SET cantidad_disponible = cantidad_disponible + 2
--  WHERE establecimiento_id = 1 AND producto_id = 1;
-- UPDATE INVENTARIOS SET cantidad_disponible = cantidad_disponible + 3
--  WHERE establecimiento_id = 1 AND producto_id = 19;
-- UPDATE SESIONES_CAJA
--    SET estado = 'A', monto_final = NULL, fecha_cierre = NULL
--  WHERE id = 14;
-- COMMIT;