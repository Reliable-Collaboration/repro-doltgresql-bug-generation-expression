-- Print NULL as (null), unlike an empty string.
\pset null '(null)'

-- A generated column whose expression needs no brackets.
CREATE TABLE t (
    a int,
    b int GENERATED ALWAYS AS (a + 1) STORED
);

-- The generated column works.
INSERT INTO t (a) VALUES (1);
SELECT a, b FROM t;

-- The generated column in information_schema.columns.
SELECT is_generated, generation_expression,
       column_default
FROM information_schema.columns
WHERE table_name = 't' AND column_name = 'b';
