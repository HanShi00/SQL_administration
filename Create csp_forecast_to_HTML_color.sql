CREATE PROCEDURE [dbo].[csp_forecast_to_HTML_color] (
	@temp_table_name NVARCHAR(255)
	, @table_header NVARCHAR(4000) = ''
	, @table_footer NVARCHAR(4000) = ''
	, @HTML_body NVARCHAR(max) OUTPUT
	)
AS
BEGIN
	-------------------------------------------------------------------------------------------------------------------------------
	-- Author:		Hans van den Berg
	-- Create date: 10-01-2014
	-- Derived:		csp_table_to_HTML; adjusted to colorize forecasting tables
	--
	-- Description:	Stored procedure die de opgegeven temp-tabel omzet in een HTML-tabel string. De HTML output van deze
	--				stored procedure kan gebruikt worden om de gegevens van een tabel via een HTML e-mail te versturen.
	--				Als er geen rows in de opgegeven temp-tabel zijn, is de output een lege string.
	--				Het inkleuren van de cellen is afhankelijk van de kolomnamen. De waardes in kolom met naam [+%]
	--				wordt vergeleken met de waarde in kolom [size_MB]. Als de eerstgenoemde waarde groter is dan de
	--				waarde in [size_MB]-5%, dan wordt de cel in de HTML string geel gekleurd. Als de waarde groter is
	--				dan de waarde in [size_MB], dan wordt de cel in de HTML string rood gekleurd.
	-------------------------------------------------------------------------------------------------------------------------------
	SET NOCOUNT ON

	DECLARE @SQL_cmd NVARCHAR(4000)
	DECLARE @rec_count INT

	-- Temporary table to hold output of dynamic SQL
	CREATE TABLE #output (
		row_nr INT identity(1, 1)
		, line NVARCHAR(4000)
		)

	-- Check the recordcount of the table
	SET @SQL_cmd = N'SELECT COUNT(1) FROM ' + @temp_table_name

	INSERT INTO #output
		EXEC sp_executesql @SQL_cmd

	SELECT @rec_count = line
	FROM #output

	TRUNCATE TABLE #output

	-- create a HTML string
	IF @rec_count > 0
	BEGIN
		-- Prepare the email header
		SET @HTML_body = '<html><body><font face="Arial" size="3">'

		-- add a header to the HTML
		IF ISNULL(@table_header, '') <> ''
		BEGIN
			SET @HTML_body = @HTML_body + '<p>' + @table_header + '</p>'
		END
		
		-- start the table definition
		SET @HTML_body = @HTML_body + '<p><table border="1"><tr>'

		-- Determine the table header by 'looping' through the columns from the temporary table (@temp_table_name)
		SELECT @HTML_body = @HTML_body + '<td><b>' + [name] + '</b></td>'
		FROM tempdb.sys.columns
		WHERE object_id = Object_Id('tempdb..' + @temp_table_name)

		SET @HTML_body = @HTML_body + '</tr>'
		
		-- create dynamic SQL to 'loop' through the table rows from the temporary table (@temp_table_name)
		SET @SQL_cmd = 'SELECT '

		-- expand the query-string with a CASE to determine the color for all columns that start with a '+' sign
		SELECT @SQL_cmd = @SQL_cmd
							+ CASE WHEN [name] like '+%'
								THEN ' ''<td style=''''background:''
										+ CASE WHEN [' + [name] + '] >= [size_MB] THEN ''red''
											WHEN [' + [name] + '] >= [size_MB] * 0.95 THEN ''Orange''
											ELSE ''white''
										END + ''''''>'''
								ELSE ' ''<td>'''
							END
							+ ' + ISNULL(CAST([' + [name] + '] AS NVARCHAR(MAX)),'''') + ''</td>'' +'
		FROM tempdb.sys.columns
		WHERE object_id = OBJECT_ID('tempdb..' + @temp_table_name)

		-- add the tablename to the dynamic SQL
		SET @SQL_cmd = @SQL_cmd + ' '''' FROM ' + @temp_table_name

		-- execute the dynamic SQL and put the partial HTML-strings into #output
		INSERT INTO #output
			EXEC sp_executesql @SQL_cmd

		-- Put the contents of #output into a single HTML
		SELECT @HTML_body = @HTML_body + '<tr>' + [line] + '</tr>'
		FROM #output
		ORDER BY row_nr

		TRUNCATE TABLE #output

		-- Close the HTML-table properly
		SET @HTML_body = @HTML_body + '</table></p>'

		-- add a footer to the HTML
		IF ISNULL(@table_footer, '') <> ''
		BEGIN
			SET @HTML_body = @HTML_body + '<p>' + @table_footer + '</p>'
		END

		-- Add an extra (empty) paragaph and close the body properly
		SET @HTML_body = @HTML_body + '<p> </p></font></body></html>'
	END

	DROP TABLE #output
END

GO
