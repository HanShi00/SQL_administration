/*****************************************
(C) 2014, Brent Ozar Unlimited. 
From http://www.brentozar.com/responder/get-top-resource-consuming-queries/
See http://BrentOzar.com/go/eula for the End User Licensing Agreement.


HOW TO USE THIS:

Don't just hit F5. This script has 3 separate parts:
Step 1. Populate a temp table
Step 2. Report on the temp table with analysis 
Step 3 (optional). Excel-friendly copy/paste version of #2.


Description: Displays a server level view of the SQL Server plan cache.

Output: One result set is presented that contains data from the statement, 
procedure, and trigger stats DMVs.

To learn more, visit http://www.brentozar.com/responder/get-top-resource-consuming-queries/ 
where you can download new versions for free, watch training videos on
how it works, get more info on the findings, and more. To contribute 
code and see your name in the change log, email your improvements & 
ideas to help@brentozar.com.


KNOWN ISSUES:
- This query will not run on SQL Server 2005.
- SQL Server 2008 and 2008R2 have a bug in trigger stats (see above).


v1.4 - 2014-02-17
 - MOAR BUG FIXES
 - Corrected multiple sorting bugs that cause confusing displays of query
   results that weren't necessarily the top anything.
 - Updated all modification timestamps to use ISO 8601 formatting because it's
   correct, sorry Britain.
 - Added a check for SQL Server 2008R2 build greater than SP1.
   Thanks to Kevan Riley for spotting this.
 - Added the stored procedure or trigger name to the Query Type column.
   Initial suggestion from Kevan Riley.
 - Corrected erronous math that could allow for % CPU/Duration/Executions/Reads
   being higher than 100% for batches/procedures with multiple poorly
   performing statements in them.
 - Renamed high level % columns to "Weight" to accurately reflect their
   meaning.

v1.3 - 2014-02-06
 - As they say on the app store, "Bug fixes"
 - Reorganized this to put the standard, gotta-run stuff at the top.
 - Switched to YYYY/MM/DD because Brits.

v1.2 - 2014-02-04
- Removed debug code
- Fixed output where SQL Server 2008 and early don't support min_rows, 
  max_rows, and total_rows.
  SQL Server 2008 and earlier will now return NULL for those columns.

v1.1 - 2014-02-02
- Incorporated sys.dm_exec_plan_attributes as recommended by Andrey 
  and Michael J. Swart.
- Added additional detail columns for plan cache analysis including
  min/max rows, total rows.
- Streamlined collection of data.



*******************************************/
SET NOCOUNT ON;




/* ************************** STEP 1 ************************** */

DECLARE @SortOrder VARCHAR(10),
        @top INT = 50;

SET @SortOrder = 'CPU';
--SET @SortOrder = 'Reads';
--SET @SortOrder = 'Duration';
--SET @SortOrder = 'Executions';


/*******************************************************************************
 *
 * Because the trigger execution count in SQL Server 2008R2 and earlier is not 
 * correct, we ignore triggers for these versions of SQL Server. If you'd like
 * to include trigger numbers, just know that the ExecutionCount, 
 * PercentExecutions, and ExecutionsPerMinute are wildly inaccurate for 
 * triggers on these versions of SQL Server. 
 * 
 * This is why we can't have nice things.
 *
 ******************************************************************************/
 DECLARE @use_triggers_anyway BIT = 0;


IF OBJECT_ID('tempdb..#p') IS NOT NULL
    DROP TABLE #p;

IF OBJECT_ID('tempdb..#procs') IS NOT NULL
    DROP TABLE #procs;

IF OBJECT_ID ('tempdb..#checkversion') IS NOT NULL
    DROP TABLE #checkversion;

CREATE TABLE #p (
    SqlHandle varbinary(60),
    TotalCPU bigint,
    TotalDuration bigint,
    TotalReads bigint,
    ExecutionCount bigint
);

