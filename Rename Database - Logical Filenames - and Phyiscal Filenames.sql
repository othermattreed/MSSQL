/* Rename Database, Logical Filenames, & Phyiscal Filenames */




/*********************************************************************************************
==============================================================================================


!!!!!!!!!!Make sure to change the SET variable strings commented with /*** ***/!!!!!!!!!!

Credit: I got the idea & steps from: 
https://www.mssqltips.com/sqlservertip/1891/steps-to-rename-a-sql-server-database/ ;  I just 
rolled it all into one with a safety net backup & error checking. Any other snippets I run
across from elsewhere I'll add when I notice them.


==============================================================================================
*********************************************************************************************/


USE [master]

DECLARE @DBName					nvarchar(128); -- Current database name
DECLARE @NewDBName				nvarchar(128); -- New database name
DECLARE @BackupFullFileString	nvarchar(max); -- Backup full filepath string
DECLARE @BackupFileExtension	nvarchar(128); -- Backup file extension
DECLARE @BackupLocation			nvarchar(max); -- Local path or UNC path where backup is to be stored 
DECLARE @BackupFileDate 		nvarchar(20);  -- Used for file name
DECLARE @MDFFilePath			nvarchar(256); -- Folder path to current MDF file
DECLARE @LDFFilePath			nvarchar(256); -- Folder path to current LDF file
DECLARE @MDFFullFilePath		nvarchar(256); -- Full file path string to current MDF file
DECLARE @LDFFullFilePath		nvarchar(256); -- Full file path string to current LDF file
DECLARE @NewMDFFilePath			nvarchar(256); -- Full file path to proposed new physical MDF filename to be renamed
DECLARE @NewLDFFilePath			nvarchar(256); -- Full file path to proposed new physical LDF filename to be renamed
DECLARE @New_MDF_Exists			int;		   -- Does proposed new physical MDF file exist
DECLARE @New_LDF_Exists			int;		   -- Does proposed new physical LDF file exist
DECLARE @New_Logical_MDF		nvarchar(128); -- New logical MDF name
DECLARE @New_Logical_LDF		nvarchar(128); -- New logical LDF name
DECLARE @Curr_Logical_MDF		nvarchar(128); -- Current logical MDF name
DECLARE @Curr_Logical_LDF		nvarchar(128); -- Current logical LDF name
DECLARE @RenameMDFCmd			nvarchar(128); -- xp_cmdshell command to rename the physical MDF file on the filesystem
DECLARE @RenameLDFCmd			nvarchar(128); -- xp_cmdshell command to rename the physical LDF file on the filesystem
DECLARE @XPCSTestCmd			nvarchar(128); -- xp_cmdshell command to test filesystem permissions to MDF & LDF locations
DECLARE @XPCSReturnCodeMDF		int;		   -- xp_cmdshell return code
DECLARE @XPCSReturnCodeLDF		int;		   -- xp_cmdshell return code

SET NOCOUNT ON

SET @DBName = N'AdventureWorks2014' /*** Change to current name of database to be renamed ***/
SET @NewDBName = N'AdventureWorks2014_OLD' /*** Change to new name wanted for the database ***/
SET	@BackupLocation		= N'N:\Backup\'  /*** Change path to appropriate local folder or UNC path. MAKE SURE TO INCLUDE THE TRAILING \ on the path ***/
SET	@BackupFileExtension	= N'_FULL-COPY_ONLY.BAK'
SELECT @BackupFileDate = CONVERT(VARCHAR(20),GETDATE(),112) + '_' + REPLACE(CONVERT(VARCHAR(20),GETDATE(),108),':','') 
SET @BackupFullFileString = @BackupLocation + @dbname + '_' + @BackupFileDate + @BackupFileExtension
SET @XPCSReturnCodeMDF = 1
SET @XPCSReturnCodeLDF = 1

