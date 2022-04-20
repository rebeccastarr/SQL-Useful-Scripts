/*
Name: R Starr
Date: 15/04/2022
Purpose: Script to output a table list that is ordered based on foreign key hierarchy dependency. 
Order: Bottom down - first level (1) are the child tables with no foreign keys that reference it.
Order: Top down - first level (1) are the parent tables with no defined foreign keys that reference other tables.

To Do: 
Verify results against script that outputs all foreign key metadata.
Create test data set for checking all scenarios (including multi-level relationships, composite keys, and self-referencing fks)

*/
DROP TABLE IF EXISTS #tables_topDown
DROP TABLE IF EXISTS #tables_bottomDown
DROP TABLE IF EXISTS #table_list

-- Expected list of tables minus exclusions
SELECT t.object_id, CONCAT_WS('.',QUOTENAME(SCHEMA_NAME(t.schema_id)), QUOTENAME(t.[name])) AS TableName, OBJECT_NAME(fk.object_id) AS [FK_Constraint] 
INTO #table_list
FROM sys.tables t
LEFT JOIN sys.foreign_keys fk ON fk.parent_object_id = t.object_id  
WHERE t.temporal_type <> 1
--AND SCHEMA_NAME(schema_id) NOT IN ('ref','hst')

-----------------------------------------------------------------------------------------------------------
-- BOTTOM Down Approach
-----------------------------------------------------------------------------------------------------------
;WITH dependencies_cte -- Get the fk dependency hierarchy
AS
(
	-- Tables that have no foreign keys that reference it
	SELECT DISTINCT 1 AS Lvl, t.object_id, CONCAT_WS('.',QUOTENAME(SCHEMA_NAME(t.schema_id)), QUOTENAME(t.[name])) AS FK_TableName 
	FROM sys.tables t
	LEFT JOIN sys.foreign_keys fk ON fk.referenced_object_id = t.object_id  
	WHERE fk.referenced_object_id IS NULL 
	AND t.temporal_type <> 1 -- Ignore the history tables that are temporal
	UNION ALL
	SELECT Lvl + 1, fk.referenced_object_id, CONCAT_WS('.',QUOTENAME(SCHEMA_NAME(fk.schema_id)), QUOTENAME(OBJECT_NAME(fk.referenced_object_id)))
	FROM dependencies_cte depends
	JOIN sys.foreign_keys fk ON depends.object_id = fk.parent_object_id 
	AND fk.parent_object_id <> fk.referenced_object_id -- Prevents self-referencing loop. But won't include the tables with a self-referencing constraint
) 
SELECT MAX(Lvl) AS Lvl, object_id, FK_TableName INTO #tables_bottomDown 
FROM dependencies_cte 
GROUP BY object_id, FK_TableName
OPTION (MAXRECURSION 1000) 

-----------------------------------------------------------------------------------------------------------
-- TOP Down Approach
-----------------------------------------------------------------------------------------------------------
-- Capture output of undocumented procedure sp_msdependencies
DROP TABLE IF EXISTS #tables_topDown
CREATE TABLE #tables_topDown (oType INT, oObjName VARCHAR(100), oOwner VARCHAR(20), oSequence INT)
INSERT INTO #tables_topDown EXEC sp_msdependencies @flags = 8
-- Remove exclusions
--DELETE FROM #output_sp_msdependencies WHERE oOwner IN ('ref','hst') 

SELECT * FROM #tables_bottomDown ORDER BY Lvl
SELECT oSequence, t.object_id, CONCAT_WS('.',QUOTENAME(oOwner),QUOTENAME(oObjName)) AS FK_TableName 
FROM #tables_topDown tbl
JOIN sys.tables t ON tbl.oOwner = SCHEMA_NAME(t.schema_id) AND tbl.oObjName = t.[name]
WHERE t.temporal_type <> 1
ORDER BY oSequence

SELECT * FROM #table_list


