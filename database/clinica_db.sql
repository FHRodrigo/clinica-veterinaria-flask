create database ClinicaVeterinaria_DB1
use ClinicaVeterinaria_DB1

-- 1. CREACIÓN DE LA MASTER KEY (Llave Maestra)F1
-- Es la raíz de la jerarquía de cifrado en la base de datos.

CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'PasswordFuerte_Vet2026!*';


-- 2. CREACIÓN DEL CERTIFICADO
-- Se utiliza para proteger la llave simétrica.

CREATE CERTIFICATE CertificadoVeterinaria
WITH SUBJECT = 'Certificado para cifrado de datos sensibles de la clinica';



-- 3. CREACIÓN DE LA SYMMETRIC KEY (Llave Simétrica)
-- Utilizaremos el algoritmo AES_256 como lo solicita el requerimiento.
-- Esta llave cifrará y descifrará los datos reales usando EncryptByKey y DecryptByKey.

CREATE SYMMETRIC KEY LlaveSimetricaVeterinaria
WITH ALGORITHM = AES_256
ENCRYPTION BY CERTIFICATE CertificadoVeterinaria;


OPEN SYMMETRIC KEY LlaveSimetricaVeterinaria 
DECRYPTION BY CERTIFICATE CertificadoVeterinaria;

CLOSE SYMMETRIC KEY LlaveSimetricaVeterinaria;

-- Verificar que la Master Key y la Llave Simétrica (AES_256) existen
SELECT name, key_length, algorithm_desc 
FROM sys.symmetric_keys;

-- Verificar que el Certificado existe
SELECT name, subject, start_date 
FROM sys.certificates;




-- 1. CREACIÓN DE SECUENCIA PARA CONTROL DE FOLIOS
-- Usaremos esta secuencia para generar identificadores de factura legibles (Ej. FAC-1001)
CREATE SEQUENCE Seq_FolioFactura
    START WITH 1000
    INCREMENT BY 1
    MINVALUE 1000
    NO CYCLE;


-- 2. TABLAS PRINCIPALES DEL NEGOCIO


CREATE TABLE Duenos (
    dueno_id INT IDENTITY(1,1) PRIMARY KEY,
    nombre_completo VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE, -- Se requiere índice único; la restricción UNIQUE lo crea automáticamente
    telefono VARCHAR(20),
    direccion VARCHAR(150),
    tipo_documento VARCHAR(20),
    numero_documento VARBINARY(MAX), -- Cifrado
    fecha_registro DATE DEFAULT GETDATE()
);

CREATE TABLE Mascotas (
    mascota_id INT IDENTITY(1,1) PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL,
    especie VARCHAR(50),
    raza VARCHAR(50),
    edad INT,
    peso DECIMAL(5,2),
    dueno_id INT FOREIGN KEY REFERENCES Duenos(dueno_id)
);

CREATE TABLE Veterinarios (
    veterinario_id INT IDENTITY(1,1) PRIMARY KEY,
    nombre_completo VARCHAR(100) NOT NULL,
    especialidad VARCHAR(50),
    cedula_profesional VARBINARY(MAX), -- Cifrada
    usuario VARCHAR(50) UNIQUE NOT NULL,
    contrasena VARBINARY(MAX), -- Cifrada
    estado VARCHAR(20) DEFAULT 'Activo'
);

CREATE TABLE Consultas (
    consulta_id INT IDENTITY(1,1) PRIMARY KEY,
    mascota_id INT FOREIGN KEY REFERENCES Mascotas(mascota_id),
    veterinario_id INT FOREIGN KEY REFERENCES Veterinarios(veterinario_id),
    fecha_consulta DATETIME DEFAULT GETDATE(),
    motivo VARCHAR(150),
    estado VARCHAR(20) DEFAULT 'Programada' 
);

CREATE TABLE Tratamientos (
    tratamiento_id INT IDENTITY(1,1) PRIMARY KEY,
    consulta_id INT FOREIGN KEY REFERENCES Consultas(consulta_id),
    diagnostico VARBINARY(MAX), -- Cifrado
    tratamiento VARBINARY(MAX), -- Cifrado
    observaciones VARBINARY(MAX) -- Cifradas
);

CREATE TABLE Facturas (
    factura_id INT IDENTITY(1,1) PRIMARY KEY,
    folio VARCHAR(20) DEFAULT CONCAT('FAC-', NEXT VALUE FOR Seq_FolioFactura), -- Integración de SEQUENCE
    consulta_id INT FOREIGN KEY REFERENCES Consultas(consulta_id),
    fecha DATE DEFAULT GETDATE(),
    total DECIMAL(10,2),
    metodo_pago VARCHAR(30),
    referencia_pago VARBINARY(MAX) -- Cifrada
);

