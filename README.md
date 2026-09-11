# DoltgreSQL 1.3.1: `generation_expression` in `information_schema.columns` is NULL for a generated column

On DoltgreSQL 1.3.1, `information_schema.columns` answers NULL in `generation_expression` for the stored
generated column `b int GENERATED ALWAYS AS (a + 1) STORED`, although the column computes its values and
`is_generated` answers `ALWAYS`. PostgreSQL 18.6 answers the expression, `(a + 1)`.

## Reproduce it

You need Docker and a POSIX shell: Linux, macOS, or Windows with WSL. The first run downloads the images.

```sh
git clone https://github.com/Reliable-Collaboration/repro-doltgresql-bug-generation-expression.git
cd repro-doltgresql-bug-generation-expression
./repro.sh
```

`repro.sh` starts a throwaway PostgreSQL 18.6 container and a throwaway DoltgreSQL 1.3.1 container, runs
[`repro.sql`](repro.sql) on each with the `psql` client inside that container, and prints the two outputs
side by side, marking the lines that differ. It exits 1 while DoltgreSQL's output differs from
PostgreSQL's and 0 once they are identical, and it removes both containers when it finishes.

To try another DoltgreSQL release, name its image:

```sh
DOLTGRESQL_IMAGE=dolthub/doltgresql:latest ./repro.sh
```

### Without the script

The same steps by hand, from the repository directory:

```sh
docker run -d --name repro-doltgresql-bug-generation-expression-postgres -e POSTGRES_PASSWORD=password postgres:18.6-bookworm
docker run -d --name repro-doltgresql-bug-generation-expression-doltgresql -e DOLTGRES_PASSWORD=password dolthub/doltgresql:1.3.1
docker cp repro.sql repro-doltgresql-bug-generation-expression-postgres:/tmp/repro.sql
docker cp repro.sql repro-doltgresql-bug-generation-expression-doltgresql:/tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-generation-expression-postgres psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-generation-expression-doltgresql psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker rm -f repro-doltgresql-bug-generation-expression-postgres repro-doltgresql-bug-generation-expression-doltgresql
```

If a `docker exec` answers that the connection was refused, that server is still starting: wait a few
seconds and run it again.

## The test

[`repro.sql`](repro.sql):

```sql
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
```

## Expected behavior

The generated column computes `b` = 2 for `a` = 1, and `information_schema.columns` answers its expression
in `generation_expression`, next to `is_generated` `ALWAYS` and a NULL `column_default`. This is what
PostgreSQL 18.6 does:

```
-- The generated column works.
INSERT INTO t (a) VALUES (1);
INSERT 0 1
SELECT a, b FROM t;
 a | b 
---+---
 1 | 2
(1 row)

-- The generated column in information_schema.columns.
SELECT is_generated, generation_expression,
       column_default
FROM information_schema.columns
WHERE table_name = 't' AND column_name = 'b';
 is_generated | generation_expression | column_default 
--------------+-----------------------+----------------
 ALWAYS       | (a + 1)               | (null)
(1 row)
```

## Actual behavior

The generated column computes the same value, and `is_generated` and `column_default` answer the same, but
`generation_expression` is NULL. This is what DoltgreSQL 1.3.1 does:

```
-- The generated column works.
INSERT INTO t (a) VALUES (1);
INSERT 0 1
SELECT a, b FROM t;
 a | b 
---+---
 1 | 2
(1 row)

-- The generated column in information_schema.columns.
SELECT is_generated, generation_expression,
       column_default
FROM information_schema.columns
WHERE table_name = 't' AND column_name = 'b';
 is_generated | generation_expression | column_default 
--------------+-----------------------+----------------
 ALWAYS       | (null)                | (null)
(1 row)
```

## Side by side

The output of `./repro.sh`:

