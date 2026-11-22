-- SELECT-only aggregate. Use a separately qualified parameterized postgres
-- session: $1 is the expected operation UUID, $2 is the expected profile SHA,
-- $3 is the expected canonical public profile. No profile/row values returned.
-- An absent row can be only a transient snapshot of an in-flight transaction.
SELECT jsonb_build_object(
 'rowCount',count(*),
 'matchesExpected',count(*) FILTER(WHERE singleton AND operation_id=$1::uuid AND profile_sha256=$2::text
  AND profile_raw=$3::text AND encode(sha256(convert_to(profile_raw,'UTF8')),'hex')=$2::text
  AND recorded_by='postgres')=1
) AS binding_observation FROM private.collect_deployment_identity;
