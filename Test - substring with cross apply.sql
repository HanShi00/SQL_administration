if object_id('tempdb..#test') is not null
	drop table #test

create table #test (value nvarchar(500))

insert into #test (value)
	values ('Tel: +44 (0)1234 566788;Email: abc@mail.com')
		, ('Alternate text;T: +56 (0)1234 4444;E: -;w:http://www.yahoo.com/faqs;')
		, ('Admissions dummy text;T: +44 (0)1234 4444;E: xyz@co.uk;w:http://www.yahoo.com/faqs;')
		, ('dummy text;dummy text;Tel: +123 32323 33;Email: test@address.com;')

-- get e-mail address from string
select
	substring(value
				-- determine start_position (temporarily replace spaces for semi_columns)
				, len(value)
					- charindex(';', reverse(replace(value, ' ', ';')), charindex('@', reverse(value)))
					+ 2
				-- determine end_position and substract start_position (same as above)
				, charindex(';', value + ';', charindex('@', value))
					- (len(value)
					- charindex(';', reverse(replace(value, ' ', ';')), charindex('@', reverse(value)))
					+ 2
					)
			)
from #test
where charindex('@', value) > 0

-- get e-mail address from string using CROSS APPLY
select
	value
	, substring(value, start_pos, end_pos-start_pos) as mail_address
	, start_pos
	, end_pos
from #test
	cross apply (select
					replace(value, ' ', ';'), reverse(replace(value, ' ', ';'))
				) as changed_value(value_new, reversed_new)
	cross apply (select
					charindex('@', value)
					, len(value) - charindex(';', reversed_new, charindex('@', reversed_new))	+ 2
					, charindex(';', value_new + ';', charindex('@', value))
				) as position(at_pos, start_pos, end_pos)
where position.at_pos > 0
