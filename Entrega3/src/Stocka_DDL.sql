--------------------------------------------------------------------------------
-- Proyecto Stocka - Sistema de inventario y ventas para pequenos negocios
-- Entrega 3 - Script DDL
--
-- Motor objetivo : Oracle Database 11g (compatible con versiones superiores)
-- Esquema        : 15 tablas, 15 secuencias
--
-- Convenciones de nomenclatura aplicadas:
--   Tablas          : plural, mayusculas, snake_case          (VENTAS)
--   Columnas        : singular, minusculas, snake_case        (precio_unitario)
--   Clave primaria  : siempre "id"                            (PRODUCTOS.id)
--   Clave foranea   : <padre_singular>_id                     (producto_id)
--   Auditoria       : fecha_creacion / fecha_actualizacion
--   Otros momentos  : fecha_<evento>                          (fecha_apertura)
--   Restricciones   : <TABLA>_PK, <HIJA>_<PADRE>_FK, <TABLA>_<COL>_UK/_CK
--
-- Ningun identificador usa tildes ni enies, y ninguno supera los 30 caracteres
-- que admite Oracle 11g.
--
-- Orden del script:
--   1. Tablas (en orden de dependencia, de padres a hijas)
--   2. Claves foraneas
--   3. Secuencias
--   4. Comentarios de documentacion
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- 1. TABLAS
--------------------------------------------------------------------------------

-- NEGOCIOS: empresa propietaria de la cuenta en Stocka. Es la raiz de todo el
-- modelo: cada negocio tiene sus propias sedes, su catalogo y sus clientes.
CREATE TABLE NEGOCIOS (
    id                  NUMBER(10)      NOT NULL,
    nombre              VARCHAR2(100)   NOT NULL,
    direccion           VARCHAR2(200)   NOT NULL,
    telefono            VARCHAR2(20)    NOT NULL,
    email               VARCHAR2(150)   NOT NULL,
    fecha_creacion      DATE            NOT NULL,
    fecha_actualizacion DATE            NOT NULL,
    CONSTRAINT NEGOCIOS_PK PRIMARY KEY (id)
);

-- ROLES: perfiles de permisos que puede tener un usuario dentro del sistema
-- (administrador, cajero, bodeguero).
CREATE TABLE ROLES (
    id          NUMBER(10)      NOT NULL,
    nombre      VARCHAR2(100)   NOT NULL,
    descripcion VARCHAR2(200)   NOT NULL,
    CONSTRAINT ROLES_PK PRIMARY KEY (id)
);

-- USUARIOS: credenciales de acceso al sistema. Un usuario pertenece a un
-- negocio y tiene un rol. Las fechas de vencimiento de token quedan nulas
-- cuando no hay ningun proceso de verificacion o recuperacion en curso.
CREATE TABLE USUARIOS (
    id                            NUMBER(10)      NOT NULL,
    rol_id                        NUMBER(10)      NOT NULL,
    negocio_id                    NUMBER(10)      NOT NULL,
    nombre                        VARCHAR2(100)   NOT NULL,
    email                         VARCHAR2(150)   NOT NULL,
    clave_hash                    VARCHAR2(255)   NOT NULL,
    telefono                      VARCHAR2(20)    NOT NULL,
    activo                        CHAR(1)         NOT NULL,
    correo_verificado             CHAR(1)         NOT NULL,
    fecha_vencimiento_token_email DATE,
    fecha_vencimiento_token_clave DATE,
    fecha_creacion                DATE            NOT NULL,
    fecha_actualizacion           DATE            NOT NULL,
    CONSTRAINT USUARIOS_PK PRIMARY KEY (id),
    CONSTRAINT USUARIOS_EMAIL_UK UNIQUE (email),
    CONSTRAINT USUARIOS_ACTIVO_CK CHECK (activo IN ('S','N')),
    CONSTRAINT USUARIOS_CORREO_VERIF_CK CHECK (correo_verificado IN ('S','N'))
);

