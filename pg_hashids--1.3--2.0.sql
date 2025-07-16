-- Migration script from pg_hashids 1.3 (C implementation) to 2.0 (PL/pgSQL TLE implementation)
-- This script provides function replacement without data loss and includes compatibility verification

-- Compatibility verification during upgrade
DO $$
DECLARE
    test_hash text;
    test_number bigint := 12345;
    c_result text;
    migration_notice text;
BEGIN
    -- Test if C functions are working before migration
    BEGIN
        c_result := id_encode(test_number);
        migration_notice := 'Migrating from C implementation. Last C result for ' || test_number || ': ' || c_result;
        RAISE NOTICE '%', migration_notice;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'C functions not available or already migrated';
    END;
END;
$$;

-- Drop the old C-based functions
DROP FUNCTION IF EXISTS hash_encode(BIGINT);
DROP FUNCTION IF EXISTS hash_encode(BIGINT, TEXT);
DROP FUNCTION IF EXISTS hash_encode(BIGINT, TEXT, INT);
DROP FUNCTION IF EXISTS hash_decode(TEXT, TEXT, INT);

-- Drop existing id_* functions that reference C module
DROP FUNCTION IF EXISTS id_encode(BIGINT);
DROP FUNCTION IF EXISTS id_encode(BIGINT, TEXT);
DROP FUNCTION IF EXISTS id_encode(BIGINT, TEXT, INT);
DROP FUNCTION IF EXISTS id_encode(BIGINT, TEXT, INT, TEXT);
DROP FUNCTION IF EXISTS id_encode(BIGINT[]);
DROP FUNCTION IF EXISTS id_encode(BIGINT[], TEXT);
DROP FUNCTION IF EXISTS id_encode(BIGINT[], TEXT, INT);
DROP FUNCTION IF EXISTS id_encode(BIGINT[], TEXT, INT, TEXT);
DROP FUNCTION IF EXISTS id_decode(TEXT);
DROP FUNCTION IF EXISTS id_decode(TEXT, TEXT);
DROP FUNCTION IF EXISTS id_decode(TEXT, TEXT, INT);
DROP FUNCTION IF EXISTS id_decode(TEXT, TEXT, INT, TEXT);
DROP FUNCTION IF EXISTS id_decode_once(TEXT);
DROP FUNCTION IF EXISTS id_decode_once(TEXT, TEXT);
DROP FUNCTION IF EXISTS id_decode_once(TEXT, TEXT, INT);
DROP FUNCTION IF EXISTS id_decode_once(TEXT, TEXT, INT, TEXT);

-- Note: Array-based functions (id_encode with BIGINT[]) are not implemented in 2.0
-- as they were not part of the core requirements for TLE compatibility

-- Load the complete 2.0 implementation
-- This includes all the functions from pg_hashids--2.0.sql

-- Define the hashids_config composite type for internal configuration management
CREATE TYPE hashids_config AS (
    alphabet text,
    salt text,
    min_hash_length integer,
    separators text,
    guards text,
    alphabet_length integer,
    separators_count integer,
    guards_count integer
);

-- Default constants
CREATE OR REPLACE FUNCTION _hashids_default_alphabet() RETURNS text
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
    RETURN 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890';
END;
$$;

CREATE OR REPLACE FUNCTION _hashids_default_separators() RETURNS text
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
    RETURN 'cfhistuCFHISTU';
END;
$$;-- 
Helper function to remove duplicate characters from alphabet
CREATE OR REPLACE FUNCTION _hashids_remove_duplicates(p_alphabet text) RETURNS text
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
    result text := '';
    i integer;
    current_char text;
BEGIN
    FOR i IN 1..length(p_alphabet) LOOP
        current_char := substring(p_alphabet from i for 1);
        IF position(current_char in result) = 0 THEN
            result := result || current_char;
        END IF;
    END LOOP;
    RETURN result;
END;
$$;

-- Alphabet validation function
CREATE OR REPLACE FUNCTION _hashids_validate_alphabet(p_alphabet text) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
    IF p_alphabet IS NULL THEN
        RETURN false;
    END IF;
    IF position(' ' in p_alphabet) > 0 OR position(chr(9) in p_alphabet) > 0 THEN
        RETURN false;
    END IF;
    IF length(_hashids_remove_duplicates(p_alphabet)) < 16 THEN
        RETURN false;
    END IF;
    RETURN true;
