--------------------------------------------------------------------------------
-- Proyecto Stocka - Entrega 3 - Script PL/SQL
--
-- Contiene dos procedimientos almacenados, una funcion y un disparador.
-- Cada objeto resuelve una regla de negocio que ya venia escrita en el caso,
-- en el numeral 2.3 o en las historias de usuario.
--
--   FN_EFECTIVO_ESPERADO    funcion       efectivo que deberia haber en caja
--   SP_REGISTRAR_VENTA      procedimiento venta completa como transaccion unica
--   SP_CERRAR_SESION_CAJA   procedimiento cierre de turno con su diferencia
--   TRG_VENTAS_SESION_ABIERTA  disparador no deja vender con la caja cerrada
--
--------------------------------------------------------------------------------
-- IMPORTANTE SOBRE EL ORDEN DE EJECUCION
--
-- Este script va de ultimo: 01_ddl, 02_dml, 03_dql y despues 04_plsql.
--
-- El disparador rechaza cualquier venta sobre una sesion de caja cerrada, y la
-- mayoria de las ventas del juego de datos pertenecen a turnos ya cerrados. Si
-- se crea el disparador antes de cargar el DML, la carga falla.
--
-- Para volver a cargar los datos desde cero hay que eliminarlo primero:
--     DROP TRIGGER TRG_VENTAS_SESION_ABIERTA;
-- y volver a crearlo con este script cuando la carga termine.
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- TIPOS DE APOYO
--
-- Permiten que SP_REGISTRAR_VENTA reciba una venta con varias lineas en una
-- sola llamada, como exige el RF-07. Sin ellos habria que llamar al
-- procedimiento una vez por producto y se perderia la atomicidad.
--
-- Los tipos se declaran dentro de un paquete y no con CREATE TYPE a nivel de
-- esquema. La razon es practica: el esquema de la universidad no tiene el
-- privilegio CREATE TYPE, y un tipo declarado en la especificacion de un
-- paquete solo necesita CREATE PROCEDURE, que es el mismo privilegio con el
-- que se crean los procedimientos y la funcion.
--
-- El paquete solo declara tipos, no tiene cuerpo ni logica: el procedimiento
-- sigue siendo un procedimiento almacenado independiente.
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_tipos_venta AS

    -- Una linea de la venta tal como la envia quien llama
    TYPE t_linea_venta IS RECORD (
        producto_id NUMBER(10),
        cantidad    NUMBER(10),
        descuento   NUMBER(12,2)
    );

    -- La coleccion de lineas de una misma venta
    TYPE t_lineas_venta IS TABLE OF t_linea_venta INDEX BY PLS_INTEGER;

END pkg_tipos_venta;
/


--------------------------------------------------------------------------------
-- FUNCION: FN_EFECTIVO_ESPERADO
--
-- Que hace
--   Devuelve cuanto efectivo deberia haber en una caja en un momento dado:
--   el monto con el que se abrio el turno mas todas las ventas en efectivo
--   completadas de esa sesion.
--
-- Por que existe
--   La regla de la HU-07 dice que solo el efectivo afecta el esperado de la
--   sesion: las ventas con tarjeta o transferencia no pasan por el cajon. Esa
--   formula se necesita en dos lugares distintos, el reporte R4 y el cierre de
--   caja, y tenerla en un solo sitio evita que las dos versiones se separen.
--
-- Parametros
--   p_sesion_id   identificador de la sesion de caja
--
-- Devuelve
--   NUMBER con el efectivo esperado, en pesos.
--
-- Excepciones
--   -20001  la sesion de caja no existe
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_efectivo_esperado (
    p_sesion_id IN NUMBER
) RETURN NUMBER
IS
    v_monto_inicial SESIONES_CAJA.monto_inicial%TYPE;
    v_efectivo      NUMBER(12,2);