-- ESTABLECIMIENTOS: sedes fisicas del negocio. Cada punto de venta con su
-- propio inventario y sus propias cajas.
CREATE TABLE ESTABLECIMIENTOS (
    id         NUMBER(10)      NOT NULL,
    negocio_id NUMBER(10)      NOT NULL,
    nombre     VARCHAR2(100)   NOT NULL,
    direccion  VARCHAR2(200),
    CONSTRAINT ESTABLECIMIENTOS_PK PRIMARY KEY (id)
);

-- EMPLEADOS: persona que trabaja en una sede. Se separa de USUARIOS porque no
-- todo usuario del sistema es empleado de una sede (el dueno del negocio, por
-- ejemplo). La clave unica sobre usuario_id garantiza la relacion uno a uno.
CREATE TABLE EMPLEADOS (
    id                  NUMBER(10)  NOT NULL,
    usuario_id          NUMBER(10)  NOT NULL,
    establecimiento_id  NUMBER(10)  NOT NULL,
    activo              CHAR(1)     NOT NULL,
    fecha_creacion      DATE        NOT NULL,
    fecha_actualizacion DATE        NOT NULL,
    CONSTRAINT EMPLEADOS_PK PRIMARY KEY (id),
    CONSTRAINT EMPLEADOS_USUARIO_UK UNIQUE (usuario_id),
    CONSTRAINT EMPLEADOS_ACTIVO_CK CHECK (activo IN ('S','N'))
);

-- CLIENTES: compradores registrados del negocio. La clave unica evita que el
-- mismo documento se registre dos veces dentro de un mismo negocio, pero
-- permite que el mismo documento exista en negocios distintos.
CREATE TABLE CLIENTES (
    id               NUMBER(10)     NOT NULL,
    negocio_id       NUMBER(10)     NOT NULL,
    tipo_documento   VARCHAR2(5)    NOT NULL,
    numero_documento VARCHAR2(20)   NOT NULL,
    nombre           VARCHAR2(100)  NOT NULL,
    telefono         VARCHAR2(20)   NOT NULL,
    email            VARCHAR2(150),
    direccion        VARCHAR2(200),
    CONSTRAINT CLIENTES_PK PRIMARY KEY (id),
    CONSTRAINT CLIENTES_DOCUMENTO_UK UNIQUE (negocio_id, tipo_documento, numero_documento)
);

-- CATEGORIAS: clasificacion del catalogo de productos.
CREATE TABLE CATEGORIAS (
    id          NUMBER(10)      NOT NULL,
    nombre      VARCHAR2(100)   NOT NULL,
    descripcion VARCHAR2(200)   NOT NULL,
    estado      CHAR(1)         NOT NULL,
    CONSTRAINT CATEGORIAS_PK PRIMARY KEY (id),
    CONSTRAINT CATEGORIAS_ESTADO_CK CHECK (estado IN ('A','I'))
);

-- PRODUCTOS: catalogo de articulos. El producto pertenece a un negocio, lo que
-- permite separar catalogos entre negocios distintos y garantizar que el codigo
-- de barras sea unico dentro de cada uno. El codigo es opcional porque hay
-- articulos que no lo tienen (venta a granel, preparados en el local).
CREATE TABLE PRODUCTOS (
    id            NUMBER(10)      NOT NULL,
    negocio_id    NUMBER(10)      NOT NULL,
    categoria_id  NUMBER(10)      NOT NULL,
    codigo_barras VARCHAR2(20),
    nombre        VARCHAR2(100)   NOT NULL,
    descripcion   VARCHAR2(200),
    costo         NUMBER(12,2)    NOT NULL,
    precio        NUMBER(12,2),
    estado        CHAR(1),
    CONSTRAINT PRODUCTOS_PK PRIMARY KEY (id),
    CONSTRAINT PRODUCTOS_ESTADO_CK CHECK (estado IN ('A','I'))
);

