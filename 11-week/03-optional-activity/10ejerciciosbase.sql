-- ================================================================================
-- SOLUCIONES COMPLETAS - SISTEMA INTEGRAL DE AEROLÍNEA
-- PostgreSQL | 10 Ejercicios sobre el modelo base
-- ================================================================================
-- Cada ejercicio incluye:
--   1. Consulta SQL con INNER JOIN de mínimo 5 tablas
--   2. Función auxiliar para el trigger (si aplica)
--   3. Trigger AFTER
--   4. Procedimiento almacenado
--   5. Script de prueba del trigger
--   6. Script de invocación del procedimiento
--   7. Consultas de validación
-- ================================================================================


-- ################################################################################
-- EJERCICIO 01
-- Flujo de check-in y trazabilidad comercial del pasajero
-- Dominios: SALES/RESERVATION/TICKETING · FLIGHT OPERATIONS · IDENTITY · BOARDING
-- ################################################################################

-- ---------------------------------------------------------------
-- EJ01 · REQUERIMIENTO 1: Consulta INNER JOIN (≥5 tablas)
-- Trazabilidad de pasajeros por vuelo: reserva → tiquete → segmento
-- ---------------------------------------------------------------
SELECT
    r.reservation_code                          AS codigo_reserva,
    f.flight_number                             AS numero_vuelo,
    f.service_date                              AS fecha_servicio,
    t.ticket_number                             AS numero_tiquete,
    rp.passenger_sequence_no                    AS secuencia_pasajero,
    p.first_name || ' ' || p.last_name          AS nombre_pasajero,
    fs.segment_number                           AS segmento_vuelo,
    fs.scheduled_departure_at                   AS hora_salida_programada
FROM reservation r
    INNER JOIN reservation_passenger rp
        ON rp.reservation_id = r.reservation_id
    INNER JOIN person p
        ON p.person_id = rp.person_id
    INNER JOIN ticket t
        ON t.reservation_passenger_id = rp.reservation_passenger_id
    INNER JOIN ticket_segment ts
        ON ts.ticket_id = t.ticket_id
    INNER JOIN flight_segment fs
        ON fs.flight_segment_id = ts.flight_segment_id
    INNER JOIN flight f
        ON f.flight_id = fs.flight_id
ORDER BY r.reservation_code, rp.passenger_sequence_no, fs.segment_number;


-- ---------------------------------------------------------------
-- EJ01 · REQUERIMIENTO 2: Función auxiliar del trigger
-- Genera el pase de abordar automáticamente tras un check-in
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_generar_boarding_pass_ej01()
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
        'BP-' || UPPER(SUBSTRING(NEW.check_in_id::text, 1, 8)),
        'BC-' || UPPER(REPLACE(gen_random_uuid()::text, '-', '')),
        now()
    );
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------
-- EJ01 · REQUERIMIENTO 2: Trigger AFTER INSERT sobre check_in
-- ---------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_ej01_boarding_pass_after_checkin
AFTER INSERT ON check_in
FOR EACH ROW
EXECUTE FUNCTION fn_generar_boarding_pass_ej01();