CREATE TABLE #checkversion (
    version nvarchar(128),
    maj_version AS SUBSTRING(version, 1,CHARINDEX('.', version) + 1 ),
    build AS PARSENAME(CONVERT(varchar(32), version), 2)
);

-- TODO: Add columns from main query to #procs
CREATE TABLE #procs (
    QueryType nvarchar(256),
    DatabaseName sysname,
    AverageCPU bigint,
    AverageCPUPerMinute money,
    TotalCPU bigint,
    PercentCPUByType money,
    PercentCPU money,
    AverageDuration bigint,
    TotalDuration bigint,
    PercentDuration money,
    PercentDurationByType money,
    AverageReads bigint,
    TotalReads bigint,
    PercentReads money,
    PercentReadsByType money,
    ExecutionCount bigint,
    PercentExecutions money,
    PercentExecutionsByType money,
    ExecutionsPerMinute money,
    PlanCreationTime datetime,
    LastExecutionTime datetime,
    PlanHandle varbinary(60),
    SqlHandle varbinary(60),
    QueryHash binary(8),
    StatementStartOffset int,
    StatementEndOffset int,
    MinReturnedRows bigint,
    MaxReturnedRows bigint,
    AverageReturnedRows money,
    TotalReturnedRows bigint,
    LastReturnedRows bigint,
    QueryText nvarchar(max),
    QueryPlan xml,
    /* these next four columns are the total for the type of query.
       don't actually use them for anything apart from math by type.
     */
    TotalWorkerTimeForType bigint,
    TotalElapsedTimeForType bigint,
    TotalReadsForType bigint,
    TotalExecutionCountForType bigint,
    NumberOfPlans int,
    NumberOfDistinctPlans int
);

DECLARE @sql nvarchar(MAX) = N'',
        @insert_list nvarchar(MAX) = N'',
        @plans_triggers_select_list nvarchar(MAX) = N'',
        @body nvarchar(MAX) = N'',
        @nl nvarchar(2) = NCHAR(13) + NCHAR(10),
        @pv varchar(20),
        @pos tinyint,
        @v decimal(6,2),
        @build int;


INSERT INTO #checkversion (version) 
SELECT CAST(SERVERPROPERTY('ProductVersion') as nvarchar(128));
 

SELECT @v = maj_version ,
       @build = build 
FROM   #checkversion ;

SET @insert_list += N'
INSERT INTO #procs (QueryType, DatabaseName, AverageCPU, TotalCPU, AverageCPUPerMinute, PercentCPUByType, PercentDurationByType, 
                    PercentReadsByType, PercentExecutionsByType, AverageDuration, TotalDuration, AverageReads, TotalReads, ExecutionCount,
                    ExecutionsPerMinute, PlanCreationTime, LastExecutionTime, StatementStartOffset, StatementEndOffset,
                    MinReturnedRows, MaxReturnedRows, AverageReturnedRows, TotalReturnedRows, LastReturnedRows, QueryText, QueryPlan, 
                    TotalWorkerTimeForType, TotalElapsedTimeForType, TotalReadsForType, TotalExecutionCountForType, SqlHandle, PlanHandle, QueryHash) ' ;

