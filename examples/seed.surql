-- Sample schema and data for the SurrealDB sandbox.
--
--   surreal import --ns demo --db demo examples/seed.surql
--
-- Shows off the things SurrealDB does that a relational database cannot:
-- record links, graph edges, and nested data on the record itself.

-- Required first statement for `surreal import` on SurrealDB 2.x/3.x: it
-- disables events, live queries, and per-field processing for a fast load.
OPTION IMPORT;

DEFINE TABLE person SCHEMAFULL;
DEFINE FIELD name    ON person TYPE string;
DEFINE FIELD email   ON person TYPE string ASSERT string::is_email($value);
DEFINE FIELD tags    ON person TYPE option<array<string>>;
DEFINE FIELD created ON person TYPE datetime DEFAULT time::now();
DEFINE INDEX person_email ON person FIELDS email UNIQUE;

DEFINE TABLE project SCHEMAFULL;
DEFINE FIELD name  ON project TYPE string;
DEFINE FIELD stars ON project TYPE int DEFAULT 0;

-- Records get stable, readable IDs rather than surrogate integers.
CREATE person:tobie SET name = 'Tobie', email = 'tobie@example.com', tags = ['founder', 'rust'];
CREATE person:jaime SET name = 'Jaime', email = 'jaime@example.com', tags = ['founder'];

CREATE project:surrealdb SET name = 'SurrealDB', stars = 30000;
CREATE project:sbx_kit   SET name = 'SurrealDB sandbox kit', stars = 1;

-- RELATE builds a graph edge, queryable in either direction.
RELATE person:tobie->works_on->project:surrealdb SET since = d'2021-01-01';
RELATE person:jaime->works_on->project:surrealdb SET since = d'2021-01-01';
RELATE person:tobie->works_on->project:sbx_kit   SET since = time::now();

-- Try these once imported:
--   SELECT * FROM person;
--   SELECT name, ->works_on->project.name AS projects FROM person;
--   SELECT * FROM project WHERE stars > 100;
