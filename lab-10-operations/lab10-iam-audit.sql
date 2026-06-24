SELECT
  timestamp,
  proto_payload.method_name AS method,
  proto_payload.authentication_info.principal_email AS who,
  proto_payload.resource_name AS resource
FROM `${PROJECT_ID}.lab10_logs.cloudaudit_googleapis_com_activity_*`
WHERE DATE(_PARTITIONTIME) = CURRENT_DATE()
  AND proto_payload.method_name LIKE '%Iam%'
ORDER BY timestamp DESC
LIMIT 20
