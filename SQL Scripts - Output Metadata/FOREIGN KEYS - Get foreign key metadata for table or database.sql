/*
Name: R Starr
Date: 18/04/2022
SQL Server Version: 2017 upwards (due to STRING_AGG function)
Purpose: Script lists all the foreign keys for a table/database. 

** If @tableName is provided, the resultset will be a list of foreign key constraints defined on that table and the 
   foreign key constraints that reference it.
** Both the below statements return the same resultset, but from a different perspective/direction.
** STRING_AGG is used to return a column list where the foreign key constraint is composite (more than one column)

-------------------------------------------------------------------------------------------------------------------
system_type_ID versus user_type_ID
-------------------------------------------------------------------------------------------------------------------
system_type_id is not unique in sys.types because user types can reuse system type.
There are two JOINs which do make sense:

1) sys.columns.user_type_id = sys.types.user_type_id
**For a built-in type, it returns the built-in type.
**For a user-defined type, it returns the user-defined type.

2) sys.columns.system_type_id = sys.types.user_type_id
**For a built-in type, it returns the built-in type.
**For a user-defined type, it returns the built-in base type. For example, if you want to get all varchar columns, 
  including the user-defined columns based on varchar.

A user-defined data type uses the existing data types with a set of constraints or rules. For example, you can create 
a UDDT for EmailAddress to ensure consistency across a database (e.g. all EmailAddress columns are NVARCHAR(100) NOT NULL)
-------------------------------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------------------------------
INFORMATION_SCHEMA versus sys.views
-------------------------------------------------------------------------------------------------------------------
INFORMATION_SCHEMA - ANSI/ISO catalogs for metadata so can be used across RDBMS's
sys.??? - MS SQL Server specific metadata

To view INFORMATION_SCHEMA definitions:
SELECT OBJECT_DEFINITION(OBJECT_ID('INFORMATION_SCHEMA.TABLES'))

*/
DECLARE @TableName VARCHAR(100) = NULL; -- If NULL, then all foreign keys for all tables will be returned

-- NOTE: If there are repeated records for a Foreign Key, this indicates that there are more than 1 column and that they 
-- are combined NULL and NOT NULL (as we group on col.is_nullable)

-- Direction: Is a foreign key that references......
SELECT
  fk.[name] AS [Foreign key constraint]
, CONCAT(fkSchm.[name]
		,'.'
		,fkTbl.[name]
		,' ('
		,STRING_AGG(col.[name]+' - '+typs.[name]+CASE WHEN col.collation_name IS NOT NULL THEN CONCAT('(',CAST(col.max_length AS VARCHAR(20)),')') ELSE '' END,', ')
		,')'
	) AS [Foreign key table]
-- Lists schame, table and column list separately
--, fkSchm.[name] AS [FK schema], fkTbl.[name] AS [FK table], STRING_AGG(col.[name]+' - '+typs.[name]+CASE WHEN col.collation_name IS NOT NULL THEN CONCAT('(',CAST(col.max_length AS VARCHAR(20)),')') ELSE '' END,', ') AS [FK column(s)], col.is_nullable AS [FK column nullable]
, CONCAT('is a'
		, CASE WHEN col.is_nullable = 1 THEN ' [nullable] ' ELSE ' [not nullable] ' END
		, 'foreign key that references'
	) AS [Direction]
, CONCAT(refSchm.[name]
		,'.',refTbl.[name]
		,' ('
		,STRING_AGG(refCol.[name]+' - '+refTyp.[name]+CASE WHEN refCol.collation_name IS NOT NULL THEN CONCAT('(',CAST(refCol.max_length AS VARCHAR(20)),')') ELSE '' END,', ')
		,')'
	) AS [Referenced table]
