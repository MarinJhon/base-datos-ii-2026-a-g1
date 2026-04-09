-- ============================================================
-- PERMISSIONS DB
-- ============================================================

CREATE ROLE gestor_vuelos;
CREATE ROLE consultor_sistema;
CREATE ROLE supervisor_admin;

CREATE USER carlos_op WITH PASSWORD 'Vuelos2026#';
CREATE USER laura_consulta WITH PASSWORD 'Consulta2026#';
CREATE USER maria_admin WITH PASSWORD 'Admin2026#';

GRANT gestor_vuelos TO carlos_op;
GRANT consultor_sistema TO laura_consulta;
GRANT supervisor_admin TO maria_admin;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO supervisor_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO supervisor_admin;

GRANT SELECT, INSERT, UPDATE ON flight TO gestor_vuelos;
GRANT SELECT, INSERT, UPDATE ON flight_segment TO gestor_vuelos;
GRANT SELECT, INSERT, UPDATE ON aircraft TO gestor_vuelos;
GRANT SELECT, INSERT, UPDATE ON boarding_gate TO gestor_vuelos;
GRANT SELECT, INSERT, UPDATE ON terminal TO gestor_vuelos;
GRANT SELECT, INSERT, UPDATE ON maintenance_event TO gestor_vuelos;
GRANT SELECT ON airport TO gestor_vuelos;
GRANT SELECT ON aircraft_seat TO gestor_vuelos;
GRANT SELECT ON airline TO gestor_vuelos;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO consultor_sistema;

REVOKE DELETE ON flight FROM gestor_vuelos;
REVOKE DELETE ON aircraft FROM gestor_vuelos;
REVOKE DELETE ON maintenance_event FROM gestor_vuelos;

-- ============================================================
-- TRIGGERS
-- ============================================================

CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_flight_set_updated
    BEFORE UPDATE ON flight
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_aircraft_set_updated
    BEFORE UPDATE ON aircraft
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_boarding_pass_set_updated
    BEFORE UPDATE ON boarding_pass
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_invoice_set_updated
    BEFORE UPDATE ON invoice
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE OR REPLACE FUNCTION fn_check_maintenance_dates()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.completed_at IS NOT NULL AND NEW.completed_at < NEW.started_at THEN
        RAISE EXCEPTION 'La fecha de finalización no puede ser anterior a la fecha de inicio del mantenimiento.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_maintenance_dates
    BEFORE INSERT OR UPDATE ON maintenance_event
    FOR EACH ROW EXECUTE FUNCTION fn_check_maintenance_dates();

CREATE OR REPLACE FUNCTION fn_check_aircraft_retired()
RETURNS TRIGGER AS $$
DECLARE
    v_retired date;
BEGIN
    SELECT retired_on INTO v_retired
    FROM aircraft WHERE aircraft_id = NEW.aircraft_id;

    IF v_retired IS NOT NULL AND v_retired < CURRENT_DATE THEN
        RAISE EXCEPTION 'No se puede asignar un vuelo a una aeronave retirada.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_aircraft_retired
    BEFORE INSERT OR UPDATE ON flight
    FOR EACH ROW EXECUTE FUNCTION fn_check_aircraft_retired();

CREATE OR REPLACE FUNCTION fn_notify_new_maintenance()
RETURNS TRIGGER AS $$
BEGIN
    RAISE NOTICE 'Evento de mantenimiento creado para aeronave %, tipo %, estado %.',
        NEW.aircraft_id, NEW.maintenance_type_id, NEW.status_code;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_notify_new_maintenance
    AFTER INSERT ON maintenance_event
    FOR EACH ROW EXECUTE FUNCTION fn_notify_new_maintenance();

-- ============================================================
-- FUNCTIONS USER
-- ============================================================

