/*
Name: R Starr
Date: 18/04/2022
Purpose: Script gets the list of columns for a constraint and saves to a temp table.
This temp table can then be used to build SQL scripts.

CONSTRAINT_TYPES
----------------
** PRIMARY KEY
** FOREIGN KEY
** CHECK
** UNIQUE
*/

DECLARE 
  @Schema VARCHAR(20) = NULL -- 'ref'
, @Table VARCHAR(100) = NULL
, @Constraint_type VARCHAR(100) = 'PRIMARY KEY'-- 'FOREIGN KEY' 

/* STEP 1: */ DROP TABLE IF EXISTS #constraint_col_list
/* STEP 2: */ DROP TABLE IF EXISTS #constraint_col_list_agg

-- STEP 1: Script to get PRIMARY KEY columns
SELECT const.TABLE_SCHEMA AS [Schema]
, const.TABLE_NAME AS [Table]
, CONCAT_WS('.',QUOTENAME(const.TABLE_SCHEMA),QUOTENAME(const.TABLE_NAME)) AS [FullName]
, keyCols.COLUMN_NAME AS [Column]
, const.CONSTRAINT_NAME AS [Constraint]
INTO #constraint_col_list
FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE keyCols
JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS const 
  ON const.CONSTRAINT_NAME		= keyCols.CONSTRAINT_NAME 
 AND keyCols.CONSTRAINT_SCHEMA	= const.CONSTRAINT_SCHEMA 
 AND keyCols.TABLE_SCHEMA		= const.TABLE_SCHEMA
 AND keyCols.TABLE_NAME			= const.TABLE_NAME
 AND keyCols.TABLE_CATALOG		= const.TABLE_CATALOG
WHERE CONSTRAINT_TYPE	 = @Constraint_type
 AND (const.TABLE_SCHEMA = @Schema OR @Schema IS NULL)
 AND (const.TABLE_NAME	 = @Table  OR @Table  IS NULL)

 -- EXAMPLE SCRIPT
 /*
 -- Get MIN and MAX values for PRIMARY KEY (for single column PKs)
 SELECT CASE WHEN ROW_NUMBER()OVER(ORDER BY [Constraint]) = 1 THEN '' ELSE ' UNION ' END +
'SELECT '''+[FullName]+''' AS TableName, MIN('+[Column]+'), MAX('+[Column]+') FROM '+[FullName]
FROM #constraint_col_list
 */

-- STEP 2: Script to get PRIMARY KEY columns aggregated as a single list
SELECT const.TABLE_SCHEMA AS [Schema]
, const.TABLE_NAME AS [Table]
, CONCAT_WS('.',QUOTENAME(const.TABLE_SCHEMA),QUOTENAME(const.TABLE_NAME)) AS [FullName]
, STRING_AGG(keyCols.COLUMN_NAME, ', ') AS [ColumnList]
INTO #constraint_col_list_agg
FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE keyCols
JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS const 
  ON const.CONSTRAINT_NAME		= keyCols.CONSTRAINT_NAME 
 AND keyCols.CONSTRAINT_SCHEMA	= const.CONSTRAINT_SCHEMA 
 AND keyCols.TABLE_SCHEMA		= const.TABLE_SCHEMA
 AND keyCols.TABLE_NAME			= const.TABLE_NAME
 AND keyCols.TABLE_CATALOG		= const.TABLE_CATALOG
WHERE CONSTRAINT_TYPE	 = @Constraint_type
 AND (const.TABLE_SCHEMA = @Schema OR @Schema IS NULL)
 AND (const.TABLE_NAME	 = @Table  OR @Table  IS NULL)
GROUP BY const.TABLE_SCHEMA, const.TABLE_NAME

SELECT * FROM #constraint_col_list
SELECT * FROM #constraint_col_list_agg


