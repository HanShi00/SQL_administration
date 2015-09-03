;WITH CTE_Last_backup_list AS
	(
	SELECT
		Last_backup.database_name
		, Last_backup.type
		, Last_backup.last_backup_date
		, media_set_id
	FROM msdb.dbo.backupset
	INNER JOIN
			(SELECT
				backupset.database_name
				, type
				, max(backupset.backup_finish_date) as last_backup_date
			FROM msdb..backupset
			group by
				backupset.database_name
				, type
			) Last_backup
		ON backupset.database_name = Last_backup.database_name
		AND backupset.type = Last_backup.type
		AND backupset.backup_finish_date = Last_backup.last_backup_date
	)
	
SELECT db.NAME as Database_name
	, db.recovery_model_desc as Recovery_Model
	, bs_full.last_backup_date as last_FULL_backup
	, media_full.physical_device_name as FULL_backup_file
	, bs_log.last_backup_date as last_LOG_backup
	, media_log.physical_device_name as LOG_backup_file
FROM sys.databases db
	LEFT OUTER JOIN CTE_Last_backup_list as bs_full
		ON db.name = bs_full.database_name
		AND bs_full.type = 'D'
	LEFT OUTER JOIN msdb.dbo.backupmediafamily media_full
		ON bs_full.media_set_id = media_full.media_set_id
	LEFT OUTER JOIN CTE_Last_backup_list as bs_log
		ON db.name = bs_log.database_name
		AND bs_log.type = 'L'
	LEFT OUTER JOIN msdb.dbo.backupmediafamily media_log
		ON bs_log.media_set_id = media_log.media_set_id
