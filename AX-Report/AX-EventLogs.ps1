﻿Param (
    [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
    [string]$ServerName,
    [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
    [string]$Guid,
    [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
    [string]$ReportDate,
    [Parameter(Mandatory=$false,ValueFromPipeline=$true)]
    [System.Management.Automation.PSCredential]$Credentials
)
[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") | Out-Null

$Scriptpath = $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path $ScriptPath
$Dir = Split-Path $ScriptDir
$ModuleFolder = $Dir + "\AX-Modules"

Import-Module $ModuleFolder\AX-Tools.psm1 -DisableNameChecking

#$EventLogName = 'Application', 'System'

function Get-EventLogs
{
    try
    {
#        foreach($LogName in $EventLogName) {
#            $EventLogs = Get-EventLog -Computername $ServerName -LogName $LogName -EntryType Warning, Error -After $((Get-Date).AddDays(-1).Date) |
#                Select @{n='LogName';e={$LogName}}, @{n='EntryType';e={($_.EntryType).ToString()}}, EventID, Source, TimeGenerated,  @{n='Message';e={$_.Message -replace '\t|\r|\n', " "}},@{n='FQDN';e={$_.MachineName}}, @{n='ServerName';e={$ServerName}}, @{n='Guid';e={$Guid}}, @{n='ReportDate';e={$ReportDate}}
#            SQL-BulkInsert 'AXReport_EventLogs' $EventLogs
#        }

        Write-Log "Running EvenLogs job for $ServerName. RunAs - $($Credentials.UserName)"
        if($Credentials) {
            $EventLogs = Get-WinEvent –FilterHashtable @{LogName = 'Application', 'System'; Level = 2, 3; StartTime=$((Get-Date).AddDays(-1).Date)} -ComputerName $ServerName -Credential $Credentials | 
                    Select @{n='LogName';e={$_.LogName}}, @{n='EntryType';e={($_.LevelDisplayName).ToString()}}, @{n='EventID';e={$_.ID}}, @{n='Source';e={$_.ProviderName}}, @{n='TimeGenerated';e={$_.TimeCreated}},  @{n='Message';e={$_.Message -replace '\t|\r|\n|  ', " "}},@{n='FQDN';e={$_.MachineName}}, @{n='ServerName';e={$ServerName}}, @{n='Guid';e={$Guid}}, @{n='ReportDate';e={$ReportDate}}
        }
        else {
            $EventLogs = Get-WinEvent –FilterHashtable @{LogName = 'Application', 'System'; Level = 2, 3; StartTime=$((Get-Date).AddDays(-1).Date)} -ComputerName $ServerName | 
                    Select @{n='LogName';e={$_.LogName}}, @{n='EntryType';e={($_.LevelDisplayName).ToString()}}, @{n='EventID';e={$_.ID}}, @{n='Source';e={$_.ProviderName}}, @{n='TimeGenerated';e={$_.TimeCreated}},  @{n='Message';e={$_.Message -replace '\t|\r|\n|  ', " "}},@{n='FQDN';e={$_.MachineName}}, @{n='ServerName';e={$ServerName}}, @{n='Guid';e={$Guid}}, @{n='ReportDate';e={$ReportDate}}
        }
        SQL-BulkInsert 'AXReport_EventLogs' $EventLogs
    }
    catch
    {
        Write-Log "$ServerName - ERROR - EventLogs: $($_.Exception.Message)"
        #$_.Exception.Message | Out-File C:\Users\Administrator\Documents\GitHub\DynamicsAxTools\AX-Report\Joberror.txt -Append
    }
}

Get-EventLogs