--, refSchm.[name] AS [Parent schema], refTbl.[name] as [Parent table], STRING_AGG(refCol.[name]+' - '+refTyp.[name]+CASE WHEN refCol.collation_name IS NOT NULL THEN CONCAT('(',CAST(refCol.max_length AS VARCHAR(20)),')') ELSE '' END,', ') AS [Referenced column(s)]
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkCol	ON fkCol.constraint_object_id = fk.object_id
JOIN sys.objects fkTbl				ON fkTbl.object_id = fkCol.parent_object_id
JOIN sys.columns col				ON (col.object_id = fkCol.parent_object_id) AND (col.column_id = fkCol.parent_column_id)
JOIN sys.types typs					ON typs.user_type_id = col.user_type_id
JOIN sys.schemas fkSchm				ON fkSchm.schema_id = fkTbl.schema_id
JOIN sys.objects refTbl				ON refTbl.object_id = fkCol.referenced_object_id
JOIN sys.columns refCol				ON (refCol.object_id = fkCol.referenced_object_id) AND (refCol.column_id = fkCol.referenced_column_id)
JOIN sys.types refTyp				ON refTyp.user_type_id = refCol.user_type_id
JOIN sys.schemas refSchm			ON refSchm.schema_id = refTbl.schema_id
WHERE
    ((fkTbl.[name] = @TableName OR @TableName IS NULL) AND (fkTbl.type = 'U'))
    OR
    ((refTbl.[name] = @TableName OR @TableName IS NULL) AND (refTbl.type = 'U'))
GROUP BY fk.[name], fkSchm.[name], fkTbl.[name], refSchm.[name], refTbl.[name], col.is_nullable
ORDER BY fkSchm.[name], fkTbl.[name], fk.[name]

-- Direction: Is referenced by a foreign key......
SELECT
  fk.[name] AS [Foreign key constraint]
, CONCAT(refSchm.[name]
		,'.',refTbl.[name]
		,' ('
		,STRING_AGG(refCol.[name]+' - '+refTyp.[name]+CASE WHEN refCol.collation_name IS NOT NULL THEN CONCAT('(',CAST(refCol.max_length AS VARCHAR(20)),')') ELSE '' END,', ')
		,')'
	) AS [Referenced table]
-- Lists schame, table and column list separately
--, refSchm.[name] AS [Parent schema], refTbl.[name] as [Parent table], STRING_AGG(refCol.[name]+' - '+refTyp.[name]+CASE WHEN refCol.collation_name IS NOT NULL THEN CONCAT('(',CAST(refCol.max_length AS VARCHAR(20)),')') ELSE '' END,', ') AS [Referenced column(s)]
, 'is referenced by a foreign key ' as [direction]
, CONCAT(fkSchm.[name]
		,'.',fkTbl.[name]
		,' ('
		,STRING_AGG(col.[name]+' - '+typs.[name]+CASE WHEN col.collation_name IS NOT NULL THEN CONCAT('(',CAST(col.max_length AS VARCHAR(20)),')') ELSE '' END,', ')
		,')'
	) AS [Foreign key table]
--, fkSchm.[name] AS [FK schema], fkTbl.[name] AS [FK table], STRING_AGG(col.[name]+' - '+typs.[name]+CASE WHEN col.collation_name IS NOT NULL THEN CONCAT('(',CAST(col.max_length AS VARCHAR(20)),')') ELSE '' END,', ') AS [FK column(s)], col.is_nullable AS [FK column nullable]
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkCol	ON fkCol.constraint_object_id = fk.object_id
JOIN sys.objects fkTbl				ON fkTbl.object_id = fkCol.parent_object_id
JOIN sys.columns col				ON (col.object_id = fkCol.parent_object_id) AND (col.column_id = fkCol.parent_column_id)
JOIN sys.types typs					ON typs.user_type_id = col.user_type_id
JOIN sys.schemas fkSchm				ON fkSchm.schema_id = fkTbl.schema_id
JOIN sys.objects refTbl				ON refTbl.object_id = fkCol.referenced_object_id
JOIN sys.columns refCol				ON (refCol.object_id = fkCol.referenced_object_id) AND (refCol.column_id = fkCol.referenced_column_id)
JOIN sys.types refTyp				ON refTyp.user_type_id = refCol.user_type_id
JOIN sys.schemas refSchm ON refSchm.schema_id = refTbl.schema_id
WHERE
    ((fkTbl.[name] = @TableName OR @TableName IS NULL) AND (fkTbl.type = 'U'))
    OR
    ((refTbl.[name] = @TableName OR @TableName IS NULL) AND (refTbl.type = 'U'))
GROUP BY fk.[name], fkSchm.[name], fkTbl.[name], refSchm.[name], refTbl.[name], col.is_nullable
ORDER BY refSchm.[name], refTbl.[name], fk.[name]



