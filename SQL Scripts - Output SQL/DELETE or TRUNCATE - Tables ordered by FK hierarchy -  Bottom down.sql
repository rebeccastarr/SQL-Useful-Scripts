/*
Name: R Starr
Date: 17/04/2022
Purpose: Script to output the foreign key hierarchy and the order in which you would need to delete data from the tables.
Order is 'Bottom down' so first level (0) are the child tables that have no foreign keys referencing them. Using bottom 
down approach means we can TRUNCATE lowest level tables. If going top down, not all child tables will be listed in the 
lowest level.

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

-- Top down approach using sp_MSforeachtable (see alternative script)
DROP TABLE IF EXISTS #tables_test
CREATE TABLE #tables_test (TypeT INT, TblName VARCHAR(100), SchemaName VARCHAR(20), FKHierarchy INT)
INSERT INTO #tables_test EXEC sp_msdependencies @flags = 8
SELECT FKHierarchy, TblName FROM #tables_test WHERE SchemaName NOT IN ('ref','hst') ORDER BY FKHierarchy
*/
DROP TABLE IF EXISTS #tables
DROP TABLE IF EXISTS #statements
DROP TABLE IF EXISTS #table_list
GO
-- Expected list of tables minus exclusions
SELECT CONCAT_WS('.',QUOTENAME(SCHEMA_NAME(schema_id)), QUOTENAME([name])) AS TableName INTO #table_list
FROM sys.tables
WHERE SCHEMA_NAME(schema_id) NOT IN ('ref','hst')

;WITH dependencies_cte -- Get the fk dependency hierarchy
AS
(
	-- Tables that have no foreign keys that reference it
	SELECT DISTINCT 0 AS Lvl, t.object_id
	FROM sys.tables t
	LEFT JOIN sys.foreign_keys fk ON fk.referenced_object_id = t.object_id  
	WHERE fk.referenced_object_id IS NULL 
	AND t.temporal_type <> 1 -- Ignore the history tables that are temporal
	UNION ALL
	SELECT Lvl + 1, fk.referenced_object_id
	FROM dependencies_cte depends
	JOIN sys.foreign_keys fk ON depends.object_id = fk.parent_object_id 
	AND fk.parent_object_id <> fk.referenced_object_id -- Prevents self-referencing loop
) 
SELECT MAX(Lvl) AS Lvl, object_id INTO #tables 
FROM dependencies_cte 
GROUP BY object_id OPTION (MAXRECURSION 1000) -- Can change level of recursion if need be

SELECT * INTO #statements FROM
(
	SELECT -1 AS Lvl, '' AS TableName, 'BEGIN TRAN' AS SqlStatement
	UNION
	SELECT Lvl
	, CONCAT_WS('.',QUOTENAME(s.[name]), QUOTENAME(t.[name]))
	-- Checks for table existance and prints out statement
	/*
	,'IF EXISTS(SELECT NULL FROM sys.tables tbl JOIN sys.schemas s ON s.schema_id = tbl.schema_id WHERE s.[name] = '''+s.[name]+''' AND tbl.[name] = '''+t.[name]+''') 
	BEGIN 
	PRINT '''+CASE WHEN Lvl = 0 AND temporal_type = 0 THEN 'Truncating' ELSE 'Deleting' END+' data from table '+QUOTENAME(s.[name])+'.'+QUOTENAME(t.[name])+''''+
	CASE WHEN Lvl = 0 AND temporal_type = 0 THEN ' TRUNCATE TABLE' ELSE ' DELETE FROM' END +' '+QUOTENAME(s.[name])+'.'+QUOTENAME(t.[name])+'
	END'
	*/
	-- Simple DELETE/TRUNCATE statement
	, CONCAT(CASE WHEN Lvl = 0 AND temporal_type = 0 THEN 'TRUNCATE TABLE' ELSE 'DELETE FROM' END, ' ',QUOTENAME(s.[name]),'.',QUOTENAME(t.[name])) 
	-- Simple DELETE/TRUNCATE statement with a WHERE clause so no deletes are performed (checks validity of statements without deleting anything as this could be timely)
	--, CONCAT(CASE WHEN Lvl = 0 AND temporal_type = 0 THEN 'TRUNCATE TABLE' ELSE 'DELETE FROM' END, ' ',QUOTENAME(s.[name]),'.',QUOTENAME(t.[name]), CASE WHEN Lvl = 0 AND temporal_type = 0 THEN '' ELSE ' WHERE 1 = 2' END) 
	FROM #tables tbls
	JOIN sys.tables t ON t.object_id = tbls.object_id
	JOIN sys.schemas s ON s.schema_id = t.schema_id
	WHERE s.[name] <> 'ref'
	UNION 
	SELECT 99999, '', 'ROLLBACK TRAN'
	--SELECT 99999, 'COMMIT TRAN'
)results
ORDER BY Lvl 
GO

-- Check if any tables are missing from the expected list
SELECT TableName FROM #table_list
EXCEPT
SELECT TableName FROM #statements
GO

-- Output the statements for execution
SELECT * FROM #statements ORDER BY Lvl

/* NOTE: Perform a record COUNT for all tables to determine expected results and an estimate of how long script it will take */

