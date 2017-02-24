/*
A set of functions that uses a single column table filed with tab-separated values (TSV) data to:
1. Create a table based on the column names in its first row.
2. Create and execute an INSERT SQL statement to split each row on tabs and load
  the extracted values into the correct column.

Assumess:
1. The TSV data is in a single-column table called "tsv_rows" in the public schema.
2. The TSV rows are in a column called "data_row".
2. The column names are in the first column.

Test Data:
The test data was taken from "ftp://ftp.ebi.ac.uk/pub/databases/genenames/new/tsv/non_alt_loci_set.txt".
Each row from this file was loaded into the table "public.tsv_rows".
Row Count: 40,617
Column Count: 48
*/

CREATE SCHEMA private_udfs;
COMMENT ON SCHEMA private_udfs IS' Defines function for general use but not ones exposed to PostgREST';

CREATE OR REPLACE FUNCTION private_udfs.create_usable_column_names(p_column_name TEXT)
RETURNS TEXT
AS
$$
BEGIN
  IF TRIM(p_column_name) ~ '^[a-zA-Z_][a-zA-Z0-9_]*$' THEN
    RETURN TRIM(p_column_name);
  ELSE
    RETURN '"' || TRIM(p_column_name) || '"';
  END IF;
END;
$$
LANGUAGE plpgsql;
COMMENT ON FUNCTION private_udfs.create_usable_column_name(TEXT) 
IS 'Used to generate valid column names for dynamic SQL used to create tables. Strips leading and trailing white space. If the trimmed given value contains only values that are allowed in PG column names, return it trimmed. Otherwise, enclose the trimmed given value in double quotes and return that.';
SELECT private_udfs.create_usable_column_name('a bc')

CREATE OR REPLACE FUNCTION private_udfs.create_usable_column_names()
RETURNS TABLE(usable_column_name TEXT)
AS
$$
BEGIN
  RETURN QUERY
  WITH first_row_values AS
    (SELECT
      STRING_TO_ARRAY(data_row, E'\t') column_name
    FROM
      tsv_rows
    LIMIT 1)
  SELECT
    private_udfs.create_usable_column_name(UNNEST(column_name))
  FROM
    first_row_values;
END;
$$
LANGUAGE plpgsql;
COMMENT ON FUNCTION private_udfs.create_usable_column_names() 
IS 'Used to generate valid column names for dynamic SQL used to create tables. Returns a table of column names by splitting the first line in the table "public.tsv_rows" on tabs. The returned single column table rows are enclosed in double quotes if the contain any characters not allowed in PG column names.'
SELECT ARRAY_TO_STRING(ARRAY_AGG(usable_column_name || ' TEXT'), E',\n') FROM private_udfs.create_usable_column_names();

CREATE OR REPLACE FUNCTION private_udfs.create_table_ddl(p_schema_name TEXT, p_new_table_name TEXT)
RETURNS TEXT
AS
$$
DECLARE
  l_usable_column_names TEXT[];
BEGIN
  SELECT ARRAY_AGG('  ' || usable_column_name || ' TEXT') INTO l_usable_column_names FROM private_udfs.create_usable_column_names();
  RETURN 'CREATE TABLE ' || p_schema_name || '.' || p_table_name || 
    '(' || E'\n' || ARRAY_TO_STRING(l_usable_column_names, E',\n') || ')';
END;
$$
LANGUAGE plpgsql;
COMMENT ON FUNCTION private_udfs.create_table_ddl(TEXT, TEXT) IS
  'Used to generate a "CREATE TABLE" statement for a given schema and table name. The column names are taken from the first row in table "public.tsv_rows" and all column types are set to type TEXT.';
SELECT private_udfs.create_table_ddl('public', 'hgnc_genes');

CREATE OR REPLACE FUNCTION private_udfs.execute_create_table_ddl(p_schema_name TEXT, p_table_name TEXT)
RETURNS VOID
AS
$$
DECLARE
  l_create_table_ddl TEXT;
BEGIN
  l_create_table_ddl := private_udfs.create_table_ddl(p_schema_name, p_table_name);
  EXECUTE l_create_table_ddl;
