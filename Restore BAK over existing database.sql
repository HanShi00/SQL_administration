/*******************************************************************************************************/
/****                                                                                              *****/
/****         Restore een backup over een bestaande database (met dezelfde naam) op een andere     *****/
/****         instance. Dit script bepaalt de logische namen uit de backupfile en vergelijkt       *****/
/****         deze met de datafiles van de bestaande database. De folder locaties van de           *****/
/****         bestaande database worden gebruikt in het restore commando. Eventuele extra files    *****/
/****         worden op de SQL default data- c.q. log-locatie geplaatst.                           *****/
/****                                                                                              *****/
/****         - Eventuele meerdere backupfiles worden m.b.v. DIR commando opgehaald.               *****/
/****         - Je kan opgeven of de database in RECOVERY, NORECOVERY of STANDBY moet komen.       *****/
/****         - Je kan opgeven of het commando alleen geprint of ook uitgevoerd moet worden.       *****/
/****                                                                                              *****/
/*******************************************************************************************************/

declare @FileName varchar(250)
declare @ExecuteRestore bit
declare @Restore varchar(10)
declare @OverruledDatabaseName varchar(50)

set @FileName = 'full_file_path'
set @ExecuteRestore = 0				-- 0 = print restore commando / 1 = print en execute restore commando
set @Restore = 'INVULLEN'			-- RECOVERY, NORECOVERY, STANDBY
set @OverruledDatabaseName = NULL	-- ALLEEN invullen indien de restore over een database met andere naam heen gezet moet worden

declare @Extention nvarchar(6)
declare @Statement nvarchar(500)
declare @DatabaseName varchar(150)
declare @backup_count tinyint
declare @DefaultDataLocation varchar(512)
declare @DefaultLogLocation varchar(512)
declare @Password varchar(100)
declare @StandbyPath varchar(100)
declare @RestoreCommand nvarchar(MAX)	-- wijzig eventueel naar nvarchar(8000) voor SQL2000

if UPPER(@Restore) not in ('RECOVERY', 'NORECOVERY', 'STANDBY')
begin
	print 'De variable @Restore moet ingevuld worden met de gewenste restore-status.'
