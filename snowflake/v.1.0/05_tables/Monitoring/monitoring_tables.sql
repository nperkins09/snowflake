/*

-- MONITORING --

- Orchestrator_Run_History
  - Orchestrator_run_id
  - Run_Status
  - Number_of_Scheduled_Runs
  - Number_of_Runs_Executed
  - Start_Time
  - End_Time
  - Run_Duration
  - Error_Message

- Pipeline_Run_History
  - Run_id
  - source_id
  - Hash_ID
  - Run_Status
  - Error_Message
  - Start_Time
  - End_Time
  - Duration
  - Number_of_Fields
  - Number_of_Records

- Transform_Run_History (Will formalize schema when in development)
  - run_id
  - source_id
  - hash_id
  - start_time
  - end_time
  - duration
  - source_table
  - target_table

*/

-- Monitoring Tables

-- Monitoring Tables

USE ROLE SYSADMIN;

CREATE TABLE IF NOT EXISTS MONITORING.HISTORY.PIPELINE_RUN_HISTORY (
  Pipeline_Run_ID    INTEGER        NOT NULL,
  Source_ID          VARCHAR(20)        NOT NULL,
  Batch_Hash_ID      VARCHAR(64),
  Row_Hash_ID        VARCHAR(64),
  Run_Status         VARCHAR(20),
  Error_Message      VARCHAR,
  Start_Time         TIMESTAMP_NTZ,
  End_Time           TIMESTAMP_NTZ,
  Duration           NUMBER(38,3),   -- seconds
  Number_of_Fields   INTEGER,
  Number_of_Records  INTEGER
)
COMMENT = 'One row per pipeline run, written by svc_ingest_role';

CREATE TABLE IF NOT EXISTS MONITORING.HISTORY.TRANSFORM_RUN_HISTORY (
  Transform_Run_ID   VARCHAR        NOT NULL,
  Source_ID          VARCHAR(20)        NOT NULL,
  Hash_ID            VARCHAR(64),
  Start_Time         TIMESTAMP_NTZ,
  End_Time           TIMESTAMP_NTZ,
  Duration           NUMBER(38,3),   -- seconds
  Source_Table       VARCHAR,
  Target_Table       VARCHAR
)
COMMENT = 'One row per Transform run, written by svc_transform_role';
