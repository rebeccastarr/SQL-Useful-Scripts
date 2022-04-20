/*
Name: R Starr
Date: 17/04/2022
Purpose: This script uses a TOP DOWN approach. For 'Bottom down' approach see alternate script:
--> Script 'DELETE or TRUNCATE - Create statements for tables based on FK hierarchy - Bottom down'. 

IMPORTANT NOTE:
** Check the expected table list to ensure that all tables have been included and identify any that are missing.
** Perform a COUNT of all records for all tables to check expected duration of execution/number of records that will be deleted.
** Potential issue is that a table is listed multiple times at different levels. We have taken the MAX level in this scenario.
** We added a filter to prevent a self referencing loop. However, this means that tables with a self-referencing foreign key
   will be ommitted in some scenarios.

-------------------------------------------------------------------------------------------------------------------------
DELETE vs TRUNCATE
-------------------------------------------------------------------------------------------------------------------------
Delete is a more expensive operation, as every record deletion is written to the TLOG. Whereas Truncate is more a metadata 
operation that deallocates the pages to the table. Both can be rolled back if executed in the context of a transaction. 
You cannot truncate a table that has foreign key references to it.

There are (undocumented) system stored procedures that can be explored for this purpose also:

-- EXEC sp_MSforeachtable 'select * from [OneIPO-MDS].[?]' -- (includes temporal history tables also) 
-- EXEC dbo.sp_MSforeachdb 'select ''?'', * from [?].INFORMATION_SCHEMA.TABLES where table_name like ''authors'' ' -- Executes against all dbs on the server
-- EXEC sp_msdependencies '?' -- (includes temporal history tables also) -- @flags = 8 -- table dependencies only
-- EXEC sp_depends @objname = 'rgt.Right' -- 'schema.table_name' (gets procedures that reference the table)

-- Top down approach
DROP TABLE IF EXISTS #tables_test
CREATE TABLE #tables_test (TypeT INT, TblName VARCHAR(100), SchemaName VARCHAR(20), FKHierarchy INT)
INSERT INTO #tables_test EXEC sp_msdependencies @flags = 8
SELECT FKHierarchy, TblName FROM #tables_test WHERE SchemaName NOT IN ('ref','hst') ORDER BY FKHierarchy
*/
DROP TABLE IF EXISTS #output_sp_msdependencies
DROP TABLE IF EXISTS #statements
DROP TABLE IF EXISTS #table_list

-- Capture output of undocumented procedure sp_msdependencies
DROP TABLE IF EXISTS #output_sp_msdependencies
CREATE TABLE #output_sp_msdependencies (oType INT, oObjName VARCHAR(100), oOwner VARCHAR(20), oSequence INT)
INSERT INTO #output_sp_msdependencies EXEC sp_msdependencies @flags = 8
-- Remove exclusions
DELETE FROM #output_sp_msdependencies WHERE oOwner IN ('ref','hst') 
-- Check output
--SELECT * FROM #output_sp_msdependencies

-- Expected list of tables minus exclusions
SELECT CONCAT_WS('.',QUOTENAME(SCHEMA_NAME(schema_id)), QUOTENAME([name])) AS TableName INTO #table_list
FROM sys.tables
WHERE SCHEMA_NAME(schema_id) NOT IN ('ref','hst')

SELECT * INTO #statements FROM
(
	SELECT 99999 AS Lvl, '' AS TableName, 'BEGIN TRAN' AS SqlStatement
	UNION
	SELECT oSequence
	, CONCAT_WS('.',QUOTENAME(s.[name]), QUOTENAME(t.[name]))
	, CONCAT(CASE WHEN fk.referenced_object_id IS NULL AND temporal_type = 0 THEN 'TRUNCATE TABLE' ELSE 'DELETE FROM' END, ' ',QUOTENAME(s.[name]),'.',QUOTENAME(t.[name])) 
	FROM #output_sp_msdependencies tbls
	JOIN sys.tables t ON t.[name] = tbls.[oObjName]
	JOIN sys.schemas s ON s.schema_id = t.schema_id AND tbls.[oOwner] = s.[name]
	LEFT JOIN sys.foreign_keys fk ON fk.referenced_object_id = t.object_id
	UNION 
	SELECT -1, '', 'ROLLBACK TRAN'
	--SELECT -1, 'COMMIT TRAN'
)results
ORDER BY Lvl 
GO

-- Check if any tables are missing from the expected list
SELECT TableName FROM #table_list
EXCEPT
SELECT TableName FROM #statements
GO

-- Output the statements for execution
SELECT * FROM #statements ORDER BY Lvl DESC

/* NOTE: Recommended to perform a COUNT of all records for all tables to check expected duration/results */