```
Starting postgres:18.6-bookworm@sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af
Starting dolthub/doltgresql:1.3.1@sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851

Left: PostgreSQL. Right: DoltgreSQL. Lines that differ are marked with |.

-- Print NULL as (null), unlike an empty string.              -- Print NULL as (null), unlike an empty string.
\pset null '(null)'                                           \pset null '(null)'
Null display is "(null)".                                     Null display is "(null)".
-- A generated column whose expression needs no brackets.     -- A generated column whose expression needs no brackets.
CREATE TABLE t (                                              CREATE TABLE t (
    a int,                                                        a int,
    b int GENERATED ALWAYS AS (a + 1) STORED                      b int GENERATED ALWAYS AS (a + 1) STORED
);                                                            );
CREATE TABLE                                                  CREATE TABLE
-- The generated column works.                                -- The generated column works.
INSERT INTO t (a) VALUES (1);                                 INSERT INTO t (a) VALUES (1);
INSERT 0 1                                                    INSERT 0 1
SELECT a, b FROM t;                                           SELECT a, b FROM t;
 a | b                                                         a | b 
---+---                                                       ---+---
 1 | 2                                                         1 | 2
(1 row)                                                       (1 row)

-- The generated column in information_schema.columns.        -- The generated column in information_schema.columns.
SELECT is_generated, generation_expression,                   SELECT is_generated, generation_expression,
       column_default                                                column_default
FROM information_schema.columns                               FROM information_schema.columns
WHERE table_name = 't' AND column_name = 'b';                 WHERE table_name = 't' AND column_name = 'b';
 is_generated | generation_expression | column_default         is_generated | generation_expression | column_default 
--------------+-----------------------+----------------       --------------+-----------------------+----------------
 ALWAYS       | (a + 1)               | (null)              |  ALWAYS       | (null)                | (null)
(1 row)                                                       (1 row)


Result: DoltgreSQL's output differs from PostgreSQL's on 1 line(s), marked with |.
```

## Other observations

Each was checked on DoltgreSQL 1.3.1 and PostgreSQL 18.6 with the same kind of test:

- `generation_expression` is NULL on DoltgreSQL for every generated column tried, while `is_generated`
  answers `ALWAYS` and `column_default` NULL on both servers: `(upper(s))`, `(length(s))`, `(a)`,
  `(a::text)`, `(a * 2)` added with `ALTER TABLE ... ADD COLUMN`, and `(a + 1)` in a table in another
  schema. PostgreSQL answers `upper(s)`, `length(s)`, `a`, `(a)::text`, `(a * 2)` and `(a + 1)`.
- It stays NULL from a new connection and, on DoltgreSQL, after `SELECT dolt_commit('-Am', 'generated')`.
- `((a + 1) * 2)` answers NULL too, where PostgreSQL answers `((a + 1) * 2)`. The test uses an expression
  without brackets because that column stores 3 for `a = 1` on DoltgreSQL 1.3.1, where PostgreSQL stores 4,
  a separate bug.
- In `pg_attribute`, `attgenerated` is `s` on both servers, but `atthasdef` is `f` on DoltgreSQL and `t` on
  PostgreSQL. `pg_attrdef` has no row for the generated column on DoltgreSQL; on PostgreSQL its row answers
  `(a + 1)` from `pg_get_expr(adbin, adrelid)`.
- For a plain `DEFAULT 7`, `pg_attrdef` has a row on DoltgreSQL, but `pg_get_expr(adbin, adrelid)` answers
  NULL, where PostgreSQL answers `7`. `column_default` answers `7` on both.
- `dtd_identifier` is NULL for both columns of the table on DoltgreSQL, where PostgreSQL answers `1` and
  `2`.
- For an identity column, `id int GENERATED ALWAYS AS IDENTITY`, DoltgreSQL answers `is_generated` `ALWAYS`,
  `is_identity` `NO` and a NULL `identity_generation`, where PostgreSQL answers `NEVER`, `YES` and `ALWAYS`.
- PostgreSQL 18.6 creates `GENERATED ALWAYS AS (a + 1) VIRTUAL`, and the same clause without `STORED`, as
  virtual columns (`attgenerated` `v`). DoltgreSQL refuses both, with
  `ERROR:  at or near "virtual": syntax error` and `ERROR:  at or near ")": syntax error`.
- Another report on the same view: [dolthub/doltgresql#3244](https://github.com/dolthub/doltgresql/issues/3244),
  where `information_schema.columns` answers blank metadata for the columns of a view.

## Environment

- DoltgreSQL 1.3.1, the newest release when this was written: image `dolthub/doltgresql:1.3.1`, digest
  `sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851`, built for linux/amd64 and
  linux/arm64. Its bundled `psql` is 17.11.
- PostgreSQL 18.6: image `postgres:18.6-bookworm`, digest
  `sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af`. Its `psql` is 18.6.
- Reproduced on 2026-09-11 (UTC) with Docker 29.7.2 on Ubuntu 26.04.1 LTS under WSL2 (Linux 6.18.33.2,
  x86_64).