CREATE TABLE Detalle_Facturas (
    detalle_id INT IDENTITY(1,1) PRIMARY KEY,
    factura_id INT FOREIGN KEY REFERENCES Facturas(factura_id),
    concepto VARCHAR(100),
    cantidad INT,
    precio_unitario DECIMAL(10,2),
    subtotal DECIMAL(10,2)
);



-- 3. TABLA PARA REGISTRO DE ERRORES (Manejo TRY/CATCH)

CREATE TABLE Log_Errores (
    log_id INT IDENTITY(1,1) PRIMARY KEY,
    fecha_error DATETIME DEFAULT GETDATE(),
    usuario_db VARCHAR(100) DEFAULT SUSER_SNAME(),
    numero_error INT,
    mensaje_error VARCHAR(4000),
    linea_error INT,
    procedimiento_origen VARCHAR(200)
);



-- 4. TABLAS DE AUDITORÍA INDEPENDIENTES
-- Registran qué pasó, cuándo y quién lo hizo en las tablas críticas.

CREATE TABLE Audit_Consultas (
    audit_id INT IDENTITY(1,1) PRIMARY KEY,
    consulta_id INT,
    accion VARCHAR(10), -- 'INSERT', 'UPDATE', 'DELETE'
    estado_anterior VARCHAR(20),
    estado_nuevo VARCHAR(20),
    fecha_modificacion DATETIME DEFAULT GETDATE(),
    usuario VARCHAR(50) DEFAULT SUSER_SNAME()
);

CREATE TABLE Audit_Tratamientos (
    audit_id INT IDENTITY(1,1) PRIMARY KEY,
    tratamiento_id INT,
    accion VARCHAR(10),
    fecha_modificacion DATETIME DEFAULT GETDATE(),
    usuario VARCHAR(50) DEFAULT SUSER_SNAME()
);

CREATE TABLE Audit_Facturas (
    audit_id INT IDENTITY(1,1) PRIMARY KEY,
    factura_id INT,
    folio VARCHAR(20),
    accion VARCHAR(10),
    total_anterior DECIMAL(10,2),
    total_nuevo DECIMAL(10,2),
    fecha_modificacion DATETIME DEFAULT GETDATE(),
    usuario VARCHAR(50) DEFAULT SUSER_SNAME()
);



-------------------------------------------INDICIES-------------------------

--–1. Creación de Índices
-- Índice compuesto para buscar consultas por fecha y estado rápidamente
CREATE NONCLUSTERED INDEX IX_Consultas_FechaEstado 
ON Consultas(fecha_consulta, estado);


-- Índice simple para agilizar la búsqueda de facturación por fecha
CREATE NONCLUSTERED INDEX IX_Facturas_Fecha 
on Facturas(fecha);




