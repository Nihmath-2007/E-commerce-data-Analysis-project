CREATE DATABASE ecommerce;
USE ecommerce;

CREATE TABLE categories (
  category_id  INT PRIMARY KEY,
  name         VARCHAR(100),
  parent_id    INT,
  FOREIGN KEY (parent_id) REFERENCES categories(category_id)
);

CREATE TABLE products (
  product_id   INT PRIMARY KEY,
  name         VARCHAR(150),
  category_id  INT,
  price        DECIMAL(10,2),
  stock_qty    INT,
  FOREIGN KEY (category_id) REFERENCES categories(category_id)
);

CREATE TABLE customers (
  customer_id  INT PRIMARY KEY,
  name         VARCHAR(100),
  email        VARCHAR(150),
  city         VARCHAR(80),
  signup_date  DATE,
  referral_id  INT
);
CREATE TABLE orders (
  order_id     INT PRIMARY KEY,
  customer_id  INT,
  order_date   DATE,
  status       VARCHAR(20),
  total_amount DECIMAL(10,2),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE order_items (
  item_id      INT PRIMARY KEY,
  order_id     INT,
  product_id   INT,
  quantity     INT,
  unit_price   DECIMAL(10,2),
  FOREIGN KEY (order_id)   REFERENCES orders(order_id),
  FOREIGN KEY (product_id) REFERENCES products(product_id)
);

CREATE TABLE shipments (
  shipment_id  INT PRIMARY KEY,
  order_id     INT,
  shipped_date DATE,
  carrier      VARCHAR(50),
  delivery_date DATE,
  FOREIGN KEY (order_id) REFERENCES orders(order_id)
);
-- Row counts for all tables
SELECT 'categories', COUNT(*) FROM categories  UNION ALL
SELECT 'products',COUNT(*) FROM products    UNION ALL
SELECT 'customers',COUNT(*)FROM customers   UNION ALL
SELECT 'orders',COUNT(*) FROM orders      UNION ALL
SELECT 'order_items', COUNT(*)FROM order_items UNION ALL
SELECT 'shipments',COUNT(*) FROM shipments;

-- Total revenue & order count
SELECT
    COUNT(DISTINCT o.order_id)              AS total_orders,
    SUM(oi.quantity * oi.unit_price)        AS gross_revenue,
    ROUND(AVG(o.total_amount), 2)           AS avg_order_value,
    MIN(o.order_date)                       AS first_order,
    MAX(o.order_date)                       AS last_order
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.status = 'completed';
 
 
-- Revenue by sub-category — SELF JOIN on categories
SELECT
    c.name                                  AS category,
    COUNT(DISTINCT o.order_id)              AS orders,
    SUM(oi.quantity)                        AS units_sold,
    ROUND(SUM(oi.quantity * oi.unit_price)) AS revenue,
    ROUND(AVG(oi.unit_price), 2)            AS avg_price
FROM orders o
INNER JOIN order_items oi  ON o.order_id    = oi.order_id
INNER JOIN products p      ON oi.product_id = p.product_id
INNER JOIN categories c    ON p.category_id = c.category_id
WHERE o.status = 'completed'
  AND c.parent_id IS NULL      
  -- top-level categories only
GROUP BY c.name
ORDER BY revenue DESC;

-- Top 15 products by revenue
SELECT
    p.name                                  AS product,
    c.name                                  AS subcategory,
    SUM(oi.quantity)                        AS units_sold,
    ROUND(SUM(oi.quantity * oi.unit_price)) AS revenue,
    p.stock_qty                             AS current_stock
FROM order_items oi
INNER JOIN orders o ON oi.order_id = o.order_id
INNER JOIN products p ON oi.product_id = p.product_id
INNER JOIN categories c ON p.category_id = c.category_id
WHERE o.status = 'completed'
GROUP BY p.product_id, p.name, c.name, p.stock_qty
ORDER BY revenue DESC
LIMIT 10;

-- Top 10 customers by lifetime value (CLV)
SELECT
    cu.customer_id,
    cu.name,
    cu.city,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(o.total_amount)) AS lifetime_value,
    ROUND(AVG(o.total_amount)) AS avg_order_value
FROM customers cu
INNER JOIN orders o ON cu.customer_id = o.customer_id
WHERE o.status = 'completed'
GROUP BY cu.customer_id, cu.name, cu.city
ORDER BY lifetime_value DESC
LIMIT 10;

-- Customers who NEVER placed an order (churn risk list)
SELECT
    cu.customer_id,
    cu.name,
    cu.email,
    cu.city,
    cu.signup_date,
    DATEDIFF(CURDATE(), cu.signup_date)     AS days_since_signup
FROM customers cu
LEFT JOIN orders o ON cu.customer_id = o.customer_id
WHERE o.order_id IS NULL
ORDER BY days_since_signup DESC;

