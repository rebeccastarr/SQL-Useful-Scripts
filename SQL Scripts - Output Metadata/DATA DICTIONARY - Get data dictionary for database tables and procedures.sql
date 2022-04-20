DECLARE @TableName VARCHAR(200) = NULL /* provide the tablename in order to refine the results */
DECLARE @IgnoreSchemas TABLE (SchemaName VARCHAR(100))

INSERT INTO @IgnoreSchemas 
VALUES ('dbo'),('hst')/* temporal table to store changes/history records */

SELECT 
/* s.[name] AS [PhysicalSchema]
, tbl.[name] AS [PhysicalTable] */
  CONCAT(s.[name],'.',tbl.[name]) AS [PhysicalTable]
, CASE tbl.temporal_type
    WHEN 0 THEN 'No'
    WHEN 1 THEN 'Yes (history)'
    WHEN 2 THEN 'Yes (current)'
  END AS IsTemporal
, CASE col.is_nullable WHEN 0 THEN 'Null' ELSE 'Not Null' END AS [IsNullable]
/*, ix.is_primary_key, ix.is_unique_constraint, fk.constraint_object_id */
, COALESCE(CASE 
    WHEN ix.is_primary_key = 1 THEN 'PK'
    WHEN fk.constraint_object_id IS NOT NULL THEN CASE WHEN ix.is_unique_constraint = 1 THEN 'FK, UQ' ELSE 'FK' END
    WHEN ix.is_unique_constraint = 1 THEN 'UQ'
  END,'') AS [Constraints]
, CASE 
    WHEN reftbl.object_id IS NOT NULL THEN CONCAT(refs.[name],'.',reftbl.[name],' (',fkcol.[name],')') 
    ELSE ''
  END AS [FK Referenced Table (Column)]
, typ.name + CASE 
    WHEN CHARINDEX('char', typ.name) >= 1 THEN ' ('+
                                            CASE WHEN col.max_length = -1 THEN 'max' 
                                                 ELSE CAST(col.max_length AS VARCHAR(100)) 
                                            END + ')'
    ELSE '' 
  END
  AS [Data Type]
/*, CASE 
    WHEN CHARINDEX('char', typ.name) >= 1 THEN CASE WHEN col.max_length = -1 THEN 'max' ELSE CAST(col.max_length AS VARCHAR(100)) END
    ELSE '' 
  END  AS [Max Length]*/
, col.name AS [PhysicalField]
FROM sys.tables tbl
JOIN sys.schemas s                   ON s.schema_id = tbl.schema_id
JOIN sys.columns col                 ON col.object_id = tbl.object_id
JOIN sys.types typ                   ON typ.user_type_id = col.user_type_id
LEFT JOIN sys.index_columns ixc      ON ixc.object_id = col.object_id AND ixc.column_id = col.column_id
LEFT JOIN sys.indexes ix             ON ix.object_id = ixc.object_id AND ix.index_id = ixc.index_id
LEFT JOIN sys.foreign_key_columns fk ON fk.parent_object_id = col.object_id AND fk.parent_column_id = col.column_id
LEFT JOIN sys.columns fkcol          ON fk.referenced_object_id = fkcol.object_id AND fk.referenced_column_id = fkcol.column_id
LEFT JOIN sys.tables reftbl          ON reftbl.object_id = fkcol.object_id
LEFT JOIN sys.schemas refs           ON refs.schema_id = reftbl.schema_id
WHERE 
    s.name NOT IN (SELECT SchemaName FROM @IgnoreSchemas) /* Ignore the history tables in hst schema and any other template tables in dbo */
AND (tbl.[name] = @TableName OR @TableName IS NULL)
ORDER BY 
  s.[name]
, tbl.[name]
, col.column_id

/* Obtain a list of the procedures and their input parameters */
SELECT 
/*  s.[name] AS [Schema]
, obj.[name] AS [ObjectName]*/
  CASE p.parameter_id
    WHEN 1 THEN CONCAT(s.[name],'.',obj.[name]) 
    ELSE ''
  END AS [ObjectName]
/*, CASE obj.[Type_Desc] 
    WHEN 'SQL_STORED_PROCEDURE' THEN 'SP'
    ELSE 'UDF'
  END AS [ObjectType (UDF/SP)]
*/
, p.parameter_id AS [ParameterID]
, p.name AS [ParameterName]
/*, typ.name AS [ParameterDataType]*/
, typ.name + CASE 
    WHEN CHARINDEX('char', typ.name) >= 1 THEN ' ('+
                                            CASE WHEN p.max_length = -1 THEN 'max' 
                                                 ELSE CAST(p.max_length AS VARCHAR(100)) 
                                            END + ')'
    ELSE '' 
  END
  AS [ParameterDataType]
/*, CASE 
    WHEN CHARINDEX('char', typ.name) >= 1 THEN CASE WHEN p.max_length = -1 THEN 'max' ELSE CAST(p.max_length AS VARCHAR(100)) END
    ELSE '' 
  END  AS [Max Length]*/
, CASE p.is_nullable WHEN 0 THEN 'Null' ELSE 'Not Null' END AS [IsNullable]
, CASE p.is_output
    WHEN 1 THEN 'Yes'
    ELSE ''
  END AS [OutPutParam]
FROM sys.objects obj
JOIN sys.schemas s ON s.schema_id = obj.schema_id
JOIN sys.parameters AS p ON obj.OBJECT_ID = p.OBJECT_ID
JOIN sys.types typ ON typ.user_type_id = p.user_type_id
WHERE obj.[Type_Desc] = 'SQL_STORED_PROCEDURE'
/*AND s.name NOT IN (SELECT SchemaName FROM @IgnoreSchemas)*/
ORDER BY s.[name], obj.name, p.parameter_id
GO
