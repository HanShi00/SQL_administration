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

set @FileName = 'full_path_and_filename'
set @ExecuteRestore = 0				-- 0 = print restore commando / 1 = print en execute restore commando
set @Restore = 'INVULLEN'			-- RECOVERY, NORECOVERY, STANDBY
set @OverruledDatabaseName = NULL	-- ALLEEN invullen indien de restore over een database met andere naam heen gezet moet worden

declare @Statement varchar(500)
declare @DatabaseName varchar(150)
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
	create table #header (header varchar(500))
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
							, IsPresent bit)

	if object_id('tempdb..#backupinfo') is not null
		drop table #backupinfo
	create table #backupinfo (DatabaseName varchar(50)
							, LogicalName varchar(75)
							, PhysicalName varchar(500)
							, Type char(1)
							)

	set nocount on

	-- determine if backup consists of multiple files
	SET @Statement = N'dir /B ' + left(@FileName, len(@FileName)-7) + '*.sqb'
	insert into #backupfiles EXEC master.dbo.xp_cmdshell @Statement
	if exists(select backupfile from #backupfiles where backupfile = 'The system cannot find the path specified.' or backupfile = 'File Not Found')
	begin
		select @RestoreCommand = backupfile from #backupfiles where backupfile = 'The system cannot find the path specified.' or backupfile = 'File Not Found'
		print @RestoreCommand
	end
	else
	begin
		------------------------------
		--Ophalen Regdate SQL backup Password.
		if cast(SERVERPROPERTY('ProductVersion') as char(2)) = '8.'
			SET @Password = '123 Sql2000'
		else
			SELECT @Password =  dbsdbamonitordatabase.dbo.fn_Mon_GetBackupPassword(1)  --1 geeft het CurrentPassword terug.

		IF ISNULL(@Password,'') = ''
		BEGIN
			RAISERROR ('Geen wachtwoord voor de backup gevonden.', 16, 1)
		END
		-------------------------------------

		-- check results from DIR command
		if exists(select backupfile from #backupfiles where backupfile like '%.sqb')
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
		SET @Statement = N'-SQL "RESTORE SQBHEADERONLY FROM DISK = ' + char(39) + @FileName + char(39) + ' WITH PASSWORD = ''' + @Password + ''', SINGLERESULTSET"'
		--EXEC master..sqlbackup @Statement
		insert into #header EXEC master..sqlbackup @Statement

		-- check if read header is succesfull
		if exists(select header from #header where header like 'SQL Backup exit code%')
		begin
			-- display results of header if exit code (means failure) is found
			select header from #header
		end
		else
		begin
			-- read backupfile for info about files
			SET @Statement = N'-SQL "RESTORE FILELISTONLY FROM DISK = ' + char(39) + @FileName + char(39) + ' WITH PASSWORD = ''' + @Password + ''' "'  
			--EXEC master..sqlbackup @Statement
			if cast(SERVERPROPERTY('ProductVersion') as char(2)) = '8.'
				-- op SQL2000 worden minder kolommen als resultaat gegeven
				insert into #filelist (LogicalName, PhysicalName, Type, FileGroupName, Size, MaxSize) EXEC master..sqlbackup @Statement
			else
				insert into #filelist EXEC master..sqlbackup @Statement
			
			-- save relevant information from backupfile to temporary table
			insert into #backupinfo
			select
				replace(replace(header, 'Database name     : ', ''), 'Database name       : ', '') as DatabaseName
				, LogicalName
				, PhysicalName
				, Type
			from
				#header cross join #filelist
			where
				header like 'Database name%'

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
				select @StandbyPath = parameter_waarde
				from dbsdbamonitordatabase.dbo.mon_parameter
				where parameter_name = 'Standby file directory'
				-- change standbyfolder if it has no value
				select @StandbyPath = COALESCE(@StandbyPath, '{standby_path}')
			end

			-- generate start of the restore command
			select @RestoreCommand = 'EXECUTE master..sqlbackup ''-SQL "RESTORE DATABASE [' + @DatabaseName + '] FROM '
			-- add backup files to the restore command
			select @RestoreCommand = @RestoreCommand + char(10) + char(9) + 
									'DISK = ' + char(39) + char(39) + backupfile + char(39) + char(39) + ','
			from #backupfiles
			where backupfile like '%.sqb'
			order by backupfile

			-- remove comma after last backupfile and add several options
			select @RestoreCommand = left(@RestoreCommand, len(@RestoreCommand)-1) +
									char(10) + 'WITH PASSWORD = ''''' + @Password + ''''', ' +
									case when @Restore = 'STANDBY'
										then
											char(10) + 'STANDBY = ''''' + REPLACE(@StandbyPath + '\Undo_', '\\', '\') + @DatabaseName + '.dat'''', '
										else
											@Restore + ', '
									end
			if cast(SERVERPROPERTY('ProductVersion') as char(2)) <> '8.'
			BEGIN
				-- add data files to the restore command
				select @RestoreCommand = @RestoreCommand + char(10) + char(9) + 
										'MOVE ' + char(39) + char(39) + LogicalName + char(39) + char(39) +
										' TO ' + char(39) + char(39) + 
											COALESCE(af.filename, 
																CASE Type 
																	WHEN 'D' THEN @DefaultDataLocation + right(PhysicalName, charindex('\', reverse(PhysicalName))-1)
																	WHEN 'F' THEN @DefaultDataLocation + right(PhysicalName, charindex('\', reverse(PhysicalName))-1)
																	WHEN 'L' THEN @DefaultLogLocation + right(PhysicalName, charindex('\', reverse(PhysicalName))-1)
																END) + char(39) + char(39) + ','
				from
					msdb.sys.sysaltfiles af inner join master.sys.databases db
						on af.dbid = db.database_id
						and db.name = @DatabaseName
					right outer join #backupinfo bi
						on db.name = @DatabaseName
						and af.name = bi.LogicalName
			END
			else
			BEGIN
				-- add data files to the restore command with dynamic SQL (required for SQL2000 sysfiles table)
				declare @DynamicSQL nvarchar(4000)
				declare @ParamDefinition nvarchar(500)
				declare @RestoreOut nvarchar(4000)
				
				set @ParamDefinition = N'@BuildRestore varchar(4000)
										, @DefaultDataLocation varchar(512)
										, @DefaultLogLocation varchar(512)
										, @RestoreOut varchar(4000) OUTPUT'
				set @DynamicSQL =
					'select @BuildRestore = @BuildRestore + char(10) + char(9) + 
											''MOVE '' + char(39) + char(39) + rtrim(LogicalName) + char(39) + char(39) +
											'' TO '' + char(39) + char(39) + 
												COALESCE(af.filename, 
																	CASE Type 
																		WHEN ''D'' THEN @DefaultDataLocation + right(PhysicalName, charindex(''\'', reverse(PhysicalName))-1)
																		WHEN ''F'' THEN @DefaultDataLocation + right(PhysicalName, charindex(''\'', reverse(PhysicalName))-1)
																		WHEN ''L'' THEN @DefaultLogLocation + right(PhysicalName, charindex(''\'', reverse(PhysicalName))-1)
																	END) + char(39) + char(39) + '',''
					from
						[' + @DatabaseName + ']..sysfiles af
						right outer join #backupinfo bi
							on af.name = bi.LogicalName
					set @RestoreOut = @BuildRestore'
				
				exec sp_executesql @DynamicSQL, @ParamDefinition
									, @DefaultDataLocation = @DefaultDataLocation, @DefaultLogLocation = @DefaultLogLocation
									, @BuildRestore = @RestoreCommand, @RestoreOut = @RestoreCommand OUTPUT
			END
			-- add final options to the restore command
			if not exists(select name from master..sysdatabases where name = @DatabaseName)
			begin
				-- do not use the REPLACE option if database doesn't exist
				select @RestoreCommand = @RestoreCommand + char(10) + 'ORPHAN_CHECK"'''
			end
			else
			begin
				-- only use the REPLACE option if database does exist
				select @RestoreCommand = @RestoreCommand + char(10) + 'REPLACE, ORPHAN_CHECK"'''
			end

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