end
else
begin
	-- create temporary objects
	if object_id('tempdb..#backupfiles') is not null
		drop table #backupfiles
	create table #backupfiles (backupfile varchar(500))
	if object_id('tempdb..#header') is not null
		drop table #header
	create table #header	(BackupName nvarchar(128)
							, BackupDescription nvarchar(255)
							, BackupType tinyint
							, ExperationDate datetime
							, Compressed bit
							, Position tinyint
							, DeviceType tinyint
							, UserName nvarchar(128)
							, ServerName nvarchar(128)
							, DatabaseName nvarchar(128)
							, DatabaseVersion int
							, DatabaseCreationDate datetime
							, BackupSize numeric(20,0)
							, FirstLSN numeric(25,0)
							, LastLSN numeric(25,0)
							, CheckpointLSN numeric(25,0)
							, DatabaseBackupLSN numeric(25,0)
							, BackupStartDate datetime
							, BackupFinishDate datetime
							, SortOrder tinyint
							, CodePage tinyint
							, UnicodeLocaleId int
							, UnicodeComparisonStyle int
							, CompatibilityLevel tinyint
							, SoftwareVendorId int
							, SoftwareVersionMajor int
							, SoftwareVersionMinor int
							, SoftwareVersionBuild int
							, MachineName nvarchar(128)
							, Flags int
							, BindingID uniqueidentifier
							, RecoveryForkID uniqueidentifier
							, Collation nvarchar(128)
							, FamilyGUID uniqueidentifier
							, HasBulkloggedData bit
							, IsSnapshot bit
							, IsReadOnly bit
							, IsSingleUser bit
							, HasBackupChecksums bit
							, IsDamaged bit
							, BeginsLogChain bit
							, HasIncompeteMetaData bit
							, IsForceOffline bit
							, IsCopyOnly bit
							, FirstRecoveryForkID uniqueidentifier
							, ForkPointLSN numeric(25,0)
							, RecoveryModel nvarchar(60)
							, DifferentialBaseLSN numeric (25,0)
							, DifferentialBaseGUID uniqueidentifier
							, BackupTypeDescription nvarchar(60)
							, BackupSetGUID uniqueidentifier
							, CompressedBackupSize int)
	if object_id('tempdb..#filelist') is not null
		drop table #filelist
	create table #filelist (LogicalName varchar(128)
							, PhysicalName varchar(260)
							, Type char(1)
							, FilegroupName varchar(128)
							, Size numeric(20,0)
							, MaxSize numeric(20,0)
							, FileID bigint
							, CreateLSN numeric(25,0)
							, DropLSN numeric(25,0)
							, UniqueID varchar(100)
							, ReadOnlyLSN numeric(25,0)
							, ReadWriteLSN numeric(25,0)
							, BackupSizeInBytes bigint
							, SourceBlockSize int
							, FileGroupID int
							, LogGroupGUID varchar(100)
							, DifferentialBaseLSN numeric(25,0)
							, DifferentialBaseGUID varchar(100)
							, IsReadOnly bit
							, IsPresent bit
							, TDEThumbprint varbinary(32))
	if object_id('tempdb..#backupinfo') is not null
		drop table #backupinfo
	create table #backupinfo (DatabaseName varchar(50)
							, LogicalName varchar(75)
							, PhysicalName varchar(500)
							, Type char(1)
							, Position tinyint
							)

	set nocount on
	
	-- determine the extension of the backup file (most common: .sqb, .bak, none)
	if charindex('.', @FileName) > 0
		set @Extention = reverse(left(reverse(@Filename), charindex('.', reverse(@FileName))))
	else
		set @Extention = ''

	-- read the current settings for xp_cmdshell
	declare @value_advanced_options bit
	declare @value_xp_cmdshell bit
	select @value_advanced_options=convert(bit, value_in_use) from master.sys.configurations where name = 'show advanced options'
	select @value_xp_cmdshell=convert(bit, value_in_use) from master.sys.configurations where name = 'xp_cmdshell'
	-- temporary enable xp_cmdshell to read contents of folder
	if @value_xp_cmdshell = 0
	begin 
		print '/*'
		exec sp_configure 'show advanced options', 1
		reconfigure
		exec sp_configure 'xp_cmdshell', 1
		reconfigure
	end
	-- determine if backup consists of multiple files
	SET @Statement = N'dir /B "' + left(@FileName, len(@FileName)-7)
					+ '*' + @Extention + '"'
	insert into #backupfiles EXEC master.dbo.xp_cmdshell @Statement
	-- disable the setting xp_cmdshell (if this setting was initially disabled)
	if @value_xp_cmdshell = 0
	begin 
		exec sp_configure 'xp_cmdshell', @value_xp_cmdshell
		reconfigure
		exec sp_configure 'show advanced options', @value_advanced_options
		reconfigure
		print '*/'
	end
	
	if exists(select backupfile from #backupfiles where backupfile = 'The system cannot find the path specified.' or backupfile = 'File Not Found')
	begin
		select @RestoreCommand = backupfile from #backupfiles where backupfile = 'The system cannot find the path specified.' or backupfile = 'File Not Found'
		print @RestoreCommand
	end
	else
	begin

		-- check results from DIR command
		if exists(select backupfile from #backupfiles where backupfile like '%' + @Extention)
		begin
			-- add path to the filenames resolved from the DIR command
			update #backupfiles set backupfile = left(@FileName, len(@FileName) - charindex('\', reverse(@FileName)) + 1) + backupfile
		end
		else
		begin
			-- clear results from DIR command and insert variable into table
			truncate table #backupfiles
			insert #backupfiles (backupfile) values (@FileName)
		end

		-- read backupfile for info about database
		SET @Statement = N'RESTORE HEADERONLY FROM DISK = ' + char(39) + @FileName + char(39) + ' WITH NOUNLOAD'
		--EXEC @Statement
		insert into #header EXEC sp_executesql @Statement
		-- check if read header is succesfull
		if (select top 1 IsDamaged from #header order by IsDamaged desc) = 1
		begin
			-- display results of header if exit code (means failure) is found
			select * from #header
		end
		else
		begin
			-- read backupfile for info about files
			SET @Statement = N'RESTORE FILELISTONLY FROM DISK = ' + char(39) + @FileName + char(39) + ' WITH NOUNLOAD'  
			--EXEC @Statement
			if cast(SERVERPROPERTY('ProductVersion') as char(2)) = '9.'
				-- op SQL2005 heeft één kolom (TDEThumbprint) minder als resultaat
				insert into #filelist (LogicalName, PhysicalName, Type, FileGroupName, Size, MaxSize, FileID
									, CreateLSN, DropLSN, UniqueID, ReadOnlyLSN, ReadWriteLSN, BackupSizeInBytes
									, SourceBlockSize, FileGroupID, LogGroupGUID, DifferentialBaseLSN
									, DifferentialBaseGUID, IsReadOnly, IsPresent)
					EXEC (@Statement)
			else
				insert into #filelist
					EXEC (@Statement)
			
			-- save relevant information from backupfile to temporary table
			insert into #backupinfo
			select
				DatabaseName
				, LogicalName
				, PhysicalName
				, Type
				, Position
			from
				#header cross join #filelist

			-- save database name in variable
			select top 1
				@DatabaseName = DatabaseName
			from
				#backupinfo
			-- overrule gevonden database naam met opgegeven naam
			if @OverruledDatabaseName IS NOT NULL
				select @DatabaseName = @OverruledDatabaseName
			
			if not exists(select name from master..sysdatabases where name = @DatabaseName)
			begin
				-- inform user about missing database
				print '/********************************************************************/'
				print '-- Er bestaat geen database met naam [' + @DatabaseName + '] op deze instance.'
				print '-- Alle database files worden op de DEFAULT locatie gelaatst.'
				print '/********************************************************************/'
				print ''
			end

			exec master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'DefaultData', @DefaultDataLocation OUTPUT 
			if right(@DefaultDataLocation, 1) <> '\'
				set @DefaultDataLocation = @DefaultDataLocation + '\'
			-- get default location for log files
			exec master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'DefaultLog', @DefaultLogLocation OUTPUT
			if right(@DefaultLogLocation, 1) <> '\'
				set @DefaultLogLocation = @DefaultLogLocation + '\'

			if @Restore = 'STANDBY'
			begin
				-- change standbyfolder if it has no value (default to LOG location)
				select @StandbyPath = COALESCE(@StandbyPath, @DefaultLogLocation)
			end

			-- process each backup from within the file (there could be multiple backups present in a single dumpdevice)
			SELECT @backup_count = MIN(position), @RestoreCommand = '' FROM #backupinfo
			WHILE @backup_count <= (select MAX(position) FROM #backupinfo)
			BEGIN
				-- generate start of the restore command
				select @RestoreCommand = @RestoreCommand + char(10) + char(10)
				select @RestoreCommand = @RestoreCommand + 'RESTORE DATABASE [' + @DatabaseName + '] FROM '
				-- add backup files to the restore command
				select @RestoreCommand = @RestoreCommand + char(10) + char(9) + 
										'DISK = ' + char(39) + backupfile + char(39) + ','
				from #backupfiles
				where backupfile like '%' + @Extention
				order by backupfile

				-- remove comma after last backupfile and prepare for adding options
				select @RestoreCommand = left(@RestoreCommand, len(@RestoreCommand)-1) +
										char(10) + 'WITH '
				-- add data files to the restore command
				select @RestoreCommand = @RestoreCommand + char(10) + char(9)
											+ 'MOVE ' + char(39) + rtrim(bi.LogicalName) + char(39)
											+ ' TO ' + char(39)
											+ COALESCE(mf.physical_name, 
															CASE bi.type 
																WHEN 'D' THEN coalesce(@DefaultDataLocation, '') + right(bi.PhysicalName, charindex('\', reverse(bi.PhysicalName))-1)
																WHEN 'F' THEN coalesce(@DefaultDataLocation, '') + right(bi.PhysicalName, charindex('\', reverse(bi.PhysicalName))-1)
																WHEN 'L' THEN coalesce(@DefaultLogLocation, '') + right(bi.PhysicalName, charindex('\', reverse(bi.PhysicalName))-1)
															END) + char(39) + ','
				from master.sys.master_files mf
					right outer join #backupinfo bi
						on mf.name = bi.LogicalName
				where
					coalesce(db_id(@DatabaseName), 0) = coalesce(database_id, 0)
					and coalesce(@backup_count, 0) = coalesce(position, 0)

				-- add final options to the restore command
				select @RestoreCommand = @RestoreCommand
										+ char(10) + 'FILE = ' + CONVERT(nvarchar(2), @backup_count)
										+ case when @Restore = 'STANDBY'
											then
												char(10) + ', STANDBY = ''' + REPLACE(@StandbyPath + '\Undo_', '\\', '\') + @DatabaseName + '.dat'' '
											else
												-- when not STANDBY then always NORECOVERY (optional RECOVERY will be set as final command)
												char(10) + ', NORECOVERY'
										end
										+ case when exists(select name from master..sysdatabases where name = @DatabaseName)
											then char(10) + ', REPLACE'
											else ''
										end
				SET @backup_count = @backup_count + 1
			END
			SELECT @RestoreCommand = @RestoreCommand
									+ CASE WHEN @Restore = 'RECOVERY'
										-- set database to RECOVERY
										THEN char(10) + char(10) + 'RESTORE DATABASE [' + @DatabaseName + '] WITH RECOVERY'
										-- leave database as-is (in NORECOVERY or STANDBY)
										ELSE ''
									END
			-- print or execute the generated command
			if @ExecuteRestore = 1
			begin
				print @RestoreCommand
				exec sp_executesql @RestoreCommand
			end
			else
				print @RestoreCommand

		end
	end

	set nocount off
	-- clean up temporary objects
	if object_id('tempdb..#backupfiles') is not null
		drop table #backupfiles
	if object_id('tempdb..#header') is not null
		drop table #header
	if object_id('tempdb..#filelist') is not null
		drop table #filelist
	if object_id('tempdb..#backupinfo') is not null
		drop table #backupinfo
end