END;
$$
LANGUAGE plpgsql;
COMMENT ON FUNCTION private_udfs.execute_create_table_ddl(TEXT, TEXT) IS
'Execute the DDL generated by "private_udfs.execute_create_table_ddl" for the given schema and table names. Column types can be changes after table creation and keys and constraints can be added as required. At the very least, a primary key should be added.';
SELECT private_udfs.execute_create_table_ddl('public', 'hgnc_genes');

CREATE OR REPLACE FUNCTION private_udfs.generate_insert_part_of_sql(p_schema_name TEXT, p_table_name TEXT)
RETURNS TEXT
AS
$$
DECLARE l_column_names TEXT[];
BEGIN
  SELECT ARRAY_AGG(usable_column_name) INTO l_column_names FROM private_udfs.create_usable_column_names();
  RETURN 'INSERT INTO ' || p_schema_name || '.' || p_table_name || '(' || 
    ARRAY_TO_STRING(l_column_names, ', ') || ')' || E'\n';
END;
$$
LANGUAGE plpgsql;
COMMENT ON FUNCTION private_udfs.generate_insert_part_of_sql(TEXT, TEXT) IS
'Generates the first part of the SQL needed to load the TSV data in table "public.tsv_rows" into the table created by "private_udfs.execute_create_table_ddl(TEXT, TEXT)".';
SELECT private_udfs.generate_insert_part_of_sql('public', 'hgnc_genes');

CREATE OR REPLACE FUNCTION private_udfs.generate_select_part_of_sql()
RETURNS TEXT
AS
$$
DECLARE
  l_column_names TEXT[];
  l_element_count INTEGER;
  l_select_expressions TEXT[];
  l_single_select_expression TEXT;
BEGIN
  SELECT ARRAY_AGG(usable_column_name) INTO l_column_names FROM private_udfs.create_usable_column_names();
  l_element_count := ARRAY_LENGTH(l_column_names, 1);
  FOR idx IN 1 .. l_element_count LOOP
    l_single_select_expression := '  (STRING_TO_ARRAY(data_row, E' || CHR(39) || '\t' || CHR(39) ||
      '))[' || idx || ']';
    l_select_expressions[idx] := l_single_select_expression;
  END LOOP;
  RETURN 'SELECT' || E'\n' || ARRAY_TO_STRING(l_select_expressions, E',\n') || E'\n' || 'FROM public.tsv_rows';
END;
$$
LANGUAGE plpgsql;
COMMENT ON FUNCTION private_udfs.generate_select_part_of_sql() IS 
'Generates the SELECT part of the SQL needed to load the TSV data in table "public.tsv_rows" into the table created by "private_udfs.execute_create_table_ddl(TEXT, TEXT)". It builds an array of statements that extract ech of the required elements from the TSV seprated row. Warning: This statement can be very large!';
SELECT private_udfs.generate_select_part_of_sql();

CREATE OR REPLACE FUNCTION private_udfs.load_tsv_data_to_new_table(p_schema_name TEXT, p_table_name TEXT)
RETURNS VOID
AS
$$
DECLARE
  l_insert_part_sql TEXT := private_udfs.generate_insert_part_of_sql(p_schema_name, p_table_name);
  l_select_part_sql TEXT := private_udfs.generate_select_part_of_sql();
  l_complete_sql_to_exec TEXT := l_insert_part_sql || E'\n' ||  l_select_part_sql;
BEGIN
  EXECUTE l_complete_sql_to_exec;
END;
$$
LANGUAGE plpgsql;
COMMENT ON FUNCTION private_udfs.load_tsv_data_to_new_table(TEXT, TEXT) IS
'Copies the tab-delimited data from "public.tsv_rows" to the newly created table by matching the extract values from the array created by splitting on tab to the columns in the new table. Creates the full INSERT INTO with SELECT SQL statement and executes it.';

SELECT private_udfs.load_tsv_data_to_new_table('public', 'hgnc_genes');

DELETE FROM public.hgnc_genes WHERE symbol = 'symbol';
ALTER TABLE public.hgnc_genes
ADD CONSTRAINT hgnc_genes_pk PRIMARY KEY(hgnc_id);
CREATE UNIQUE INDEX hgnc_genes_symbol_idx ON public.hgnc_genes(symbol);