-- Codigo de barras unico por negocio.
-- No se puede usar una restriccion UNIQUE (negocio_id, codigo_barras) normal:
-- en Oracle, cuando una clave unica compuesta queda parcialmente nula, se
-- comparan solo las columnas con valor, de modo que esa restriccion permitiria
-- un unico producto sin codigo de barras en todo el sistema. El indice
-- funcional deja la clave completamente nula en esos casos, y Oracle no indexa
-- las filas cuya clave es nula por completo.
CREATE UNIQUE INDEX PRODUCTOS_CODIGO_BARRAS_UK ON PRODUCTOS
    (CASE WHEN codigo_barras IS NOT NULL THEN negocio_id    END,
     CASE WHEN codigo_barras IS NOT NULL THEN codigo_barras END);

-- INVENTARIOS: existencias de un producto en una sede. La clave unica sobre
-- (establecimiento, producto) es la clave alterna de la tabla: impide registrar
-- dos veces las existencias del mismo producto en la misma sede.
CREATE TABLE INVENTARIOS (
    id                  NUMBER(10)  NOT NULL,
    establecimiento_id  NUMBER(10)  NOT NULL,
    producto_id         NUMBER(10)  NOT NULL,
    cantidad_disponible NUMBER(10)  NOT NULL,
    stock_minimo        NUMBER(10)  NOT NULL,
    fecha_creacion      DATE        NOT NULL,
    fecha_actualizacion DATE        NOT NULL,
    CONSTRAINT INVENTARIOS_PK PRIMARY KEY (id),
    CONSTRAINT INVENTARIOS_ESTAB_PROD_UK UNIQUE (establecimiento_id, producto_id),
    CONSTRAINT INVENTARIOS_CANTIDAD_CK CHECK (cantidad_disponible >= 0 AND stock_minimo >= 0)
);

-- CAJAS: puntos de cobro fisicos de una sede.
CREATE TABLE CAJAS (
    id                 NUMBER(10)     NOT NULL,
    establecimiento_id NUMBER(10)     NOT NULL,
    empleado_id        NUMBER(10)     NOT NULL,
    nombre             VARCHAR2(100)  NOT NULL,
    CONSTRAINT CAJAS_PK PRIMARY KEY (id)
);

-- SESIONES_CAJA: turno de trabajo de una caja, desde que se abre con un monto
-- inicial hasta que se cierra con el conteo final. El monto final y la fecha de
-- cierre son nulos mientras la sesion sigue abierta.
CREATE TABLE SESIONES_CAJA (
    id                  NUMBER(10)      NOT NULL,
    caja_id             NUMBER(10)      NOT NULL,
    monto_inicial       NUMBER(12,2)    NOT NULL,
    monto_final         NUMBER(12,2),
    estado              CHAR(1)         NOT NULL,
    numero_turno        NUMBER(10)      NOT NULL,
    fecha_apertura      DATE            NOT NULL,
    fecha_cierre        DATE,
    fecha_actualizacion DATE,
    CONSTRAINT SESIONES_CAJA_PK PRIMARY KEY (id),
    CONSTRAINT SESIONES_CAJA_ESTADO_CK CHECK (estado IN ('A','C'))
);

-- Implementa la HU-07: una caja no puede tener dos sesiones abiertas a la vez.
-- No se puede hacer con una restriccion UNIQUE normal porque esa tambien
-- impediria tener varias sesiones cerradas sobre la misma caja, que es lo
-- normal. El indice funcional solo indexa las filas en estado 'A'; las cerradas
-- producen NULL y Oracle no las almacena en el indice.
CREATE UNIQUE INDEX SESIONES_CAJA_ABIERTA_UK ON SESIONES_CAJA
    (CASE WHEN estado = 'A' THEN caja_id END);

