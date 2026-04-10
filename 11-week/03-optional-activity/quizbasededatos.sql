-- Consulta con INNER JOIN de mínimo 5 tablas
SELECT
    r.reservation_code AS codigo_reserva,
    f.flight_number AS numero_vuelo,
    f.service_date AS fecha_servicio,
    t.ticket_number AS numero_tiquete,
    rp.passenger_sequence_no AS secuencia_pasajero,
    CONCAT(
        p.first_name, ' ',
        COALESCE(p.middle_name || ' ', ''),
        p.last_name, ' ',
        COALESCE(p.second_last_name, '')
    ) AS nombre_pasajero,
    fs.segment_number AS segmento_vuelo,
    fs.scheduled_departure_at AS hora_programada_salida
FROM reservation r
INNER JOIN reservation_passenger rp
    ON r.reservation_id = rp.reservation_id
INNER JOIN person p
    ON rp.person_id = p.person_id
INNER JOIN ticket t
    ON rp.reservation_passenger_id = t.reservation_passenger_id
INNER JOIN ticket_segment ts
    ON t.ticket_id = ts.ticket_id
INNER JOIN flight_segment fs
    ON ts.flight_segment_id = fs.flight_segment_id
INNER JOIN flight f
    ON fs.flight_id = f.flight_id
ORDER BY f.service_date, f.flight_number, fs.segment_number, rp.passenger_sequence_no;

-- Función auxiliar del trigger
CREATE OR REPLACE FUNCTION fn_generar_boarding_pass()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO boarding_pass (
        check_in_id,
        boarding_pass_code,
        barcode_value,
        issued_at
    )
    VALUES (
        NEW.check_in_id,
        'BP-' || REPLACE(NEW.check_in_id::text, '-', ''),
        'BAR-' || REPLACE(NEW.check_in_id::text, '-', '') || '-' ||
        TO_CHAR(NEW.checked_in_at, 'YYYYMMDDHH24MISS'),
        NOW()
    );

    RETURN NEW;
END;
$$;

-- Trigger AFTER INSERT
DROP TRIGGER IF EXISTS trg_generar_boarding_pass ON check_in;

CREATE TRIGGER trg_generar_boarding_pass
AFTER INSERT ON check_in
FOR EACH ROW
EXECUTE FUNCTION fn_generar_boarding_pass();

-- Procedimiento almacenado para registrar check-in
CREATE OR REPLACE PROCEDURE sp_registrar_check_in(
    IN p_ticket_segment_id uuid,
    IN p_check_in_status_id uuid,
    IN p_boarding_group_id uuid,
    IN p_checked_in_by_user_id uuid,
    IN p_checked_in_at timestamptz
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO check_in (
        ticket_segment_id,
        check_in_status_id,
        boarding_group_id,
        checked_in_by_user_id,
        checked_in_at
    )
    VALUES (
        p_ticket_segment_id,
        p_check_in_status_id,
        p_boarding_group_id,
        p_checked_in_by_user_id,
        p_checked_in_at
    );
END;
$$;

-- Script para disparar el trigger manualmente
-- 1. Ver datos base disponibles
SELECT * FROM check_in_status;
SELECT * FROM boarding_group;
SELECT * FROM user_account;
SELECT * FROM ticket_segment;

-- 2. Insert manual en check_in para disparar el trigger
INSERT INTO check_in (
    ticket_segment_id,
    check_in_status_id,
    boarding_group_id,
    checked_in_by_user_id,
    checked_in_at
)
VALUES (
    'UUID_TICKET_SEGMENT',
    'UUID_CHECK_IN_STATUS',
    'UUID_BOARDING_GROUP',
    'UUID_USER_ACCOUNT',
    NOW()
);

-- 3. Validar el efecto del trigger
SELECT
    ci.check_in_id,
    ci.ticket_segment_id,
    ci.checked_in_at,
    bp.boarding_pass_id,
    bp.boarding_pass_code,
    bp.barcode_value,
    bp.issued_at
FROM check_in ci
INNER JOIN boarding_pass bp
    ON ci.check_in_id = bp.check_in_id
WHERE ci.ticket_segment_id = 'Aca va el UUID que tengamos en nuestra bd';

-- Consulta de validación más completa
SELECT
    r.reservation_code,
    f.flight_number,
    f.service_date,
    t.ticket_number,
    CONCAT(
        p.first_name, ' ',
        COALESCE(p.middle_name || ' ', ''),
        p.last_name, ' ',
        COALESCE(p.second_last_name, '')
    ) AS pasajero,
    fs.segment_number,
    ci.check_in_id,
    ci.checked_in_at,
    bp.boarding_pass_code,
    bp.barcode_value
FROM reservation r
INNER JOIN reservation_passenger rp
    ON r.reservation_id = rp.reservation_id
INNER JOIN person p
    ON rp.person_id = p.person_id
INNER JOIN ticket t
    ON rp.reservation_passenger_id = t.reservation_passenger_id
INNER JOIN ticket_segment ts
    ON t.ticket_id = ts.ticket_id
INNER JOIN flight_segment fs
    ON ts.flight_segment_id = fs.flight_segment_id
INNER JOIN flight f
    ON fs.flight_id = f.flight_id
LEFT JOIN check_in ci
    ON ts.ticket_segment_id = ci.ticket_segment_id
LEFT JOIN boarding_pass bp
    ON ci.check_in_id = bp.check_in_id
ORDER BY f.service_date, f.flight_number, fs.segment_number;