BEGIN
    SELECT monto_inicial
      INTO v_monto_inicial
      FROM SESIONES_CAJA
     WHERE id = p_sesion_id;

    SELECT NVL(SUM(total), 0)
      INTO v_efectivo
      FROM VENTAS
     WHERE sesion_caja_id = p_sesion_id
       AND estado         = 'COMPLETADA'
       AND metodo_pago    = 'EFECTIVO';

    RETURN v_monto_inicial + v_efectivo;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20001,
            'La sesion de caja ' || p_sesion_id || ' no existe.');
END fn_efectivo_esperado;
/


--------------------------------------------------------------------------------
-- PROCEDIMIENTO: SP_REGISTRAR_VENTA
--
-- Que hace
--   Registra una venta completa: valida, calcula los totales, inserta el
--   encabezado en VENTAS, inserta cada linea en DETALLES_VENTA y descuenta las
--   existencias del establecimiento. Todo ocurre como una sola transaccion: si
--   algo falla en cualquier punto, no queda nada a medias.
--
-- Por que existe
--   El requerimiento no funcional del numeral 2.3 pide exactamente eso: "la
--   venta, su detalle y la actualizacion de existencias se registran como una
--   unica transaccion atomica". Hacerlo desde la aplicacion con tres sentencias
--   sueltas deja la puerta abierta a que se descuente inventario de una venta
--   que nunca se grabo, o al reves.
--
-- Validaciones que aplica, todas antes de escribir nada
--   1. La venta trae al menos una linea y todas con cantidad positiva.
--   2. El empleado existe y esta activo.
--   3. La caja pertenece al establecimiento del empleado.
--   4. La caja tiene una sesion abierta (HU-01: no se vende con el turno cerrado).
--   5. El producto tiene inventario en ese establecimiento y tiene precio.
--   6. Hay existencias suficientes (HU-01: rechaza la venta si no alcanzan).
--
-- Como calcula el dinero
--   El precio de PRODUCTOS ya incluye el IVA del 19%, asi que el total es la
--   suma de precio por cantidad menos descuentos, y de ahi se extrae la base
--   dividiendo entre 1.19. El impuesto es la diferencia. Nunca se suma el IVA
--   por encima del precio.
--
--   El numero de ticket se calcula como el siguiente consecutivo de la caja,
--   no de la sesion, porque la regla del caso dice "correlativo y unico por
--   caja".
--
-- Parametros
--   p_empleado_id  empleado que realiza la venta
--   p_caja_id      caja en la que se cobra
--   p_cliente_id   cliente, o NULL si es venta a consumidor final
--   p_metodo_pago  EFECTIVO, TARJETA o TRANSFERENCIA
--   p_lineas       coleccion de lineas (producto, cantidad, descuento)
--   p_venta_id     SALIDA: identificador de la venta creada
--
-- Excepciones
--   -20010  la venta no trae lineas
--   -20011  cantidad menor o igual que cero
--   -20012  el empleado no existe o esta inactivo
--   -20013  la caja no pertenece al establecimiento del empleado
--   -20014  la caja no tiene una sesion abierta
--   -20015  el producto no tiene inventario en ese establecimiento
--   -20016  el producto no tiene precio de venta asignado
--   -20017  existencias insuficientes
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_venta (
    p_empleado_id IN  NUMBER,
    p_caja_id     IN  NUMBER,
    p_cliente_id  IN  NUMBER,
    p_metodo_pago IN  VARCHAR2,
    p_lineas      IN  pkg_tipos_venta.t_lineas_venta,
    p_venta_id    OUT NUMBER
) IS
    k                    PLS_INTEGER;
    v_establecimiento_id EMPLEADOS.establecimiento_id%TYPE;
    v_caja_est_id        CAJAS.establecimiento_id%TYPE;
    v_sesion_id          SESIONES_CAJA.id%TYPE;
    v_ticket             NUMBER(10);
    v_precio             PRODUCTOS.precio%TYPE;
    v_disponible         INVENTARIOS.cantidad_disponible%TYPE;
    v_total              NUMBER(12,2) := 0;
    v_descuento          NUMBER(12,2) := 0;
    v_subtotal           NUMBER(12,2);
    v_impuesto           NUMBER(12,2);
    v_linea_subtotal     NUMBER(12,2);