-- TRANSFERENCIAS: traslado de mercancia entre dos sedes del mismo negocio.
-- Agrupa los dos ajustes de inventario que genera el movimiento: la salida en
-- la sede de origen y la entrada en la de destino. El origen y el destino no se
-- guardan aqui porque se deducen siguiendo cada ajuste hacia su inventario.
CREATE TABLE TRANSFERENCIAS (
    id              NUMBER(10)      NOT NULL,
    empleado_id     NUMBER(10)      NOT NULL,
    estado          VARCHAR2(15)    NOT NULL,
    motivo          VARCHAR2(200),
    fecha_solicitud DATE            NOT NULL,
    CONSTRAINT TRANSFERENCIAS_PK PRIMARY KEY (id),
    CONSTRAINT TRANSFERENCIAS_ESTADO_CK
        CHECK (estado IN ('PENDIENTE','EN_TRANSITO','RECIBIDA','ANULADA'))
);

-- AJUSTES_INVENTARIO: toda modificacion de existencias que no proviene de una
-- venta (mermas, conteos fisicos, traslados). La transferencia es opcional
-- porque la mayoria de ajustes no vienen de un traslado. La clave unica sobre
-- (transferencia, tipo) impide que un mismo traslado registre dos salidas o dos
-- entradas; los ajustes sueltos tienen la transferencia nula y Oracle permite
-- repetirlos sin restriccion.
CREATE TABLE AJUSTES_INVENTARIO (
    id               NUMBER(10)     NOT NULL,
    inventario_id    NUMBER(10)     NOT NULL,
    empleado_id      NUMBER(10)     NOT NULL,
    transferencia_id NUMBER(10),
    tipo_ajuste      VARCHAR2(20)   NOT NULL,
    cantidad         NUMBER(10)     NOT NULL,
    stock_anterior   NUMBER(10)     NOT NULL,
    stock_nuevo      NUMBER(10)     NOT NULL,
    motivo           VARCHAR2(200)  NOT NULL,
    fecha_ajuste     DATE           NOT NULL,
    CONSTRAINT AJUSTES_INVENTARIO_PK PRIMARY KEY (id),
    CONSTRAINT AJUSTES_INVENTARIO_TIPO_CK
        CHECK (tipo_ajuste IN ('ENTRADA','SALIDA','MERMA','CONTEO_FISICO'))
);

-- Una transferencia no puede registrar dos salidas ni dos entradas.
-- Igual que en PRODUCTOS, no sirve una restriccion UNIQUE normal sobre
-- (transferencia_id, tipo_ajuste): la mayoria de los ajustes no pertenecen a
-- ninguna transferencia y dejan esa columna nula, y Oracle compararia entonces
-- solo el tipo, permitiendo un unico ajuste de cada tipo en toda la tabla.
-- Con el indice funcional, los ajustes sueltos producen una clave totalmente
-- nula que Oracle no indexa, y la restriccion aplica solo a los de traslado.
CREATE UNIQUE INDEX AJUSTES_TRANSFER_TIPO_UK ON AJUSTES_INVENTARIO
    (CASE WHEN transferencia_id IS NOT NULL THEN transferencia_id END,
     CASE WHEN transferencia_id IS NOT NULL THEN tipo_ajuste      END);

-- VENTAS: encabezado de la factura. El cliente es opcional porque se admite la
-- venta a consumidor final sin registrar sus datos. La clave unica garantiza
-- que el numero de ticket no se repita dentro de una misma sesion de caja.
CREATE TABLE VENTAS (
    id                  NUMBER(10)      NOT NULL,
    empleado_id         NUMBER(10)      NOT NULL,
    sesion_caja_id      NUMBER(10)      NOT NULL,
    cliente_id          NUMBER(10),
    numero_ticket       NUMBER(10)      NOT NULL,
    subtotal            NUMBER(12,2)    NOT NULL,
    impuesto            NUMBER(12,2)    NOT NULL,
    descuento           NUMBER(12,2)    NOT NULL,
    total               NUMBER(12,2)    NOT NULL,
    metodo_pago         VARCHAR2(20)    NOT NULL,
    estado              VARCHAR2(15)    NOT NULL,
    fecha_creacion      DATE            NOT NULL,
    fecha_actualizacion DATE            NOT NULL,
    CONSTRAINT VENTAS_PK PRIMARY KEY (id),
    CONSTRAINT VENTAS_NUMERO_TICKET_UK UNIQUE (sesion_caja_id, numero_ticket),
    CONSTRAINT VENTAS_METODO_PAGO_CK
        CHECK (metodo_pago IN ('EFECTIVO','TRANSFERENCIA','TARJETA')),
    CONSTRAINT VENTAS_ESTADO_CK
        CHECK (estado IN ('COMPLETADA','ANULADA','PENDIENTE'))
);

