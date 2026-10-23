-- Narrow SQLite compatibility required by the retained domain contracts.
-- JSON remains TEXT during the behavior-preserving migration; no implicit
-- frontend access is granted to app or private.
CREATE FUNCTION app.unixepoch() RETURNS bigint LANGUAGE sql STABLE AS $$SELECT floor(extract(epoch FROM transaction_timestamp()))::bigint$$;
CREATE FUNCTION app.unixepoch(value text) RETURNS bigint LANGUAGE sql STABLE AS $$SELECT floor(extract(epoch FROM CASE WHEN value='now' THEN transaction_timestamp() ELSE value::timestamptz END))::bigint$$;
CREATE FUNCTION app.julianday(value text) RETURNS numeric LANGUAGE sql STABLE AS $$SELECT extract(epoch FROM CASE WHEN value='now' THEN transaction_timestamp() ELSE value::timestamptz END)/86400+2440587.5$$;
CREATE FUNCTION app.json_valid(value text) RETURNS boolean LANGUAGE plpgsql IMMUTABLE STRICT AS $$BEGIN PERFORM value::jsonb; RETURN true; EXCEPTION WHEN invalid_text_representation THEN RETURN false; END$$;
CREATE FUNCTION app.json_path(value text) RETURNS text[] LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=pg_catalog AS $$
DECLARE result text[]:=ARRAY[]::text[];position integer:=2;started integer;character text;part text;closed boolean;
BEGIN
 IF left(value,1)<>'$' THEN RAISE EXCEPTION 'invalid_json_path' USING ERRCODE='22023';END IF;
 WHILE position<=length(value) LOOP
  character:=substr(value,position,1);
  IF character='.' THEN
   position:=position+1;started:=position;
   IF substr(value,position,1)='"' THEN
    position:=position+1;closed:=false;
    WHILE position<=length(value) LOOP
     IF substr(value,position,1)=chr(92) THEN position:=position+2;
     ELSIF substr(value,position,1)='"' THEN position:=position+1;closed:=true;EXIT;
     ELSE position:=position+1;END IF;
    END LOOP;
    IF NOT closed THEN RAISE EXCEPTION 'invalid_json_path' USING ERRCODE='22023';END IF;
    part:=substr(value,started,position-started)::jsonb #>> '{}';
   ELSE
    WHILE position<=length(value) AND substr(value,position,1) NOT IN('.','[') LOOP position:=position+1;END LOOP;
    part:=substr(value,started,position-started);
    IF part='' OR position>length(value)+1 THEN RAISE EXCEPTION 'invalid_json_path' USING ERRCODE='22023';END IF;
   END IF;
  ELSIF character='[' THEN
   position:=position+1;started:=position;
   WHILE position<=length(value) AND substr(value,position,1)~'^[0-9]$' LOOP position:=position+1;END LOOP;
   part:=substr(value,started,position-started);
   IF part='' OR substr(value,position,1)<>']' THEN RAISE EXCEPTION 'unsupported_json_path' USING ERRCODE='22023';END IF;
   position:=position+1;
  ELSE RAISE EXCEPTION 'invalid_json_path' USING ERRCODE='22023';END IF;
  result:=array_append(result,part);
 END LOOP;
 RETURN result;
