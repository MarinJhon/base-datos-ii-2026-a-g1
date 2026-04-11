-- =========================================================
-- ACTIVIDAD 3: EXPLAIN E ÍNDICES (versión alternativa)
-- Script base para práctica en MySQL
-- =========================================================

DROP DATABASE IF EXISTS optimizacion_academica;
CREATE DATABASE optimizacion_academica;
USE optimizacion_academica;

-- 1. Tablas
CREATE TABLE estudiante (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    semestre INT NOT NULL
);

CREATE TABLE materia (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    creditos INT NOT NULL
);

CREATE TABLE inscripcion (
    id INT AUTO_INCREMENT PRIMARY KEY,
    estudiante_id INT NOT NULL,
    materia_id INT NOT NULL,
    periodo VARCHAR(20) NOT NULL,
    calificacion DECIMAL(3,2) NOT NULL,
    FOREIGN KEY (estudiante_id) REFERENCES estudiante(id),
    FOREIGN KEY (materia_id) REFERENCES materia(id)
);

-- 2. Datos de prueba
INSERT INTO estudiante (nombre, semestre) VALUES
('Camila Torres', 1),
('Andres Peña', 2),
('Valentina Ruiz', 3),
('Miguel Herrera', 2),
('Julian Lara', 4),
('Paula Medina', 1);

INSERT INTO materia (nombre, creditos) VALUES
('Bases de Datos', 4),
('Estructuras de Datos', 3),
('Redes de Computadores', 3),
('Ingenieria de Software', 4);

INSERT INTO inscripcion (estudiante_id, materia_id, periodo, calificacion) VALUES
(1, 1, '2026-1', 4.20),
(1, 2, '2026-1', 3.80),
(2, 1, '2026-1', 4.00),
(2, 3, '2026-1', 3.50),
(3, 4, '2026-1', 4.70),
(4, 2, '2026-1', 3.90),
(4, 3, '2026-1', 4.10),
(5, 1, '2026-1', 3.60),
(5, 4, '2026-1', 4.30),
(6, 2, '2026-1', 4.00),
(3, 1, '2026-2', 4.50),
(2, 4, '2026-2', 3.90);

-- 3. Consultas reales del modelo

-- Consulta 1: búsqueda por semestre
SELECT *
FROM estudiante
WHERE semestre = 2;

-- Consulta 2: inscripciones por estudiante y periodo
SELECT *
FROM inscripcion
WHERE estudiante_id = 2
  AND periodo = '2026-1';

-- Consulta 3: JOIN entre inscripcion, estudiante y materia
SELECT e.nombre AS estudiante,
       m.nombre AS materia,
       i.periodo,
       i.calificacion
FROM inscripcion i
JOIN estudiante e ON i.estudiante_id = e.id
JOIN materia m ON i.materia_id = m.id
WHERE m.id = 1;

-- 4. EXPLAIN antes de crear índices
EXPLAIN SELECT *
FROM estudiante
WHERE semestre = 2;

EXPLAIN SELECT *
FROM inscripcion
WHERE estudiante_id = 2
  AND periodo = '2026-1';

EXPLAIN SELECT e.nombre AS estudiante,
               m.nombre AS materia,
               i.periodo,
               i.calificacion
FROM inscripcion i
JOIN estudiante e ON i.estudiante_id = e.id
JOIN materia m ON i.materia_id = m.id
WHERE m.id = 1;

-- 5. Índices
-- 1 simple, 1 compuesto, 1 para JOIN
CREATE INDEX idx_estudiante_semestre
ON estudiante(semestre);

CREATE INDEX idx_inscripcion_estudiante_periodo
ON inscripcion(estudiante_id, periodo);

CREATE INDEX idx_inscripcion_materia
ON inscripcion(materia_id);

-- 6. EXPLAIN después de crear índices
EXPLAIN SELECT *
FROM estudiante
WHERE semestre = 2;

EXPLAIN SELECT *
FROM inscripcion
WHERE estudiante_id = 2
  AND periodo = '2026-1';

EXPLAIN SELECT e.nombre AS estudiante,
               m.nombre AS materia,
               i.periodo,
               i.calificacion
FROM inscripcion i
JOIN estudiante e ON i.estudiante_id = e.id
JOIN materia m ON i.materia_id = m.id
WHERE m.id = 1;

-- 7. Verificación final
SELECT * FROM estudiante;
SELECT * FROM materia;
SELECT * FROM inscripcion;
