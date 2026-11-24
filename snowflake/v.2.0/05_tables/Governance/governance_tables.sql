/* Tables

-- GOVERNANCE --

- Governance.Operations.Data_Source_Registry -> Catalog of Data Sources (Dim Table)
  - source_id
  - source_name
  - source_publisher
  - source_link
  - date_added
  - source_repo_url
  - description
  - use_case

- Governance.Orchestrator_Config -> Determines which data source should be updated for the day (Fact Table)
  - source_id
  - is_active
  - schedule_frequency
  - updated_at
  - last_pipeline_run_status
  - Next_Update_Schedule

- Pipeline_Config -> Determines pipeline behavior and configuration (Fact Table)
  - source_id
  - overight_table
  - target_database
  - target_schema
  - target_table
  - warehouse_used
  - Pipeline_Connector_Type (e.g. REST_API, JDBC, .html, etc.)
  - Max_Retries
  - Timeout_Minutes

*/

-- GOVERNANCE TABLES

USE ROLE SYSADMIN;

/* Data Source Registry

*/
CREATE TABLE IF NOT EXISTS GOVERNANCE.OPERATIONS.DATA_SOURCE_REGISTRY (
  source_id
  source_name
  source_publisher
  source_link
  date_added
  source_repo_url
  description_notes
  use_case_notes

)
COMMENT = 'A comprehensive catalog of all data sources';

CREATE TABLE IF NOT EXISTS GOVERNANCE.OPERATIONS.ORCHESTRATOR_CONFIG (
  source_id
  is_active
  schedule_frequency
  updated_at
  last_pipeline_run_status
  Next_Update_Schedule
)
COMMENT = 'Configuration for the orchestrator';


CREATE TABLE IF NOT EXISTS GOVERNANCE.OPERATIONS.PIPELINE_CONFIG (
  source_id
  overight_table
  target_database
  target_schema
  target_table
  warehouse_used
  Pipeline_Connector_Type (e.g. REST_API, JDBC, .html, etc.)
  Max_Retries
  Timeout_Minutes
)
COMMENT = 'Configuration for pipeline execution';





