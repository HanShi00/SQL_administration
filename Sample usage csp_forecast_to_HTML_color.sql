if object_id('tempdb..#forecast') is not null
	drop table #forecast

create table #forecast (
	Hostname SYSNAME
	, instancename SYSNAME
	, dbname SYSNAME
	, size_MB DECIMAL(18, 2)
	, [-12 mnd] DECIMAL(18, 2)
	, [-11 mnd] DECIMAL(18, 2)
	, [-10 mnd] DECIMAL(18, 2)
	, [-9 mnd] DECIMAL(18, 2)
	, [-8 mnd] DECIMAL(18, 2)
	, [-7 mnd] DECIMAL(18, 2)
	, [-6 mnd] DECIMAL(18, 2)
	, [-5 mnd] DECIMAL(18, 2)
	, [-4 mnd] DECIMAL(18, 2)
	, [-3 mnd] DECIMAL(18, 2)
	, [-2 mnd] DECIMAL(18, 2)
	, [-1 mnd] DECIMAL(18, 2)
	, [0 mnd] DECIMAL(18, 2)
	, [+1 mnd] DECIMAL(18, 2)
	, [+2 mnd] DECIMAL(18, 2)
	, [+3 mnd] DECIMAL(18, 2)
	, [+4 mnd] DECIMAL(18, 2)
	, [+5 mnd] DECIMAL(18, 2)
	, [+6 mnd] DECIMAL(18, 2)
	)

declare @HTML nvarchar(max)
declare @Color nvarchar(8)
set @Color = 'Orange'

insert into #forecast
	EXECUTE [csp_rpt_database_size_forecast] 

exec dbo.csp_forecast_to_HTML_color
	#forecast
	, ''
	, ''
	, @HTML OUTPUT

select @html as [copy_paste_to_HTML_file_and_open_in_browser]

if object_id('tempdb..#forecast') is not null
	drop table #forecast
