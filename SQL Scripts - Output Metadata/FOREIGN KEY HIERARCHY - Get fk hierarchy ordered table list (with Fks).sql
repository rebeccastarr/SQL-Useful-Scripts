/*
Name: R Starr
Date: 18/04/2022
Purpose: Script to output table and foreign key metadata (limited) in the order of the foreign key hierarchy dependency.
Uses 2 approaches:
Order: Bottom down - first level (1) are the child tables with no foreign keys that reference it.
Order: Top down - first level (1) are the parent tables with no defined foreign keys that reference other tables.

To Do: 
Verify results against #table_list as currently, both top and bottom down approach omits some FKs.
Create test data set for checking all scenarios (including multi-level relationships, composite keys, and self-referencing fks)
*/
DROP TABLE IF EXISTS #output_sp_msdependencies
DROP TABLE IF EXISTS #tables_topDown
DROP TABLE IF EXISTS #tables_bottomDown
DROP TABLE IF EXISTS #table_list

-- Expected list of tables minus exclusions
SELECT t.object_id
, CONCAT_WS('.',QUOTENAME(SCHEMA_NAME(t.schema_id)), QUOTENAME(t.[name])) AS [Referencing table]
, OBJECT_NAME(fk.object_id) AS [FK Constraint] 
, CONCAT_WS('.',QUOTENAME(SCHEMA_NAME(reft.schema_id)), QUOTENAME(OBJECT_NAME(fk.referenced_object_id))) AS [Referenced table] 
INTO #table_list
FROM sys.tables t
LEFT JOIN sys.foreign_keys fk ON fk.parent_object_id = t.object_id
LEFT JOIN sys.tables reft ON reft.object_id = fk.referenced_object_id
WHERE t.temporal_type <> 1
--AND SCHEMA_NAME(schema_id) NOT IN ('ref','hst')

-----------------------------------------------------------------------------------------------------------
-- BOTTOM Down Approach
-----------------------------------------------------------------------------------------------------------
;WITH dependencies_cte -- Get the fk dependency hierarchy
AS
(
	-- Tables that have no foreign keys that reference it
	SELECT DISTINCT 1 AS Lvl
	, t.object_id
	FROM sys.tables t
	LEFT JOIN sys.foreign_keys fk ON fk.referenced_object_id = t.object_id  
	WHERE fk.referenced_object_id IS NULL 
	AND t.temporal_type <> 1 -- Ignore the history tables that are temporal
	UNION ALL
	SELECT Lvl + 1
	, fk.referenced_object_id
	FROM dependencies_cte depends
	JOIN sys.foreign_keys fk ON depends.object_id = fk.parent_object_id 
	AND fk.parent_object_id <> fk.referenced_object_id -- Prevents self-referencing loop. But won't include the tables with a self-referencing constraint
) 
SELECT DISTINCT -- To remove dupes (possibly because table is referenced by more than one FK constraint)
  d.Lvl
, CONCAT_WS('.', QUOTENAME(SCHEMA_NAME(t.schema_id)), QUOTENAME(OBJECT_NAME(d.object_id))) AS [Referencing table]
, 'has a foreign key' AS [has an fk]
, OBJECT_NAME(fk.object_id) AS [FK constraint]
, 'that references' AS [Direction]
, CONCAT_WS('.', QUOTENAME(SCHEMA_NAME(reft.schema_id)), QUOTENAME(OBJECT_NAME(reft.object_id))) AS [Referenced table]
INTO #tables_bottomDown
FROM 
( SELECT MAX(Lvl) AS Lvl, object_id FROM dependencies_cte GROUP BY object_id )AS d -- Remove dupes (where table appears at multiple levels - select MAX)
JOIN sys.tables t ON t.object_id = d.object_id
JOIN sys.foreign_keys fk ON fk.parent_object_id = t.object_id
JOIN sys.tables reft ON reft.object_id = fk.referenced_object_id
ORDER BY Lvl --DESC
OPTION (MAXRECURSION 1000) 

-----------------------------------------------------------------------------------------------------------
-- TOP Down Approach
-----------------------------------------------------------------------------------------------------------
-- Capture output of undocumented procedure sp_msdependencies
DROP TABLE IF EXISTS #output_sp_msdependencies
CREATE TABLE #output_sp_msdependencies (oType INT, oObjName VARCHAR(100), oOwner VARCHAR(20), oSequence INT)
INSERT INTO #output_sp_msdependencies EXEC sp_msdependencies @flags = 8
-- Remove exclusions
--DELETE FROM #output_sp_msdependencies WHERE oOwner IN ('ref','hst') 

SELECT
  oSequence AS Lvl
, CONCAT_WS('.', QUOTENAME(SCHEMA_NAME(t.schema_id)), QUOTENAME(OBJECT_NAME(t.object_id))) AS [Referencing table]
, 'has a foreign key' AS [has an fk]
, OBJECT_NAME(fk.object_id) AS [FK constraint]
, 'that references' AS [Direction]
, CONCAT_WS('.', QUOTENAME(SCHEMA_NAME(reft.schema_id)), QUOTENAME(OBJECT_NAME(reft.object_id))) AS [Referenced table]
INTO #tables_topDown
FROM #output_sp_msdependencies d
JOIN sys.tables t ON d.oOwner = SCHEMA_NAME(t.schema_id) AND d.oObjName = t.[name]
JOIN sys.foreign_keys fk ON fk.parent_object_id = t.object_id
JOIN sys.tables reft ON reft.object_id = fk.referenced_object_id
WHERE t.temporal_type <> 1
ORDER BY oSequence

SELECT * FROM #tables_bottomDown
SELECT * FROM #tables_topDown
SELECT * FROM #table_list

-- Check for missing results
SELECT [Referencing table], [FK Constraint], [Referenced table] FROM #table_list
EXCEPT
SELECT [Referencing table], [FK Constraint], [Referenced table] FROM #tables_bottomDown

-- Check for missing results
SELECT [Referencing table], [FK Constraint], [Referenced table] FROM #table_list
EXCEPT
SELECT [Referencing table], [FK Constraint], [Referenced table] FROM #tables_topDown


