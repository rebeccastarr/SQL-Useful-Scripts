/*
Name: R Starr
Date: 20/04/2022
Purpose: Script to create list of columns for a table(s).

IMPORTANT NOTE:
---------------------------------------------------------------------------
@PrintOrExecute: 
0	 = Will print out the column list as a single string
1	 = Will print out the column list in column format
---------------------------------------------------------------------------
*/

DECLARE 
  @ListOrTable BIT			= 0 -- See above for valid values
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
SELECT 
  ROW_NUMBER()OVER(ORDER BY s.[name], t.[name], c.column_id) AS RowNo
, ROW_NUMBER()OVER(PARTITION BY s.[name], t.[name] ORDER BY c.column_id) AS TableOrder
, CONCAT_WS('.',QUOTENAME(s.[name]),  QUOTENAME(t.[name])) AS TableName
, c.[name] AS ColumnName
, c.column_id AS ColumnOrder
INTO #tables
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.columns c ON c.object_id = t.object_id
WHERE /* comment out scripts that are not required */
	(  s.[name] = @SchemaName
	OR s.[name] LIKE '%'+@SchemaName+'%'
	OR s.[name] IN (SELECT SchemaName FROM @Tables)
	OR @SchemaName IS NULL
	)
AND (  t.[name] = @TableName
	OR t.[name] LIKE '%'+@TableName+'%'
	OR t.[name] IN (SELECT TableName FROM @Tables)
	OR @TableName IS NULL
	)
ORDER BY s.[name], t.[name]

IF @ListOrTable = 0 
BEGIN
	-- Print columns as as single List
	SELECT TableName, STRING_AGG(QUOTENAME(ColumnName), ', ') AS ColumnList 
	FROM #tables 
	GROUP BY TableName
	ORDER BY TableName
END
ELSE IF @ListOrTable = 1
BEGIN
	-- Print columns
	SELECT 
	  CASE WHEN TableOrder = 1 THEN TableName ELSE '' END AS TableName
	, CASE WHEN TableOrder = 1 THEN '' ELSE ', ' END+ColumnName AS ColumnName
	FROM #tables 
	ORDER BY RowNo, ColumnOrder
END