BEGIN
    ----------------------------------------------------------------------------
    -- 1. La venta tiene que traer lineas
    ----------------------------------------------------------------------------
    IF p_lineas.COUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20010,
            'La venta debe tener al menos una linea de detalle.');
    END IF;

    ----------------------------------------------------------------------------
    -- 2. El empleado existe y esta activo
    ----------------------------------------------------------------------------
    BEGIN
        SELECT establecimiento_id
          INTO v_establecimiento_id
          FROM EMPLEADOS
         WHERE id     = p_empleado_id
           AND activo = 'S';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20012,
                'El empleado ' || p_empleado_id || ' no existe o esta inactivo.');
    END;

    ----------------------------------------------------------------------------
    -- 3. La caja es del mismo establecimiento del empleado
    ----------------------------------------------------------------------------
    BEGIN
        SELECT establecimiento_id
          INTO v_caja_est_id
          FROM CAJAS
         WHERE id = p_caja_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20013,
                'La caja ' || p_caja_id || ' no existe.');
    END;

    IF v_caja_est_id <> v_establecimiento_id THEN
        RAISE_APPLICATION_ERROR(-20013,
            'La caja ' || p_caja_id || ' no pertenece al establecimiento del empleado.');
    END IF;

    ----------------------------------------------------------------------------
    -- 4. La caja tiene una sesion abierta
    ----------------------------------------------------------------------------
    BEGIN
        SELECT id
          INTO v_sesion_id
          FROM SESIONES_CAJA
         WHERE caja_id = p_caja_id
           AND estado  = 'A';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20014,
                'La caja ' || p_caja_id || ' no tiene una sesion abierta.');
    END;

    ----------------------------------------------------------------------------
    -- 5. Validar cada linea y acumular los totales, sin escribir todavia
    ----------------------------------------------------------------------------
    -- Se recorre con FIRST y NEXT en lugar de un FOR numerico, para que
    -- funcione igual si quien llama dejo huecos en los indices.
    k := p_lineas.FIRST;
    WHILE k IS NOT NULL LOOP

        IF NVL(p_lineas(k).cantidad, 0) <= 0 THEN
            RAISE_APPLICATION_ERROR(-20011,
                'La cantidad del producto ' || p_lineas(k).producto_id ||
                ' debe ser mayor que cero.');
        END IF;

        BEGIN
            SELECT pro.precio, inv.cantidad_disponible
              INTO v_precio, v_disponible
              FROM PRODUCTOS   pro
              JOIN INVENTARIOS inv ON inv.producto_id = pro.id
             WHERE pro.id                  = p_lineas(k).producto_id
               AND inv.establecimiento_id  = v_establecimiento_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20015,
                    'El producto ' || p_lineas(k).producto_id ||
                    ' no tiene inventario en este establecimiento.');
        END;

        IF v_precio IS NULL THEN
            RAISE_APPLICATION_ERROR(-20016,
                'El producto ' || p_lineas(k).producto_id ||
                ' no tiene precio de venta asignado.');
        END IF;

        IF v_disponible < p_lineas(k).cantidad THEN
            RAISE_APPLICATION_ERROR(-20017,
                'Existencias insuficientes del producto ' || p_lineas(k).producto_id ||
                '. Disponible: ' || v_disponible ||
                ', solicitado: ' || p_lineas(k).cantidad || '.');
        END IF;

        v_total     := v_total + (v_precio * p_lineas(k).cantidad)
                       - NVL(p_lineas(k).descuento, 0);
        v_descuento := v_descuento + NVL(p_lineas(k).descuento, 0);

        k := p_lineas.NEXT(k);
    END LOOP;

    ----------------------------------------------------------------------------
    -- 6. Extraer el IVA del total, que ya viene incluido en el precio
    ----------------------------------------------------------------------------
    v_subtotal := ROUND(v_total / 1.19, 2);
    v_impuesto := v_total - v_subtotal;

    ----------------------------------------------------------------------------
    -- 7. Consecutivo del ticket, por caja
    ----------------------------------------------------------------------------
    SELECT NVL(MAX(ven.numero_ticket), 0) + 1
      INTO v_ticket
      FROM VENTAS        ven
      JOIN SESIONES_CAJA ses ON ses.id = ven.sesion_caja_id
     WHERE ses.caja_id = p_caja_id;

    ----------------------------------------------------------------------------
    -- 8. Encabezado de la venta
    ----------------------------------------------------------------------------
    p_venta_id := SEQ_VENTAS.NEXTVAL;

    INSERT INTO VENTAS (id, empleado_id, sesion_caja_id, cliente_id, numero_ticket,
                        subtotal, impuesto, descuento, total, metodo_pago, estado,
                        fecha_creacion, fecha_actualizacion)
    VALUES (p_venta_id, p_empleado_id, v_sesion_id, p_cliente_id, v_ticket,
            v_subtotal, v_impuesto, v_descuento, v_total, p_metodo_pago, 'COMPLETADA',
            SYSDATE, SYSDATE);

    ----------------------------------------------------------------------------
    -- 9. Lineas del detalle y descuento de existencias
    ----------------------------------------------------------------------------
    k := p_lineas.FIRST;
    WHILE k IS NOT NULL LOOP

        SELECT precio
          INTO v_precio
          FROM PRODUCTOS
         WHERE id = p_lineas(k).producto_id;

        v_linea_subtotal := (v_precio * p_lineas(k).cantidad)
                            - NVL(p_lineas(k).descuento, 0);

        INSERT INTO DETALLES_VENTA (id, venta_id, producto_id, precio_unitario,
                                    cantidad, descuento, subtotal)
        VALUES (SEQ_DETALLES_VENTA.NEXTVAL, p_venta_id, p_lineas(k).producto_id,
                v_precio, p_lineas(k).cantidad, NVL(p_lineas(k).descuento, 0),
                v_linea_subtotal);

        UPDATE INVENTARIOS
           SET cantidad_disponible = cantidad_disponible - p_lineas(k).cantidad,
               fecha_actualizacion = SYSDATE
         WHERE producto_id        = p_lineas(k).producto_id
           AND establecimiento_id = v_establecimiento_id;

        k := p_lineas.NEXT(k);
    END LOOP;

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        -- Si algo fallo, la venta no queda a medias: ni encabezado, ni detalle,
        -- ni descuento de inventario.
        ROLLBACK;
        RAISE;