-- ---------------------------------------------------------------
-- EJ01 · REQUERIMIENTO 3: Procedimiento almacenado
-- Registra un check-in para un ticket_segment existente
-- ---------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_checkin_ej01(
    p_ticket_segment_id  uuid,
    p_status_code        varchar,
    p_boarding_group_id  uuid,
    p_user_id            uuid,
    p_checked_in_at      timestamptz DEFAULT now()
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status_id uuid;
BEGIN
    SELECT check_in_status_id
    INTO v_status_id
    FROM check_in_status
    WHERE status_code = p_status_code;

    IF v_status_id IS NULL THEN
        RAISE EXCEPTION 'Estado de check-in no encontrado: %', p_status_code;
    END IF;

    INSERT INTO check_in (
        ticket_segment_id,
        check_in_status_id,
        boarding_group_id,
        checked_in_by_user_id,
        checked_in_at
    )
    VALUES (
        p_ticket_segment_id,
        v_status_id,
        p_boarding_group_id,
        p_user_id,
        p_checked_in_at
    );

    RAISE NOTICE 'Check-in registrado para ticket_segment %', p_ticket_segment_id;
END;
$$;


-- ---------------------------------------------------------------
-- EJ01 · SCRIPT DE PRUEBA DEL TRIGGER
-- ---------------------------------------------------------------
-- Paso 1: Verificar datos base existentes
SELECT ts.ticket_segment_id, t.ticket_number, r.reservation_code
FROM ticket_segment ts
JOIN ticket t ON t.ticket_id = ts.ticket_id
JOIN reservation_passenger rp ON rp.reservation_passenger_id = t.reservation_passenger_id
JOIN reservation r ON r.reservation_id = rp.reservation_id
LIMIT 3;

-- Paso 2: Verificar estados de check-in disponibles
SELECT check_in_status_id, status_code FROM check_in_status LIMIT 5;

-- Paso 3: Invocar el procedimiento (ajustar UUIDs con los del paso 1 y 2)
-- CALL sp_registrar_checkin_ej01(
--     '<ticket_segment_id>',
--     '<status_code>',
--     NULL,
--     NULL
-- );

-- Paso 4: Validar que el trigger creó el boarding_pass
-- SELECT bp.*
-- FROM boarding_pass bp
-- JOIN check_in ci ON ci.check_in_id = bp.check_in_id
-- WHERE ci.ticket_segment_id = '<ticket_segment_id>';


-- ---------------------------------------------------------------
-- EJ01 · CONSULTA DE VALIDACIÓN FINAL
-- ---------------------------------------------------------------
SELECT
    ci.checked_in_at,
    bp.boarding_pass_code,
    bp.barcode_value,
    bp.issued_at
FROM check_in ci
    INNER JOIN boarding_pass bp ON bp.check_in_id = ci.check_in_id
ORDER BY ci.checked_in_at DESC
LIMIT 10;


-- ################################################################################
-- EJERCICIO 02
-- Control de pagos y trazabilidad de transacciones financieras
-- Dominios: SALES · PAYMENT · BILLING · GEOGRAPHY
-- ################################################################################

-- ---------------------------------------------------------------
-- EJ02 · REQUERIMIENTO 1: Consulta INNER JOIN (≥5 tablas)
-- Ciclo completo: venta → pago → transacción → moneda
-- ---------------------------------------------------------------
SELECT
    s.sale_code                     AS codigo_venta,
    r.reservation_code              AS codigo_reserva,
    p.payment_reference             AS referencia_pago,
    ps.status_name                  AS estado_pago,
    pm.method_name                  AS metodo_pago,
    pt.transaction_reference        AS referencia_transaccion,
    pt.transaction_type             AS tipo_transaccion,
    pt.transaction_amount           AS monto_procesado,
    c.iso_currency_code             AS moneda
FROM sale s
    INNER JOIN reservation r
        ON r.reservation_id = s.reservation_id
    INNER JOIN payment p
        ON p.sale_id = s.sale_id
    INNER JOIN payment_status ps
        ON ps.payment_status_id = p.payment_status_id
    INNER JOIN payment_method pm
        ON pm.payment_method_id = p.payment_method_id
    INNER JOIN payment_transaction pt
        ON pt.payment_id = p.payment_id
    INNER JOIN currency c
        ON c.currency_id = p.currency_id
ORDER BY s.sale_code, pt.processed_at;


-- ---------------------------------------------------------------
-- EJ02 · REQUERIMIENTO 2: Función auxiliar del trigger
-- Genera un reembolso automático cuando se inserta una transacción de tipo REFUND
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_auto_refund_ej02()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.transaction_type = 'REFUND' THEN
        INSERT INTO refund (
            payment_id,
            refund_reference,
            amount,
            requested_at,
            processed_at,
            refund_reason
        )
        VALUES (
            NEW.payment_id,
            'REF-' || UPPER(SUBSTRING(NEW.payment_transaction_id::text, 1, 10)),
            NEW.transaction_amount,
            now(),
            now(),
            'Generado automáticamente por transacción REFUND: ' || NEW.transaction_reference
        );
    END IF;
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------
-- EJ02 · REQUERIMIENTO 2: Trigger AFTER INSERT sobre payment_transaction
-- ---------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_ej02_auto_refund
AFTER INSERT ON payment_transaction
FOR EACH ROW
EXECUTE FUNCTION fn_auto_refund_ej02();


-- ---------------------------------------------------------------
-- EJ02 · REQUERIMIENTO 3: Procedimiento almacenado
-- Registra una transacción de pago sobre un pago existente
-- ---------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_transaccion_ej02(
    p_payment_id            uuid,
    p_transaction_reference varchar,
    p_transaction_type      varchar,
    p_transaction_amount    numeric,
    p_processed_at          timestamptz DEFAULT now(),
    p_provider_message      text        DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_transaction_type NOT IN ('AUTH','CAPTURE','VOID','REFUND','REVERSAL') THEN
        RAISE EXCEPTION 'Tipo de transacción inválido: %', p_transaction_type;
    END IF;

    IF p_transaction_amount <= 0 THEN
        RAISE EXCEPTION 'El monto de la transacción debe ser mayor que cero';
    END IF;

    INSERT INTO payment_transaction (
        payment_id,
        transaction_reference,
        transaction_type,
        transaction_amount,
        processed_at,
        provider_message
    )
    VALUES (
        p_payment_id,
        p_transaction_reference,
        p_transaction_type,
        p_transaction_amount,
        p_processed_at,
        p_provider_message
    );

    RAISE NOTICE 'Transacción % registrada sobre pago %', p_transaction_type, p_payment_id;
END;
$$;


-- ---------------------------------------------------------------
-- EJ02 · SCRIPT DE PRUEBA DEL TRIGGER
-- ---------------------------------------------------------------
-- Paso 1: Obtener un pago existente
SELECT payment_id, payment_reference, amount FROM payment LIMIT 3;

-- Paso 2: Invocar el procedimiento con tipo REFUND para disparar el trigger
-- CALL sp_registrar_transaccion_ej02(
--     '<payment_id>',
--     'TXN-REFUND-001',
--     'REFUND',
--     150.00,
--     now(),
--     'Devolución por cancelación'
-- );

-- Paso 3: Validar que el trigger generó el reembolso
-- SELECT r.* FROM refund r
-- JOIN payment p ON p.payment_id = r.payment_id
-- WHERE p.payment_id = '<payment_id>';


-- ---------------------------------------------------------------
-- EJ02 · CONSULTA DE VALIDACIÓN FINAL
-- ---------------------------------------------------------------
SELECT
    p.payment_reference,
    pt.transaction_type,
    pt.transaction_amount,
    r.refund_reference,
    r.amount              AS monto_reembolso,
    r.refund_reason
FROM payment_transaction pt
    INNER JOIN payment p ON p.payment_id = pt.payment_id
    INNER JOIN refund r   ON r.payment_id = pt.payment_id
WHERE pt.transaction_type = 'REFUND'
ORDER BY pt.processed_at DESC;


-- ################################################################################
-- EJERCICIO 03
-- Facturación e integración entre venta, impuestos y detalle facturable
-- Dominios: SALES · BILLING · GEOGRAPHY
-- ################################################################################

-- ---------------------------------------------------------------
-- EJ03 · REQUERIMIENTO 1: Consulta INNER JOIN (≥5 tablas)
-- Venta → factura → estado → líneas → impuesto → moneda
-- ---------------------------------------------------------------
SELECT
    s.sale_code                         AS codigo_venta,
    i.invoice_number                    AS numero_factura,
    ist.status_name                     AS estado_factura,
    il.line_number                      AS linea,
    il.line_description                 AS descripcion,
    il.quantity                         AS cantidad,
    il.unit_price                       AS precio_unitario,
    tx.tax_name                         AS impuesto_aplicado,
    tx.rate_percentage                  AS tasa_impuesto,
    c.iso_currency_code                 AS moneda
FROM sale s
    INNER JOIN invoice i
        ON i.sale_id = s.sale_id
    INNER JOIN invoice_status ist
        ON ist.invoice_status_id = i.invoice_status_id
    INNER JOIN invoice_line il
        ON il.invoice_id = i.invoice_id
    INNER JOIN currency c
        ON c.currency_id = i.currency_id
    INNER JOIN tax tx
        ON tx.tax_id = il.tax_id
ORDER BY s.sale_code, i.invoice_number, il.line_number;


-- ---------------------------------------------------------------
-- EJ03 · REQUERIMIENTO 2: Función auxiliar del trigger
-- Actualiza updated_at de la factura cuando se inserta una línea nueva
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_actualizar_factura_ej03()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE invoice
    SET updated_at = now()
    WHERE invoice_id = NEW.invoice_id;

    RAISE NOTICE 'Factura % actualizada al agregar línea %', NEW.invoice_id, NEW.line_number;
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------
-- EJ03 · REQUERIMIENTO 2: Trigger AFTER INSERT sobre invoice_line
-- ---------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_ej03_actualizar_factura
AFTER INSERT ON invoice_line
FOR EACH ROW
EXECUTE FUNCTION fn_actualizar_factura_ej03();


-- ---------------------------------------------------------------
-- EJ03 · REQUERIMIENTO 3: Procedimiento almacenado
-- Registra una nueva línea facturable sobre una factura existente
-- ---------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_agregar_linea_factura_ej03(
    p_invoice_id        uuid,
    p_tax_id            uuid,
    p_line_number       integer,
    p_line_description  varchar,
    p_quantity          numeric,
    p_unit_price        numeric
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor que cero';
    END IF;

    IF p_unit_price < 0 THEN
        RAISE EXCEPTION 'El precio unitario no puede ser negativo';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM invoice WHERE invoice_id = p_invoice_id) THEN
        RAISE EXCEPTION 'La factura % no existe', p_invoice_id;
    END IF;

    INSERT INTO invoice_line (
        invoice_id,
        tax_id,
        line_number,
        line_description,
        quantity,
        unit_price
    )
    VALUES (
        p_invoice_id,
        p_tax_id,
        p_line_number,
        p_line_description,
        p_quantity,
        p_unit_price
    );

    RAISE NOTICE 'Línea % agregada a factura %', p_line_number, p_invoice_id;
END;
$$;


-- ---------------------------------------------------------------
-- EJ03 · SCRIPT DE PRUEBA DEL TRIGGER
-- ---------------------------------------------------------------
-- Paso 1: Obtener factura e impuesto disponibles
SELECT invoice_id, invoice_number FROM invoice LIMIT 3;
SELECT tax_id, tax_code, tax_name FROM tax LIMIT 3;

-- Paso 2: Invocar el procedimiento (el INSERT dispara el trigger)
-- CALL sp_agregar_linea_factura_ej03(
--     '<invoice_id>',
--     '<tax_id>',
--     1,
--     'Tiquete aéreo BOG-MDE',
--     1,
--     350000.00
-- );

-- Paso 3: Validar updated_at de la factura (debe ser reciente)
-- SELECT invoice_id, invoice_number, updated_at FROM invoice WHERE invoice_id = '<invoice_id>';


-- ---------------------------------------------------------------
-- EJ03 · CONSULTA DE VALIDACIÓN FINAL
-- ---------------------------------------------------------------
SELECT
    i.invoice_number,
    i.updated_at              AS ultima_actualizacion,
    COUNT(il.invoice_line_id) AS total_lineas,
    SUM(il.quantity * il.unit_price) AS total_bruto
FROM invoice i
    INNER JOIN invoice_line il ON il.invoice_id = i.invoice_id
GROUP BY i.invoice_id, i.invoice_number, i.updated_at
ORDER BY i.updated_at DESC;


-- ################################################################################
-- EJERCICIO 04
-- Acumulación de millas y actualización del historial de nivel
-- Dominios: CUSTOMER AND LOYALTY · AIRLINE · IDENTITY · SALES
-- ################################################################################

-- ---------------------------------------------------------------
-- EJ04 · REQUERIMIENTO 1: Consulta INNER JOIN (≥5 tablas)
-- Cliente → persona → cuenta → programa → nivel → venta
-- ---------------------------------------------------------------
SELECT
    p.first_name || ' ' || p.last_name     AS persona,
    c.customer_since,
    la.account_number                       AS cuenta_fidelizacion,
    lp.program_name                         AS programa,
    lt.tier_name                            AS nivel,
    lat.assigned_at                         AS fecha_asignacion_nivel,
    s.sale_code                             AS venta_relacionada
FROM customer c
    INNER JOIN person p
        ON p.person_id = c.person_id
    INNER JOIN loyalty_account la
        ON la.customer_id = c.customer_id
    INNER JOIN loyalty_program lp
        ON lp.loyalty_program_id = la.loyalty_program_id
    INNER JOIN loyalty_account_tier lat
        ON lat.loyalty_account_id = la.loyalty_account_id
    INNER JOIN loyalty_tier lt
        ON lt.loyalty_tier_id = lat.loyalty_tier_id
    INNER JOIN reservation r
        ON r.booked_by_customer_id = c.customer_id
    INNER JOIN sale s
        ON s.reservation_id = r.reservation_id
ORDER BY c.customer_id, lat.assigned_at DESC;


-- ---------------------------------------------------------------
-- EJ04 · REQUERIMIENTO 2: Función auxiliar del trigger
-- Al acumular millas, revisa si el cliente debe subir de nivel
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_revisar_nivel_ej04()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_miles    bigint;
    v_program_id     uuid;
    v_new_tier_id    uuid;
    v_current_tier   uuid;
BEGIN
    -- Obtener programa de la cuenta
    SELECT lp.loyalty_program_id
    INTO v_program_id
    FROM loyalty_account la
    JOIN loyalty_program lp ON lp.loyalty_program_id = la.loyalty_program_id
    WHERE la.loyalty_account_id = NEW.loyalty_account_id;

    -- Sumar millas totales acumuladas (EARN - REDEEM)
    SELECT COALESCE(SUM(miles_delta), 0)
    INTO v_total_miles
    FROM miles_transaction
    WHERE loyalty_account_id = NEW.loyalty_account_id
      AND transaction_type IN ('EARN', 'ADJUST');

    -- Buscar el nivel más alto que califica con esas millas
    SELECT loyalty_tier_id
    INTO v_new_tier_id
    FROM loyalty_tier
    WHERE loyalty_program_id = v_program_id
      AND required_miles <= v_total_miles
    ORDER BY required_miles DESC
    LIMIT 1;

    IF v_new_tier_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Verificar nivel actual vigente
    SELECT loyalty_tier_id
    INTO v_current_tier
    FROM loyalty_account_tier
    WHERE loyalty_account_id = NEW.loyalty_account_id
    ORDER BY assigned_at DESC
    LIMIT 1;

    -- Insertar nuevo nivel solo si cambió
    IF v_current_tier IS DISTINCT FROM v_new_tier_id THEN
        INSERT INTO loyalty_account_tier (
            loyalty_account_id,
            loyalty_tier_id,
            assigned_at
        )
        VALUES (
            NEW.loyalty_account_id,
            v_new_tier_id,
            now()
        );
        RAISE NOTICE 'Nivel actualizado para cuenta %', NEW.loyalty_account_id;
    END IF;

    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------
-- EJ04 · REQUERIMIENTO 2: Trigger AFTER INSERT sobre miles_transaction
-- ---------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_ej04_revisar_nivel
AFTER INSERT ON miles_transaction
FOR EACH ROW
EXECUTE FUNCTION fn_revisar_nivel_ej04();


-- ---------------------------------------------------------------
-- EJ04 · REQUERIMIENTO 3: Procedimiento almacenado
-- Registra una transacción de millas sobre una cuenta de fidelización
-- ---------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_acumular_millas_ej04(
    p_loyalty_account_id  uuid,
    p_transaction_type    varchar,
    p_miles_delta         integer,
    p_occurred_at         timestamptz DEFAULT now(),
    p_reference_code      varchar     DEFAULT NULL,
    p_notes               text        DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_transaction_type NOT IN ('EARN', 'REDEEM', 'ADJUST') THEN
        RAISE EXCEPTION 'Tipo de transacción inválido: %', p_transaction_type;
    END IF;

    IF p_miles_delta = 0 THEN
        RAISE EXCEPTION 'El delta de millas no puede ser cero';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM loyalty_account WHERE loyalty_account_id = p_loyalty_account_id) THEN
        RAISE EXCEPTION 'Cuenta de fidelización % no encontrada', p_loyalty_account_id;
    END IF;

    INSERT INTO miles_transaction (
        loyalty_account_id,
        transaction_type,
        miles_delta,
        occurred_at,
        reference_code,
        notes
    )
    VALUES (
        p_loyalty_account_id,
        p_transaction_type,
        p_miles_delta,
        p_occurred_at,
        p_reference_code,
        p_notes
    );

    RAISE NOTICE '% millas (%) registradas en cuenta %', p_miles_delta, p_transaction_type, p_loyalty_account_id;
END;
$$;


-- ---------------------------------------------------------------
-- EJ04 · SCRIPT DE PRUEBA DEL TRIGGER
-- ---------------------------------------------------------------
-- Paso 1: Obtener cuenta de fidelización disponible
SELECT la.loyalty_account_id, la.account_number, c.customer_id
FROM loyalty_account la
JOIN customer c ON c.customer_id = la.customer_id
LIMIT 3;

-- Paso 2: Invocar el procedimiento (dispara el trigger de nivel)
-- CALL sp_acumular_millas_ej04(
--     '<loyalty_account_id>',
--     'EARN',
--     5000,
--     now(),
--     'VUELO-BOG-MDE-2025',
--     'Millas por vuelo BOG-MDE'
-- );

-- Paso 3: Verificar si se actualizó el historial de nivel
-- SELECT lat.*, lt.tier_name
-- FROM loyalty_account_tier lat
-- JOIN loyalty_tier lt ON lt.loyalty_tier_id = lat.loyalty_tier_id
-- WHERE lat.loyalty_account_id = '<loyalty_account_id>'
-- ORDER BY lat.assigned_at DESC;


-- ---------------------------------------------------------------
-- EJ04 · CONSULTA DE VALIDACIÓN FINAL
-- ---------------------------------------------------------------
SELECT
    la.account_number,
    COALESCE(SUM(mt.miles_delta), 0) AS millas_acumuladas,
    lt.tier_name                      AS nivel_actual,
    lat.assigned_at                   AS nivel_desde
FROM loyalty_account la
    INNER JOIN miles_transaction mt
        ON mt.loyalty_account_id = la.loyalty_account_id
    INNER JOIN loyalty_account_tier lat
        ON lat.loyalty_account_id = la.loyalty_account_id
    INNER JOIN loyalty_tier lt
        ON lt.loyalty_tier_id = lat.loyalty_tier_id
GROUP BY la.account_number, lt.tier_name, lat.assigned_at
ORDER BY lat.assigned_at DESC;


-- ################################################################################
-- EJERCICIO 05
-- Mantenimiento de aeronaves y habilitación operativa
-- Dominios: AIRCRAFT · AIRLINE · GEOGRAPHY
-- ################################################################################

-- ---------------------------------------------------------------
-- EJ05 · REQUERIMIENTO 1: Consulta INNER JOIN (≥5 tablas)
-- Aeronave → aerolínea → modelo → fabricante → mantenimiento → proveedor
-- ---------------------------------------------------------------
SELECT
    ac.registration_number          AS matricula,
    al.airline_name                 AS aerolinea,
    am.model_name                   AS modelo,
    mfr.manufacturer_name           AS fabricante,
    mt.type_name                    AS tipo_mantenimiento,
    mp.provider_name                AS proveedor,
    me.status_code                  AS estado_evento,
    me.started_at                   AS fecha_inicio,
    me.completed_at                 AS fecha_fin
FROM aircraft ac
    INNER JOIN airline al
        ON al.airline_id = ac.airline_id
    INNER JOIN aircraft_model am
        ON am.aircraft_model_id = ac.aircraft_model_id
    INNER JOIN aircraft_manufacturer mfr
        ON mfr.aircraft_manufacturer_id = am.aircraft_manufacturer_id
    INNER JOIN maintenance_event me
        ON me.aircraft_id = ac.aircraft_id
    INNER JOIN maintenance_type mt
        ON mt.maintenance_type_id = me.maintenance_type_id
    INNER JOIN maintenance_provider mp
        ON mp.maintenance_provider_id = me.maintenance_provider_id
ORDER BY ac.registration_number, me.started_at DESC;


-- ---------------------------------------------------------------
-- EJ05 · REQUERIMIENTO 2: Función auxiliar del trigger
-- Al completar un mantenimiento, registra un evento en la misma tabla
-- marcando que la aeronave quedó habilitada operativamente
-- (efecto verificable: inserta un nuevo registro PLANNED o deja nota)
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_log_mantenimiento_ej05()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Cuando un evento cambia a COMPLETED, se notifica operativamente
    IF NEW.status_code = 'COMPLETED' AND
       (OLD.status_code IS DISTINCT FROM 'COMPLETED') THEN
        RAISE NOTICE 'Aeronave % habilitada operativamente. Evento de mantenimiento % completado en %.',
            NEW.aircraft_id,
            NEW.maintenance_event_id,
            now();

        -- Actualizar el campo updated_at de la aeronave para trazabilidad
        UPDATE aircraft
        SET updated_at = now()
        WHERE aircraft_id = NEW.aircraft_id;
    END IF;
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------
-- EJ05 · REQUERIMIENTO 2: Trigger AFTER INSERT/UPDATE sobre maintenance_event
-- ---------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_ej05_habilitacion_aeronave
AFTER INSERT OR UPDATE ON maintenance_event
FOR EACH ROW
EXECUTE FUNCTION fn_log_mantenimiento_ej05();


-- ---------------------------------------------------------------
-- EJ05 · REQUERIMIENTO 3: Procedimiento almacenado
-- Registra un nuevo evento de mantenimiento para una aeronave
-- ---------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_mantenimiento_ej05(
    p_aircraft_id              uuid,
    p_maintenance_type_id      uuid,
    p_maintenance_provider_id  uuid,
    p_status_code              varchar DEFAULT 'PLANNED',
    p_started_at               timestamptz DEFAULT now(),
    p_notes                    text        DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_status_code NOT IN ('PLANNED','IN_PROGRESS','COMPLETED','CANCELLED') THEN
        RAISE EXCEPTION 'Estado inválido: %', p_status_code;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM aircraft WHERE aircraft_id = p_aircraft_id) THEN
        RAISE EXCEPTION 'Aeronave % no encontrada', p_aircraft_id;
    END IF;

    INSERT INTO maintenance_event (
        aircraft_id,
        maintenance_type_id,
        maintenance_provider_id,
        status_code,
        started_at,
        notes
    )
    VALUES (
        p_aircraft_id,
        p_maintenance_type_id,
        p_maintenance_provider_id,
        p_status_code,
        p_started_at,
        p_notes
    );

    RAISE NOTICE 'Evento de mantenimiento registrado para aeronave %', p_aircraft_id;
END;
$$;


-- ---------------------------------------------------------------
-- EJ05 · SCRIPT DE PRUEBA DEL TRIGGER
-- ---------------------------------------------------------------
-- Paso 1: Obtener aeronave, tipo y proveedor de mantenimiento
SELECT aircraft_id, registration_number FROM aircraft LIMIT 3;
SELECT maintenance_type_id, type_code FROM maintenance_type LIMIT 3;
SELECT maintenance_provider_id, provider_name FROM maintenance_provider LIMIT 3;

-- Paso 2: Registrar nuevo evento (trigger se activa por INSERT)
-- CALL sp_registrar_mantenimiento_ej05(
--     '<aircraft_id>',
--     '<maintenance_type_id>',
--     '<maintenance_provider_id>',
--     'IN_PROGRESS',
--     now(),
--     'Revisión de motores programada'
-- );

-- Paso 3: Actualizar a COMPLETED para disparar la rama del trigger
-- UPDATE maintenance_event
-- SET status_code = 'COMPLETED', completed_at = now()
-- WHERE aircraft_id = '<aircraft_id>'
--   AND status_code = 'IN_PROGRESS';

-- Paso 4: Verificar que updated_at de la aeronave cambió
-- SELECT aircraft_id, registration_number, updated_at
-- FROM aircraft WHERE aircraft_id = '<aircraft_id>';


-- ---------------------------------------------------------------
-- EJ05 · CONSULTA DE VALIDACIÓN FINAL
-- ---------------------------------------------------------------
SELECT
    ac.registration_number,
    ac.updated_at                  AS ultima_actualizacion_aeronave,
    me.status_code,
    me.started_at,
    me.completed_at,
    mt.type_name
FROM maintenance_event me
    INNER JOIN aircraft ac     ON ac.aircraft_id = me.aircraft_id
    INNER JOIN maintenance_type mt ON mt.maintenance_type_id = me.maintenance_type_id
ORDER BY me.completed_at DESC NULLS LAST;


-- ################################################################################
-- EJERCICIO 06
-- Retrasos operativos y análisis de impacto por segmento de vuelo
-- Dominios: FLIGHT OPERATIONS · AIRPORT · AIRLINE
-- ################################################################################

-- ---------------------------------------------------------------
-- EJ06 · REQUERIMIENTO 1: Consulta INNER JOIN (≥5 tablas)
-- Aerolínea → vuelo → estado → segmento → aeropuertos → retraso
-- ---------------------------------------------------------------
SELECT
    al.airline_name                         AS aerolinea,
    f.flight_number                         AS numero_vuelo,
    f.service_date                          AS fecha_servicio,
    fst.status_name                         AS estado_vuelo,
    fs.segment_number                       AS segmento,
    ao.airport_name                         AS aeropuerto_origen,
    ad.airport_name                         AS aeropuerto_destino,
    fd.delay_minutes                        AS minutos_demora,
    drt.reason_name                         AS motivo_retraso
FROM airline al
    INNER JOIN flight f
        ON f.airline_id = al.airline_id
    INNER JOIN flight_status fst
        ON fst.flight_status_id = f.flight_status_id
    INNER JOIN flight_segment fs
        ON fs.flight_id = f.flight_id
    INNER JOIN airport ao
        ON ao.airport_id = fs.origin_airport_id
    INNER JOIN airport ad
        ON ad.airport_id = fs.destination_airport_id
    INNER JOIN flight_delay fd
        ON fd.flight_segment_id = fs.flight_segment_id
    INNER JOIN delay_reason_type drt
        ON drt.delay_reason_type_id = fd.delay_reason_type_id
ORDER BY f.service_date DESC, fd.delay_minutes DESC;


-- ---------------------------------------------------------------
-- EJ06 · REQUERIMIENTO 2: Función auxiliar del trigger
-- Al insertar una demora, actualiza el estado del vuelo si la demora
-- supera 60 minutos (efecto verificable sobre flight)
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_impacto_vuelo_ej06()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_flight_id     uuid;
    v_delay_status  uuid;
BEGIN
    -- Obtener el vuelo del segmento demorado
    SELECT flight_id INTO v_flight_id
    FROM flight_segment
    WHERE flight_segment_id = NEW.flight_segment_id;

    -- Si la demora es mayor a 60 minutos, buscar estado 'DELAYED' y actualizar
    IF NEW.delay_minutes > 60 THEN
        SELECT flight_status_id INTO v_delay_status
        FROM flight_status
        WHERE status_code = 'DELAYED'
        LIMIT 1;

        IF v_delay_status IS NOT NULL THEN
            UPDATE flight
            SET flight_status_id = v_delay_status,
                updated_at = now()
            WHERE flight_id = v_flight_id;

            RAISE NOTICE 'Vuelo % marcado como DELAYED por demora de % minutos',
                v_flight_id, NEW.delay_minutes;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------
-- EJ06 · REQUERIMIENTO 2: Trigger AFTER INSERT sobre flight_delay
-- ---------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_ej06_impacto_vuelo
AFTER INSERT ON flight_delay
FOR EACH ROW
EXECUTE FUNCTION fn_impacto_vuelo_ej06();


-- ---------------------------------------------------------------
-- EJ06 · REQUERIMIENTO 3: Procedimiento almacenado
-- Registra una demora para un flight_segment existente
-- ---------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_demora_ej06(
    p_flight_segment_id     uuid,
    p_delay_reason_type_id  uuid,
    p_reported_at           timestamptz,
    p_delay_minutes         integer,
    p_notes                 text DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_delay_minutes <= 0 THEN
        RAISE EXCEPTION 'Los minutos de demora deben ser mayores que cero';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM flight_segment WHERE flight_segment_id = p_flight_segment_id) THEN
        RAISE EXCEPTION 'Segmento de vuelo % no encontrado', p_flight_segment_id;
    END IF;

    INSERT INTO flight_delay (
        flight_segment_id,
        delay_reason_type_id,
        reported_at,
        delay_minutes,
        notes
    )
    VALUES (
        p_flight_segment_id,
        p_delay_reason_type_id,
        p_reported_at,
        p_delay_minutes,
        p_notes
    );

    RAISE NOTICE 'Demora de % minutos registrada para segmento %', p_delay_minutes, p_flight_segment_id;
END;
$$;


-- ---------------------------------------------------------------
-- EJ06 · SCRIPT DE PRUEBA DEL TRIGGER
-- ---------------------------------------------------------------
-- Paso 1: Obtener segmento de vuelo y tipo de motivo de retraso
SELECT flight_segment_id, segment_number FROM flight_segment LIMIT 3;
SELECT delay_reason_type_id, reason_code FROM delay_reason_type LIMIT 3;

-- Paso 2: Invocar el procedimiento con > 60 minutos para disparar el trigger
-- CALL sp_registrar_demora_ej06(
--     '<flight_segment_id>',
--     '<delay_reason_type_id>',
--     now(),
--     90,
--     'Falla técnica en sistemas de navegación'
-- );

-- Paso 3: Verificar que el vuelo cambió de estado
-- SELECT f.flight_number, fst.status_name, f.updated_at
-- FROM flight f
-- JOIN flight_status fst ON fst.flight_status_id = f.flight_status_id
-- JOIN flight_segment fs ON fs.flight_id = f.flight_id
-- WHERE fs.flight_segment_id = '<flight_segment_id>';


-- ---------------------------------------------------------------
-- EJ06 · CONSULTA DE VALIDACIÓN FINAL
-- ---------------------------------------------------------------
SELECT
    f.flight_number,
    fst.status_name           AS estado_actual,
    SUM(fd.delay_minutes)     AS minutos_totales_demora,
    COUNT(fd.flight_delay_id) AS total_demoras
FROM flight f
    INNER JOIN flight_status fst   ON fst.flight_status_id = f.flight_status_id
    INNER JOIN flight_segment fs   ON fs.flight_id = f.flight_id
    INNER JOIN flight_delay fd     ON fd.flight_segment_id = fs.flight_segment_id
GROUP BY f.flight_id, f.flight_number, fst.status_name
ORDER BY minutos_totales_demora DESC;


-- ################################################################################
-- EJERCICIO 07
-- Asignación de asientos y registro de equipaje por segmento ticketed
-- Dominios: SALES/RESERVATION/TICKETING · AIRCRAFT · FLIGHT OPERATIONS
-- ################################################################################

-- ---------------------------------------------------------------
-- EJ07 · REQUERIMIENTO 1: Consulta INNER JOIN (≥5 tablas)
-- Tiquete → segmento → asiento → cabina → equipaje
-- ---------------------------------------------------------------
SELECT
    t.ticket_number                             AS numero_tiquete,
    ts.segment_sequence_no                      AS secuencia_segmento,
    f.flight_number                             AS vuelo,
    cc.class_name                               AS cabina,
    aseat.seat_row_number                       AS fila,
    aseat.seat_column_code                      AS columna,
    b.baggage_tag                               AS etiqueta_equipaje,
    b.baggage_type                              AS tipo_equipaje,
    b.baggage_status                            AS estado_equipaje
FROM ticket t
    INNER JOIN ticket_segment ts
        ON ts.ticket_id = t.ticket_id
    INNER JOIN flight_segment fs
        ON fs.flight_segment_id = ts.flight_segment_id
    INNER JOIN flight f
        ON f.flight_id = fs.flight_id
    INNER JOIN seat_assignment sa
        ON sa.ticket_segment_id = ts.ticket_segment_id
    INNER JOIN aircraft_seat aseat
        ON aseat.aircraft_seat_id = sa.aircraft_seat_id
    INNER JOIN aircraft_cabin ac
        ON ac.aircraft_cabin_id = aseat.aircraft_cabin_id
    INNER JOIN cabin_class cc
        ON cc.cabin_class_id = ac.cabin_class_id
    INNER JOIN baggage b
        ON b.ticket_segment_id = ts.ticket_segment_id
ORDER BY t.ticket_number, ts.segment_sequence_no;


-- ---------------------------------------------------------------
-- EJ07 · REQUERIMIENTO 2: Función auxiliar del trigger
-- Al registrar equipaje, actualiza el estado del ticket_segment
-- poniendo en evidencia el equipaje facturado (efecto en baggage mismo)
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_log_equipaje_ej07()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Efecto verificable: actualizar updated_at del ticket relacionado
    UPDATE ticket
    SET updated_at = now()
    WHERE ticket_id = (
        SELECT ticket_id
        FROM ticket_segment
        WHERE ticket_segment_id = NEW.ticket_segment_id
    );

    RAISE NOTICE 'Equipaje % (%) registrado para segmento %. Tiquete actualizado.',
        NEW.baggage_tag, NEW.baggage_type, NEW.ticket_segment_id;

    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------
-- EJ07 · REQUERIMIENTO 2: Trigger AFTER INSERT sobre baggage
-- ---------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_ej07_log_equipaje
AFTER INSERT ON baggage
FOR EACH ROW
EXECUTE FUNCTION fn_log_equipaje_ej07();


-- ---------------------------------------------------------------
-- EJ07 · REQUERIMIENTO 3: Procedimiento almacenado
-- Registra equipaje para un ticket_segment existente
-- ---------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_equipaje_ej07(
    p_ticket_segment_id  uuid,
    p_baggage_tag        varchar,
    p_baggage_type       varchar,
    p_weight_kg          numeric,
    p_checked_at         timestamptz DEFAULT now()
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_baggage_type NOT IN ('CHECKED','CARRY_ON','SPECIAL') THEN
        RAISE EXCEPTION 'Tipo de equipaje inválido: %', p_baggage_type;
    END IF;

    IF p_weight_kg <= 0 THEN
        RAISE EXCEPTION 'El peso debe ser mayor que cero';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ticket_segment WHERE ticket_segment_id = p_ticket_segment_id) THEN
        RAISE EXCEPTION 'Segmento de tiquete % no encontrado', p_ticket_segment_id;
    END IF;

    INSERT INTO baggage (
        ticket_segment_id,
        baggage_tag,
        baggage_type,
        baggage_status,
        weight_kg,
        checked_at
    )
    VALUES (
        p_ticket_segment_id,
        p_baggage_tag,
        p_baggage_type,
        'REGISTERED',
        p_weight_kg,
        p_checked_at
    );

    RAISE NOTICE 'Equipaje % registrado para segmento %', p_baggage_tag, p_ticket_segment_id;
END;
$$;


-- ---------------------------------------------------------------
-- EJ07 · SCRIPT DE PRUEBA DEL TRIGGER
-- ---------------------------------------------------------------
-- Paso 1: Obtener un ticket_segment existente
SELECT ts.ticket_segment_id, t.ticket_number
FROM ticket_segment ts
JOIN ticket t ON t.ticket_id = ts.ticket_id
LIMIT 3;

-- Paso 2: Invocar el procedimiento (dispara el trigger)
-- CALL sp_registrar_equipaje_ej07(
--     '<ticket_segment_id>',
--     'TAG-EJ07-001',
--     'CHECKED',
--     23.5,
--     now()
-- );

-- Paso 3: Verificar que el tiquete fue actualizado
-- SELECT ticket_id, ticket_number, updated_at FROM ticket
-- WHERE ticket_id = (
--     SELECT ticket_id FROM ticket_segment WHERE ticket_segment_id = '<ticket_segment_id>'
-- );


-- ---------------------------------------------------------------
-- EJ07 · CONSULTA DE VALIDACIÓN FINAL
-- ---------------------------------------------------------------
SELECT
    t.ticket_number,
    t.updated_at               AS tiquete_actualizado,
    b.baggage_tag,
    b.baggage_type,
    b.baggage_status,
    b.weight_kg
FROM baggage b
    INNER JOIN ticket_segment ts ON ts.ticket_segment_id = b.ticket_segment_id
    INNER JOIN ticket t           ON t.ticket_id = ts.ticket_id
ORDER BY t.updated_at DESC;


-- ################################################################################
-- EJERCICIO 08
-- Auditoría de acceso y asignación de roles a usuarios
-- Dominios: SECURITY · IDENTITY
-- ################################################################################

-- ---------------------------------------------------------------
-- EJ08 · REQUERIMIENTO 1: Consulta INNER JOIN (≥5 tablas)
-- Persona → cuenta → estado → rol → permisos
-- ---------------------------------------------------------------
SELECT
    p.first_name || ' ' || p.last_name     AS persona,
    ua.username                             AS usuario,
    us.status_name                          AS estado_usuario,
    sr.role_name                            AS rol_asignado,
    ur.assigned_at                          AS fecha_asignacion,
    sp.permission_name                      AS permiso_asociado
FROM person p
    INNER JOIN user_account ua
        ON ua.person_id = p.person_id
    INNER JOIN user_status us
        ON us.user_status_id = ua.user_status_id
    INNER JOIN user_role ur
        ON ur.user_account_id = ua.user_account_id
    INNER JOIN security_role sr
        ON sr.security_role_id = ur.security_role_id
    INNER JOIN role_permission rp
        ON rp.security_role_id = sr.security_role_id
    INNER JOIN security_permission sp
        ON sp.security_permission_id = rp.security_permission_id
ORDER BY ua.username, sr.role_name;


-- ---------------------------------------------------------------
-- EJ08 · REQUERIMIENTO 2: Función auxiliar del trigger
-- Al asignar un rol, copia los permisos del rol como log informativo
-- (efecto verificable: actualiza updated_at en user_account)
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_log_asignacion_rol_ej08()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_role_name  varchar;
BEGIN
    SELECT role_name INTO v_role_name
    FROM security_role
    WHERE security_role_id = NEW.security_role_id;

    -- Efecto verificable: actualizar el timestamp de la cuenta
    UPDATE user_account
    SET updated_at = now()
    WHERE user_account_id = NEW.user_account_id;

    RAISE NOTICE 'Rol "%" asignado a cuenta %. Cuenta actualizada.',
        v_role_name, NEW.user_account_id;

    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------
-- EJ08 · REQUERIMIENTO 2: Trigger AFTER INSERT sobre user_role
-- ---------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_ej08_log_rol
AFTER INSERT ON user_role
FOR EACH ROW
EXECUTE FUNCTION fn_log_asignacion_rol_ej08();


-- ---------------------------------------------------------------
-- EJ08 · REQUERIMIENTO 3: Procedimiento almacenado
-- Asigna un rol a un usuario existente
-- ---------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_asignar_rol_ej08(
    p_user_account_id    uuid,
    p_security_role_id   uuid,
    p_assigned_by        uuid DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM user_account WHERE user_account_id = p_user_account_id) THEN
        RAISE EXCEPTION 'Cuenta de usuario % no encontrada', p_user_account_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM security_role WHERE security_role_id = p_security_role_id) THEN
        RAISE EXCEPTION 'Rol % no encontrado', p_security_role_id;
    END IF;

    IF EXISTS (
        SELECT 1 FROM user_role
        WHERE user_account_id = p_user_account_id
          AND security_role_id = p_security_role_id
    ) THEN
        RAISE NOTICE 'El rol ya está asignado a este usuario';
        RETURN;
    END IF;

    INSERT INTO user_role (
        user_account_id,
        security_role_id,
        assigned_at,
        assigned_by_user_id
    )
    VALUES (
        p_user_account_id,
        p_security_role_id,
        now(),
        p_assigned_by
    );

    RAISE NOTICE 'Rol % asignado a usuario %', p_security_role_id, p_user_account_id;
END;
$$;


-- ---------------------------------------------------------------
-- EJ08 · SCRIPT DE PRUEBA DEL TRIGGER
-- ---------------------------------------------------------------
-- Paso 1: Obtener cuenta de usuario y rol disponibles
SELECT user_account_id, username FROM user_account LIMIT 3;
SELECT security_role_id, role_code FROM security_role LIMIT 3;

-- Paso 2: Invocar el procedimiento (dispara el trigger)
-- CALL sp_asignar_rol_ej08(
--     '<user_account_id>',
--     '<security_role_id>',
--     NULL
-- );

-- Paso 3: Verificar que updated_at de la cuenta cambió
-- SELECT user_account_id, username, updated_at
-- FROM user_account WHERE user_account_id = '<user_account_id>';


-- ---------------------------------------------------------------
-- EJ08 · CONSULTA DE VALIDACIÓN FINAL
-- ---------------------------------------------------------------
SELECT
    ua.username,
    ua.updated_at             AS cuenta_actualizada,
    sr.role_name,
    ur.assigned_at,
    COUNT(rp.security_permission_id) AS permisos_heredados
FROM user_account ua
    INNER JOIN user_role ur      ON ur.user_account_id = ua.user_account_id
    INNER JOIN security_role sr  ON sr.security_role_id = ur.security_role_id
    LEFT JOIN role_permission rp ON rp.security_role_id = sr.security_role_id
GROUP BY ua.user_account_id, ua.username, ua.updated_at, sr.role_name, ur.assigned_at
ORDER BY ua.updated_at DESC;


-- ################################################################################
-- EJERCICIO 09
-- Publicación de tarifas y análisis de reservas comercializadas
-- Dominios: SALES/RESERVATION/TICKETING · AIRPORT · AIRLINE · GEOGRAPHY
-- ################################################################################

-- ---------------------------------------------------------------
-- EJ09 · REQUERIMIENTO 1: Consulta INNER JOIN (≥5 tablas)
-- Aerolínea → tarifa → clase → aeropuertos → moneda → reserva → venta → tiquete
-- ---------------------------------------------------------------
SELECT
    al.airline_name                         AS aerolinea,
    fa.fare_code                            AS codigo_tarifa,
    fc.fare_class_name                      AS clase_tarifaria,
    ao.airport_name                         AS aeropuerto_origen,
    ad.airport_name                         AS aeropuerto_destino,
    c.iso_currency_code                     AS moneda,
    r.reservation_code                      AS reserva,
    s.sale_code                             AS venta,
    t.ticket_number                         AS tiquete
FROM airline al
    INNER JOIN fare fa
        ON fa.airline_id = al.airline_id
    INNER JOIN fare_class fc
        ON fc.fare_class_id = fa.fare_class_id
    INNER JOIN airport ao
        ON ao.airport_id = fa.origin_airport_id
    INNER JOIN airport ad
        ON ad.airport_id = fa.destination_airport_id
    INNER JOIN currency c
        ON c.currency_id = fa.currency_id
    INNER JOIN ticket t
        ON t.fare_id = fa.fare_id
    INNER JOIN sale s
        ON s.sale_id = t.sale_id
    INNER JOIN reservation r
        ON r.reservation_id = s.reservation_id
ORDER BY al.airline_name, fa.fare_code;


-- ---------------------------------------------------------------
-- EJ09 · REQUERIMIENTO 2: Función auxiliar del trigger
-- Al publicar (insertar) una tarifa, deja constancia en la tabla
-- de auditoría: actualiza updated_at en airline para trazabilidad
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_log_tarifa_ej09()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Efecto verificable: actualizar timestamp de la aerolínea
    UPDATE airline
    SET updated_at = now()
    WHERE airline_id = NEW.airline_id;

    RAISE NOTICE 'Tarifa % publicada para aerolínea %. Vigencia: % a %.',
        NEW.fare_code,
        NEW.airline_id,
        NEW.valid_from,
        COALESCE(NEW.valid_to::text, 'indefinida');

    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------
-- EJ09 · REQUERIMIENTO 2: Trigger AFTER INSERT sobre fare
-- ---------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_ej09_log_tarifa
AFTER INSERT ON fare
FOR EACH ROW
EXECUTE FUNCTION fn_log_tarifa_ej09();


-- ---------------------------------------------------------------
-- EJ09 · REQUERIMIENTO 3: Procedimiento almacenado
-- Registra una nueva tarifa para una ruta y clase específica
-- ---------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_publicar_tarifa_ej09(
    p_airline_id              uuid,
    p_origin_airport_id       uuid,
    p_destination_airport_id  uuid,
    p_fare_class_id           uuid,
    p_currency_id             uuid,
    p_fare_code               varchar,
    p_base_amount             numeric,
    p_valid_from              date,
    p_valid_to                date    DEFAULT NULL,
    p_baggage_allowance_qty   integer DEFAULT 0
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_origin_airport_id = p_destination_airport_id THEN
        RAISE EXCEPTION 'Origen y destino no pueden ser el mismo aeropuerto';
    END IF;

    IF p_base_amount < 0 THEN
        RAISE EXCEPTION 'El monto base no puede ser negativo';
    END IF;

    IF p_valid_to IS NOT NULL AND p_valid_to < p_valid_from THEN
        RAISE EXCEPTION 'La fecha de vencimiento no puede ser anterior a la vigencia';
    END IF;

    INSERT INTO fare (
        airline_id,
        origin_airport_id,
        destination_airport_id,
        fare_class_id,
        currency_id,
        fare_code,
        base_amount,
        valid_from,
        valid_to,
        baggage_allowance_qty
    )
    VALUES (
        p_airline_id,
        p_origin_airport_id,
        p_destination_airport_id,
        p_fare_class_id,
        p_currency_id,
        p_fare_code,
        p_base_amount,
        p_valid_from,
        p_valid_to,
        p_baggage_allowance_qty
    );

    RAISE NOTICE 'Tarifa % publicada correctamente', p_fare_code;
END;
$$;


-- ---------------------------------------------------------------
-- EJ09 · SCRIPT DE PRUEBA DEL TRIGGER
-- ---------------------------------------------------------------
-- Paso 1: Obtener aerolínea, aeropuertos, clase y moneda
SELECT airline_id, airline_code FROM airline LIMIT 3;
SELECT airport_id, iata_code FROM airport LIMIT 5;
SELECT fare_class_id, fare_class_code FROM fare_class LIMIT 3;
SELECT currency_id, iso_currency_code FROM currency LIMIT 3;

-- Paso 2: Invocar el procedimiento (dispara el trigger de tarifa)
-- CALL sp_publicar_tarifa_ej09(
--     '<airline_id>',
--     '<origin_airport_id>',
--     '<destination_airport_id>',
--     '<fare_class_id>',
--     '<currency_id>',
--     'FARE-EJ09-001',
--     450000.00,
--     CURRENT_DATE,
--     CURRENT_DATE + INTERVAL '6 months',
--     1
-- );

-- Paso 3: Verificar que updated_at de la aerolínea se actualizó
-- SELECT airline_id, airline_code, updated_at FROM airline WHERE airline_id = '<airline_id>';


-- ---------------------------------------------------------------
-- EJ09 · CONSULTA DE VALIDACIÓN FINAL
-- ---------------------------------------------------------------
SELECT
    al.airline_name,
    al.updated_at               AS aerolinea_actualizada,
    fa.fare_code,
    fa.base_amount,
    fa.valid_from,
    fa.valid_to,
    c.iso_currency_code
FROM fare fa
    INNER JOIN airline al  ON al.airline_id = fa.airline_id
    INNER JOIN currency c  ON c.currency_id = fa.currency_id
ORDER BY fa.created_at DESC
LIMIT 10;


-- ################################################################################
-- EJERCICIO 10
-- Identidad de pasajeros, documentos y medios de contacto
-- Dominios: IDENTITY · CUSTOMER AND LOYALTY · SALES/RESERVATION/TICKETING
-- ################################################################################

-- ---------------------------------------------------------------
-- EJ10 · REQUERIMIENTO 1: Consulta INNER JOIN (≥5 tablas)
-- Persona → tipo → documentos → contactos → reservas
-- ---------------------------------------------------------------
SELECT
    p.first_name || ' ' || p.last_name     AS persona,
    pt.type_name                            AS tipo_persona,
    dt.type_name                            AS tipo_documento,
    pd.document_number                      AS numero_documento,
    ct.type_name                            AS tipo_contacto,
    pc.contact_value                        AS valor_contacto,
    r.reservation_code                      AS reserva,
    rp.passenger_sequence_no                AS secuencia_pasajero
FROM person p
    INNER JOIN person_type pt
        ON pt.person_type_id = p.person_type_id
    INNER JOIN person_document pd
        ON pd.person_id = p.person_id
    INNER JOIN document_type dt
        ON dt.document_type_id = pd.document_type_id
    INNER JOIN person_contact pc
        ON pc.person_id = p.person_id
    INNER JOIN contact_type ct
        ON ct.contact_type_id = pc.contact_type_id
    INNER JOIN reservation_passenger rp
        ON rp.person_id = p.person_id
    INNER JOIN reservation r
        ON r.reservation_id = rp.reservation_id
ORDER BY p.last_name, p.first_name, r.reservation_code;


-- ---------------------------------------------------------------
-- EJ10 · REQUERIMIENTO 2: Función auxiliar del trigger
-- Al registrar un nuevo documento, actualiza updated_at de la persona
-- y notifica la acción (efecto verificable)
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_actualizar_persona_ej10()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_doc_type  varchar;
BEGIN
    SELECT type_name INTO v_doc_type
    FROM document_type
    WHERE document_type_id = NEW.document_type_id;

    -- Efecto verificable: actualizar timestamp de la persona
    UPDATE person
    SET updated_at = now()
    WHERE person_id = NEW.person_id;

    RAISE NOTICE 'Documento "%" (%) registrado para persona %. Persona actualizada.',
        v_doc_type,
        NEW.document_number,
        NEW.person_id;

    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------
-- EJ10 · REQUERIMIENTO 2: Trigger AFTER INSERT sobre person_document
-- ---------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_ej10_actualizar_persona
AFTER INSERT ON person_document
FOR EACH ROW
EXECUTE FUNCTION fn_actualizar_persona_ej10();


-- ---------------------------------------------------------------
-- EJ10 · REQUERIMIENTO 3: Procedimiento almacenado
-- Registra un nuevo documento para una persona existente
-- ---------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_documento_ej10(
    p_person_id          uuid,
    p_document_type_id   uuid,
    p_issuing_country_id uuid,
    p_document_number    varchar,
    p_issued_on          date    DEFAULT NULL,
    p_expires_on         date    DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM person WHERE person_id = p_person_id) THEN
        RAISE EXCEPTION 'Persona % no encontrada', p_person_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM document_type WHERE document_type_id = p_document_type_id) THEN
        RAISE EXCEPTION 'Tipo de documento % no encontrado', p_document_type_id;
    END IF;

    IF p_expires_on IS NOT NULL AND p_issued_on IS NOT NULL
       AND p_expires_on < p_issued_on THEN
        RAISE EXCEPTION 'La fecha de vencimiento no puede ser anterior a la de expedición';
    END IF;

    INSERT INTO person_document (
        person_id,
        document_type_id,
        issuing_country_id,
        document_number,
        issued_on,
        expires_on
    )
    VALUES (
        p_person_id,
        p_document_type_id,
        p_issuing_country_id,
        p_document_number,
        p_issued_on,
        p_expires_on
    );

    RAISE NOTICE 'Documento % registrado para persona %', p_document_number, p_person_id;
END;
$$;


-- ---------------------------------------------------------------
-- EJ10 · SCRIPT DE PRUEBA DEL TRIGGER
-- ---------------------------------------------------------------
-- Paso 1: Obtener persona, tipo de documento y país emisor
SELECT person_id, first_name, last_name FROM person LIMIT 3;
SELECT document_type_id, type_code FROM document_type LIMIT 3;
SELECT country_id, iso_alpha2 FROM country LIMIT 5;

-- Paso 2: Invocar el procedimiento (dispara el trigger)
-- CALL sp_registrar_documento_ej10(
--     '<person_id>',
--     '<document_type_id>',
--     '<country_id>',
--     'PA-EJ10-98765432',
--     '2020-01-15',
--     '2030-01-15'
-- );

-- Paso 3: Verificar que updated_at de la persona cambió
-- SELECT person_id, first_name, last_name, updated_at
-- FROM person WHERE person_id = '<person_id>';


-- ---------------------------------------------------------------
-- EJ10 · CONSULTA DE VALIDACIÓN FINAL
-- ---------------------------------------------------------------
SELECT
    p.first_name || ' ' || p.last_name     AS persona,
    p.updated_at                            AS persona_actualizada,
    dt.type_name                            AS tipo_documento,
    pd.document_number,
    pd.issued_on,
    pd.expires_on
FROM person_document pd
    INNER JOIN person p          ON p.person_id = pd.person_id
    INNER JOIN document_type dt  ON dt.document_type_id = pd.document_type_id
ORDER BY p.updated_at DESC
LIMIT 10;


-- ================================================================================
-- FIN DEL ARCHIVO - SISTEMA INTEGRAL DE AEROLÍNEA | 10 EJERCICIOS
-- ================================================================================
