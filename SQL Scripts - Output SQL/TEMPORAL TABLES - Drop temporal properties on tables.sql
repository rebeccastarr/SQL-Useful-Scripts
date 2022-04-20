/*
Name: R Starr
Date: 20/03/2022
Purpose: Script deletes the columns/properties associated with making the table temporal:

Options: 
** @Execute			- If set to '1', the script to drop the temporal properties will execute. 
					  Otherwise you will just get the printed output (which you can select and execute yourself).
** @DropCols		- If set to '1', the columns that were created for temporal purposes (to capture timestamps) will be DROPPED.
** @DropHistoryTbl	- If set to '1', the history table associated with the temporal table will be DROPPED.
*/
DECLARE 
  @RowNo INT
, @Schema VARCHAR(100)
, @Table VARCHAR(100)
, @object_id INT
, @SqlStart NVARCHAR(MAX)
, @SqlEnd NVARCHAR(MAX)
, @Sqlstatement NVARCHAR(MAX)
, @Tran VARCHAR(20) 		= 'ROLLBACK' --'COMMIT'--  Change to COMMIT once script is tested
, @Execute BIT				= 0 -- Default is '0' (false) so the script will not execute
, @DropCols BIT				= 1 -- Default is '0' (false) so the datetime2 columns will not be dropped
, @DropHistoryTbl BIT		= 1 -- Default is '0' (false) so the table containing history records will not be dropped

DECLARE delete_temporal_table CURSOR 
FOR
SELECT  
  s.[name] AS [Schema]
, t.[name] AS [Table]
, t.object_id
, 'BEGIN TRAN
PRINT ''DROPPING temporal properties on table '+CONCAT_WS('.',QUOTENAME(s.[name]),QUOTENAME(t.[name]))+'''
ALTER TABLE '+CONCAT_WS('.',QUOTENAME(s.[name]),QUOTENAME(t.[name]))+' SET (SYSTEM_VERSIONING = OFF); 
ALTER TABLE '+CONCAT_WS('.',QUOTENAME(s.[name]),QUOTENAME(t.[name]))+' DROP PERIOD FOR SYSTEM_TIME; 
' AS [SqlStart]
, @Tran+' TRAN' AS [SqlEnd]
FROM sys.tables t 
JOIN sys.schemas s ON s.schema_id = t.schema_id 
WHERE t.temporal_type = 2 -- 0 = NON_TEMPORAL_TABLE, 1 = HISTORY_TABLE, 2 = SYSTEM_VERSIONED_TEMPORAL_TABLE
--and T.name IN ('Party', 'Right')
ORDER BY s.[name], t.[name]

OPEN delete_temporal_table
FETCH NEXT FROM delete_temporal_table INTO @Schema, @Table, @object_id, @SqlStart, @SqlEnd

WHILE @@FETCH_STATUS = 0
BEGIN
	-- Drop the columns associated to the temporal table for SYSTEM_TIME period
	SELECT @SqlStatement = @SqlStart 
						 + CASE WHEN @DropCols = 1 THEN 'PRINT ''DROPPING temporal columns: '+STRING_AGG(c.[name],', ')+''''+CHAR(13)
														+STRING_AGG('ALTER TABLE ['+@Schema+'].['+@Table+'] DROP COLUMN ['+c.[name]+']' , '; '+CHAR(13))+'; '+CHAR(13) 
								ELSE '' END -- CHAR(13) adds a carriage return
	FROM sys.columns c
	JOIN sys.types t ON t.user_type_id = c.user_type_id
	WHERE generated_always_type IN (1,2) -- 1 = AS_ROW_START, 2 = AS_ROW_END
	AND object_id = @object_id

	-- Drop the history table associated to the temporal table
	SELECT @SqlStatement = @SqlStatement
						 + CASE WHEN @DropHistoryTbl = 1 THEN 'PRINT ''DROPPING table ['+SCHEMA_NAME(t.schema_id)+'].['+@Table+']'''+CHAR(13)+'DROP TABLE ['+SCHEMA_NAME(t.schema_id)+'].['+@Table+'];'+CHAR(13) 
								ELSE '' END -- CHAR(13) adds a carriage return				 
	FROM sys.tables t
	WHERE [name] = @Table
	AND temporal_type = 1

	-- End transaction
	SET @SqlStatement = @SqlStatement + @SqlEnd

	IF @Execute = 1
	BEGIN
		PRINT 'Executing start.....'
		EXEC sp_executesql @sqlstatement
		PRINT 'Executing end.....'
	END
	ELSE
	BEGIN
		PRINT @Sqlstatement
	END

	FETCH NEXT FROM delete_temporal_table INTO @Schema, @Table, @object_id, @SqlStart, @SqlEnd
END

CLOSE delete_temporal_table
DEALLOCATE delete_temporal_table

IF @@TRANCOUNT > 0 BEGIN ROLLBACK TRAN END