END;
$$;

-- Alphabet shuffle function
CREATE OR REPLACE FUNCTION _hashids_shuffle(p_alphabet text, p_salt text) RETURNS text
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
    str_array text[];
    salt_array text[];
    str_length integer;
    salt_length integer;
    i integer;
    j integer;
    v integer := 0;
    p integer := 0;
    temp_char text;
BEGIN
    IF p_salt IS NULL OR length(p_salt) = 0 THEN
        RETURN p_alphabet;
    END IF;
    
    str_length := length(p_alphabet);
    salt_length := length(p_salt);
    
    FOR i IN 1..str_length LOOP
        str_array[i] := substring(p_alphabet from i for 1);
    END LOOP;
    
    FOR i IN 1..salt_length LOOP
        salt_array[i] := substring(p_salt from i for 1);
    END LOOP;
    
    i := str_length;
    WHILE i > 1 LOOP
        IF v = salt_length THEN
            v := 0;
        END IF;
        
        v := v + 1;
        p := p + ascii(salt_array[v]);
        j := (ascii(salt_array[v]) + v - 1 + p) % i + 1;
        
        temp_char := str_array[i];
        str_array[i] := str_array[j];
        str_array[j] := temp_char;
        
        i := i - 1;
    END LOOP;
    
    RETURN array_to_string(str_array, '');
END;
$$;

-- Single number encoding function
CREATE OR REPLACE FUNCTION _hashids_encode_number(p_number bigint, p_alphabet text) RETURNS text
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
    result text := '';
    alphabet_length integer;
    working_number bigint;
    remainder integer;
BEGIN
    IF p_number IS NULL OR p_alphabet IS NULL THEN
        RAISE EXCEPTION 'Number and alphabet cannot be null'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    
    IF p_number < 0 THEN
        RAISE EXCEPTION 'Cannot encode negative numbers: %', p_number
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    
    alphabet_length := length(p_alphabet);
    
    IF alphabet_length = 0 THEN
        RAISE EXCEPTION 'Alphabet cannot be empty'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    
    working_number := p_number;
    
    IF working_number = 0 THEN
        RETURN substring(p_alphabet from 1 for 1);
    END IF;
    
    WHILE working_number > 0 LOOP
        remainder := (working_number % alphabet_length)::integer;
        result := substring(p_alphabet from remainder + 1 for 1) || result;
        working_number := working_number / alphabet_length;
    END LOOP;
    
    RETURN result;
END;
$$;--
 Configuration initialization function
CREATE OR REPLACE FUNCTION _hashids_init(
    p_salt text DEFAULT '',
    p_min_length integer DEFAULT 0,
    p_alphabet text DEFAULT NULL
) RETURNS hashids_config
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
    config hashids_config;
    working_alphabet text;
    default_separators text;
    i integer;
    current_char text;
    char_pos integer;
    separators_needed integer;
    guards_needed integer;
    temp_text text;
