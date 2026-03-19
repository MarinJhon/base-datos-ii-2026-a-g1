DELIMITER //
CREATE TRIGGER validar_precio 
BEFORE INSERT ON productos 
FOR EACH ROW 
BEGIN 
IF NEW.precio <= 0 THEN 
SIGNAL SQLSTATE '45000' 
SET MESSAGE_TEXT = 'El precio debe ser mayor a 0'; 
END IF; 
END; 
// DELIMITER ;

DELIMITER //
CREATE TRIGGER actualizar_producto
AFTER INSERT ON productos
FOR EACH ROW
BEGIN
    UPDATE log_productos SET mensaje="adibas" WHERE id = NEW.id;
END;
//
DELIMITER ;

drop trigger actualizar_producto;
select * from log_productos;
INSERT INTO productos (nombre, precio, stock)
VALUES ('Celular', 334, 5);
insert into log_productos(mensaje)values("hola"),("messi"),("ronaldo");