/*
Date: 16/05/2022
Purpose: Creating full-text indexes and trying to understand what word-breakers exist for a language:

•	Word-breakers – Characters that are used to identify word boundaries and break up words to be indexed (for example, -, ‘ ‘, @)
•	Stemmers - Conjugate verbs (running, ran, run, runner)
•	Stopwords – Words that are discarded from the index as they don’t help a search (and, is, a, an, on, ….etc) 
(There is a list of 154 words in the system default for 1033/2057)

https://stuart-moore.com/generating-a-list-of-full-text-word-breakers-for-sql-server/
This T-SQL loops through all the 255 ASCII characters. For each one we’re going to use it to join 2 ‘words’, and then 
run the string through sys.dm_fts_parser. If the function returns more than 1 row we now that it’s found a word breaker, 
so we then output the character, and the character code as not all the characters are printable. You’ll also notice that 
code 34 throws an error, that’s because it’s ” which is a reserved character within full Text searches.
*/
DECLARE @i INTEGER
DECLARE @count INTEGER

SET @i = 32

WHILE @i <= 255
BEGIN
	SET @count = 0
	SELECT @count = COUNT(1) FROM sys.dm_fts_parser ('"word1'+CHAR(@i)+'word2"', 1033, 0, 0)

	IF @count > 1
	BEGIN
		PRINT CONCAT('ASCII ', @i, ': ', CHAR(@i))
	END

	SET @i=@i+1
END