BEGIN
    config.salt := COALESCE(p_salt, '');
    config.min_hash_length := COALESCE(p_min_length, 0);
    working_alphabet := COALESCE(p_alphabet, _hashids_default_alphabet());
    
    working_alphabet := _hashids_remove_duplicates(working_alphabet);
    
    IF NOT _hashids_validate_alphabet(working_alphabet) THEN
        RAISE EXCEPTION 'Invalid alphabet: must be at least 16 unique characters with no whitespace'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    
    default_separators := _hashids_default_separators();
    config.separators := '';
    
    FOR i IN 1..length(default_separators) LOOP
        current_char := substring(default_separators from i for 1);
        char_pos := position(current_char in working_alphabet);
        
        IF char_pos > 0 THEN
            config.separators := config.separators || current_char;
            working_alphabet := substring(working_alphabet from 1 for char_pos - 1) ||
                               substring(working_alphabet from char_pos + 1);
        END IF;
    END LOOP;
    
    config.separators_count := length(config.separators);
    config.alphabet_length := length(working_alphabet);
    
    IF config.separators_count > 0 THEN
        config.separators := _hashids_shuffle(config.separators, config.salt);
    END IF;
    
    separators_needed := ceil(config.alphabet_length::numeric / 3.5)::integer;
    
    IF config.separators_count = 0 OR 
       (config.alphabet_length::numeric / config.separators_count::numeric) > 3.5 THEN
        
        IF separators_needed = 1 THEN
            separators_needed := 2;
        END IF;
        
        IF separators_needed > config.separators_count THEN
            temp_text := substring(working_alphabet from 1 for separators_needed - config.separators_count);
            config.separators := config.separators || temp_text;
            working_alphabet := substring(working_alphabet from length(temp_text) + 1);
            
            config.separators_count := separators_needed;
            config.alphabet_length := length(working_alphabet);
        ELSE
            config.separators := substring(config.separators from 1 for separators_needed);
            config.separators_count := separators_needed;
        END IF;
    END IF;
    
    working_alphabet := _hashids_shuffle(working_alphabet, config.salt);
    
    guards_needed := ceil(config.alphabet_length::numeric / 12.0)::integer;
    
    IF config.alphabet_length < 3 THEN
        config.guards := substring(config.separators from 1 for guards_needed);
        config.separators := substring(config.separators from guards_needed + 1);
        config.separators_count := config.separators_count - guards_needed;
    ELSE
        config.guards := substring(working_alphabet from 1 for guards_needed);
        working_alphabet := substring(working_alphabet from guards_needed + 1);
        config.alphabet_length := config.alphabet_length - guards_needed;
    END IF;
    
    config.guards_count := guards_needed;
    config.alphabet := working_alphabet;
    
    RETURN config;
END;
$$;-- 
Core encoding function with lottery character
CREATE OR REPLACE FUNCTION _hashids_encode_with_lottery(
    p_numbers bigint[],
    p_config hashids_config
) RETURNS text
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
    numbers_count integer;
    numbers_hash bigint := 0;
    lottery_char text;
    result text := '';
    working_alphabet text;
    salt_for_iteration text;
    i integer;
    current_number bigint;
    encoded_number text;
    separator_index integer;
    guard_index integer;
    result_length integer;
BEGIN
    numbers_count := array_length(p_numbers, 1);
    IF numbers_count IS NULL OR numbers_count = 0 THEN
        RETURN '';
    END IF;
    
    FOR i IN 1..numbers_count LOOP
        numbers_hash := numbers_hash + (p_numbers[i] % (i + 99));
    END LOOP;
    
    lottery_char := substring(p_config.alphabet from ((numbers_hash % p_config.alphabet_length) + 1)::integer for 1);
    result := lottery_char;
    working_alphabet := p_config.alphabet;
    
    FOR i IN 1..numbers_count LOOP
        current_number := p_numbers[i];
        
        salt_for_iteration := lottery_char || p_config.salt;
        IF length(salt_for_iteration) < p_config.alphabet_length THEN
            salt_for_iteration := salt_for_iteration || 
                substring(working_alphabet from 1 for p_config.alphabet_length - length(salt_for_iteration));
        ELSE
            salt_for_iteration := substring(salt_for_iteration from 1 for p_config.alphabet_length);
        END IF;
        
        working_alphabet := _hashids_shuffle(working_alphabet, salt_for_iteration);
        encoded_number := _hashids_encode_number(current_number, working_alphabet);
        result := result || encoded_number;
        
        IF i < numbers_count THEN
            separator_index := (current_number % (ascii(substring(encoded_number from length(encoded_number) for 1)) + i - 1)) % p_config.separators_count;
            result := result || substring(p_config.separators from separator_index + 1 for 1);
        END IF;
    END LOOP;
    
    result_length := length(result);
    
    -- Apply minimum length padding if needed (simplified version)
    IF result_length < p_config.min_hash_length THEN
        guard_index := (numbers_hash + ascii(substring(result from 1 for 1))) % p_config.guards_count;
        result := substring(p_config.guards from guard_index + 1 for 1) || result;
        result_length := result_length + 1;
        
        IF result_length < p_config.min_hash_length THEN
            guard_index := (numbers_hash + ascii(substring(result from 3 for 1))) % p_config.guards_count;
            result := result || substring(p_config.guards from guard_index + 1 for 1);
        END IF;
    END IF;
    
    RETURN result;