CREATE OR REPLACE FUNCTION fn_buscar_vuelos_por_ruta(
    p_origin_airport_id uuid,
    p_destination_airport_id uuid,
    p_fecha date
)
RETURNS TABLE (
    flight_number varchar,
    service_date date,
    departure timestamptz,
    arrival timestamptz
) AS $$
BEGIN
    RETURN QUERY
    SELECT f.flight_number, f.service_date,
           fs.scheduled_departure_at, fs.scheduled_arrival_at
    FROM flight_segment fs
    JOIN flight f ON f.flight_id = fs.flight_id
    WHERE fs.origin_airport_id = p_origin_airport_id
      AND fs.destination_airport_id = p_destination_airport_id
      AND f.service_date = p_fecha
    ORDER BY fs.scheduled_departure_at;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_total_pagado_por_reserva(p_reservation_id uuid)
RETURNS numeric AS $$
DECLARE
    v_total numeric;
BEGIN
    SELECT COALESCE(SUM(p.total_amount), 0)
    INTO v_total
    FROM payment p
    JOIN sale s ON s.sale_id = p.sale_id
    WHERE s.reservation_id = p_reservation_id;

    RETURN v_total;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_pasajeros_en_vuelo(p_flight_id uuid)
RETURNS integer AS $$
DECLARE
    v_count integer;
BEGIN
    SELECT COUNT(DISTINCT rp.person_id)
    INTO v_count
    FROM ticket t
    JOIN ticket_segment ts ON ts.ticket_id = t.ticket_id
    JOIN flight_segment fs ON fs.flight_segment_id = ts.flight_segment_id
    JOIN reservation_passenger rp ON rp.reservation_passenger_id = t.reservation_passenger_id
    WHERE fs.flight_id = p_flight_id;

    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_aeronave_en_mantenimiento(p_aircraft_id uuid)
RETURNS boolean AS $$
DECLARE
    v_count integer;
BEGIN
    SELECT COUNT(*)
    INTO v_count
    FROM maintenance_event
    WHERE aircraft_id = p_aircraft_id
      AND status_code = 'IN_PROGRESS';

    RETURN v_count > 0;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- FUNCTIONS SYSTEM
-- ============================================================

CREATE OR REPLACE FUNCTION fn_sys_codigo_reserva()
RETURNS varchar AS $$
DECLARE
    v_code varchar;
BEGIN
    v_code := 'RES-' || TO_CHAR(now(), 'YYYYMMDD') || '-' ||
              UPPER(SUBSTRING(gen_random_uuid()::text, 1, 8));
    RETURN v_code;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_sys_cancelar_vuelos_aeronave(p_aircraft_id uuid)
RETURNS integer AS $$
DECLARE
    v_cancelled_status_id uuid;
    v_rows integer;
BEGIN
    SELECT flight_status_id INTO v_cancelled_status_id
    FROM flight_status WHERE status_code = 'CANCELLED'
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Estado CANCELLED no encontrado en flight_status.';
    END IF;

    UPDATE flight
    SET flight_status_id = v_cancelled_status_id, updated_at = now()
    WHERE aircraft_id = p_aircraft_id
      AND service_date >= CURRENT_DATE
      AND flight_status_id NOT IN (
          SELECT flight_status_id FROM flight_status WHERE status_code = 'CANCELLED'
      );

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_sys_porcentaje_ocupacion(p_flight_segment_id uuid)
RETURNS numeric AS $$
DECLARE
    v_asignados integer;
    v_capacidad integer;
