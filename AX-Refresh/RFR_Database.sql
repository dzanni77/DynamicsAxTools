USE [master]
GO
CREATE DATABASE [DynamicsAxTools]
GO
ALTER DATABASE [DynamicsAxTools] SET RECOVERY SIMPLE 
GO

USE [DynamicsAxTools]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[RFR_AXServers](
	[ENVIRONMENT] [nvarchar](30) NULL,
	[SERVERID] [int] NULL,
	[AOSID] [nvarchar](100) NULL,
	[INSTANCE_NAME] [nvarchar](10) NULL,
	[VERSION] [int] NULL,
	[STATUS] [int] NULL,
	[AOSACCOUNT] [nvarchar](180) NULL,
	[CREATEDDATETIME] [datetime] NULL
) ON [PRIMARY]

GO

CREATE TABLE [dbo].[RFR_Environments](
	[ENVIRONMENT] [nvarchar](30) NULL,
	[MACHINENAME] [nvarchar](100) NULL,
	[DBSERVER] [nvarchar](50) NULL,
	[DBNAME] [nvarchar](50) NULL,
	[CREATEDDATETIME] [datetime] NULL
) ON [PRIMARY]

GO

CREATE TABLE [dbo].[RFR_EnvironmentStore](
	[ENVIRONMENT] [nvarchar](30) NULL,
	[SOURCEDBSERVER] [nvarchar](50) NULL,
	[SOURCEDBNAME] [nvarchar](50) NULL,
	[SOURCETABLE] [nvarchar](100) NULL,
	[RFRTABLENAME] [nvarchar](100) NULL,
	[SQLSCRIPT] [nvarchar](max) NULL,
	[COUNT] [bigint] NULL,
	[CREATEDDATETIME] [datetime] NULL,
	[SQLCOMPRESSION] [nvarchar](50) NULL,
	[DELETED] [tinyint] NULL,
	[DELETEDDATETIME] [datetime] NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
SET ANSI_PADDING ON

GO

CREATE CLUSTERED INDEX [idx_Environment_CreatedDateTime] ON [dbo].[RFR_EnvironmentStore]
(
	[CREATEDDATETIME] DESC,
	[ENVIRONMENT] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
