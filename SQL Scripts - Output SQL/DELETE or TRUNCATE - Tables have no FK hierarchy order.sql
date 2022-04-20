/*
Name: R Starr
Date: 14/04/2022
Purpose: Script to create DELETE or TRUNCATE scripts to empty tables. 

If the table has no foreign keys that reference it, then we use a TRUNCATE statement. However, if the table has foreign keys, 
then we use a DELETE statement. There is no ordering based on foreign key hierarchy, so for use within a Staging environment 
with limited FK relationships (1 level max).

Alternatively, you can specify whether statements are to be TRUNCATE/DELETE or dynamically created by populating the attribute
@DeletionType. Valid values include:
** NULL
** 'TRUNCATE TABLE'
** 'DELETE FROM'

You can comment out the statements that are irrelevent. You can provide:
** Schema or table list
** Specific schema/table
** Schema or table that contains a word
** Returns everything (schema or table are NULL)

You can add this to a cursor to perform the actual delete statements, or copy and paste into a new window for execution.
*/

DECLARE 
  @TableName VARCHAR(100) = NULL
, @SchemaName VARCHAR(20) = NULL
, @DeletionType VARCHAR(20) = NULL -- 'DELETE FROM' -- If specified, this will replace the dynamic DELETE or TRUNCATE statement

-- For creating a list of Schema and Table Names
DECLARE @Tables TABLE (SchemaName VARCHAR(20), TableName VARCHAR(100))
INSERT INTO @Tables(SchemaName, TableName)
VALUES(NULL,NULL)
	, (NULL,NULL)
	, (NULL,NULL)

SELECT '['+s.[name]+'].['+tbl.[name]+']' AS TableName
, CASE WHEN @DeletionType IS NULL
	  THEN CASE WHEN referenced_object_id IS NULL THEN 'TRUNCATE' ELSE 'DELETE' END 
  ELSE @DeletionType 
  END AS [Deletion type]
, 'IF EXISTS(SELECT NULL FROM sys.tables tbl JOIN sys.schemas s ON s.schema_id = tbl.schema_id WHERE s.[name] = '''+s.[name]+''' AND tbl.[name] = '''+tbl.[name]+''') 
BEGIN 
PRINT '''+CASE  WHEN @DeletionType IS NULL
				THEN CASE WHEN referenced_object_id IS NULL THEN 'Truncating table' ELSE 'Deleting from' END
				ELSE @DeletionType
		  END+' ['+s.[name]+'].['+tbl.[name]+']'''++' '+
CASE WHEN @DeletionType IS NULL
	 THEN CASE WHEN referenced_object_id IS NULL THEN 'TRUNCATE TABLE' ELSE 'DELETE FROM' END 
	 ELSE @DeletionType
END+' ['+s.[name]+'].['+tbl.[name]+'] 
END'
FROM sys.tables tbl
JOIN sys.schemas s ON s.schema_id = tbl.schema_id
LEFT JOIN 
	(SELECT DISTINCT referenced_object_id FROM sys.foreign_key_columns) fks ON fks.referenced_object_id = tbl.object_id
WHERE /* comment out scripts that are not required */
	(  s.[name] = @SchemaName
	OR s.[name] LIKE '%'+@SchemaName+'%'
	OR s.[name] IN (SELECT SchemaName FROM @Tables)
	OR @SchemaName IS NULL
	)
AND (  tbl.[name] = @TableName
	OR tbl.[name] LIKE '%'+@TableName+'%'
	OR tbl.[name] IN (SELECT TableName FROM @Tables)
	OR @TableName IS NULL
	)
ORDER BY s.[name], tbl.[name]
