/*
-- Metadata functions versus catalog views. 
-- Great article by Aaron Bertrand:
-- https://www.sentryone.com/blog/aaronbertrand/bad-habits-metadata-helper-functions

-- Summary of reasons not to use 'some' of the SQL Server metadata functions

-- 1) Some functions are blocked/cause blocking even when using read uncommitted (do not obey isolation semantics):
--    OBJECT_ID, OBJECT_NAME, OBJECT_SCHEMA_NAME, SCHEMA_ID, SCHEMA_NAME, OBJECTPROPERTY, COLUMNPROPERTY, HAS_PERMS_BY_NAME
-- 2) If metadata is locked down to users, using the catalog views vs metadata functions can return different results. This
      can pose issues when creating internal auditing, for example.
-- 3) It is possible to have the same object_id for an object across databases causing unexpected results. You will need
      to include the database context in the query joins.
-- 4) You need to ensure you execute queries that use the functions in the right database context. 
*/

-- 1) Query blocked when using 
-- execute in a different window:
BEGIN TRANSACTION;
CREATE TABLE dbo.foo(id INT);

-- Now execute the below query - should work fine
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT name, [object_id] FROM sys.objects WHERE name = N'foo';

-- Now try this query - it is blocked
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT OBJECT_ID(N'dbo.foo'); -- blocked

-- Execute this query in the same window in which the table was created
SELECT request_mode, request_status--, *
  FROM sys.dm_tran_locks
  WHERE resource_database_id = DB_ID()
  AND resource_associated_entity_id = OBJECT_ID(N'dbo.foo');

-- Results:
/*
request_mode	request_status
------------------------------
Sch-M			GRANT
Sch-S			WAIT
*/

-- Clean up - rollback the transaction in the other window
ROLLBACK TRAN

-- 2) Different results returned when permissions are locked down to metadata catalogs
USE [master];
GO
CREATE LOGIN peon WITH PASSWORD = N'peon', CHECK_POLICY = OFF;
GO
USE [AdventureWorks2019];
GO
CREATE USER peon FOR LOGIN peon;
GO
CREATE PROCEDURE dbo.NestedProcedure
AS
BEGIN
  SET NOCOUNT ON;
 
  SELECT helper = OBJECT_SCHEMA_NAME(@@PROCID);
 
  SELECT [catalog] = s.name
    FROM sys.schemas AS s
    INNER JOIN sys.objects AS o
    ON s.[schema_id] = o.[schema_id]
    WHERE o.[object_id] = @@PROCID;
END
GO
CREATE PROCEDURE dbo.WrapperProcedure
AS
BEGIN
  SET NOCOUNT ON;
  EXEC dbo.NestedProcedure;
END
GO
GRANT EXECUTE ON dbo.WrapperProcedure TO peon;
GO
EXECUTE AS USER = N'peon';
EXEC dbo.WrapperProcedure;
REVERT

/*
-- Results
helper -- Returns a NULL result
------------
NULL

catalog -- Returns an empty resultset
------------
*/

-- Clean up
USE [AdventureWorks2019];
GO
DROP PROCEDURE dbo.NestedProcedure;
DROP PROCEDURE dbo.WrapperProcedure;
DROP USER peon;
DROP LOGIN peon;
GO

-- 3) Same object_id in different databases 
USE [master]
GO
CREATE DATABASE db1;
CREATE DATABASE db2;
GO
DECLARE @sql NVARCHAR(MAX);
SET @sql = N'CREATE PROCEDURE dbo.db1_foo AS PRINT ''does something harmless'';'
EXEC db1.sys.sp_executesql @sql;
SET @sql = N'CREATE PROCEDURE dbo.db2_bar AS PRINT ''does something dangerous'';'
EXEC db2.sys.sp_executesql @sql;
GO

SELECT db1.[object_id], db1.[name], db2.[object_id], db2.[name] 
FROM db1.sys.procedures AS db1
INNER JOIN db2.sys.procedures AS db2 
ON db1.[object_id] = db2.[object_id]
AND db1.[name] <> db2.[name]
GO
/*
-- Results
object_id	 name	object_id	name
------------------------------------------
581577110	db1_foo	581577110	db2_foo
*/

-- Execute the procedure in db1
EXEC db1.dbo.db1_foo;
GO 100

