CREATE OR REPLACE FUNCTION array_functions.element_counts(p_array ANYARRAY)
RETURNS TABLE(element TEXT, element_count INTEGER) AS
$$             
BEGIN
  RETURN QUERY
  SELECT
    iqy.element::TEXT,
    (COUNT(iqy.element_index))::INTEGER element_count
  FROM
    (SELECT
      UNNEST(p_array) element,
      GENERATE_SERIES(1, ARRAY_LENGTH(p_array, 1)) element_index) iqy
  GROUP BY
    iqy.element;
  RETURN; -- optional
END;
$$
LANGUAGE plpgsql;
COMMENT ON FUNCTION array_functions.element_counts IS 'Given an one-dimensional array of any type, return a two-column table with a unique list of the array elements with their occurrence counts. Python test: plpgsql/tests/test_array_functions.py';
SELECT
  element,
  element_count
FROM
  array_functions.element_counts(ARRAY['cat', 'dog', 'mouse', 'cat', 'cow', 'rat', 'mouse']);
  


CREATE OR REPLACE FUNCTION array_functions.array_pair_as_hstore(p_array_a TEXT[], p_array_b TEXT[])
RETURNS HSTORE AS
$$
DECLARE
  l_array_to_array_map HSTORE;
BEGIN
  l_array_to_array_map := HSTORE(p_array_a, p_array_b);
  RETURN l_array_to_array_map;
END;
$$
LANGUAGE plpgsql;
SELECT array_functions.array_pair_as_hstore(ARRAY[1, 2, 3, 1, 4]::TEXT[], ARRAY['one', 'two', 'three', 'eins', 'four']);
COMMENT ON FUNCTION array_functions.array_pair_as_hstore IS 'Taking two text arrays of the same length, return a HSTORE output that maps the values in the first array to those in the second. Duplicates are ignored but an error is thrown if the arrays are of different lengths.  Python test: plpgsql/tests/test_array_functions.py';