END$$;
CREATE FUNCTION app.json_extract(document text, path text) RETURNS text LANGUAGE sql IMMUTABLE STRICT AS $$SELECT CASE jsonb_typeof(document::jsonb #> app.json_path(path)) WHEN 'null' THEN NULL WHEN 'boolean' THEN CASE WHEN document::jsonb #>> app.json_path(path)='true' THEN '1' ELSE '0' END ELSE document::jsonb #>> app.json_path(path) END$$;
-- SQLite compares nonnumeric JSON TEXT above every numeric storage class.
-- PostgreSQL numeric NaN has the same ordering versus finite numeric literals.
CREATE FUNCTION app.json_numeric(document text,path text) RETURNS numeric LANGUAGE sql IMMUTABLE STRICT AS $$SELECT CASE jsonb_typeof(document::jsonb #> app.json_path(path)) WHEN 'number' THEN (document::jsonb #>> app.json_path(path))::numeric WHEN 'boolean' THEN CASE WHEN document::jsonb #>> app.json_path(path)='true' THEN 1 ELSE 0 END WHEN 'null' THEN NULL ELSE CASE WHEN document::jsonb #> app.json_path(path) IS NULL THEN NULL ELSE 'NaN'::numeric END END$$;
CREATE FUNCTION app.json_type(document text, path text DEFAULT '$') RETURNS text LANGUAGE sql IMMUTABLE STRICT AS $$SELECT CASE jsonb_typeof(document::jsonb #> app.json_path(path)) WHEN 'string' THEN 'text' WHEN 'number' THEN CASE WHEN (document::jsonb #>> app.json_path(path)) ~ '^-?[0-9]+$' THEN 'integer' ELSE 'real' END WHEN 'boolean' THEN document::jsonb #>> app.json_path(path) ELSE jsonb_typeof(document::jsonb #> app.json_path(path)) END$$;
CREATE FUNCTION app.json_array_length(document text, path text DEFAULT '$') RETURNS bigint LANGUAGE sql IMMUTABLE STRICT AS $$SELECT CASE WHEN document::jsonb #> app.json_path(path) IS NULL THEN NULL WHEN jsonb_typeof(document::jsonb #> app.json_path(path))='array' THEN jsonb_array_length(document::jsonb #> app.json_path(path)) ELSE 0 END::bigint$$;
CREATE FUNCTION app.json_each(document text, path text DEFAULT '$') RETURNS TABLE(key text,value text,type text) LANGUAGE sql IMMUTABLE STRICT AS $$
 WITH selected AS (SELECT document::jsonb #> app.json_path(path) AS body), elements AS (
 SELECT e.key,e.value FROM selected CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(body)='object' THEN body ELSE '{}'::jsonb END) e
 UNION ALL SELECT (e.ordinality-1)::text,e.value FROM selected CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(body)='array' THEN body ELSE '[]'::jsonb END) WITH ORDINALITY e(value,ordinality))
 SELECT key,CASE jsonb_typeof(value) WHEN 'string' THEN value #>> '{}' WHEN 'null' THEN NULL WHEN 'boolean' THEN CASE WHEN value='true'::jsonb THEN '1' ELSE '0' END ELSE value::text END,CASE jsonb_typeof(value) WHEN 'string' THEN 'text' ELSE jsonb_typeof(value) END FROM elements
$$;
CREATE FUNCTION app.strftime(pattern text,value text DEFAULT 'now',modifier text DEFAULT NULL) RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE stamp timestamptz; translated text;
BEGIN
 stamp:=CASE WHEN value='now' THEN transaction_timestamp() ELSE value::timestamptz END;
 IF modifier IS NOT NULL THEN
  IF modifier !~ '^-?[0-9]+ (second|seconds|minute|minutes|hour|hours|day|days)$' THEN RAISE EXCEPTION 'unsupported_datetime_modifier'; END IF;
  stamp:=stamp+modifier::interval;
 END IF;
 IF pattern='%s' THEN RETURN floor(extract(epoch FROM stamp))::bigint::text; END IF;
 IF pattern='%Y-%m-%dT%H:%M:%fZ' THEN translated:='YYYY-MM-DD"T"HH24:MI:SS.MS"Z"';
 ELSIF pattern='%Y-%m-%dT%H:%M:%SZ' THEN translated:='YYYY-MM-DD"T"HH24:MI:SS"Z"';
 ELSIF pattern='%Y-%m-%d' THEN translated:='YYYY-MM-DD';
 ELSE RAISE EXCEPTION 'unsupported_datetime_format'; END IF;
 RETURN to_char(stamp AT TIME ZONE 'UTC',translated);
END$$;
CREATE FUNCTION app.printf(pattern text,value bigint) RETURNS text LANGUAGE plpgsql IMMUTABLE STRICT AS $$BEGIN IF pattern='%06d' THEN RETURN lpad(value::text,6,'0'); END IF; RAISE EXCEPTION 'unsupported_printf_format'; END$$;
CREATE FUNCTION app.changes() RETURNS bigint LANGUAGE sql STABLE AS $$SELECT coalesce(nullif(current_setting('collect.last_changes',true),''),'0')::bigint$$;
