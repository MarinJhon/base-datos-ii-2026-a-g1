DROP DATABASE IF EXISTS repaso_semana1;
CREATE DATABASE repaso_semana1;
USE repaso_semana1;
 // crear --table
  CREATE TABLE estudiante (
  id_estudiante INT AUTO_INCREMENT PRIMARY KEY,
  nombre        VARCHAR(80) NOT NULL,
  correo        VARCHAR(120) UNIQUE
);

CREATE TABLE asignatura (
  id_asignatura INT AUTO_INCREMENT PRIMARY KEY,
  nombre        VARCHAR(100) NOT NULL,
  creditos      INT NOT NULL
);

CREATE TABLE matricula (
  id_matricula   INT AUTO_INCREMENT PRIMARY KEY,
  id_estudiante  INT NOT NULL,
  id_asignatura  INT NOT NULL,
  semestre       VARCHAR(10) NOT NULL,     -- Ej: 2026-1
  nota_final     DECIMAL(4,2) NULL,        -- Ej: 3.50 (0.00 a 5.00)
  fecha_registro DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP)
  
  --insertar datos
  INSERT INTO estudiante (nombre, correo) VALUES
('Ana Pérez',  'ana@uni.edu'),
('Brayan Díaz','brayan@uni.edu'),
('Camila Ruiz','camila@uni.edu'),
('Diego Mora', 'diego@uni.edu'),
('Elena Soto', 'elena@uni.edu');

INSERT INTO asignatura (nombre, creditos) VALUES
('Bases de Datos I', 3),
('Programación I',   4),
('Matemáticas',      3),
('Redes I',          3);

INSERT INTO matricula (id_estudiante, id_asignatura, semestre, nota_final, fecha_registro) VALUES
(1, 1, '2026-1', 4.20, '2026-02-01 10:10:00'),
(1, 2, '2026-1', 4.00, '2026-02-02 09:00:00'),
(2, 1, '2026-1', 3.50, '2026-02-01 11:20:00'),
(2, 4, '2026-1', 3.90, '2026-02-03 14:30:00'),
(3, 1, '2026-1', 4.80, '2026-02-02 16:00:00'),
(3, 3, '2026-1', 3.20, '2026-02-04 08:40:00'),
(4, 2, '2026-1', 2.90, '2026-02-02 12:15:00'),
(5, 3, '2025-2', 4.10, '2025-10-15 09:30:00');

--CONSULTA A (JOIN detalle)
SELECT
  m.semestre,
  e.id_estudiante,
  e.nombre      AS estudiante,
  a.id_asignatura,
  a.nombre      AS asignatura,
  m.nota_final,
  m.fecha_registro
FROM matricula m
INNER JOIN estudiante e ON e.id_estudiante = m.id_estudiante
INNER JOIN asignatura a ON a.id_asignatura = m.id_asignatura
WHERE m.semestre = '2026-1'
ORDER BY a.nombre, e.nombre;

--CONSULTA B (LEFT JOIN) -- Estudiantes SIN matrícula en el semestre 2026-1
SELECT
  e.id_estudiante,
  e.nombre
FROM estudiante e
LEFT JOIN matricula m
  ON m.id_estudiante = e.id_estudiante
 AND m.semestre = '2026-1'
WHERE m.id_matricula IS NULL
ORDER BY e.nombre;

--CONSULTA C (GROUP BY + HAVING)
   Asignaturas con MÁS de N matrículas en un semestre (elige N)
   Ejemplo: N = 2
========================================================= */
SELECT
  a.id_asignatura,
  a.nombre AS asignatura,
  COUNT(*) AS total_matriculas
FROM matricula m
INNER JOIN asignatura a ON a.id_asignatura = m.id_asignatura
WHERE m.semestre = '2026-1'
GROUP BY a.id_asignatura, a.nombre
HAVING COUNT(*) > 2
ORDER BY total_matriculas DESC, a.nombre;
  