END sp_registrar_venta;
/


--------------------------------------------------------------------------------
-- PROCEDIMIENTO: SP_CERRAR_SESION_CAJA
--
-- Que hace
--   Cierra un turno de caja: recibe el efectivo que el cajero conto fisicamente,
--   lo compara contra el esperado y deja la sesion en estado cerrado con su
--   monto final y su fecha de cierre. Devuelve la diferencia.
--
-- Por que existe
--   La HU-07 pide que quede constancia de si sobro o falto dinero al cerrar, y
--   la regla del numeral 2.3 dice que una sesion cerrada no se vuelve a
--   modificar. Centralizar el cierre en un procedimiento es lo que garantiza
--   que las dos cosas pasen juntas y en el orden correcto.
--
--   Reutiliza FN_EFECTIVO_ESPERADO en vez de repetir la formula, que es la
--   razon por la que esa funcion existe.
--
-- Parametros
--   p_sesion_id      sesion que se va a cerrar
--   p_monto_contado  efectivo contado fisicamente al cerrar
--   p_diferencia     SALIDA: contado menos esperado. Negativo si falto plata,
--                    positivo si sobro, cero si cuadro exacto.
--
-- Excepciones
--   -20030  la sesion ya esta cerrada
--   -20031  la sesion no existe
--   -20032  el monto contado es negativo
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_cerrar_sesion_caja (
    p_sesion_id     IN  NUMBER,
    p_monto_contado IN  NUMBER,
    p_diferencia    OUT NUMBER
) IS
    v_estado   SESIONES_CAJA.estado%TYPE;
    v_esperado NUMBER(12,2);