SET @body += N'
FROM   (SELECT *,
               CAST((CASE WHEN DATEDIFF(second, cached_time, GETDATE()) > 0 And execution_count > 1
                          THEN DATEDIFF(second, cached_time, GETDATE()) / 60.0
                          ELSE NULL END) as MONEY) as age_minutes, 
               CAST((CASE WHEN DATEDIFF(second, cached_time, last_execution_time) > 0 And execution_count > 1
                          THEN DATEDIFF(second, cached_time, last_execution_time) / 60.0
                          ELSE Null END) as MONEY) as age_minutes_lifetime
        FROM   sys.#view#) AS qs
       CROSS JOIN(SELECT SUM(execution_count) AS t_TotalExecs,
                         SUM(total_elapsed_time) AS t_TotalElapsed, 
                         SUM(total_worker_time) AS t_TotalWorker,
                         SUM(total_logical_reads) AS t_TotalReads
                  FROM   sys.#view#) AS t
       CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
       CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
       CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
WHERE  pa.attribute = ''dbid''
ORDER BY #sortable# DESC
OPTION(RECOMPILE);'

SET @plans_triggers_select_list += N'
SELECT TOP (@top)
       CASE WHEN qp.query_plan.value(''declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan";max(//p:RelOp/@Parallel)'', ''float'')  > 0 THEN ''* '' ELSE '''' END 
         + ''#query_type#'' 
         + COALESCE('': '' + OBJECT_NAME(qs.object_id, qs.database_id),'''') AS QueryType,
       COALESCE(DB_NAME(database_id), CAST(pa.value AS sysname), ''-- N/A --'') AS DatabaseName,
       total_worker_time / execution_count AS AvgCPU ,
       total_worker_time AS TotalCPU ,
       CASE WHEN total_worker_time = 0 THEN 0
            WHEN COALESCE(age_minutes, DATEDIFF(mi, qs.cached_time, qs.last_execution_time), 0) = 0 THEN 0
            ELSE CAST(total_worker_time / COALESCE(age_minutes, DATEDIFF(mi, qs.cached_time, qs.last_execution_time)) AS MONEY) 
            END AS AverageCPUPerMinute ,
       CASE WHEN t.t_TotalWorker = 0 THEN 0
            ELSE CAST(ROUND(100.00 * total_worker_time / t.t_TotalWorker, 2) AS MONEY)
            END AS PercentCPUByType,
       CASE WHEN t.t_TotalElapsed = 0 THEN 0
            ELSE CAST(ROUND(100.00 * total_elapsed_time / t.t_TotalElapsed, 2) AS MONEY)
            END AS PercentDurationByType,
       CASE WHEN t.t_TotalReads = 0 THEN 0
            ELSE CAST(ROUND(100.00 * total_logical_reads / t.t_TotalReads, 2) AS MONEY)
            END AS PercentReadsByType,
       CASE WHEN t.t_TotalExecs = 0 THEN 0
            ELSE CAST(ROUND(100.00 * execution_count / t.t_TotalExecs, 2) AS MONEY)
            END AS PercentExecutionsByType,
       total_elapsed_time / execution_count AS AvgDuration , 
       total_elapsed_time AS TotalDuration ,
       total_logical_reads / execution_count AS AvgReads ,
       total_logical_reads AS TotalReads ,
       execution_count AS ExecutionCount ,
       CASE WHEN execution_count = 0 THEN 0
            WHEN COALESCE(age_minutes, DATEDIFF(mi, qs.cached_time, qs.last_execution_time), 0) = 0 THEN 0
            ELSE CAST((1.00 * execution_count / COALESCE(age_minutes, DATEDIFF(mi, qs.cached_time, qs.last_execution_time))) AS money)
            END AS ExecutionsPerMinute ,
       qs.cached_time AS PlanCreationTime,
       qs.last_execution_time AS LastExecutionTime,
       NULL AS StatementStartOffset,
       NULL AS StatementEndOffset,
       NULL AS MinReturnedRows,
       NULL AS MaxReturnedRows,
       NULL AS AvgReturnedRows,
       NULL AS TotalReturnedRows,
       NULL AS LastReturnedRows,
       st.text AS QueryText , 
       query_plan AS QueryPlan, 
       t.t_TotalWorker,
       t.t_TotalElapsed,
       t.t_TotalReads,
       t.t_TotalExecs,
       qs.sql_handle AS SqlHandle,
       qs.plan_handle AS PlanHandle,
       NULL AS QueryHash '


SET @sql += @insert_list;

SET @sql += N'
SELECT TOP (@top)
       CASE WHEN qp.query_plan.value(''declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan";max(//p:RelOp/@Parallel)'', ''float'')  > 0 THEN ''* '' ELSE '''' END 
         + ''Statement'' AS QueryType,
       COALESCE(DB_NAME(CAST(pa.value AS INT)), ''-- N/A --'') AS DatabaseName,
       total_worker_time / execution_count AS AvgCPU ,
       total_worker_time AS TotalCPU ,
       CASE WHEN total_worker_time = 0 THEN 0
            WHEN COALESCE(age_minutes, DATEDIFF(mi, qs.creation_time, qs.last_execution_time), 0) = 0 THEN 0
            ELSE CAST(total_worker_time / COALESCE(age_minutes, DATEDIFF(mi, qs.creation_time, qs.last_execution_time)) AS MONEY) 
            END AS AverageCPUPerMinute ,
       CAST(ROUND(100.00 * total_worker_time / t.t_TotalWorker, 2) AS MONEY) AS PercentCPUByType,
       CAST(ROUND(100.00 * total_elapsed_time / t.t_TotalElapsed, 2) AS MONEY) AS PercentDurationByType, 
       CAST(ROUND(100.00 * total_logical_reads / t.t_TotalReads, 2) AS MONEY) AS PercentReadsByType,
       CAST(ROUND(100.00 * execution_count / t.t_TotalExecs, 2) AS MONEY) AS PercentExecutionsByType,
       total_elapsed_time / execution_count AS AvgDuration , 
       total_elapsed_time AS TotalDuration ,
       total_logical_reads / execution_count AS AvgReads ,
       total_logical_reads AS TotalReads ,
       execution_count AS ExecutionCount ,
       CASE WHEN execution_count = 0 THEN 0
            WHEN COALESCE(age_minutes, DATEDIFF(mi, qs.creation_time, qs.last_execution_time), 0) = 0 THEN 0
            ELSE CAST((1.00 * execution_count / COALESCE(age_minutes, DATEDIFF(mi, qs.creation_time, qs.last_execution_time))) AS money)
            END AS ExecutionsPerMinute ,
       qs.creation_time AS PlanCreationTime,
       qs.last_execution_time AS LastExecutionTime,
       qs.statement_start_offset AS StatementStartOffset,
       qs.statement_end_offset AS StatementEndOffset, '

IF (@v = 10.5 AND @build >= 2500) OR (@v >= 10.5)
BEGIN
    SET @sql += N'
       qs.min_rows AS MinReturnedRows,
       qs.max_rows AS MaxReturnedRows,
       CAST(qs.total_rows as MONEY) / execution_count AS AvgReturnedRows,
       qs.total_rows AS TotalReturnedRows,
       qs.last_rows AS LastReturnedRows, ' ;
END
ELSE
BEGIN
    SET @sql += N'
       NULL AS MinReturnedRows,
       NULL AS MaxReturnedRows,
       NULL AS AvgReturnedRows,
       NULL AS TotalReturnedRows,
       NULL AS LastReturnedRows, ' ;
END

SET @sql += N'
       SUBSTRING(st.text, ( qs.statement_start_offset / 2 ) + 1, ( ( CASE qs.statement_end_offset
                                                                        WHEN -1 THEN DATALENGTH(st.text)
                                                                        ELSE qs.statement_end_offset
                                                                      END - qs.statement_start_offset ) / 2 ) + 1) AS QueryText , 
       query_plan AS QueryPlan, 
       t.t_TotalWorker,
       t.t_TotalElapsed,
       t.t_TotalReads,
       t.t_TotalExecs,
       qs.sql_handle AS SqlHandle,
       NULL AS PlanHandle,
       qs.query_hash AS QueryHash '

SET @sql += REPLACE(REPLACE(@body, '#view#', 'dm_exec_query_stats'), 'cached_time', 'creation_time') ;
SET @sql += @nl + @nl;



SET @sql += @insert_list;
SET @sql += REPLACE(@plans_triggers_select_list, '#query_type#', 'Stored Procedure') ;

SET @sql += REPLACE(@body, '#view#', 'dm_exec_procedure_stats') ;
SET @sql += @nl + @nl;




IF @use_triggers_anyway = 1 OR @v >= 11
BEGIN
    /* Trigger level information from the plan cache */
    SET @sql += @insert_list ;

    SET @sql += REPLACE(@plans_triggers_select_list, '#query_type#', 'Trigger') ;

    SET @sql += REPLACE(@body, '#view#', 'dm_exec_trigger_stats') ;
END




DECLARE @sort NVARCHAR(30);

SELECT @sort = CASE @SortOrder WHEN 'CPU' THEN 'total_worker_time'
                               WHEN 'Reads' THEN 'total_logical_reads'
                               WHEN 'Duration' THEN 'total_elapsed_time'
                               WHEN 'Executions' THEN 'execution_count'
                END ;

SELECT @sql = REPLACE(@sql, '#sortable#', @sort);

SET @sql += N'
INSERT INTO #p (SqlHandle, TotalCPU, TotalReads, TotalDuration, ExecutionCount)
SELECT  SqlHandle, 
        TotalCPU,
        TotalReads,
        TotalDuration,
        ExecutionCount
FROM    (SELECT  SqlHandle, 
                 TotalCPU,
                 TotalReads,
                 TotalDuration,
                 ExecutionCount,
                 ROW_NUMBER() OVER (PARTITION BY SqlHandle ORDER BY #sortable# DESC) AS rn
         FROM    #procs) AS x
WHERE x.rn = 1
';

SELECT @sort = CASE @SortOrder WHEN 'CPU' THEN 'TotalCPU'
                               WHEN 'Reads' THEN 'TotalReads'
                               WHEN 'Duration' THEN 'TotalDuration'
                               WHEN 'Executions' THEN 'ExecutionCount'
                END ;

SELECT @sql = REPLACE(@sql, '#sortable#', @sort);

EXEC sp_executesql @sql, N'@top INT', @top;



/* Compute the total CPU, etc across our active set of the plan cache.
 * Yes, there's a flaw - this doesn't include anything outside of our @top 
 * metric.
 */
DECLARE @total_duration BIGINT,
        @total_cpu BIGINT,
        @total_reads BIGINT,
        @total_execution_count BIGINT;

SELECT  @total_cpu = SUM(TotalCPU),
        @total_duration = SUM(TotalDuration),
        @total_reads = SUM(TotalReads),
        @total_execution_count = SUM(ExecutionCount)
FROM    #p
OPTION (RECOMPILE) ;

DECLARE @cr NVARCHAR(1) = NCHAR(13);
DECLARE @lf NVARCHAR(1) = NCHAR(10);
DECLARE @tab NVARCHAR(1) = NCHAR(9);

/* Update CPU percentage for stored procedures */
UPDATE #procs
SET     PercentCPU = y.PercentCPU,
        PercentDuration = y.PercentDuration,
        PercentReads = y.PercentReads,
        PercentExecutions = y.PercentExecutions,
        ExecutionsPerMinute = y.ExecutionsPerMinute,
        /* Strip newlines and tabs. Tabs are replaced with multiple spaces
           so that the later whitespace trim will completely eliminate them
         */
        QueryText = REPLACE(REPLACE(REPLACE(QueryText, @cr, ' '), @lf, ' '), @tab, '  ')
FROM (
    SELECT  PlanHandle,
            CAST((100. * TotalCPU) / @total_cpu AS MONEY) AS PercentCPU,
            CAST((100. * TotalDuration) / @total_duration AS MONEY) AS PercentDuration,
            CAST((100. * TotalReads) / @total_reads AS MONEY) AS PercentReads,
            CAST((100. * ExecutionCount) / @total_execution_count AS MONEY) AS PercentExecutions,
            CASE  DATEDIFF(mi, PlanCreationTime, LastExecutionTime)
                WHEN 0 THEN 0
                ELSE CAST((1.00 * ExecutionCount / DATEDIFF(mi, PlanCreationTime, LastExecutionTime)) AS money) 
            END AS ExecutionsPerMinute
    FROM (
        SELECT  PlanHandle,
                TotalCPU,
                TotalDuration,
                TotalReads,
                ExecutionCount,
                PlanCreationTime,
                LastExecutionTime
        FROM    #procs
        WHERE   PlanHandle IS NOT NULL
        GROUP BY PlanHandle,
                TotalCPU,
                TotalDuration,
                TotalReads,
                ExecutionCount,
                PlanCreationTime,
                LastExecutionTime
    ) AS x
) AS y
WHERE #procs.PlanHandle = y.PlanHandle
      AND #procs.PlanHandle IS NOT NULL
OPTION (RECOMPILE) ;



UPDATE #procs
SET     PercentCPU = y.PercentCPU,
        PercentDuration = y.PercentDuration,
        PercentReads = y.PercentReads,
        PercentExecutions = y.PercentExecutions,
        ExecutionsPerMinute = y.ExecutionsPerMinute,
        /* Strip newlines and tabs. Tabs are replaced with multiple spaces
           so that the later whitespace trim will completely eliminate them
         */
        QueryText = REPLACE(REPLACE(REPLACE(QueryText, @cr, ' '), @lf, ' '), @tab, '  ')
FROM (
    SELECT  DatabaseName,
            SqlHandle,
            QueryHash,            
            CAST((100. * TotalCPU) / @total_cpu AS MONEY) AS PercentCPU,
            CAST((100. * TotalDuration) / @total_duration AS MONEY) AS PercentDuration,
            CAST((100. * TotalReads) / @total_reads AS MONEY) AS PercentReads,
            CAST((100. * ExecutionCount) / @total_execution_count AS MONEY) AS PercentExecutions,
            CASE  DATEDIFF(mi, PlanCreationTime, LastExecutionTime)
                WHEN 0 THEN 0
                ELSE CAST((1.00 * ExecutionCount / DATEDIFF(mi, PlanCreationTime, LastExecutionTime)) AS money) 
            END AS ExecutionsPerMinute
    FROM (
        SELECT  DatabaseName,
                SqlHandle,
                QueryHash,
                TotalCPU,
                TotalDuration,
                TotalReads,
                ExecutionCount,
                PlanCreationTime,
                LastExecutionTime
        FROM    #procs
        GROUP BY DatabaseName,
                SqlHandle,
                QueryHash,
                TotalCPU,
                TotalDuration,
                TotalReads,
                ExecutionCount,
                PlanCreationTime,
                LastExecutionTime
    ) AS x
) AS y
WHERE   #procs.SqlHandle = y.SqlHandle
        AND #procs.QueryHash = y.QueryHash
        AND #procs.DatabaseName = y.DatabaseName
        AND #procs.PlanHandle IS NULL
OPTION (RECOMPILE) ;
GO

UPDATE #procs
SET NumberOfDistinctPlans = distinct_plan_count,
    NumberOfPlans = number_of_plans
FROM (
SELECT COUNT(DISTINCT QueryHash) AS distinct_plan_count,
       COUNT(QueryHash) AS number_of_plans,
       QueryHash
FROM   #procs
GROUP BY QueryHash
) AS x 
WHERE #procs.QueryHash = x.QueryHash
OPTION (RECOMPILE) ;



/* STOP HERE. 
 * 
 * Right now you should have a temp table (#procs) that has all of 
 * procedure cache information in it. You can run the next query to 
 * results that can be easily pasted into Excel. 
 *
 * Or you could page down a bit and run the last query that includes
 * interesting things like:
 *  1) More SQL text
 *  2) A query hash
 *  3) An execution plan
 */










/* ************************** STEP 2 ************************** */

/* For in-depth analysis */
DECLARE @SortOrder VARCHAR(10);

SET @SortOrder = 'CPU';
--SET @SortOrder = 'Reads';
--SET @SortOrder = 'Duration';
--SET @SortOrder = 'Executions';

SELECT  ExecutionCount AS [# Executions],
        ExecutionsPerMinute AS [Executions / Minute],
        PercentExecutions AS [% Executions],
        DatabaseName AS [Database],
        TotalCPU AS [Total CPU],
        AverageCPU AS [Avg CPU],
        PercentCPU AS [CPU Weight],
        TotalDuration AS [Total Duration],
        AverageDuration AS [Avg Duration],
        PercentDuration AS [Duration Weight],
        TotalReads AS [Total Reads],
        AverageReads AS [Average Reads],
        PercentReads AS [Read Weight],
        QueryType AS [Query Type],
        QueryText AS [Query Text], 
        PercentExecutionsByType AS [% Executions (Type)],
        PercentCPUByType AS [% CPU (Type)],
        PercentDurationByType AS [% Duration (Type)],
        PercentReadsByType AS [% Reads (Type)],        
        TotalReturnedRows AS [Total Rows],
        AverageReturnedRows AS [Avg Rows],
        MinReturnedRows AS [Min Rows],
        MaxReturnedRows AS [Max Rows],
        NumberOfPlans AS [# Plans],
        NumberOfDistinctPlans AS [# Distinct Plans],
        PlanCreationTime AS [Created At],
        LastExecutionTime AS [Last Execution],
        QueryPlan AS [Query Plan],
        PlanHandle AS [Plan Handle],
        SqlHandle AS [SQL Handle],
        QueryHash AS [Query Hash],
        StatementStartOffset,
        StatementEndOffset
FROM    #procs
ORDER BY CASE @SortOrder WHEN 'CPU' THEN TotalCPU
                         WHEN 'Reads' THEN TotalReads
                         WHEN 'Duration' THEN TotalDuration
                         WHEN 'Executions' THEN ExecutionCount
                         END DESC
OPTION (RECOMPILE) ;
GO










/* ************************** STEP 3 ************************** */

/* For reporting purposes only */
/*
DECLARE @SortOrder VARCHAR(10);

SET @SortOrder = 'CPU';
--SET @SortOrder = 'Reads';
--SET @SortOrder = 'Duration';
--SET @SortOrder = 'Executions';

SELECT  ExecutionCount AS [# Executions],
        ExecutionsPerMinute AS [Executions / Minute],
        PercentExecutions AS [% Executions],
        DatabaseName AS [Database],
        TotalCPU AS [Total CPU],
        AverageCPU AS [Avg CPU],
        PercentCPU AS [CPU Weight],
        TotalDuration AS [Total Duration],
        AverageDuration AS [Avg Duration],
        PercentDuration AS [Duration Weight],
        TotalReads AS [Total Reads],
        AverageReads AS [Average Reads],
        PercentReads AS [Reads Weight],
        QueryType AS [Query Type],
        SUBSTRING(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(QueryText)),' ','<>'),'><',''),'<>',' '), 1, 100) AS QueryText,
        PercentExecutionsByType AS [% Executions (Type)],
        PercentCPUByType AS [% CPU (Type)],
        PercentDurationByType AS [% Duration (Type)],
        PercentReadsByType AS [% Reads (Type)],        
        TotalReturnedRows AS [Total Rows],
        AverageReturnedRows AS [Avg Rows],
        MinReturnedRows AS [Min Rows],
        MaxReturnedRows AS [Max Rows],
        NumberOfPlans AS [# Plans],
        NumberOfDistinctPlans AS [# Distinct Plans],
        PlanCreationTime AS [Created At],
        LastExecutionTime AS [Last Execution],
        PlanHandle AS [Plan Handle],
        SqlHandle AS [SQL Handle],
        QueryHash AS [Query Hash],
        StatementStartOffset,
        StatementEndOffset
FROM    #procs
ORDER BY CASE @SortOrder WHEN 'CPU' THEN TotalCPU
                         WHEN 'Reads' THEN TotalReads
                         WHEN 'Duration' THEN TotalDuration
                         WHEN 'Executions' THEN ExecutionCount
                         END DESC
OPTION (RECOMPILE) ;
GO
*/
