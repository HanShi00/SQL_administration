EXEC sys.sp_configure N'show advanced options', N'1'
RECONFIGURE WITH OVERRIDE
EXEC sys.sp_configure N'Database Mail XPs', N'1'
RECONFIGURE
EXEC sys.sp_configure N'show advanced options', N'0'
RECONFIGURE WITH OVERRIDE


USE [master]
EXEC msdb.dbo.sysmail_add_account_sp @account_name=N'HB_DBA'
									, @email_address=N'hb_dba@live.nl', @mailserver_name=N'smtp.live.com', @port=587
									, @username=N'hb_dba@live.nl', @password=N'#######'
									, @use_default_credentials=0, @enable_ssl=1
EXEC msdb.dbo.sysmail_add_profile_sp @profile_name=N'HB_DBA_Profile'
EXEC msdb.dbo.sysmail_add_profileaccount_sp @profile_name=N'HB_DBA_Profile', @account_name=N'HB_DBA', @sequence_number=1
EXEC msdb.dbo.sysmail_delete_principalprofile_sp @principal_name=N'guest', @profile_name=N'HB_DBA_Profile'
EXEC msdb.dbo.sysmail_add_principalprofile_sp @principal_name=N'guest', @profile_name=N'HB_DBA_Profile', @is_default=1
