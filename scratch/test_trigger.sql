CREATE SCHEMA IF NOT EXISTS test_schema;
SET search_path = test_schema;

CREATE TABLE products (id int PRIMARY KEY, stock int);
CREATE TABLE orders (id int PRIMARY KEY, status text);
CREATE TABLE order_items (id int PRIMARY KEY, order_id int, product_id int, qty int);

INSERT INTO products VALUES (1, 5);
INSERT INTO orders VALUES (1, 'pending');
INSERT INTO order_items VALUES (1, 1, 1, 2);

CREATE OR REPLACE FUNCTION restore_stock() RETURNS TRIGGER AS $$
DECLARE v RECORD;
BEGIN
  FOR v IN 
    SELECT oi.product_id, SUM(oi.qty) as q
    FROM new_orders n
    JOIN old_orders o ON n.id = o.id
    JOIN order_items oi ON oi.order_id = n.id
    WHERE n.status = 'rejected' AND o.status != 'rejected'
    GROUP BY oi.product_id
  LOOP
    UPDATE products SET stock = stock + v.q WHERE id = v.product_id;
  END LOOP;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg AFTER UPDATE ON orders
REFERENCING OLD TABLE AS old_orders NEW TABLE AS new_orders
FOR EACH STATEMENT EXECUTE FUNCTION restore_stock();

UPDATE orders SET status = 'rejected' WHERE id = 1;

SELECT * FROM products;

DROP SCHEMA test_schema CASCADE;
