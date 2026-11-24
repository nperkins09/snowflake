-- Run in Snowsight after a workflow run to see the login from Snowflake's side.

-- Did the login succeed, and did it use WIF?
SELECT event_timestamp, first_authentication_factor, is_success, error_message
FROM TABLE(wif_test.information_schema.login_history_by_user(USER_NAME => 'SVC_WIF_TEST'))
ORDER BY event_timestamp DESC;

-- What did the session run? (filtered by the QUERY_TAG the code sets)
SELECT start_time, query_tag, LEFT(query_text, 80) AS query, execution_status
FROM TABLE(wif_test.information_schema.query_history_by_user(USER_NAME => 'SVC_WIF_TEST'))
ORDER BY start_time DESC;