-- Find current database files folder location
-- IF/ELSE for trapping incorrectly set @dbname, if this happens, the default instance paths are pulled for the data & log folder paths
IF (DB_ID(@dbname) IS NOT NULL)
BEGIN
	-- Full file paths are pulled for the current data & log files
	SELECT @MDFFilePath = [physical_name] FROM sys.master_files WHERE database_id = DB_ID(@dbname) AND [type] = 0
	SELECT @LDFFilePath = [physical_name] FROM sys.master_files WHERE database_id = DB_ID(@dbname) AND [type] = 1
	
	-- Truncating the file names of the current data & logs files leaving just the folder paths
	SELECT @MDFFilePath = reverse(substring(reverse (@MDFFilePath), CHARINDEX('\', reverse (@MDFFilePath)), len(reverse (@MDFFilePath))));
	SELECT @LDFFilePath = reverse(substring(reverse (@LDFFilePath), CHARINDEX('\', reverse (@LDFFilePath)), len(reverse (@LDFFilePath))));
END
ELSE
BEGIN
	-- Default instance paths are pulled for the data & log folder paths instead
	SELECT @MDFFilePath = CONVERT(nvarchar, SERVERPROPERTY('INSTANCEDEFAULTDATAPATH'));
	SELECT @LDFFilePath = CONVERT(nvarchar, SERVERPROPERTY('INSTANCEDEFAULTLOGPATH'));
END

-- Build new MDF & LDF file paths to verify that the new physical files don't already exist
SET @NewMDFFilePath = @MDFFilePath + @newdbname + '.mdf'
SET @NewLDFFilePath = @LDFFilePath + @newdbname + '_log.ldf'

-- Find out if new proposed physical filenames exist on the filesystem
EXEC Master.dbo.xp_fileexist @NewMDFFilePath, @New_MDF_Exists OUT
EXEC Master.dbo.xp_fileexist @NewLDFFilePath, @New_LDF_Exists OUT

-- Get current logical filenames
SELECT @Curr_Logical_MDF = [name] FROM sys.master_files WHERE database_id = DB_ID(@dbname) AND [type] = 0
SELECT @Curr_Logical_LDF = [name] FROM sys.master_files WHERE database_id = DB_ID(@dbname) AND [type] = 1

-- Check if proposed logical MDF and/or LDF filenames already exist
SET @New_Logical_MDF = @NewDBName
SET @New_Logical_LDF = @NewDBName + '_log'

-- Check that xp_cmdshell has permissions to the filesystem for MDF & LDF locations. Creates & deletes a text file.
	-- Enable xp_cmdshell
	/* 0 = Disabled , 1 = Enabled */
	EXEC sp_configure 'show advanced options', 1
	RECONFIGURE WITH OVERRIDE
	/* 0 = Disabled , 1 = Enabled */
	EXEC sp_configure 'xp_cmdshell', 1
	RECONFIGURE WITH OVERRIDE
	PRINT  char(13) + char(10) -- Spacing out sp_configure informational messages not suppressed

SET @XPCSTestCmd = 'echo hello > ' + @MDFFilePath + 'RenameTest.txt'
EXEC @XPCSReturnCodeMDF = master..xp_cmdshell @XPCSTestCmd, NO_OUTPUT
SET @XPCSTestCmd = 'del "'  + @MDFFilePath + 'RenameTest.txt"'
-- Didn't check for the return code on the delete command since it'll fail if the file creation above does
EXEC master..xp_cmdshell @XPCSTestCmd, NO_OUTPUT

SET @XPCSTestCmd = 'echo hello > ' + @LDFFilePath + 'RenameTest.txt'
EXEC @XPCSReturnCodeLDF = master..xp_cmdshell @XPCSTestCmd, NO_OUTPUT
SET @XPCSTestCmd = 'del "'  + @LDFFilePath + 'RenameTest.txt"'
-- Didn't check for the return code on the delete command since it'll fail if the file creation above does
EXEC master..xp_cmdshell @XPCSTestCmd, NO_OUTPUT

	-- Disable xp_cmdshell
	/* 0 = Disabled , 1 = Enabled */
	EXEC sp_configure 'xp_cmdshell', 0
	RECONFIGURE WITH OVERRIDE
	/* 0 = Disabled , 1 = Enabled */
	EXEC sp_configure 'show advanced options', 0
	RECONFIGURE WITH OVERRIDE
	PRINT  char(13) + char(10) -- Spacing out sp_configure informational messages not suppressed

/*------------------------------------------------------------------------------------------------------------------------------------------
Check if original database name exists, that new database name does not exist,  that the database doesn't contain more than two files, 
that new logical filenames & physical filenames do not exist, & that xp_cmdshell has filesystem permissions to Data & Log directories
------------------------------------------------------------------------------------------------------------------------------------------*/

IF (DB_ID(@dbname) IS NOT NULL) -- Check that current database name exists
AND (DB_ID(@newdbname) IS NULL) -- Check that new database name does not exist
AND ((SELECT count(*) FROM sys.master_files WHERE database_id = DB_ID(@dbname)) !> 2) -- Check that database to be renamed doesn't contain more than two files
AND (@New_MDF_Exists = 0) -- Check that new physical MDF does not already exist
AND (@New_LDF_Exists = 0) -- Check that new physical LDF does not already exist
AND (SELECT [database_id] FROM sys.master_files WHERE [name] LIKE @New_Logical_MDF) IS NULL -- Check if new logical MDF name does not already exist
AND (SELECT [database_id] FROM sys.master_files WHERE [name] LIKE @New_Logical_LDF) IS NULL -- Check if new logical LDF name does not already exist
AND (@XPCSReturnCodeMDF = 0) -- Check filesystem permissions to write to Data directory
AND (@XPCSReturnCodeLDF = 0) -- Check filesystem permissions to write to Log directory
BEGIN
	-- Take a COPY_ONLY backup
	BACKUP DATABASE @DBName TO DISK = @BackupFullFileString WITH COMPRESSION, COPY_ONLY
	PRINT 'FULLFILESTRING = ' + @BackupFullFileString + char(13) + char(10) + char(13) + char(10)
	
	-- Disconnect all existing sessions to current database
	EXEC('ALTER DATABASE ' + @DBName + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE')

	-- Rename database
	EXEC master..sp_renamedb @DBName,@NewDBName
	PRINT 'Database: ' + @DBName + ' has been renamed to ' + @NewDBName + char(13) + char(10)

	-- Change logical file Names
	EXEC('ALTER DATABASE ' + @NewDBName + ' MODIFY FILE (NAME = ' + @Curr_Logical_MDF + ', NEWNAME = ' + @New_Logical_MDF +')')
	PRINT 'Logical MDF: ' + @Curr_Logical_MDF + ' has been renamed to ' + @New_Logical_MDF + char(13) + char(10)
	EXEC('ALTER DATABASE ' + @NewDBName + ' MODIFY FILE (NAME = ' + @Curr_Logical_LDF + ', NEWNAME = ' + @New_Logical_LDF +')')
	PRINT 'Logical LDF: ' + @Curr_Logical_LDF + ' has been renamed to ' + @New_Logical_LDF + char(13) + char(10)

	-- Change database into OFFLINE mode
	EXEC('ALTER DATABASE ' + @NewDBName + ' SET OFFLINE')
	PRINT @NewDBName + ' is offline' + char(13) + char(10)

	-- Enable xp_cmdshell
	/* 0 = Disabled , 1 = Enabled */
	EXEC sp_configure 'show advanced options', 1
	RECONFIGURE WITH OVERRIDE
	/* 0 = Disabled , 1 = Enabled */
	EXEC sp_configure 'xp_cmdshell', 1
	RECONFIGURE WITH OVERRIDE
	PRINT  char(13) + char(10) -- Spacing out sp_configure informational messages not suppressed

	-- Full file paths for the current data & log files are pulled again for xp_cmdshell
	SELECT @MDFFullFilePath = [physical_name] FROM sys.master_files WHERE database_id = DB_ID(@NewDBName) AND [type] = 0
	SELECT @LDFFullFilePath = [physical_name] FROM sys.master_files WHERE database_id = DB_ID(@NewDBName) AND [type] = 1

	SET @RenameMDFCmd = 'RENAME "' + @MDFFullFilePath + '", "' + @NewDBName + '.mdf"'
	SET @RenameLDFCmd = 'RENAME "' + @LDFFullFilePath + '", "' + @NewDBName + '_log.ldf"'
	
	-- Execute xp_cmdshell command strings to change physical filenames on the filesystem
	EXEC master..xp_cmdshell @RenameMDFCmd
	PRINT 'Physical MDF: ' + @MDFFullFilePath + ' has been renamed to ' + @NewMDFFilePath + char(13) + char(10)
	EXEC master..xp_cmdshell @RenameLDFCmd
	PRINT 'Physical LDF: ' + @LDFFullFilePath + ' has been renamed to ' + @NewLDFFilePath + char(13) + char(10) + char(13) + char(10)

	-- Disable xp_cmdshell
	/* 0 = Disabled , 1 = Enabled */
	EXEC sp_configure 'xp_cmdshell', 0
	RECONFIGURE WITH OVERRIDE
	/* 0 = Disabled , 1 = Enabled */
	EXEC sp_configure 'show advanced options', 0
	RECONFIGURE WITH OVERRIDE
	PRINT  char(13) + char(10) -- Spacing out sp_configure informational messages not suppressed

	-- Change physical filenames in system catalog
	EXEC('ALTER DATABASE ' + @NewDBName + ' MODIFY FILE (Name = ' + @New_Logical_MDF + ', FILENAME = ''' + @NewMDFFilePath + ''')')
	EXEC('ALTER DATABASE ' + @NewDBName + ' MODIFY FILE (Name = ' + @New_Logical_LDF + ', FILENAME = ''' + @NewLDFFilePath + ''')')

	-- Bring DB online
	EXEC('ALTER DATABASE ' + @NewDBName + ' SET ONLINE')
	EXEC('ALTER DATABASE ' + @NewDBName + ' SET MULTI_USER')

	-- Check DB status
	SELECT name, State_desc from sys.databases WHERE [name] LIKE @NewDBName

	-- Validate the file name changes
	EXEC('USE [' + @NewDBName + ']; SELECT file_id, name as [logical_file_name], physical_name FROM sys.database_files')
END

ELSE
BEGIN
	IF (DB_ID(@dbname) IS NULL)
		--Problem: Database to be renamed doesn't exist
		PRINT 'PROBLEM: ' + @dbname + ' does not exist' + char(13) + char(10);

	IF (DB_ID(@newdbname) IS NOT NULL)
		--Problem: New database name already exists
		PRINT 'PROBLEM: ' + @newdbname + ' already exists' + char(13) + char(10);

	IF ((SELECT count(*) FROM sys.master_files WHERE database_id = DB_ID(@dbname)) > 2)
		--Problem: Database to be renamed contains more than two files, NDFs present
		PRINT 'PROBLEM: ' + @dbname + ' contains more than two physical files' + char(13) + char(10);

	IF (@New_MDF_Exists = 1)
		--Problem: Proposed new physical MDF name already exists
		PRINT 'PROBLEM: Proposed new physical MDF already exists' + char(13) + char(10);

	IF (@New_LDF_Exists = 1)
		--Problem: Proposed new physical LDF name already exists
		PRINT 'PROBLEM: Proposed new physical LDF already exists' + char(13) + char(10);

	IF (SELECT [database_id] FROM sys.master_files WHERE [name] LIKE @New_Logical_MDF) IS NOT NULL
		--Problem: Proposed new logical MDF name already exists
		PRINT 'PROBLEM: Proposed logical MDF filename ' + @New_Logical_MDF + ' already exists' + char(13) + char(10);

	IF (SELECT [database_id] FROM sys.master_files WHERE [name] LIKE @New_Logical_LDF) IS NOT NULL
		--Problem: Proposed new logical LDF name already exists
		PRINT 'PROBLEM: Proposed logical LDF filename ' + @New_Logical_LDF + ' already exists' + char(13) + char(10);

	IF (@XPCSReturnCodeMDF = 1)
		--Problem: xp_cmdshell doesn't have filesystem permissions to Data directory
		PRINT 'PROBLEM: xp_cmdshell does not have filesystem permissions to Data directory: ' + @MDFFilePath

	IF (@XPCSReturnCodeLDF = 1)
		--Problem: xp_cmdshell doesn't have filesystem permissions to Log directory
		PRINT 'PROBLEM: xp_cmdshell does not have filesystem permissions to Log directory: ' + @LDFFilePath
END
