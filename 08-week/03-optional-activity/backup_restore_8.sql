-- =========================================================
-- ACTIVIDAD 2: BACKUP Y RESTORE (versión alternativa)
-- Script base para práctica en MySQL
-- =========================================================

DROP DATABASE IF EXISTS respaldo_laboratorio;
CREATE DATABASE respaldo_laboratorio;
USE respaldo_laboratorio;

-- 1. Tabla principal
CREATE TABLE alumno (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    programa VARCHAR(100) NOT NULL,
    promedio DECIMAL(3,2) NOT NULL
);

-- 2. Datos de prueba
INSERT INTO alumno (nombre, programa, promedio) VALUES
('Laura Gomez', 'Ingenieria de Sistemas', 4.40),
('Pedro Rojas', 'Ingenieria Industrial', 3.90),
('Sofia Martinez', 'Administracion', 4.10),
('Daniel Castro', 'Contaduria', 3.70);

-- 3. Verificación inicial
SELECT * FROM alumno;

-- 4. Simulación de daño
-- Si SQL_SAFE_UPDATES está activo, esta forma evita el error 1175
DELETE FROM alumno WHERE id > 0;

-- 5. Verificación después del daño
SELECT * FROM alumno;

-- 6. Restauración manual de prueba
-- En la actividad real también puede restaurarse desde el archivo exportado
INSERT INTO alumno (nombre, programa, promedio) VALUES
('Laura Gomez', 'Ingenieria de Sistemas', 4.40),
('Pedro Rojas', 'Ingenieria Industrial', 3.90),
('Sofia Martinez', 'Administracion', 4.10),
('Daniel Castro', 'Contaduria', 3.70);

-- 7. Verificación final del restore
SELECT * FROM alumno;

-- 8. Consultas extra para evidencia
SELECT COUNT(*) AS total_alumnos FROM alumno;

SELECT nombre, programa, promedio
FROM alumno
ORDER BY promedio DESC;