-- Imagine you are trying to find execution stats for the other procedure db2.dbo.db2_bar
USE db2;
GO
-- Query 1
SELECT [SP Name] = OBJECT_NAME(t.objectid),
   [Number of Executions] = SUM(s.execution_Count)
FROM sys.dm_exec_procedure_stats AS s
CROSS APPLY sys.dm_exec_sql_text(s.sql_handle) AS t
WHERE OBJECT_NAME(t.objectid) = N'db2_bar'
GROUP BY OBJECT_NAME(t.objectid);

-- Query 2
SELECT [SP Name] = p.name,
   [Number of Executions] = SUM(s.execution_Count)
FROM sys.dm_exec_procedure_stats AS s  
CROSS APPLY sys.dm_exec_sql_text(s.sql_handle) AS t
INNER JOIN sys.procedures AS p
   ON p.[object_id] = t.objectid
WHERE p.name = N'db2_bar'
GROUP BY p.name;
GO
/*
-- Results - you would expect an empty result set
-- Query 1 - but you see the stats for the other procedure
SP Name	Number of Executions
------------------------------
db1_foo	100

-- Query 2 -- same results
SP Name	Number of Executions
------------------------------
db1_foo	100
*/
-- You need to specify the database so you don't have to worry about the database context
SELECT [SP Name] = p.name,
   [Number of Executions] = SUM(ps.execution_count)
FROM sys.dm_exec_procedure_stats AS ps  
CROSS APPLY sys.dm_exec_sql_text(ps.sql_handle) AS t
INNER JOIN db2.sys.procedures AS p
   ON p.[object_id] = t.objectid
INNER JOIN db2.sys.schemas AS s
   ON p.[schema_id] = s.[schema_id]
WHERE p.name = N'db2_bar'
  AND s.name = N'dbo'
  AND t.[dbid] = DB_ID(N'db2')
GROUP BY p.name;

-- Clean up
USE [master]
GO
DROP DATABASE db1;
DROP DATABASE db2;
GO

-- 4) Same object_id/object_name in different databases - need to execute in the correct database context when objects of the same name are created
USE [master]
GO
CREATE DATABASE db1;
CREATE DATABASE db2;
GO
DECLARE @sql NVARCHAR(MAX);
SET @sql = N'CREATE PROCEDURE dbo.db1_foo AS PRINT ''does something harmless'';'
EXEC db1.sys.sp_executesql @sql;
SET @sql = N'CREATE PROCEDURE dbo.db1_foo AS PRINT ''does something dangerous'';'
EXEC db2.sys.sp_executesql @sql;
GO

-- Execute the procedure in db1
EXEC db1.dbo.db1_foo;
GO 100

-- Imagine you are trying to find execution stats for the 'dangerous' procedure in db2
USE [db2];
GO
-- Query 1 - returns results for the procedure with the same name
SELECT [SP Name] = OBJECT_NAME(t.objectid),
   [Number of Executions] = SUM(s.execution_Count)
FROM sys.dm_exec_procedure_stats AS s
CROSS APPLY sys.dm_exec_sql_text(s.sql_handle) AS t
WHERE OBJECT_NAME(t.objectid) = N'db1_foo'
GROUP BY OBJECT_NAME(t.objectid);

-- By including the database in the JOIN, you can guarantee the right results
-- Query 2
SELECT [SP Name] = p.name,
   [Number of Executions] = SUM(s.execution_Count)
FROM sys.dm_exec_procedure_stats AS s  
CROSS APPLY sys.dm_exec_sql_text(s.sql_handle) AS t
INNER JOIN sys.procedures AS p
   ON p.[object_id] = t.objectid
INNER JOIN sys.schemas AS schm
   ON p.[schema_id] = schm.[schema_id]
WHERE p.[name] = N'db1_foo'
  AND schm.[name] = N'dbo'
  AND t.[dbid] = DB_ID(N'db2')
GROUP BY p.name;
GO
/*
-- Results
-- Query 1 -- you see the stats for the other procedure
SP Name	Number of Executions
------------------------------
db1_foo	100

-- Query 2 -- no results
SP Name	Number of Executions
-----------------------------
*/

-- Clean up
USE [master]
GO
DROP DATABASE db1;
DROP DATABASE db2;
GO

