-- ============================================================
-- EJERCICIO 6 
-- ============================================================

-- Cambiar algunos usuarios para pruebas
UPDATE user 
SET status = 'inactive' 
WHERE id = 2;

UPDATE user 
SET status = 'suspended' 
WHERE id = 6;


-- VERSIÓN 1
-- Usuarios Inactivos con Historial de Facturas (Usando funciones de agregación directamente)


USE facturacion_db;

SELECT 
    CONCAT(p.first_name, ' ', p.last_name) AS nombre_completo,
    u.status AS estado_usuario,
    r.name AS rol_asignado,
    u.last_login AS ultima_fecha_login,
    COUNT(b.id) AS cantidad_facturas,
    COALESCE(SUM(b.total_amount), 0) AS monto_total_facturado,
    MAX(b.bill_date) AS fecha_ultima_factura

FROM user u

INNER JOIN person p ON u.person_id = p.id
INNER JOIN role r ON u.role_id = r.id

LEFT JOIN bill b 
    ON b.user_id = u.id
    AND b.status IN ('issued', 'paid')

WHERE u.status IN ('inactive', 'suspended')

GROUP BY 
    p.first_name,
    p.last_name,
    u.status,
    r.name,
    u.last_login

ORDER BY fecha_ultima_factura DESC;


-- VERSIÓN 2
-- Con subconsulta correlacionada para última factura


USE facturacion_db;

SELECT 
    CONCAT(p.first_name, ' ', p.last_name) AS nombre_completo,
    u.status AS estado_usuario,
    r.name AS rol_asignado,
    u.last_login AS ultima_fecha_login,
    COUNT(b.id) AS cantidad_facturas,
    COALESCE(SUM(b.total_amount), 0) AS monto_total_facturado,

    (
        SELECT MAX(b2.bill_date)
        FROM bill b2
        WHERE b2.user_id = u.id
        AND b2.status IN ('issued', 'paid')
    ) AS fecha_ultima_factura

FROM user u

INNER JOIN person p ON u.person_id = p.id
INNER JOIN role r ON u.role_id = r.id

LEFT JOIN bill b 
    ON b.user_id = u.id
    AND b.status IN ('issued', 'paid')

WHERE u.status IN ('inactive', 'suspended')

GROUP BY 
    p.first_name,
    p.last_name,
    u.status,
    r.name,
    u.last_login

ORDER BY fecha_ultima_factura DESC;