---Procedimientos Almacenados Transaccionales con Cifrado
-- ==============================================================================
-- SP 1: Registrar Dueño (Con cifrado de documento)
-- ==============================================================================
CREATE OR ALTER PROCEDURE sp_RegistrarDueno
    @nombre_completo VARCHAR(100),
    @email VARCHAR(100),
    @telefono VARCHAR(20),
    @direccion VARCHAR(150),
    @tipo_documento VARCHAR(20),
    @numero_documento_plano VARCHAR(100) -- Recibe texto plano desde Python
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- 1. Abrimos la llave simétrica
        OPEN SYMMETRIC KEY LlaveSimetricaVeterinaria 
        DECRYPTION BY CERTIFICATE CertificadoVeterinaria;

        -- 2. Iniciamos la transacción
        BEGIN TRANSACTION;
            
            INSERT INTO Duenos (nombre_completo, email, telefono, direccion, tipo_documento, numero_documento)
            VALUES (
                @nombre_completo, 
                @email, 
                @telefono, 
                @direccion, 
                @tipo_documento, 
                -- Ciframos el texto plano usando la llave
                EncryptByKey(Key_GUID('LlaveSimetricaVeterinaria'), @numero_documento_plano)
            );

        -- 3. Confirmamos transacción
        COMMIT TRANSACTION;

        -- 4. Cerramos la llave por seguridad
        CLOSE SYMMETRIC KEY LlaveSimetricaVeterinaria;

    END TRY
    BEGIN CATCH
        -- Si hay error, deshacemos los cambios
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        
        -- Si la llave quedó abierta debido al error, la cerramos
        IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'LlaveSimetricaVeterinaria')
            CLOSE SYMMETRIC KEY LlaveSimetricaVeterinaria;

        -- Registramos el error en nuestra tabla de auditoría técnica
        INSERT INTO Log_Errores (numero_error, mensaje_error, linea_error, procedimiento_origen)
        VALUES (ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        
        -- Lanzamos el error al backend para que el usuario web se entere
        THROW; 
    END CATCH
END;



-- SP 2: Registrar Consulta (Lógica estándar)

CREATE OR ALTER PROCEDURE sp_RegistrarConsulta
    @mascota_id INT,
    @veterinario_id INT,
    @motivo VARCHAR(150)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
            INSERT INTO Consultas (mascota_id, veterinario_id, fecha_consulta, motivo, estado)
            VALUES (@mascota_id, @veterinario_id, GETDATE(), @motivo, 'Programada');
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        
        INSERT INTO Log_Errores (numero_error, mensaje_error, linea_error, procedimiento_origen)
        VALUES (ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        
        THROW;
    END CATCH
END;



-- SP 3: Generar Tratamiento (Cifrado Múltiple)

CREATE OR ALTER PROCEDURE sp_GenerarTratamiento
    @consulta_id INT,
    @diagnostico_plano VARCHAR(MAX),
    @tratamiento_plano VARCHAR(MAX),
    @observaciones_plano VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        OPEN SYMMETRIC KEY LlaveSimetricaVeterinaria 
        DECRYPTION BY CERTIFICATE CertificadoVeterinaria;

        BEGIN TRANSACTION;
            INSERT INTO Tratamientos (consulta_id, diagnostico, tratamiento, observaciones)
            VALUES (
                @consulta_id,
                EncryptByKey(Key_GUID('LlaveSimetricaVeterinaria'), @diagnostico_plano),
                EncryptByKey(Key_GUID('LlaveSimetricaVeterinaria'), @tratamiento_plano),
                EncryptByKey(Key_GUID('LlaveSimetricaVeterinaria'), @observaciones_plano)
            );
        COMMIT TRANSACTION;

        CLOSE SYMMETRIC KEY LlaveSimetricaVeterinaria;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        
        IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'LlaveSimetricaVeterinaria')
            CLOSE SYMMETRIC KEY LlaveSimetricaVeterinaria;
            
        INSERT INTO Log_Errores (numero_error, mensaje_error, linea_error, procedimiento_origen)
        VALUES (ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        
        THROW;
    END CATCH
END;


--–Procedimiento para Consultar y Descifrar Datos

-- SP 4: Consultar Dueños (Con Descifrado)

CREATE OR ALTER PROCEDURE sp_ConsultarDuenos
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- Abrimos la llave para poder descifrar
        OPEN SYMMETRIC KEY LlaveSimetricaVeterinaria 
        DECRYPTION BY CERTIFICATE CertificadoVeterinaria;

        SELECT 
            dueno_id,
            nombre_completo,
            email,
            telefono,
            tipo_documento,
            -- IMPORTANTE: Convertimos el binario descifrado a VARCHAR legible
            CONVERT(VARCHAR(100), DecryptByKey(numero_documento)) AS numero_documento_legible,
            fecha_registro
        FROM Duenos;

        CLOSE SYMMETRIC KEY LlaveSimetricaVeterinaria;
    END TRY
    BEGIN CATCH
        IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'LlaveSimetricaVeterinaria')
            CLOSE SYMMETRIC KEY LlaveSimetricaVeterinaria;
        THROW;
    END CATCH
END;


----------------PRUEBA 2--------------------------------

-- 1. Insertamos un dueño de prueba
EXEC sp_RegistrarDueno 
    @nombre_completo = 'Carlos Mendoza', 
    @email = 'carlos.men@email.com', 
    @telefono = '555-1234', 
    @direccion = 'Av. Reforma 123', 
    @tipo_documento = 'INE', 
    @numero_documento_plano = 'ABC123456789';

    -- 2. Verificamos cómo se ve en la tabla base (El documento debe verse como hexadecimal ininteligible: 0x005...)
SELECT nombre_completo, numero_documento 
FROM Duenos;

-- 3. Verificamos cómo lo extrae nuestro SP de lectura (Debe decir 'ABC123456789')
EXEC sp_ConsultarDuenos;

-- 4. Forzamos un error para probar el TRY/CATCH (Email duplicado)
-- Ejecuta de nuevo el SP 1 con el mismo correo y luego revisa la tabla de errores:
SELECT * FROM Log_Errores;




----------------PRUEBA 1--------------------------------
-- 1. Verificar las tablas creadas y la cantidad de filas (actualmente 0)
SELECT t.name AS Tabla, p.rows AS Filas
FROM sys.tables t
INNER JOIN sys.partitions p ON t.object_id = p.object_id
WHERE p.index_id IN (0,1);

-- 2. Verificar que los campos sensibles son VARBINARY(MAX)
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE COLUMN_NAME IN ('numero_documento', 'cedula_profesional', 'contrasena', 
                      'diagnostico', 'tratamiento', 'observaciones', 'referencia_pago');

-- 3. Verificar que la secuencia existe
SELECT name, start_value, increment, current_value 
FROM sys.sequences
WHERE name = 'Seq_FolioFactura';



--------------------------TRIGGERS-----------------------------------

-- ==============================================================================
-- TRIGGER 1: Auditoría de Consultas (Evalúa INSERT, UPDATE y DELETE)
-- ==============================================================================
CREATE OR ALTER TRIGGER trg_Audit_Consultas
ON Consultas
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Accion VARCHAR(10);

    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted)
        SET @Accion = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted)
        SET @Accion = 'INSERT';
    ELSE
        SET @Accion = 'DELETE';

    -- Insertamos el registro en la tabla de auditoría, capturando estados antiguos y nuevos
    INSERT INTO Audit_Consultas (consulta_id, accion, estado_anterior, estado_nuevo)
    SELECT 
        ISNULL(i.consulta_id, d.consulta_id),
        @Accion,
        d.estado,
        i.estado
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.consulta_id = d.consulta_id;
END;