-- DETALLES_VENTA: renglones de la factura. El precio unitario se guarda aqui y
-- no se lee de PRODUCTOS, porque el precio del catalogo cambia con el tiempo y
-- la factura debe conservar el valor con el que se vendio.
CREATE TABLE DETALLES_VENTA (
    id              NUMBER(10)      NOT NULL,
    venta_id        NUMBER(10)      NOT NULL,
    producto_id     NUMBER(10)      NOT NULL,
    precio_unitario NUMBER(12,2)    NOT NULL,
    cantidad        NUMBER(10)      NOT NULL,
    descuento       NUMBER(12,2)    NOT NULL,
    subtotal        NUMBER(12,2)    NOT NULL,
    CONSTRAINT DETALLES_VENTA_PK PRIMARY KEY (id),
    CONSTRAINT DETALLES_VENTA_CANTIDAD_CK CHECK (cantidad > 0)
);


--------------------------------------------------------------------------------
-- 2. CLAVES FORANEAS
--------------------------------------------------------------------------------

ALTER TABLE USUARIOS ADD CONSTRAINT USUARIOS_ROLES_FK
    FOREIGN KEY (rol_id) REFERENCES ROLES (id);

ALTER TABLE USUARIOS ADD CONSTRAINT USUARIOS_NEGOCIOS_FK
    FOREIGN KEY (negocio_id) REFERENCES NEGOCIOS (id);

ALTER TABLE ESTABLECIMIENTOS ADD CONSTRAINT ESTABLECIMIENTOS_NEGOCIOS_FK
    FOREIGN KEY (negocio_id) REFERENCES NEGOCIOS (id);

ALTER TABLE EMPLEADOS ADD CONSTRAINT EMPLEADOS_USUARIOS_FK
    FOREIGN KEY (usuario_id) REFERENCES USUARIOS (id);

ALTER TABLE EMPLEADOS ADD CONSTRAINT EMPLEADOS_ESTABLECIMIENTOS_FK
    FOREIGN KEY (establecimiento_id) REFERENCES ESTABLECIMIENTOS (id);

ALTER TABLE CLIENTES ADD CONSTRAINT CLIENTES_NEGOCIOS_FK
    FOREIGN KEY (negocio_id) REFERENCES NEGOCIOS (id);

ALTER TABLE PRODUCTOS ADD CONSTRAINT PRODUCTOS_NEGOCIOS_FK
    FOREIGN KEY (negocio_id) REFERENCES NEGOCIOS (id);

ALTER TABLE PRODUCTOS ADD CONSTRAINT PRODUCTOS_CATEGORIAS_FK
    FOREIGN KEY (categoria_id) REFERENCES CATEGORIAS (id);

ALTER TABLE INVENTARIOS ADD CONSTRAINT INVENTARIOS_ESTABLECIM_FK
    FOREIGN KEY (establecimiento_id) REFERENCES ESTABLECIMIENTOS (id);

ALTER TABLE INVENTARIOS ADD CONSTRAINT INVENTARIOS_PRODUCTOS_FK
    FOREIGN KEY (producto_id) REFERENCES PRODUCTOS (id);

ALTER TABLE CAJAS ADD CONSTRAINT CAJAS_ESTABLECIMIENTOS_FK
    FOREIGN KEY (establecimiento_id) REFERENCES ESTABLECIMIENTOS (id);

ALTER TABLE CAJAS ADD CONSTRAINT CAJAS_EMPLEADOS_FK
    FOREIGN KEY (empleado_id) REFERENCES EMPLEADOS (id);

