/*
Name: R Starr
Date: 14/04/2022
Purpose: Script to create IF EXISTS scripts to identify if tables are used.

IMPORTANT NOTE:
---------------------------------------------
@PrintOrExecute: 
0	 = Will print out the SQL statements
1	 = Will execute the SQL statements
NULL = Will do both the above
---------------------------------------------
*/

DECLARE 
  @PrintOrExecute BIT		= 1 -- See above for valid values
, @TableName VARCHAR(100)	= NULL
, @SchemaName VARCHAR(20)	= NULL
, @Sql NVARCHAR(MAX)		= ''

-- For creating a list of Schema and Table Names
DECLARE @Tables TABLE (SchemaName VARCHAR(20), TableName VARCHAR(100))
INSERT INTO @Tables(SchemaName, TableName)
VALUES(NULL,NULL)
	, (NULL,NULL)
	, (NULL,NULL)

DROP TABLE IF EXISTS #tables
SELECT CONCAT_WS('.',QUOTENAME(TABLE_SCHEMA),  QUOTENAME(TABLE_NAME)) AS TableName
, CASE WHEN ROW_NUMBER()OVER(ORDER BY TABLE_SCHEMA, TABLE_NAME) = 1 THEN '' ELSE ' UNION ' END 
+ 'SELECT TOP 1 '''+CONCAT_WS('.',QUOTENAME(TABLE_SCHEMA),  QUOTENAME(TABLE_NAME))+''' AS [Table contains data] FROM '+CONCAT_WS('.',QUOTENAME(TABLE_SCHEMA),  QUOTENAME(TABLE_NAME)) AS SqlStatement
INTO #tables
FROM INFORMATION_SCHEMA.TABLES
WHERE /* comment out scripts that are not required */
	(  TABLE_SCHEMA = @SchemaName
	OR TABLE_SCHEMA LIKE '%'+@SchemaName+'%'
	OR TABLE_SCHEMA IN (SELECT SchemaName FROM @Tables)
	OR @SchemaName IS NULL
	)
AND (  TABLE_NAME = @TableName
	OR TABLE_NAME LIKE '%'+@TableName+'%'
	OR TABLE_NAME IN (SELECT TableName FROM @Tables)
	OR @TableName IS NULL
	)
ORDER BY TABLE_SCHEMA, TABLE_NAME

IF @PrintOrExecute = 0 
BEGIN
	-- PRINT SQL Statements only
	SELECT * FROM #tables ORDER BY TableName
END
ELSE IF @PrintOrExecute = 1
BEGIN
	-- EXECUTE SQL Statements only
	SELECT @Sql = @Sql+SqlStatement FROM #tables ORDER BY TableName
	EXEC sp_executesql @Sql
END
ELSE
BEGIN
	-- PRINT & EXECUTE SQL Statements
	SELECT @Sql = @Sql+SqlStatement FROM #tables ORDER BY TableName
	EXEC sp_executesql @Sql
	SELECT * FROM #tables ORDER BY TableName
END