-- ==============================================================================
-- TRIGGER 2: Automatización - Cambio de Estado de Consulta
-- Requisito: Al generar un tratamiento, la consulta pasa automáticamente a 'Atendida'.
-- ==============================================================================
CREATE OR ALTER TRIGGER trg_AutoUpdate_EstadoConsulta
ON Tratamientos
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Actualizamos la tabla Consultas uniéndola con la tabla virtual 'inserted'
    UPDATE c
    SET c.estado = 'Atendida'
    FROM Consultas c
    INNER JOIN inserted i ON c.consulta_id = i.consulta_id
    WHERE c.estado <> 'Atendida'; -- Solo actualizamos si no estaba ya atendida
END;

-- ==============================================================================
-- TRIGGER 3: Auditoría de Tratamientos
-- ==============================================================================
CREATE OR ALTER TRIGGER trg_Audit_Tratamientos
ON Tratamientos
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Accion VARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted)
        SET @Accion = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted)
        SET @Accion = 'INSERT';
    ELSE
        SET @Accion = 'DELETE';

    INSERT INTO Audit_Tratamientos (tratamiento_id, accion)
    SELECT 
        ISNULL(i.tratamiento_id, d.tratamiento_id),
        @Accion
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.tratamiento_id = d.tratamiento_id;
END;
GO

-- ==============================================================================
-- TRIGGER 4: Auditoría de Facturas
-- ==============================================================================
CREATE OR ALTER TRIGGER trg_Audit_Facturas
ON Facturas
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Accion VARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted)
        SET @Accion = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted)
        SET @Accion = 'INSERT';
    ELSE
        SET @Accion = 'DELETE';

    INSERT INTO Audit_Facturas (factura_id, folio, accion, total_anterior, total_nuevo)
    SELECT 
        ISNULL(i.factura_id, d.factura_id),
        ISNULL(i.folio, d.folio),
        @Accion,
        d.total,
        i.total
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.factura_id = d.factura_id;
END;
GO


--------------------------------CONSULTAS AVANZADAS-------------------------------

-- ==============================================================================
-- CONSULTA 1: PIVOT (Consultas por Mes)
-- Transforma las filas de meses en columnas para un reporte gerencial.
-- ==============================================================================
WITH DatosBase AS (
    SELECT 
        consulta_id, 
        DATENAME(MONTH, fecha_consulta) AS Mes
    FROM Consultas
)
SELECT * 
FROM DatosBase
PIVOT (
    COUNT(consulta_id) 
    FOR Mes IN ([January], [February], [March], [April], [May], [June], 
                [July], [August], [September], [October], [November], [December])
) AS ReportePivot;