ALTER TABLE SESIONES_CAJA ADD CONSTRAINT SESIONES_CAJA_CAJAS_FK
    FOREIGN KEY (caja_id) REFERENCES CAJAS (id);

ALTER TABLE TRANSFERENCIAS ADD CONSTRAINT TRANSFERENCIAS_EMPLEADOS_FK
    FOREIGN KEY (empleado_id) REFERENCES EMPLEADOS (id);

ALTER TABLE AJUSTES_INVENTARIO ADD CONSTRAINT AJUSTES_INVENTARIOS_FK
    FOREIGN KEY (inventario_id) REFERENCES INVENTARIOS (id);

ALTER TABLE AJUSTES_INVENTARIO ADD CONSTRAINT AJUSTES_EMPLEADOS_FK
    FOREIGN KEY (empleado_id) REFERENCES EMPLEADOS (id);

ALTER TABLE AJUSTES_INVENTARIO ADD CONSTRAINT AJUSTES_TRANSFERENCIAS_FK
    FOREIGN KEY (transferencia_id) REFERENCES TRANSFERENCIAS (id);

ALTER TABLE VENTAS ADD CONSTRAINT VENTAS_EMPLEADOS_FK
    FOREIGN KEY (empleado_id) REFERENCES EMPLEADOS (id);

ALTER TABLE VENTAS ADD CONSTRAINT VENTAS_SESIONES_CAJA_FK
    FOREIGN KEY (sesion_caja_id) REFERENCES SESIONES_CAJA (id);

ALTER TABLE VENTAS ADD CONSTRAINT VENTAS_CLIENTES_FK
    FOREIGN KEY (cliente_id) REFERENCES CLIENTES (id);

ALTER TABLE DETALLES_VENTA ADD CONSTRAINT DETALLES_VENTA_VENTAS_FK
    FOREIGN KEY (venta_id) REFERENCES VENTAS (id);

ALTER TABLE DETALLES_VENTA ADD CONSTRAINT DETALLES_VENTA_PRODUCTOS_FK
    FOREIGN KEY (producto_id) REFERENCES PRODUCTOS (id);


--------------------------------------------------------------------------------
-- 3. SECUENCIAS
--
-- Oracle 11g no admite columnas IDENTITY, asi que los identificadores se
-- generan con secuencias. El script DML usa valores literales para que los
-- datos de prueba sean reproducibles; las secuencias arrancan en 1000 para no
-- chocar con esos valores.
--------------------------------------------------------------------------------

CREATE SEQUENCE SEQ_NEGOCIOS           START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_ROLES              START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_USUARIOS           START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_ESTABLECIMIENTOS   START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_EMPLEADOS          START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_CLIENTES           START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_CATEGORIAS         START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_PRODUCTOS          START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_INVENTARIOS        START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_CAJAS              START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_SESIONES_CAJA      START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_TRANSFERENCIAS     START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_AJUSTES_INVENTARIO START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_VENTAS             START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_DETALLES_VENTA     START WITH 1000 INCREMENT BY 1 NOCACHE;


--------------------------------------------------------------------------------
-- 4. COMENTARIOS DE DOCUMENTACION
--
-- Quedan almacenados en el diccionario de datos y se consultan con
-- USER_TAB_COMMENTS y USER_COL_COMMENTS.
--------------------------------------------------------------------------------