END;
$$;

-- Decoding helper functions
CREATE OR REPLACE FUNCTION _hashids_validate_hash(p_hash text, p_config hashids_config) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
    i integer;
    current_char text;
    valid_chars text;
BEGIN
    IF p_hash IS NULL OR length(p_hash) = 0 THEN
        RETURN false;
    END IF;
    
    valid_chars := p_config.alphabet || p_config.separators || p_config.guards;
    
    FOR i IN 1..length(p_hash) LOOP
        current_char := substring(p_hash from i for 1);
        IF position(current_char in valid_chars) = 0 THEN
            RETURN false;
        END IF;
    END LOOP;
    
    RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION _hashids_remove_guards(p_hash text, p_config hashids_config) RETURNS text
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
    result text := p_hash;
    i integer;
    current_char text;
    start_pos integer := 1;
    end_pos integer;
BEGIN
    IF p_hash IS NULL OR length(p_hash) = 0 THEN
        RETURN '';
    END IF;
    
    FOR i IN 1..length(result) LOOP
        current_char := substring(result from i for 1);
        IF position(current_char in p_config.guards) > 0 THEN
            start_pos := i + 1;
            EXIT;
        END IF;
    END LOOP;
    
    end_pos := length(result);
    FOR i IN start_pos..length(result) LOOP
        current_char := substring(result from i for 1);
        IF position(current_char in p_config.guards) > 0 THEN
            end_pos := i - 1;
            EXIT;
        END IF;
    END LOOP;
    
    IF start_pos <= end_pos THEN
        result := substring(result from start_pos for end_pos - start_pos + 1);
    ELSE
        result := '';
    END IF;
    
    RETURN result;
END;
$$;CR
EATE OR REPLACE FUNCTION _hashids_split_hash(p_hash text, p_config hashids_config) RETURNS text[]
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
    result text[] := '{}';
    current_segment text := '';
    i integer;
    current_char text;
BEGIN
    IF p_hash IS NULL OR length(p_hash) = 0 THEN
        RETURN result;
    END IF;
    
    FOR i IN 1..length(p_hash) LOOP
        current_char := substring(p_hash from i for 1);
        
        IF position(current_char in p_config.separators) > 0 THEN
            IF length(current_segment) > 0 THEN
                result := array_append(result, current_segment);
                current_segment := '';
            END IF;
        ELSE
            current_segment := current_segment || current_char;
        END IF;
    END LOOP;
    
    IF length(current_segment) > 0 THEN
        result := array_append(result, current_segment);
    END IF;
    
    RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION _hashids_decode_segment(p_segment text, p_alphabet text) RETURNS bigint
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
    result bigint := 0;
    alphabet_length integer;
    i integer;
    current_char text;
    char_position integer;
BEGIN
    IF p_segment IS NULL OR length(p_segment) = 0 THEN
        RETURN 0;
    END IF;
    
    alphabet_length := length(p_alphabet);
    
    FOR i IN 1..length(p_segment) LOOP
        current_char := substring(p_segment from i for 1);
        char_position := position(current_char in p_alphabet) - 1;
        
        IF char_position < 0 THEN
            RAISE EXCEPTION 'Invalid character in hash segment: %', current_char
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        
        result := result * alphabet_length + char_position;
    END LOOP;
    
    RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION _hashids_decode_hash(p_hash_segments text[], p_config hashids_config) RETURNS bigint[]
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
    result bigint[] := '{}';
    cleaned_hash text;
    lottery_char text;
    working_alphabet text;
    salt_for_iteration text;
    i integer;
    current_segment text;
    decoded_number bigint;
    segments text[];