-- ==============================================================================
-- CONSULTA 2: JOINs completos y CASE (Clasificación de Clientes)
-- Conecta Dueños -> Mascotas -> Consultas para evaluar la lealtad del cliente.
-- ==============================================================================
SELECT 
    d.nombre_completo AS Dueno,
    COUNT(c.consulta_id) AS Total_Consultas,
    CASE 
        WHEN COUNT(c.consulta_id) >= 5 THEN 'Cliente VIP'
        WHEN COUNT(c.consulta_id) BETWEEN 2 AND 4 THEN 'Cliente Frecuente'
        ELSE 'Cliente Ocasional'
    END AS Clasificacion_Lealtad
FROM Duenos d
LEFT JOIN Mascotas m ON d.dueno_id = m.dueno_id
LEFT JOIN Consultas c ON m.mascota_id = c.mascota_id
GROUP BY d.dueno_id, d.nombre_completo
ORDER BY Total_Consultas DESC;


-- ==============================================================================
-- CONSULTA 3: Funciones de Ventana / RANKING (Veterinarios más solicitados)
-- Evalúa quién tiene más trabajo sin agrupar destructivamente.
-- ==============================================================================
SELECT 
    v.nombre_completo AS Veterinario,
    v.especialidad,
    COUNT(c.consulta_id) AS Consultas_Atendidas,
    RANK() OVER (ORDER BY COUNT(c.consulta_id) DESC) AS Ranking_Productividad
FROM Veterinarios v
LEFT JOIN Consultas c ON v.veterinario_id = c.veterinario_id
GROUP BY v.veterinario_id, v.nombre_completo, v.especialidad;



-------------Prueba: 
-- 1. Insertamos un Veterinario y una Mascota (Asumiendo que el dueño de la Fase 3 es el dueno_id = 1)
INSERT INTO Veterinarios (nombre_completo, especialidad, usuario) 
VALUES ('Dra. Ana Torres', 'Cirugía', 'atorres');

INSERT INTO Mascotas (nombre, especie, raza, dueno_id) 
VALUES ('Max', 'Perro', 'Golden Retriever', 1);

-- 2. Registramos una consulta (Por defecto entrará con estado 'Programada')
EXEC sp_RegistrarConsulta 
    @mascota_id = 1, 
    @veterinario_id = 1, 
    @motivo = 'Revisión general';

-- Verificamos el estado (Debe decir 'Programada') e inserta en Auditoría
SELECT consulta_id, motivo, estado FROM Consultas;
SELECT * FROM Audit_Consultas; 

-- 3. Generamos el tratamiento (Esto disparará nuestro Trigger Automático)
EXEC sp_GenerarTratamiento 
    @consulta_id = 1, 
    @diagnostico_plano = 'Infección leve', 
    @tratamiento_plano = 'Antibiótico 5 días', 
    @observaciones_plano = 'Reposo';

-- 4. Volvemos a revisar la consulta (¡El estado debió cambiar mágicamente a 'Atendida'!)
SELECT consulta_id, motivo, estado FROM Consultas;

-- 5.ejecuta las Consultas Analíticas (PIVOT, CASE, RANKING) para ver los reportes poblados.

-- ==============================================================================
-- SP 5: Registrar Factura (Cifra la referencia de pago y usa la secuencia de folios)
-- ==============================================================================
CREATE OR ALTER PROCEDURE sp_RegistrarFactura
    @consulta_id INT,
    @total DECIMAL(10,2),
    @metodo_pago VARCHAR(30),
    @referencia_pago_plano VARCHAR(100) -- Recibe texto plano desde Flask
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- 1. Abrimos la llave simétrica para cifrar la referencia de pago
        OPEN SYMMETRIC KEY LlaveSimetricaVeterinaria 
        DECRYPTION BY CERTIFICATE CertificadoVeterinaria;
        
        BEGIN TRANSACTION;
            INSERT INTO Facturas (consulta_id, total, metodo_pago, referencia_pago)
            VALUES (
                @consulta_id,
                @total,
                @metodo_pago,
                EncryptByKey(Key_GUID('LlaveSimetricaVeterinaria'), @referencia_pago_plano)
            );
        COMMIT TRANSACTION;
        
        CLOSE SYMMETRIC KEY LlaveSimetricaVeterinaria;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        
        IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'LlaveSimetricaVeterinaria')
            CLOSE SYMMETRIC KEY LlaveSimetricaVeterinaria;
            
        INSERT INTO Log_Errores (numero_error, mensaje_error, linea_error, procedimiento_origen)
        VALUES (ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE());
        
        THROW;
    END CATCH
END;

























