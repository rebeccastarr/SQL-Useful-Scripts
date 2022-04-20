/*
Name: R Starr
Date: 18/04/2022
Purpose: Different methods to obtain the row count for all tables in a database.
There are different ways to achieve this, with pros and cons for each method. 

Sometimes these catalog tables can become out of sync. However, you can run DBCC UPDATEUSAGE to update 
the catalog views. Recommended to only run if sp_spaceused appears to be inaccurate. It is not recommended 
to run routinely as it can take time on large databases. Only recommended to run routinely (weekly) if 
database undergoes frequent DDL modifications.

The dmv's are the recommended approach. They provide an approximate and fairly accurate representation of 
RowCounts. To obtain a 'really accurate' count, you would need to lock the table whilst doing the count, 
meaning all the write requests are queuing up. As soon as you obtain your accurate COUNT and release the
lock, that count will no longer be accurate.

** Step 1: COUNT(*): Has to do a table blocking scan which can take a long time (on a large table) so not recommended in a busy or production system.
** Step 2: sys.partitions: RowCount obtained from internal table sys.sysrowsets. Can include dirty reads and table values can be manually updated.
** Step 3: sys.dm_db_partition_stats: RowCount obtained from internal table PARTITIONCOUNTS.Same view used for sp_spaceused (but sp_spaceused performs a lot more calcs).
** Step 4: Synapse Analytics compatible
** Step 5: sys.dm_db_index_physical_stats: Function can be even more expensive that COUNT(*) and block.
** Step 6: sys.dm_db_column_store_row_group_physical_stats: RowCount on columnstore indexes

See useful article on architecture: https://www.red-gate.com/simple-talk/cloud/azure/azure-sql-data-warehouse-explaining-architecture-system-views/
Other good articles: https://sqlperformance.com/2014/10/t-sql-queries/bad-habits-count-the-hard-way
*/
-- STEP 1: Using COUNT(1)
SELECT 'SELECT '''+CONCAT_WS('.',QUOTENAME(TABLE_SCHEMA), QUOTENAME(TABLE_NAME))+''', COUNT(1) AS [TableCount] FROM '+CONCAT_WS('.',QUOTENAME(TABLE_SCHEMA), QUOTENAME(TABLE_NAME))
FROM INFORMATION_SCHEMA.TABLES 

-- STEP 2: Using sys.partitions
SELECT CONCAT_WS('.', QUOTENAME(SCHEMA_NAME(t.schema_id)), QUOTENAME(t.[name])) AS [TableName], SUM( p.rows) AS [RowCount]
FROM sys.tables AS t
JOIN sys.partitions AS p ON t.object_id = p.object_id AND p.index_id < 2 -- heap, clustered index, 2 or greater = nonclustered index
GROUP BY t.schema_id, t.[name]
ORDER BY t.[name]

-- STEP 3: Using SQL Server dynamic management view
SELECT CONCAT_WS(',', QUOTENAME(SCHEMA_NAME(obj.schema_id)), QUOTENAME(obj.[name])) AS [TableName]
, SUM(dmv.row_count) AS [RowCount]
FROM sys.dm_db_partition_stats AS dmv
LEFT JOIN sys.objects AS obj ON obj.object_id = dmv.object_id
WHERE obj.type = 'U'		-- U = Table (user-defined)
  AND obj.is_ms_shipped = 0 -- Indicates if object is created by user or was shipped with SQL Server installation
  AND dmv.index_id < 2		-- heap, clustered index, 2 or greater = nonclustered index
GROUP BY obj.schema_id, obj.name
ORDER BY obj.name

-- STEP 4: Using Synapse Analytics compatible dynamic management view
SELECT CONCAT_WS(',', QUOTENAME(SCHEMA_NAME(obj.schema_id)), QUOTENAME(obj.[name])) AS [TableName]
, SUM(dmv.row_count) AS [RowCount]
FROM sys.objects AS obj
JOIN sys.dm_pdw_nodes_db_partition_stats AS dmv ON obj.object_id = dmv.object_id
WHERE obj.type = 'U'		-- U = Table (user-defined)
  AND obj.is_ms_shipped = 0 -- Indicates if object is created by user or was shipped with SQL Server installation
  AND dmv.index_id < 2		-- heap, clustered index, 2 or greater = nonclustered index
GROUP BY obj.schema_id, obj.name
ORDER BY obj.name

--STEP 5: Using sys.dm_db_index_physical_stats (database_id, object_id, index_id, partition_number, mode)
DECLARE @dbid SMALLINT = DB_ID() -- In the context of the current database connection
SELECT * FROM sys.dm_db_index_physical_stats (@dbid, NULL, NULL, NULL, NULL);  

-- Step 6: Using sys.dm_db_column_store_row_group_physical_stats on columnstore indexes