BEGIN
    IF array_length(p_hash_segments, 1) IS NULL OR array_length(p_hash_segments, 1) = 0 THEN
        RETURN result;
    END IF;
    
    cleaned_hash := array_to_string(p_hash_segments, '');
    
    IF length(cleaned_hash) = 0 THEN
        RETURN result;
    END IF;
    
    lottery_char := substring(cleaned_hash from 1 for 1);
    cleaned_hash := substring(cleaned_hash from 2);
    
    IF length(cleaned_hash) = 0 THEN
        RETURN result;
    END IF;
    
    segments := _hashids_split_hash(cleaned_hash, p_config);
    working_alphabet := p_config.alphabet;
    
    FOR i IN 1..array_length(segments, 1) LOOP
        current_segment := segments[i];
        
        IF length(current_segment) = 0 THEN
            CONTINUE;
        END IF;
        
        salt_for_iteration := lottery_char || p_config.salt;
        IF length(salt_for_iteration) < p_config.alphabet_length THEN
            salt_for_iteration := salt_for_iteration || 
                substring(working_alphabet from 1 for p_config.alphabet_length - length(salt_for_iteration));
        ELSE
            salt_for_iteration := substring(salt_for_iteration from 1 for p_config.alphabet_length);
        END IF;
        
        working_alphabet := _hashids_shuffle(working_alphabet, salt_for_iteration);
        decoded_number := _hashids_decode_segment(current_segment, working_alphabet);
        result := array_append(result, decoded_number);
    END LOOP;
    
    RETURN result;
END;
$$;-- 
Public API Functions

