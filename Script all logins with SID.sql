
select
	sp.name
	, sp.type_desc
	, 'CREATE LOGIN [' + sp.name + '] '
		+ case when sp.type in ('U', 'G')
			then 'FROM WINDOWS '
			else ''
		end
		+ 'WITH '
		+ case when sl.password_hash IS NOT NULL
			then 'PASSWORD = ' + convert(nvarchar(max), password_hash, 1) + ' HASHED ' 
			else ''
		end
		+ 'DEFAULT_DATABASE = [' + ISNULL(sp.default_database_name, 'master') + '], '
		+ ISNULL('DEFAULT_LANGUAGE = [' + sp.default_language_name + '] ', '')
		+ 'CHECK_EXPIRATION = ' + case is_expiration_checked when 0 then 'OFF ' else 'ON ' END
		+ 'CHECK_POLICY = ' + case is_policy_checked when 0 then 'OFF ' else 'ON ' END
		+ 'SID = ' + convert(nvarchar(max), sp.sid, 1)
		+ case when sp.is_disabled = 'TRUE'
			then ';ALTER LOGIN [' + sp.name + '] DISABLE'
			else ''
		end
	as create_stmt
from master.sys.server_principals sp		-- get all logins from [server_principals]
left outer join master.sys.sql_logins sl	-- and get some additional information from [sql_logins]
	on sp.principal_id = sl.principal_id
	and sp.type = sl.type
where
	sp.name <> 'sa'					-- don't create 'sa' account
	and sp.name not like '##%##'	-- don't create logins for internal use only
	and sp.name not in ('public'	-- don't create default server roles
						, 'sysadmin'
						, 'securityadmin'
						, 'serveradmin'
						, 'setupadmin'
						, 'processadmin'
						, 'diskadmin'
						, 'dbcreator'
						, 'bulkadmin'
						)
order by sp.name