-- Customers with only 1 order (one-time buyers — re-engagement targets)
SELECT
    cu.customer_id,
    cu.name,
    cu.email,
    MAX(o.order_date)                       AS purchase_date,
    SUM(o.total_amount)                     AS spend
FROM customers cu
LEFT JOIN orders o ON cu.customer_id = o.customer_id
GROUP BY cu.customer_id, cu.name, cu.email
HAVING COUNT(DISTINCT o.order_id) = 1
ORDER BY purchase_date;

-- Completed orders with NO shipment record (operations alert)
SELECT
    o.order_id,
    o.customer_id,
    cu.name                                 AS customer_name,
    o.order_date,
    o.total_amount,
    DATEDIFF(CURDATE(), o.order_date)       AS days_unshipped
FROM orders o
INNER JOIN customers cu ON o.customer_id   = cu.customer_id
LEFT  JOIN shipments s  ON o.order_id      = s.order_id
WHERE o.status = 'completed'
  AND s.shipment_id IS NULL
ORDER BY days_unshipped DESC;

-- Full order detail report — 5-table JOIN
SELECT
    o.order_id,
    o.order_date,
    cu.name                                 AS customer,
    cu.city,
    p.name                                  AS product,
    c.name                                AS category,
    oi.quantity,
    oi.unit_price,
    ROUND(oi.quantity * oi.unit_price)      AS line_total,
    o.status,
    s.carrier,
    s.shipped_date,
    s.delivery_date,
    DATEDIFF(s.delivery_date,
             s.shipped_date)                AS delivery_days
FROM orders o
INNER JOIN customers cu    ON o.customer_id   = cu.customer_id
INNER JOIN order_items oi  ON o.order_id      = oi.order_id
INNER JOIN products p      ON oi.product_id   = p.product_id
INNER JOIN categories c  ON p.category_id   = cat.category_id
LEFT  JOIN shipments s     ON o.order_id      = s.order_id
ORDER BY o.order_date DESC, o.order_id, oi.item_id;

-- Low stock products (below 50 units)
SELECT
    p.product_id,
    p.name,
    c.name                                  AS category,
    p.stock_qty,
    COALESCE(SUM(oi.quantity), 0)           AS units_sold,
    CASE
        WHEN p.stock_qty = 0   THEN 'Out of stock'
        WHEN p.stock_qty < 20  THEN 'Critical'
        WHEN p.stock_qty < 50  THEN 'Low'
        ELSE 'OK'
    END                                     AS stock_status
FROM products p
INNER JOIN categories c    ON p.category_id = c.category_id
LEFT  JOIN order_items oi  ON p.product_id  = oi.product_id
GROUP BY p.product_id, p.name, c.name, p.stock_qty
HAVING p.stock_qty < 50
ORDER BY p.stock_qty;

-- Products with ZERO sales (dead stock)
SELECT
    p.product_id,
    p.name,
    c.name                                  AS category,
    p.price,
    p.stock_qty
FROM products p
INNER JOIN categories c    ON p.category_id = c.category_id
LEFT  JOIN order_items oi  ON p.product_id  = oi.product_id
WHERE oi.item_id IS NULL
ORDER BY p.stock_qty DESC;

-- Monthly revenue trend
SELECT
    DATE_FORMAT(o.order_date, '%Y-%m')      AS month,
    COUNT(DISTINCT o.order_id)              AS orders,
    ROUND(SUM(oi.quantity * oi.unit_price)) AS revenue
FROM orders o
INNER JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.status = 'completed'
GROUP BY DATE_FORMAT(o.order_date, '%Y-%m')
ORDER BY month;

-- Customer ranking by revenue — RANK window function
SELECT
    cu.name,
    cu.city,
    ROUND(SUM(o.total_amount))              AS lifetime_value,
    RANK() OVER (ORDER BY SUM(o.total_amount) DESC) AS revenue_rank
FROM customers cu
INNER JOIN orders o ON cu.customer_id = o.customer_id
WHERE o.status = 'completed'
GROUP BY cu.customer_id, cu.name, cu.city
ORDER BY revenue_rank;

-- Cancelled order analysis — revenue lost
SELECT
    c.name                                  AS category,
    COUNT(DISTINCT o.order_id)              AS cancelled_orders,
    ROUND(SUM(oi.quantity * oi.unit_price)) AS lost_revenue
FROM orders o
INNER JOIN order_items oi  ON o.order_id    = oi.order_id
INNER JOIN products p      ON oi.product_id = p.product_id
INNER JOIN categories c    ON p.category_id = c.category_id
WHERE o.status = 'cancelled'
GROUP BY c.name
ORDER BY lost_revenue DESC;

select sum(products.product_id * order_items.quantity) AS total
FROM order_items 
JOIN products  ON products.product_id = order_items.order_id
GROUP BY order_id