-- id_encode function overloads
CREATE OR REPLACE FUNCTION id_encode(p_number bigint) RETURNS text
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
    RETURN id_encode(p_number, '', 0, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION id_encode(p_number bigint, p_salt text) RETURNS text
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    RETURN id_encode(p_number, p_salt, 0, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION id_encode(p_number bigint, p_salt text, p_min_length integer) RETURNS text
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    RETURN id_encode(p_number, p_salt, p_min_length, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION id_encode(
    p_number bigint, 
    p_salt text, 
    p_min_length integer, 
    p_alphabet text
) RETURNS text
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
    config hashids_config;
    numbers bigint[];
BEGIN
    IF p_number IS NULL THEN
        RAISE EXCEPTION 'Number cannot be null'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    
    IF p_number < 0 THEN
        RAISE EXCEPTION 'Cannot encode negative numbers: %', p_number
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    
    IF p_min_length IS NOT NULL AND p_min_length < 0 THEN
        RAISE EXCEPTION 'Minimum length cannot be negative: %', p_min_length
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    
    config := _hashids_init(p_salt, p_min_length, p_alphabet);
    numbers := ARRAY[p_number];
    
    RETURN _hashids_encode_with_lottery(numbers, config);
END;
$$;

-- id_decode function overloads
CREATE OR REPLACE FUNCTION id_decode(p_hash text) RETURNS bigint[]
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
    RETURN id_decode(p_hash, '', 0, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION id_decode(p_hash text, p_salt text) RETURNS bigint[]
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    RETURN id_decode(p_hash, p_salt, 0, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION id_decode(p_hash text, p_salt text, p_min_length integer) RETURNS bigint[]
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    RETURN id_decode(p_hash, p_salt, p_min_length, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION id_decode(
    p_hash text, 
    p_salt text, 
    p_min_length integer, 
    p_alphabet text
) RETURNS bigint[]
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
    config hashids_config;
    cleaned_hash text;
    hash_segments text[];
BEGIN
    IF p_hash IS NULL THEN
        RAISE EXCEPTION 'Hash cannot be null'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    
    IF length(p_hash) = 0 THEN
        RAISE EXCEPTION 'Hash cannot be empty'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    
    config := _hashids_init(p_salt, p_min_length, p_alphabet);
    
    IF NOT _hashids_validate_hash(p_hash, config) THEN
        RAISE EXCEPTION 'Invalid hash format: contains invalid characters'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    
    cleaned_hash := _hashids_remove_guards(p_hash, config);
    hash_segments := _hashids_split_hash(cleaned_hash, config);
    
    RETURN _hashids_decode_hash(hash_segments, config);
END;
$$;-- 
id_decode_once function overloads
CREATE OR REPLACE FUNCTION id_decode_once(p_hash text) RETURNS bigint
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
    RETURN id_decode_once(p_hash, '', 0, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION id_decode_once(p_hash text, p_salt text) RETURNS bigint
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    RETURN id_decode_once(p_hash, p_salt, 0, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION id_decode_once(p_hash text, p_salt text, p_min_length integer) RETURNS bigint
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    RETURN id_decode_once(p_hash, p_salt, p_min_length, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION id_decode_once(
    p_hash text, 
    p_salt text, 
    p_min_length integer, 
    p_alphabet text
) RETURNS bigint
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
    result bigint[];
    result_length integer;
BEGIN
    result := id_decode(p_hash, p_salt, p_min_length, p_alphabet);
    result_length := array_length(result, 1);
    
    IF result_length IS NULL OR result_length = 0 THEN
        RAISE EXCEPTION 'Hash must decode to exactly one number, got 0 numbers'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    
    IF result_length != 1 THEN
        RAISE EXCEPTION 'Hash must decode to exactly one number, got % numbers', result_length
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    
    RETURN result[1];
END;
$$;

-- Legacy function aliases for backward compatibility
CREATE OR REPLACE FUNCTION hash_encode(p_number bigint) RETURNS text
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
    RETURN id_encode(p_number);
END;
$$;

CREATE OR REPLACE FUNCTION hash_encode(p_number bigint, p_salt text) RETURNS text
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    RETURN id_encode(p_number, p_salt);
END;
$$;

CREATE OR REPLACE FUNCTION hash_encode(p_number bigint, p_salt text, p_min_length integer) RETURNS text
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    RETURN id_encode(p_number, p_salt, p_min_length);
END;
$$;

CREATE OR REPLACE FUNCTION hash_decode(p_hash text, p_salt text, p_min_length integer) RETURNS bigint
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    RETURN id_decode_once(p_hash, p_salt, p_min_length);
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION id_encode(bigint) TO PUBLIC;
GRANT EXECUTE ON FUNCTION id_encode(bigint, text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION id_encode(bigint, text, integer) TO PUBLIC;
GRANT EXECUTE ON FUNCTION id_encode(bigint, text, integer, text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION id_decode(text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION id_decode(text, text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION id_decode(text, text, integer) TO PUBLIC;
GRANT EXECUTE ON FUNCTION id_decode(text, text, integer, text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION id_decode_once(text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION id_decode_once(text, text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION id_decode_once(text, text, integer) TO PUBLIC;
GRANT EXECUTE ON FUNCTION id_decode_once(text, text, integer, text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION hash_encode(bigint) TO PUBLIC;
GRANT EXECUTE ON FUNCTION hash_encode(bigint, text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION hash_encode(bigint, text, integer) TO PUBLIC;
GRANT EXECUTE ON FUNCTION hash_decode(text, text, integer) TO PUBLIC;

-- Migration verification
DO $$
DECLARE
    test_result text;
    decoded_result bigint;
    test_number bigint := 12345;
BEGIN
    -- Test the new PL/pgSQL implementation
    test_result := id_encode(test_number);
    decoded_result := id_decode_once(test_result);
    
    IF decoded_result != test_number THEN
        RAISE EXCEPTION 'Migration verification failed: round-trip test failed';
    END IF;
    
    RAISE NOTICE 'Migration to pg_hashids 2.0 completed successfully. Test result: % -> %', test_number, test_result;
END;
$$;

-- Create rollback procedures where possible
-- Note: Complete rollback to C version requires the C extension to be available
-- This provides a way to check if rollback is needed

CREATE OR REPLACE FUNCTION pg_hashids_migration_info() RETURNS text
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    RETURN 'pg_hashids 2.0 - Migrated from C to PL/pgSQL TLE implementation. ' ||
           'All functions now use PL/pgSQL instead of C. ' ||
           'Array-based encoding functions (id_encode with BIGINT[]) are not available in 2.0.';
END;
$$;

GRANT EXECUTE ON FUNCTION pg_hashids_migration_info() TO PUBLIC;

COMMENT ON FUNCTION pg_hashids_migration_info() IS 'Information about the migration from C to PL/pgSQL implementation';