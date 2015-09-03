declare @ThisDate datetime;
set @ThisDate = getdate();  

-- the 0 in the below statements represent the 'default' date 1900-01-01
select
	dateadd(dd, datediff(dd, 0, @ThisDate), 0)		 as 'Beginning of this day'
	, dateadd(dd, datediff(dd, 0, @ThisDate) + 1, 0) as 'Beginning of next day'
	, dateadd(dd, datediff(dd, 0, @ThisDate) - 1, 0) as 'Beginning of previous day'
	, dateadd(wk, datediff(wk, 0, @ThisDate), 0)     as 'Beginning of this week (Monday)'
	, dateadd(wk, datediff(wk, 0, @ThisDate) + 1, 0) as 'Beginning of next week (Monday)'
	, dateadd(wk, datediff(wk, 0, @ThisDate) - 1, 0) as 'Beginning of previous week (Monday)'
	, dateadd(mm, datediff(mm, 0, @ThisDate), 0)     as 'Beginning of this month'
	, dateadd(mm, datediff(mm, 0, @ThisDate) + 1, 0) as 'Beginning of next month'
	, dateadd(mm, datediff(mm, 0, @ThisDate) - 1, 0) as 'Beginning of previous month'
	, dateadd(qq, datediff(qq, 0, @ThisDate), 0)     as 'Beginning of this quarter (Calendar)'
	, dateadd(qq, datediff(qq, 0, @ThisDate) + 1, 0) as 'Beginning of next quarter (Calendar)'
	, dateadd(qq, datediff(qq, 0, @ThisDate) - 1, 0) as 'Beginning of previous quarter (Calendar)'
	, dateadd(yy, datediff(yy, 0, @ThisDate), 0)     as 'Beginning of this year'
	, dateadd(yy, datediff(yy, 0, @ThisDate) + 1, 0) as 'Beginning of next year'
	, dateadd(yy, datediff(yy, 0, @ThisDate) - 1, 0) as 'Beginning of previous year'