BEGIN
    SELECT COUNT(*)
    INTO v_asignados
    FROM seat_assignment sa
    JOIN ticket_segment ts ON ts.ticket_segment_id = sa.ticket_segment_id
    WHERE ts.flight_segment_id = p_flight_segment_id;

    SELECT COUNT(*)
    INTO v_capacidad
    FROM aircraft_seat acs
    JOIN aircraft_cabin acb ON acb.aircraft_cabin_id = acs.aircraft_cabin_id
    JOIN aircraft a ON a.aircraft_id = acb.aircraft_id
    JOIN flight f ON f.aircraft_id = a.aircraft_id
    JOIN flight_segment fs ON fs.flight_id = f.flight_id
    WHERE fs.flight_segment_id = p_flight_segment_id;

    IF v_capacidad = 0 THEN RETURN 0; END IF;

    RETURN ROUND((v_asignados::numeric / v_capacidad::numeric) * 100, 2);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_sys_registrar_miles_ganadas(
    p_loyalty_account_id uuid,
    p_miles integer,
    p_referencia varchar DEFAULT NULL
)
RETURNS void AS $$
BEGIN
    IF p_miles <= 0 THEN
        RAISE EXCEPTION 'Las millas a registrar deben ser un valor positivo.';
    END IF;

    INSERT INTO miles_transaction (
        loyalty_account_id, transaction_type, miles_delta,
        occurred_at, reference_code
    ) VALUES (
        p_loyalty_account_id, 'EARN', p_miles, now(), p_referencia
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- STORED PROCEDURES
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_crear_vuelo(
    p_airline_id uuid,
    p_aircraft_id uuid,
    p_flight_number varchar,
    p_service_date date,
    OUT p_flight_id uuid
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status_id uuid;
BEGIN
    IF fn_aeronave_en_mantenimiento(p_aircraft_id) THEN
        RAISE EXCEPTION 'La aeronave está en mantenimiento y no puede ser asignada a un vuelo.';
    END IF;

    SELECT flight_status_id INTO v_status_id
    FROM flight_status WHERE status_code = 'SCHEDULED'
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Estado SCHEDULED no encontrado en flight_status.';
    END IF;

    INSERT INTO flight (airline_id, aircraft_id, flight_status_id, flight_number, service_date)
    VALUES (p_airline_id, p_aircraft_id, v_status_id, p_flight_number, p_service_date)
    RETURNING flight_id INTO p_flight_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_registrar_mantenimiento(
    p_aircraft_id uuid,
    p_maintenance_type_id uuid,
    p_provider_id uuid,
    p_started_at timestamptz,
    OUT p_maintenance_event_id uuid
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO maintenance_event (
        aircraft_id, maintenance_type_id, maintenance_provider_id,
        status_code, started_at
    ) VALUES (
        p_aircraft_id, p_maintenance_type_id, p_provider_id,
        'IN_PROGRESS', p_started_at
    ) RETURNING maintenance_event_id INTO p_maintenance_event_id;

    PERFORM fn_sys_cancelar_vuelos_aeronave(p_aircraft_id);
END;
$$;

CREATE OR REPLACE PROCEDURE sp_emitir_factura(
    p_sale_id uuid,
    p_currency_id uuid,
    p_due_days integer DEFAULT 30,
    OUT p_invoice_id uuid
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status_id uuid;
    v_invoice_number varchar;
BEGIN
    SELECT invoice_status_id INTO v_status_id
    FROM invoice_status WHERE status_code = 'ISSUED'
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Estado ISSUED no encontrado en invoice_status.';
    END IF;

    v_invoice_number := 'INV-' || TO_CHAR(now(), 'YYYYMMDD-HH24MISS') || '-' ||
                        UPPER(SUBSTRING(gen_random_uuid()::text, 1, 5));

    INSERT INTO invoice (
        sale_id, invoice_status_id, currency_id,
        invoice_number, issued_at, due_at
    ) VALUES (
        p_sale_id, v_status_id, p_currency_id,
        v_invoice_number, now(), now() + (p_due_days || ' days')::interval
    ) RETURNING invoice_id INTO p_invoice_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_actualizar_estado_vuelo(
    p_flight_id uuid,
    p_nuevo_status_code varchar
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status_id uuid;
BEGIN
    SELECT flight_status_id INTO v_status_id
    FROM flight_status WHERE status_code = p_nuevo_status_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Estado de vuelo % no existe.', p_nuevo_status_code;
    END IF;

    UPDATE flight
    SET flight_status_id = v_status_id, updated_at = now()
    WHERE flight_id = p_flight_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Vuelo % no encontrado.', p_flight_id;
    END IF;
END;
$$;