BEGIN
    IF NVL(p_monto_contado, -1) < 0 THEN
        RAISE_APPLICATION_ERROR(-20032,
            'El monto contado no puede ser negativo ni nulo.');
    END IF;

    -- FOR UPDATE bloquea la fila mientras se cierra, para que dos cierres
    -- simultaneos del mismo turno no se pisen.
    BEGIN
        SELECT estado
          INTO v_estado
          FROM SESIONES_CAJA
         WHERE id = p_sesion_id
           FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20031,
                'La sesion de caja ' || p_sesion_id || ' no existe.');
    END;

    IF v_estado = 'C' THEN
        RAISE_APPLICATION_ERROR(-20030,
            'La sesion de caja ' || p_sesion_id || ' ya esta cerrada.');
    END IF;

    v_esperado   := fn_efectivo_esperado(p_sesion_id);
    p_diferencia := p_monto_contado - v_esperado;

    UPDATE SESIONES_CAJA
       SET monto_final         = p_monto_contado,
           estado              = 'C',
           fecha_cierre        = SYSDATE,
           fecha_actualizacion = SYSDATE
     WHERE id = p_sesion_id;

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_cerrar_sesion_caja;
/


--------------------------------------------------------------------------------
-- DISPARADOR: TRG_VENTAS_SESION_ABIERTA
--
-- Que hace
--   Antes de insertar una venta, verifica que la sesion de caja a la que se
--   asocia este abierta. Si esta cerrada, lanza un error con mensaje propio y
--   la venta no se graba.
--
-- Por que existe
--   La regla del numeral 2.3 dice que "solo se registran ventas con una sesion
--   de caja abierta" y que "una sesion cerrada no se modifica". El
--   procedimiento SP_REGISTRAR_VENTA ya valida eso, pero la validacion vive en
--   la aplicacion: cualquiera que escriba un INSERT directo contra la tabla se
--   la salta. El disparador cierra ese camino, porque actua sin importar por
--   donde llegue la escritura.
--
--   Es la diferencia entre una regla que la aplicacion respeta y una regla que
--   la base de datos garantiza.
--
-- Cuando actua
--   BEFORE INSERT, fila por fila, sobre VENTAS.
--
-- Excepciones
--   -20020  la sesion de caja esta cerrada
--   -20021  la sesion de caja no existe
--------------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_ventas_sesion_abierta
    BEFORE INSERT ON VENTAS
    FOR EACH ROW
DECLARE
    v_estado SESIONES_CAJA.estado%TYPE;
BEGIN
    SELECT estado
      INTO v_estado
      FROM SESIONES_CAJA
     WHERE id = :NEW.sesion_caja_id;

    IF v_estado <> 'A' THEN
        RAISE_APPLICATION_ERROR(-20020,
            'No se puede registrar la venta: la sesion de caja ' ||
            :NEW.sesion_caja_id || ' esta cerrada.');
    END IF;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20021,
            'La sesion de caja ' || :NEW.sesion_caja_id || ' no existe.');
END trg_ventas_sesion_abierta;
/


--------------------------------------------------------------------------------
-- Comprobacion de que los cuatro objetos quedaron compilados y validos.
-- La columna STATUS debe decir VALID en los cuatro.
--------------------------------------------------------------------------------
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name IN ('PKG_TIPOS_VENTA', 'FN_EFECTIVO_ESPERADO',
                       'SP_REGISTRAR_VENTA', 'SP_CERRAR_SESION_CAJA',
                       'TRG_VENTAS_SESION_ABIERTA')
 ORDER BY object_type, object_name;