COMMENT ON TABLE NEGOCIOS           IS 'Empresa propietaria de la cuenta en Stocka. Raiz del modelo multiempresa.';
COMMENT ON TABLE ROLES              IS 'Perfiles de permisos asignables a un usuario del sistema.';
COMMENT ON TABLE USUARIOS           IS 'Credenciales de acceso al sistema, asociadas a un negocio y a un rol.';
COMMENT ON TABLE ESTABLECIMIENTOS   IS 'Sedes fisicas de un negocio, cada una con inventario y cajas propias.';
COMMENT ON TABLE EMPLEADOS          IS 'Persona que trabaja en una sede. Relacion uno a uno con USUARIOS.';
COMMENT ON TABLE CLIENTES           IS 'Compradores registrados de un negocio.';
COMMENT ON TABLE CATEGORIAS         IS 'Clasificacion del catalogo de productos.';
COMMENT ON TABLE PRODUCTOS          IS 'Catalogo de articulos de un negocio.';
COMMENT ON TABLE INVENTARIOS        IS 'Existencias de un producto en una sede. Clave alterna: (establecimiento, producto).';
COMMENT ON TABLE CAJAS              IS 'Puntos de cobro fisicos de una sede.';
COMMENT ON TABLE SESIONES_CAJA      IS 'Turno de trabajo de una caja, desde su apertura hasta su cierre.';
COMMENT ON TABLE TRANSFERENCIAS     IS 'Traslado de mercancia entre dos sedes. Agrupa el ajuste de salida y el de entrada.';
COMMENT ON TABLE AJUSTES_INVENTARIO IS 'Modificaciones de existencias que no provienen de una venta.';
COMMENT ON TABLE VENTAS             IS 'Encabezado de la factura de venta.';
COMMENT ON TABLE DETALLES_VENTA     IS 'Renglones de la factura de venta.';

COMMENT ON COLUMN USUARIOS.clave_hash                    IS 'Hash de la contrasena. Nunca se almacena la contrasena en texto plano.';
COMMENT ON COLUMN USUARIOS.activo                        IS 'S = activo, N = inactivo. Baja logica, no se borran usuarios.';
COMMENT ON COLUMN USUARIOS.correo_verificado             IS 'S = correo confirmado por el usuario, N = pendiente.';
COMMENT ON COLUMN USUARIOS.fecha_vencimiento_token_email IS 'Caducidad del token de verificacion de correo. Nula si no hay proceso en curso.';
COMMENT ON COLUMN USUARIOS.fecha_vencimiento_token_clave IS 'Caducidad del token de restablecimiento de clave. Nula si no hay proceso en curso.';
COMMENT ON COLUMN PRODUCTOS.codigo_barras                IS 'Opcional: hay articulos sin codigo (granel, preparados en el local). Unico por negocio.';
COMMENT ON COLUMN PRODUCTOS.costo                        IS 'Costo de adquisicion, usado para calcular el margen.';
COMMENT ON COLUMN PRODUCTOS.estado                       IS 'A = activo en el catalogo, I = inactivo.';
COMMENT ON COLUMN INVENTARIOS.stock_minimo               IS 'Umbral a partir del cual el producto se reporta como proximo a agotarse.';
COMMENT ON COLUMN SESIONES_CAJA.monto_inicial            IS 'Base en efectivo con la que se abre el turno.';
COMMENT ON COLUMN SESIONES_CAJA.monto_final              IS 'Conteo de cierre. Nulo mientras la sesion sigue abierta.';
COMMENT ON COLUMN SESIONES_CAJA.estado                   IS 'A = abierta, C = cerrada. Solo puede haber una abierta por caja (HU-07).';
COMMENT ON COLUMN SESIONES_CAJA.fecha_cierre             IS 'Nula mientras la sesion sigue abierta.';
COMMENT ON COLUMN AJUSTES_INVENTARIO.transferencia_id    IS 'Nulo en los ajustes que no provienen de un traslado entre sedes.';
COMMENT ON COLUMN AJUSTES_INVENTARIO.stock_anterior      IS 'Existencias antes del ajuste, para trazabilidad.';
COMMENT ON COLUMN AJUSTES_INVENTARIO.stock_nuevo         IS 'Existencias despues del ajuste, para trazabilidad.';
COMMENT ON COLUMN VENTAS.cliente_id                      IS 'Nulo en ventas a consumidor final sin registro de cliente.';
COMMENT ON COLUMN VENTAS.numero_ticket                   IS 'Consecutivo del ticket, unico dentro de cada sesion de caja.';
COMMENT ON COLUMN DETALLES_VENTA.precio_unitario         IS 'Precio al momento de la venta. No se lee de PRODUCTOS porque el catalogo cambia.';