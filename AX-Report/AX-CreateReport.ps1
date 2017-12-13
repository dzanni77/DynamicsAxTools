﻿Param (
    [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
    [string]$FileDateTime,
    [string]$Environment,
    [system.object]$Settings
)
[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | Out-Null

$Scriptpath = $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path $ScriptPath
$Dir = Split-Path $ScriptDir
$ModuleFolder = $Dir + "\AX-Modules"
$ToolsFolder = $Dir + "\AX-Tools"
$ReportFolder = $Dir + "\Reports\AX-Report\$Environment"
$LogFolder = $Dir + "\Logs\AX-Report\$Environment"
#
Import-Module $ModuleFolder\AX-Database.psm1 -DisableNameChecking
Import-Module $ModuleFolder\AX-HTMLReport.psm1 -DisableNameChecking

$Footer="AX Report v{3} run {0} by {1}\{2}" -f (Get-Date),$env:UserDomain,$env:UserName,'2.0'
$ReportName = "AX Daily Report"
#
function HTML-Create
{
    #Prepare Summary Table
    $Summary = @()
    #AOS
    if($AxServicesReport.Count -eq ($AxServicesReport | Where {$_.Status -match 'Running'}).Count) { 
        $Summary += New-Object PSObject -Property @{ Name = "AOS Services"; Status = "Ok. All Services Running."; RowColor = 'Green' }
    }
    else {
        $Summary += New-Object PSObject -Property @{ Name = "AOS Services"; Status = "AOS Services Failure Found."; RowColor = 'Red' }
    }
    #MRP
    if($AxMRPLogsReport) {
        switch -wildcard ($AxMRPLogsReport) {
            {$($AxMRPLogsReport.TotalTime) -eq 0} {$Summary += New-Object PSObject -Property @{ Name = "MRP Status"; Status = "MRP Failed or Cancelled."; RowColor = 'Red' }}
            {($($AxMRPLogsReport.TotalTime) -gt 0) -and ($($AxMRPLogsReport.TotalTime) -le 45)} {$Summary += New-Object PSObject -Property @{ Name = "MRP Status"; Status = "$($AxMRPLogsReport.TotalTime) minutes."; RowColor = 'Green' }}
            {($($AxMRPLogsReport.TotalTime) -gt 45) -and ($($AxMRPLogsReport.TotalTime) -le 60)} {$Summary += New-Object PSObject -Property @{ Name = "MRP Status"; Status = "$($AxMRPLogsReport.TotalTime) minutes."; RowColor = 'Yellow' }}
            Default {$Summary += New-Object PSObject -Property @{ Name = "MRP Status"; Status = "$($AxMRPLogsReport.TotalTime) minutes."; RowColor = 'Red' }}
        }
    }
    else {
         $Summary += New-Object PSObject -Property @{ Name = "MRP Status"; Status = "MRP Long Run or Failed."; RowColor = 'Red'; }
    }
    #BATCH
    if($AxBatchJobsReport.Count -eq 0) { 
        $Summary += New-Object PSObject -Property @{ Name = "Batch Jobs"; Status = "Ok."; RowColor = 'Green' }
    }
    else {
        $Summary += New-Object PSObject -Property @{ Name = "Batch Jobs"; Status = "Errors Found."; RowColor = 'Red' }
    }
    if($AxLongBatchJobsReport.Count -eq 0) {
        $Summary += New-Object PSObject -Property @{ Name = "Long Batch Jobs (>15min)"; Status = "Ok."; RowColor = 'Green' }
    }
    else {
        $Summary += New-Object PSObject -Property @{ Name = "Long Batch Jobs (>15min)"; Status = "$($AxLongBatchJobsReport.Count) Jobs Found."; RowColor = 'Red' }
    }
    #RETAIL
    if($AxCDXJobsReport.Count -eq 0) { 
        $Summary += New-Object PSObject -Property @{ Name = "Retail Jobs"; Status = "Ok."; RowColor = 'Green' }
    }
    else {
        $Summary += New-Object PSObject -Property @{ Name = "Retail Jobs"; Status = "Errors Found."; RowColor = 'Red' }
    }
    #PERFMON SET COLOR
    $Green = '(($this.Counter -like "CPU Time %" -and $this.Max -le 60) -or ($this.Counter -like "Available GBytes" -and $this.Min -ge 8) -or ($this.Counter -like "Paging File %" -and $this.Max -le 35) -or ($this.Counter -like "*Buffer cache hit ratio" -and $this.Min -ge 95) -or ($this.Counter -like "*Page life expectancy" -and $this.Min -ge 6000))'
    $Yellow = '(($this.Counter -like "CPU Time %" -and $this.Max -gt 60 -and $this.Max -lt 80) -or ($this.Counter -like "Available GBytes" -and $this.Max -gt 4 -and $this.Max -lt 8) -or ($this.Counter -like "Paging File %" -and $this.Max -gt 35 -and $this.Max -lt 50) -or ($this.Counter -like "*Buffer cache hit ratio" -and $this.Min -gt 90 -and $this.Min -lt 95) -or ($this.Counter -like "*Page life expectancy" -and $this.Min -gt 1200 -and $this.Min -lt 6000))'    
    $Red = '(($this.Counter -like "CPU Time %" -and $this.Max -ge 80) -or ($this.Counter -like "Available GBytes" -and $this.Max -le 4) -or ($this.Counter -like "Paging File %" -and $this.Max -ge 50) -or ($this.Counter -like "*Buffer cache hit ratio" -and $this.Min -le 90) -or ($this.Counter -like "*Page life expectancy" -and $this.Min -le 1200))'
    #REMOVING INSTANCES NOT RUNNING
    $PermonDataLogsTmp = $PermonDataLogsReport | Where {$_.ServerType -notmatch 'SQL' -or $_.CounterType -like 'SRV' }
    $PermonDataLogsTmp += $PermonDataLogsReport | Where {(($_.Max -ne 0) -or ($_.Min -ne 0)) -and ($_.CounterType -notmatch 'SRV') -and ($_.ServerType -match 'SQL')}
    $AXPerfmonCLR = Set-TableRowColor $PermonDataLogsTmp -Red $Red -Yellow $Yellow -Green $Green
    #PERFMON
    if(((($AXPerfmonCLR | Group RowColor | Where Name -like 'Green').Count) + (($AXPerfmonCLR | Group RowColor | Where Name -like 'Green').Count)) -eq $AXPerfmonCLR.Count) {
        $Summary += New-Object PSObject -Property @{ Name = "Performance Monitor"; Status = "$(($AXPerfmonCLR | Group RowColor | Where Name -like 'Green').Count) Alerts."; RowColor = 'Green' }
    }
    elseif (((($AXPerfmonCLR | Group RowColor | Where Name -like 'Yellow').Count) -gt 0) -and ((($AXPerfmonCLR | Group RowColor | Where Name -like 'Red').Count) -eq 0)) {
        $Summary += New-Object PSObject -Property @{ Name = "Performance Monitor"; Status = "$((($AXPerfmonCLR | Group RowColor | Where Name -like 'Yellow').Count)) Warnings."; RowColor = 'Yellow' }
    }
    else {
        $Summary += New-Object PSObject -Property @{ Name = "Performance Monitor"; Status = "$((($AXPerfmonCLR | Group RowColor | Where Name -like 'Red').Count)) Criticals and $((($AXPerfmonCLR | Group RowColor | Where Name -like 'Yellow').Count)) Warnings."; RowColor = 'Red' }
    }
    
    #EVENTLOGS
    if(($($AxEventLogsChart | Group Id | Where Name -like 1000).Count -gt 0) -or ($($AxEventLogsChart | Group Id | Where Name -like 1002).Count -gt 0)) { 
        $Query = "SELECT  ServerName as [Server],
                          ServerType = Case ServerType
		                    WHEN 'AOS' then 'AOS Server'
		                    WHEN 'RDP' then 'RDP Server'
		                  END, 
		                  Application = CASE SUBSTRING(MESSAGE,(CHARINDEX('Ax32',MESSAGE)), ((CHARINDEX('.exe',MESSAGE)) - (CHARINDEX('Ax32',MESSAGE))))
		                    WHEN 'Ax32' then 'client'
		                    WHEN 'Ax32Serv' then 'server'
		                  END, 
		                  Type = Case EVENTID
		                    WHEN '1000' then 'crash(es)'
		                    WHEN '1002' then 'hang(s)'
		                  END, COUNT(1) as Count
                    FROM AXREPORTEVENTLOGS 
                    WHERE REPORTID = '$FileDateTime' AND (EVENTID = '1000' or EVENTID = '1002') AND ENTRYTYPE = 'ERROR' AND MESSAGE LIKE '%AX32%'
                    GROUP BY ServerName, ServerType, SUBSTRING(MESSAGE,(CHARINDEX('Ax32',MESSAGE)), ((CHARINDEX('.exe',MESSAGE)) - (CHARINDEX('Ax32',MESSAGE)))), EVENTID
                    ORDER BY 1 DESC, COUNT DESC"
        $Cmd = New-Object System.Data.SqlClient.SqlCommand($Query,$Conn)
        $Adapter = New-Object System.Data.SqlClient.SqlDataAdapter
        $Adapter.SelectCommand = $Cmd
        $AxCrashReport = New-Object System.Data.DataSet
        $Adapter.Fill($AxCrashReport)
        $AxCrashReportLog = $AxCrashReport.Tables[0] | Sort Server, Type
        $Summary += New-Object PSObject -Property @{
                            Name = "Event Logs";
                            Status = "$(($AxCrashReportLog | Where {$_.Type -like 'Crash(es)'} | Measure-Object Count -Sum).Sum) Crash(es) and $(($AxCrashReportLog | Where {$_.Type -like 'Hang(s)'} | Measure-Object Count -Sum).Sum) Hang(s)"; 
                            RowColor = if((($AxCrashReportLog | Where {$_.Type -like 'Crash(es)'}).Count -gt 0) -and (($AxCrashReportLog | Where {$_.Application -like 'server'}).Count -gt 0)) {'Red'} else {'Yellow'}
                          }
        foreach($Crash in $AxCrashReportLog | Group Server) {
            $TmpSummary = @()
            $i = 1
            foreach($CrashRpt in $Crash.Group) {
                if($i -eq 1) {
                    $TmpSummary += "$($CrashRpt.Count) $($CrashRpt.Application) $($CrashRpt.Type)"
                }
                else {
                    $TmpSummary += "and $($CrashRpt.Count) $($CrashRpt.Application) $($CrashRpt.Type)"
                }
                $i++
            }
            $Summary += New-Object PSObject -Property @{ 
                            Name = "`t"; 
                            Status = " -› $($Crash.Name) - $TmpSummary"; 
                            RowColor = if($TmpSummary -match ("server crash")) {'Red'} else {'Yellow'} }
        }
    }
    else {
        $Summary += New-Object PSObject -Property @{ Name = "Event Logs"; Status = "Ok."; RowColor = 'Green' }
    }

    #SQL
    if(($SQLErrorLogsReport.Log | Where {$_ -like 'SQL Server is starting*' }) -or 
                ($SQLErrorLogsReport.Log | Where {$_ -like 'Starting up database*' }) -or 
                    ($SQLErrorLogsReport.Log | Where {$_ -like 'Recovery of database*' })) { 
        $Summary += New-Object PSObject -Property @{ Name = "SQL Errors"; Status = "SQL Restarted."; RowColor = 'Red' }
    }
    elseif($SQLErrorLogsReport.Process.Contains('Server')) {
        $Summary += New-Object PSObject -Property @{ Name = "SQL Errors"; Status = "SQL Server Failure Found."; RowColor = 'Yellow' }
    }
    else {
        $Summary += New-Object PSObject -Property @{ Name = "SQL Errors"; Status = "Ok."; RowColor = 'Green' }
    }
    #SSRS
    if((($SSRSErrorLogsReport | Where { $_.Status -notlike 'rsReportParameterValueNotSet'}).Count) -eq 0) { 
        $Summary += New-Object PSObject -Property @{ Name = "SSRS Errors"; Status = "Ok."; RowColor = 'Green' }
    }
    else {
        $Summary += New-Object PSObject -Property @{ Name = "SSRS Errors"; Status = "$((($SSRSErrorLogsReport | Where { $_.Status -notlike 'rsReportParameterValueNotSet'}).Count)) Issues Found."; RowColor = 'Yellow' }
    }

    #Start Report
    $AXR = @()
    $AXR += Get-HtmlOpen -TitleText ($ReportName)
    $AXR += Get-HtmlContentOpen -HeaderText "AX Daily Report"

    ###First
    ##Summary Report
    $AXR += Get-HtmlColumn1of2
    $AXR += Get-HtmlContentOpen -BackgroundShade 1 -HeaderText "Summary Information"
    $AXR += Get-HtmlContentTable($Summary | Select Name, Status, RowColor)
    $AXR += Get-HtmlContentClose
    $AXR += Get-HtmlColumnClose
    #
    #AX Services Status
    $AXR += Get-HtmlColumn2of2
    $Green = '$this.Status -match "Running"'
    $Red = '$this.Status -match "Stopped"'
    $AXR += Get-HtmlContentOpen -BackgroundShade 1 -HeaderText "AX Services Status"
    $AXR += Get-HtmlContentTable(Set-TableRowColor $AxServicesReport -Red $Red -Green $Green)
    $AXR += Get-HtmlContentClose
    $AXR += Get-HtmlColumnClose
    $AXR += Get-HtmlContentClose
    #

    #MRP Status
    if($AxMRPLogsReport)
    {
        $Green = '$this.TotalTime -gt 0 -and $this.TotalTime -le 45'
        $Yellow = '$this.TotalTime -gt 45 -and $this.TotalTime -le 60'
        $Red = '$this.TotalTime -eq 0 -or $this.TotalTime -gt 60'
        $AxMRPColor = Set-TableRowColor $AxMRPLogsReport -Green $Green -Yellow $Yellow -Red $Red
        $AXR += Get-HtmlContentOpen -BackgroundShade 1 -HeaderText "MRP Run Status"
        $AXR += Get-HtmlContentTable($AxMRPColor)
        $AXR += Get-HtmlContentClose
    }

    #Second
    ##Perfmon Logs
    $AXR += Get-HtmlContentOpen
    $AXR += Get-HtmlColumn1of2
        $AXR += Get-HtmlContentOpen -HeaderText "Performance Monitor by Server [Total - $($AXPerfmonCLR.Count)]" -BackgroundShade 1
        foreach ($Type in ($AXPerfmonCLR | Group ServerType | Sort Name ) ) {
            $AXR += Get-HtmlContentOpen -HeaderText ($Type.Name + " Servers") -IsHidden -BackgroundShade 1
            foreach ($Group in ($AXPerfmonCLR | Where-Object {$_.ServerType -match $Type.Name} | Group ServerName | Sort Name ) ) {
                $AXR += Get-HtmlContentOpen -HeaderText ($Group.Name) -IsHidden -BackgroundShade 1
                $AXR += Get-HtmlContentTable ($Group.Group | Select Counter, Max, Min, Avg, RowColor)
                $AXR += Get-HtmlContentClose
            }
            $AXR += Get-HtmlContentClose
        }
        $AXR += Get-HtmlContentClose
    $AXR += Get-HtmlColumnClose
    #
    $AXR += Get-HtmlColumn2of2
    $AXR += Get-HtmlContentOpen -HeaderText "Performance Monitor Alerts by Threshold" -BackgroundShade 1
        $AxPerfMonGrp = $AXPerfmonCLR | Where {($_.RowColor -like 'Red') -or ($_.RowColor -like 'Yellow')} | Group RowColor | Sort Name
        $AXR += Get-HtmlContentTable ($AxPerfMonGrp.Group | Select ServerName, Counter, Max, Min, Avg, RowColor)
    $AXR += Get-HtmlContentClose
    $AXR += Get-HtmlContentClose
    $AXR += Get-HtmlColumnClose
    
    #Third
    #Event Logs Graphs
    $PieChartObject1 = New-HTMLPieChartObject
    $PieChartObject1.Title = " "
    $PieChartObject1.Size.Height = 300
    $PieChartObject1.Size.Width = 300
    $PieChartObject1.ChartStyle.ExplodeMaxValue = $true
    $PieChartObject2 = New-HTMLPieChartObject
    $PieChartObject2.Title = " "
    $PieChartObject2.Size.Height = 300
    $PieChartObject2.Size.Width = 300
    $PieChartObject2.ChartStyle.ExplodeMaxValue = $true    				
    
    $AXR += Get-HtmlContentOpen
    $AXR += Get-HtmlColumn1of2
    $AXR += Get-HtmlContentOpen -HeaderText "Event Logs by Server (Top 5)"
    $AXR += New-HTMLPieChart -PieChartObject $PieChartObject2 -PieChartData ($AxEventLogsChart | Group ServerName | Sort Count -Descending | Select -First 5)
    $AXR += Get-HtmlContentTable ($AxEventLogsChart | Group ServerName | Select Name, Count | Sort Count -Descending | Select -First 5)
    $AXR += Get-HtmlContentClose
    $AXR += Get-HtmlColumnClose

    $AXR += Get-HtmlColumn2of2
    $AXR += Get-HtmlContentOpen -HeaderText "Event Logs by Server" -BackgroundShade 1
    foreach ($Type in ($AxEventLogsChart | Group ServerType | Sort Name ) ) {
        $AXR += Get-HtmlContentOpen -HeaderText ($Type.Name + " Servers") -IsHidden -BackgroundShade 1
        foreach ($Group in ($AxEventLogsChart | Where-Object {$_.ServerType -match $Type.Name} | Group ServerName | Sort Name ) ) {
            $AXR += Get-HtmlContentOpen -HeaderText ($Group.Name) -IsHidden -BackgroundShade 1
            $AXR += Get-HtmlContentTable ($AxEventLogsReport | Where {$_.ServerName -match $Group.Name} | Select LogName, Type, Id, Source, Count | Sort Count -Descending)
            $AXR += Get-HtmlContentClose
        }
        $AXR += Get-HtmlContentClose
    }
    $AXR += Get-HtmlContentClose   
    #
    $AXR += Get-HtmlColumnClose
    $AXR += Get-HtmlContentClose

    #Batch Jobs Errors
    $AXR += Get-HtmlContentOpen -BackgroundShade 1 -HeaderText "AX Batch Jobs Errors [Total - $($AxBatchJobsReport.Count)]"
    $AXR += Get-HtmlContentTable ($AxBatchJobsReport)
    $AXR += Get-HtmlContentClose
    #
    $PieChartObject3 = New-HTMLPieChartObject
    $PieChartObject3.Title = " "
    $PieChartObject3.Size.Height = 300
    $PieChartObject3.Size.Width = 300
    $PieChartObject3.ChartStyle.ExplodeMaxValue = $true

    $AXR += Get-HtmlContentOpen
    $AXR += Get-HtmlColumn1of2
    $AXR += Get-HtmlContentOpen -BackgroundShade 1 -HeaderText "SSRS Error Logs [Total - $($SSRSErrorLogsReport.Count)]"
    $AXR += Get-HtmlContentTable(Set-TableRowColor($SSRSErrorLogsReport | Select Instance, Message, Report, Count) -Alternating)
    $AXR += Get-HtmlContentClose
    $AXR += Get-HtmlColumnClose
    #
    $AXR += Get-HtmlColumn2of2
    $AXR += Get-HtmlContentOpen -BackgroundShade 1 -HeaderText "SSRS Errors by User (Top 5)"
    $AXR += New-HTMLPieChart -PieChartObject $PieChartObject3 -PieChartData ($SSRSUsersReport | Sort Count -Descending | Select -First 5)
    $AXR += Get-HtmlContentTable($SSRSUsersReport | Select User, Count | Sort Count -Descending | Select -First 5)
    $AXR += Get-HtmlContentClose
    $AXR += Get-HtmlColumnClose
    $AXR += Get-HtmlContentClose
 
    #CDX Jobs Errors
    $AXR += Get-HtmlContentOpen -BackgroundShade 1 -HeaderText "CDX Jobs Errors [Total - $($AxCDXJobsReport.Count)]" 
    $AXR += Get-HtmlContentTable (Set-TableRowColor $AxCDXJobsReport -Alternating)
    $AXR += Get-HtmlContentClose

    ##SQL Error Logs
    $AXR += Get-HtmlContentOpen -BackgroundShade 1 -HeaderText "SQL Server Error Logs [Total - $($SQLErrorLogsReport.Count)]" 
    $AXR += Get-HtmlContentTable ($SQLErrorLogsReport) 
    $AXR += Get-HtmlContentClose

    $PieChartObject4 = New-HTMLPieChartObject
    $PieChartObject4.Title = " "
    $PieChartObject4.Size.Height = 400
    $PieChartObject4.Size.Width = 400
    $PieChartObject4.ChartStyle.ExplodeMaxValue = $true    			
    
    $AXR += Get-HtmlContentOpen
    $AXR += Get-HtmlColumn1of2
    $AXR += Get-HtmlContentOpen -HeaderText "SSRS Errors 7 Days"
    $AXR += New-HTMLPieChart -PieChartObject $PieChartObject4 -PieChartData ($SSRSWeekReport | Sort Date)
    $AXR += Get-HtmlContentTable ($SSRSWeekReport | Select Date, Count | Sort Date -Descending)
    $AXR += Get-HtmlContentClose
    $AXR += Get-HtmlColumnClose

    $AXR += Get-HtmlColumn2of2

    $AXR += Get-HtmlColumnClose
    $AXR += Get-HtmlContentClose

    #Close Report
    $AXR += Get-HtmlContentClose
    $AXR += Get-HtmlClose
    #Save HTML
    $AXReportPath = join-path $ReportOutputPath ("AXReport-$FileDateTime" + ".mht")
    $AXR | Set-Content -Path $AXReportPath -Force

    ##Summary Email
    $Summary += New-Object PSObject -Property @{ Name = '**Please see the attached report for details.'; Status = ''; RowColor = 'None' }
    $AXREmail = @()
    $AXREmail += Get-SummaryOpen -TitleText ($ReportName)
    $AXREmail += Get-HtmlContentOpen -HeaderText "Summary Information"
    $AXREmail += Get-HtmlContentTable($Summary | Select Name, Status, RowColor)
    $AXREmail += Get-HtmlContentClose
    $AXREmail += Get-SummaryClose
    $AXReportPath = join-path $ReportOutputPath ("AXReport-$FileDateTime-Summary" + ".html")
    $AXREmail | Set-Content -Path $AXReportPath -Force

}

function Get-HtmlOpen {
<#
	.SYNOPSIS
		Get's HTML for the header of the HTML report
    .PARAMETER TitleText
		The title of the report
#>
[CmdletBinding()]
param (
	[String] $TitleText
)
	
$CurrentDate = Get-Date -format "MMM d, yyyy hh:mm tt"
$Report = @"
MIME-Version: 1.0
Content-Type: multipart/related; boundary="PART"; type="text/html"

--PART
Content-Type: text/html; charset=us-ascii
Content-Transfer-Encoding: 7bit

<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">
<html>

<head>
<title>$($TitleText)</title>
<style type="text/css">
* {    
    margin: 0px;
    font-family: sans-serif;
    font-size: 8pt;
}

body {
    margin: 8px 5px 8px 5px; 
}

hr {
    height: 4px; 
    background-color: #337e94; 
    border: 0px;
}

table {
    table-layout: auto; 
    width: 100%;
    border-collapse: collapse;   
}

th {
    vertical-align: top; 
    text-align: left;
    padding: 2px 5px 2px 5px;
}

td {
    vertical-align: top; 
    padding: 2px 5px 2px 5px;
    border-top: 1px solid #bbbbbb;  
}

div.section {
    padding-bottom: 12px;
} 

div.header {
    border: 1px solid #bbbbbb; 
    padding: 4px 5em 0px 5px; 
    margin: 0px 0px -1px 0px;
    height: 2em; 
    width: 95%; 
    font-weight: bold ;
    color: #ffffff;
    background-color: #337e94;
}

div.content { 
    border: 1px solid #bbbbbb; 
    padding: 4px 0px 5px 11px; 
    margin: 0px 0px -1px 0px;
    width: 95%; 
    color: #000000; 
    background-color: #f9f9f9;
}

div.reportname {
    font-size: 16pt; 
    font-weight: bold;
}

div.reportdate {
    font-size: 12pt; 
    font-weight: bold;
}

div.footer {
    padding-right: 5em;
    text-align: right; 
}

table.fixed {
    table-layout: fixed; 
}

th.content { 
    border-top: 1px solid #bbbbbb; 
	width: 25%;
}

td.content { 
	width: 75%;
}

td.groupby {
	border-top: 3px double #bbbbbb;
}

.green {
	background-color: #a1cda4;
}

.yellow {
	background-color: #fffab1;
}

.red {
	background-color: #f5a085;
}

.odd {
	background-color: #D5D8DC;
}

.even {
	background-color: #F7F9F9;
}

.header {
	background-color: #616A6B; color: #F7F9F9;
}

div.column { width: 100%; float: left; overflow-y: auto; }
div.first  { border-right: 1px  grey solid; width: 49% }
div.second { margin-left: 10px;width: 49% }

</style>

<script type="text/javascript"> 
function show(obj) {
  document.getElementById(obj).style.display='block'; 
  document.getElementById("hide_" + obj).style.display=''; 
  document.getElementById("show_" + obj).style.display='none'; 
} 
function hide(obj) { 
  document.getElementById(obj).style.display='none'; 
  document.getElementById("hide_" + obj).style.display='none'; 
  document.getElementById("show_" + obj).style.display=''; 
} 
</script> 

</head>

<body onload="hide();">

<div class="section">
    <div class="ReportName">$($TitleText) - $((Get-Date).AddDays(-1) | Get-Date -Format "D")</div>
    <hr/>
</div>
"@
	Return $Report
}


function Get-HtmlClose
{
$Report = @"
<div class="section">
    <hr />
    <div class="Footer">$Footer</div>
</div>
    
</body>
</html>

--PART-- 
"@
	Write-Output $Report
}


function Get-HtmlContentOpen {
<#
	.SYNOPSIS
		Creates a section in HTML
	    .PARAMETER HeaderText
			The heading for the section
		.PARAMETER IsHidden
		    Switch parameter to define if the section can collapse
		.PARAMETER BackgroundShade
		    An int for 1 to 6 that defines background shading
#>	
Param(
	[string]$HeaderText, 
	[switch]$IsHidden, 
	[validateset(1,2,3,4,5,6)][int]$BackgroundShade
)

switch ($BackgroundShade)
{
    1 { $bgColorCode = "#F8F8F8" }
	2 { $bgColorCode = "#D0D0D0" }
    3 { $bgColorCode = "#A8A8A8" }
    4 { $bgColorCode = "#888888" }
    5 { $bgColorCode = "#585858" }
    6 { $bgColorCode = "#282828" }
    default { $bgColorCode = "#ffffff" }
}



if ($IsHidden) {
	$RandomNumber = Get-Random
	$Report = @"
<div class="section">
    <div class="header">
        <a name="$($HeaderText)">$($HeaderText)</a> (<a id="show_$RandomNumber" href="javascript:void(0);" onclick="show('$RandomNumber');" style="color: #ffffff;">Show</a><a id="hide_$RandomNumber" href="javascript:void(0);" onclick="hide('$RandomNumber');" style="color: #ffffff; display:none;">Hide</a>)
    </div>
    <div class="content" id="$RandomNumber" style="display:none;background-color:$($bgColorCode);"> 
"@	
}
else {
	$Report = @"
<div class="section">
    <div class="header">
        <a name="$($HeaderText)">$($HeaderText)</a>
    </div>
    <div class="content" style="background-color:$($bgColorCode);"> 
"@
}
	Return $Report
}

function Get-HtmlContentClose {
<#
	.SYNOPSIS
		Closes an HTML section
#>	
	$Report = @"
</div>
</div>
"@
	Return $Report
}

function Get-HtmlContentTable {
<#
	.SYNOPSIS
		Creates an HTML table from an array of objects
	    .PARAMETER ArrayOfObjects
			An array of objects
		.PARAMETER Fixed
		    fixes the html column width by the number of columns
		.PARAMETER GroupBy
		    The column to group the data.  make sure this is first in the array
#>	
param(
	[Array]$ArrayOfObjects, 
	[Switch]$Fixed, 
	[String]$GroupBy
)
	if ($GroupBy -eq '') {
		$Report = $ArrayOfObjects | ConvertTo-Html -Fragment
		$Report = $Report -replace '<col/>', "" -replace '<colgroup>', "" -replace '</colgroup>', ""
		$Report = $Report -replace "<tr>(.*)<td>Green</td></tr>","<tr class=`"green`">`$+</tr>"
		$Report = $Report -replace "<tr>(.*)<td>Yellow</td></tr>","<tr class=`"yellow`">`$+</tr>"
    	$Report = $Report -replace "<tr>(.*)<td>Red</td></tr>","<tr class=`"red`">`$+</tr>"
		$Report = $Report -replace "<tr>(.*)<td>Odd</td></tr>","<tr class=`"odd`">`$+</tr>"
		$Report = $Report -replace "<tr>(.*)<td>Even</td></tr>","<tr class=`"even`">`$+</tr>"
		$Report = $Report -replace "<tr>(.*)<td>None</td></tr>","<tr>`$+</tr>"
		$Report = $Report -replace '<th>RowColor</th>', ''

		if ($Fixed.IsPresent) {	$Report = $Report -replace '<table>', '<table class="fixed">' }
	}
	else {
		$NumberOfColumns = ($ArrayOfObjects | Get-Member -MemberType NoteProperty  | select Name).Count
		$Groupings = @()
		$ArrayOfObjects | select $GroupBy -Unique  | sort $GroupBy | foreach { $Groupings += [String]$_.$GroupBy}
		if ($Fixed.IsPresent) {	$Report = '<table class="fixed">' }
		else { $Report = "<table>" }
		$GroupHeader = $ArrayOfObjects | ConvertTo-Html -Fragment 
		$GroupHeader = $GroupHeader -replace '<col/>', "" -replace '<colgroup>', "" -replace '</colgroup>', "" -replace '<table>', "" -replace '</table>', "" -replace "<td>.+?</td>" -replace "<tr></tr>", ""
		$GroupHeader = $GroupHeader -replace '<th>RowColor</th>', ''
		$Report += $GroupHeader
		foreach ($Group in $Groupings) {
			$Report += "<tr><td colspan=`"$NumberOfColumns`" class=`"groupby`">$Group</td></tr>"
			$GroupBody = $ArrayOfObjects | where { [String]$($_.$GroupBy) -eq $Group } | select * -ExcludeProperty $GroupBy | ConvertTo-Html -Fragment
			$GroupBody = $GroupBody -replace '<col/>', "" -replace '<colgroup>', "" -replace '</colgroup>', "" -replace '<table>', "" -replace '</table>', "" -replace "<th>.+?</th>" -replace "<tr></tr>", "" -replace '<tr><td>', "<tr><td></td><td>"
			$GroupBody = $GroupBody -replace "<tr>(.*)<td>Green</td></tr>","<tr class=`"green`">`$+</tr>"
			$GroupBody = $GroupBody -replace "<tr>(.*)<td>Yellow</td></tr>","<tr class=`"yellow`">`$+</tr>"
    		$GroupBody = $GroupBody -replace "<tr>(.*)<td>Red</td></tr>","<tr class=`"red`">`$+</tr>"
			$GroupBody = $GroupBody -replace "<tr>(.*)<td>Odd</td></tr>","<tr class=`"odd`">`$+</tr>"
			$GroupBody = $GroupBody -replace "<tr>(.*)<td>Even</td></tr>","<tr class=`"even`">`$+</tr>"
			$GroupBody = $GroupBody -replace "<tr>(.*)<td>None</td></tr>","<tr>`$+</tr>"
			$Report += $GroupBody
		}
		$Report += "</table>" 
	}
	$Report = $Report -replace 'URL01', '<a href="'
	$Report = $Report -replace 'URL02', '">'
	$Report = $Report -replace 'URL03', '</a>'
	
	if ($Report -like "*<tr>*" -and $report -like "*odd*" -and $report -like "*even*") {
			$Report = $Report -replace "<tr>",'<tr class="header">'
	}
	
	return $Report
}

function Get-HtmlContentText 
{
<#
	.SYNOPSIS
		Creates an HTML entry with heading and detail
	    .PARAMETER Heading
			The type of logo
		.PARAMETER Detail
		     Some additional pish
#>	
param(
	$Heading,
	$Detail
)

$Report = @"
<table><tbody>
	<tr>
	<th class="content">$Heading</th>
	<td class="content">$($Detail)</td>
	</tr>
</tbody></table>
"@
$Report = $Report -replace 'URL01', '<a href="'
$Report = $Report -replace 'URL02', '">'
$Report = $Report -replace 'URL03', '</a>'
Return $Report
}

function Set-TableRowColor {
<#
	.SYNOPSIS
		adds a row colour field to the array of object for processing with htmltable
	    .PARAMETER ArrayOfObjects
			The type of logo
		.PARAMETER Green
		     Some additional pish
		.PARAMETER Yellow
		     Some additional pish
		.PARAMETER Red
		    use $this and an expression to measure the value
		.PARAMETER Alertnating
			a switch the will define Odd and Even Rows in the rowcolor column 
#>	
Param (
	$ArrayOfObjects, 
	$Green, 
	$Yellow, 
	$Red,
	[switch]$Alternating 
) 
    if ($Alternating) {
		$ColoredArray = $ArrayOfObjects | Add-Member -MemberType ScriptProperty -Name RowColor -Value {
		if ((([array]::indexOf($ArrayOfObjects,$this)) % 2) -eq 0) {'Odd'}
		if ((([array]::indexOf($ArrayOfObjects,$this)) % 2) -eq 1) {'Even'}
		} -PassThru -Force | Select-Object *
	} else {
		$ColoredArray = $ArrayOfObjects | Add-Member -MemberType ScriptProperty -Name RowColor -Value {
			if (Invoke-Expression $Green) {'Green'} 
			elseif (Invoke-Expression $Red) {'Red'} 
			elseif (Invoke-Expression $Yellow) {'Yellow'} 
			else {'None'}
			} -PassThru -Force | Select-Object *
	}
	return $ColoredArray
}

function New-HTMLBarChartObject
{
<#
	.SYNOPSIS
		create a Bar chart object for use with Create-HTMLPieChart
#>	
	$ChartSize = New-Object PSObject -Property @{`
		Width = 500
		Height = 400
		Left = 40
		Top = 30
	}
	
	$DataDefinition = New-Object PSObject -Property @{`
		AxisXTitle = "AxisXTitle"
		AxisYTitle = "AxisYTitle"
		DrawingStyle = "Cylinder"
		DataNameColumnName = "name"
		DataValueColumnName = "count"
		
	}
	
	$ChartStyle = New-Object PSObject -Property @{`
		BackColor = [System.Drawing.Color]::Transparent
		ExplodeMaxValue = $false
		Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right -bor	[System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
	}
	
	$ChartObject = New-Object PSObject -Property @{`
		Type = "Column"
		Title = "Chart Title"
		Size = $ChartSize
		DataDefinition = $DataDefinition
		ChartStyle = $ChartStyle
	}
	return $ChartObject
}

function New-HTMLChart
{
<#
	.SYNOPSIS
		adds a row colour field to the array of object for processing with htmltable
	    .PARAMETER PieChartObject
			This is a custom object with Pie chart properties, Create-HTMLPieChartObject
		.PARAMETER PieChartData
			Required an array with the headings Name and Count.  Using Powershell Group-object on an array
		    
#>
	param (
		$ChartObject,
		$ChartData
	)
	
	[void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
	[void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms.DataVisualization")
	
	#Create our chart object 
	$Chart = New-object System.Windows.Forms.DataVisualization.Charting.Chart
	$Chart.Width = $ChartObject.Size.Width
	$Chart.Height = $ChartObject.Size.Height
	$Chart.Left = $ChartObject.Size.Left
	$Chart.Top = $ChartObject.Size.Top
	
	#Create a chartarea to draw on and add this to the chart 
	$ChartArea = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
	$Chart.ChartAreas.Add($ChartArea)
	[void]$Chart.Series.Add("Data")
	
	#Add a datapoint for each value specified in the arguments (args) 
	foreach ($value in $ChartData)
	{
		$datapoint = new-object System.Windows.Forms.DataVisualization.Charting.DataPoint(0, $value.Count)
		$datapoint.AxisLabel = [string]$value.Name
		$Chart.Series["Data"].Points.Add($datapoint)
	}
	
	switch ($ChartObject.type) {
		"Column"	{
			$Chart.Series["Data"].ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::Column
			$Chart.Series["Data"]["DrawingStyle"] = $ChartObject.ChartStyle.DrawingStyle
			($Chart.Series["Data"].points.FindMaxByValue())["Exploded"] = $ChartObject.ChartStyle.ExplodeMaxValue
		}
		
		"Pie" {
			$Chart.Series["Data"].ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::Pie
			$Chart.Series["Data"]["PieLabelStyle"] = $ChartObject.ChartStyle.PieLabelStyle
			$Chart.Series["Data"]["PieLineColor"] = $ChartObject.ChartStyle.PieLineColor
			$Chart.Series["Data"]["PieDrawingStyle"] = $ChartObject.ChartStyle.PieDrawingStyle
			($Chart.Series["Data"].points.FindMaxByValue())["Exploded"] = $ChartObject.ChartStyle.ExplodeMaxValue
			
		}
		default
		{
				
		}
	}
	
    #Set the title of the Chart to the current date and time 
	$Title = new-object System.Windows.Forms.DataVisualization.Charting.Title
	[Void]$Chart.Titles.Add($Title)
	$Chart.Titles[0].Text = $ChartObject.Title
	
	$tempfile = (Join-Path $env:TEMP $ChartObject.Title.replace(' ', '')) + ".png"
	#Save the chart to a file
	if ((test-path $tempfile)) { Remove-Item $tempfile -Force }
	$Chart.SaveImage($tempfile, "png")
	
	$Base64Chart = [Convert]::ToBase64String((Get-Content $tempfile -Encoding Byte))
	$HTMLCode = '<IMG SRC="data:image/gif;base64,' + $Base64Chart + '" ALT="' + $ChartObject.Title + '">'
	return $HTMLCode
	#return $tempfile
}

function New-HTMLPieChartObject {
<#
	.SYNOPSIS
		create a Pie chart object for use with Create-HTMLPieChart
#>	
	$ChartSize = New-Object PSObject -Property @{`
		Width = 350
		Height = 350 
		Left = 1
		Top = 1
	}
	
	$DataDefinition = New-Object PSObject -Property @{`
		DataNameColumnName = "Name"
		DataValueColumnName = "Count"
	}
	
	$ChartStyle = New-Object PSObject -Property @{`
		#PieLabelStyle = "Outside"
        PieLabelStyle = "Disabled"
		PieLineColor = "Black"
		PieDrawingStyle = "Concave"
		ExplodeMaxValue = $false
	}
	
	$PieChartObject = New-Object PSObject -Property @{`
		Type = "Pie"
		Title = "Chart Title"
		Size = $ChartSize
		DataDefinition = $DataDefinition
		ChartStyle = $ChartStyle
	}
	return $PieChartObject
}

function New-HTMLPieChart {
<#
	.SYNOPSIS
		adds a row colour field to the array of object for processing with htmltable
	    .PARAMETER PieChartObject
			This is a custom object with Pie chart properties, Create-HTMLPieChartObject
		.PARAMETER PieChartData
			Required an array with the headings Name and Count.  Using Powershell Group-object on an array
		    
#>
	param(
		$PieChartObject,
		$PieChartData
		)
	      
	[void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
	[void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms.DataVisualization")

	#Create our chart object 
	$Chart = New-object System.Windows.Forms.DataVisualization.Charting.Chart 
	$Chart.Width = $PieChartObject.Size.Width
	$Chart.Height = $PieChartObject.Size.Height
	$Chart.Left = $PieChartObject.Size.Left
	$Chart.Top = $PieChartObject.Size.Top

	#Create a chartarea to draw on and add this to the chart 
	$ChartArea = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
	$Chart.ChartAreas.Add($ChartArea) 
	[void]$Chart.Series.Add("Data") 

	#Add a datapoint for each value specified in the arguments (args) 
	foreach ($value in $PieChartData) {
		$datapoint = new-object System.Windows.Forms.DataVisualization.Charting.DataPoint(0, $value.Count)
		$datapoint.AxisLabel = [string]$value.Name
		$Chart.Series["Data"].Points.Add($datapoint)
	}
	
	$Chart.Series["Data"].ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::Pie
	$Chart.Series["Data"]["PieLabelStyle"] = $PieChartObject.ChartStyle.PieLabelStyle
	$Chart.Series["Data"]["PieLineColor"] = $PieChartObject.ChartStyle.PieLineColor 
	$Chart.Series["Data"]["PieDrawingStyle"] = $PieChartObject.ChartStyle.PieDrawingStyle
	($Chart.Series["Data"].points.FindMaxByValue())["Exploded"] = $PieChartObject.ChartStyle.ExplodeMaxValue
	

	#Set the title of the Chart to the current date and time 
	$Title = new-object System.Windows.Forms.DataVisualization.Charting.Title 
	[Void]$Chart.Titles.Add($Title) 
	$Chart.Titles[0].Text = $PieChartObject.Title

	$tempfile = (Join-Path $env:TEMP $PieChartObject.Title.replace(' ','') ) + ".png"
	#Save the chart to a file
	if ((test-path $tempfile)) {Remove-Item $tempfile -Force}
	$Chart.SaveImage( $tempfile  ,"png")

	$Base64Chart = [Convert]::ToBase64String((Get-Content $tempfile -Encoding Byte))
	$HTMLCode = '<IMG SRC="data:image/gif;base64,' + $Base64Chart + '" ALT="' + $PieChartObject.Title + '">'
	return $HTMLCode 
	#return $tempfile
	
}

function Get-HTMLColumn1of2
{
	$report = '<div class="first column">'
	return $report
}

function Get-HTMLColumn2of2
{
	$report = '<div class="second column">'
	return $report
}


function Get-HTMLColumnClose
{
	$report = '</div>'
	return $report
}

function Get-SummaryOpen {
[CmdletBinding()]
param (
	[String] $TitleText
)

$Report = @"
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">
<html>

<head>
<title>$($TitleText)</title>
<style type="text/css">
* {    
    margin: 0px;
    font-family: sans-serif;
    font-size: 8pt;
}

body {
    margin: 8px 5px 8px 5px; 
}

hr {
    height: 4px; 
    background-color: #337e94; 
    border: 0px;
}

table {
    table-layout: auto; 
    width: 100%;
    border-collapse: collapse;   
}

th {
    vertical-align: top; 
    text-align: left;
    padding: 2px 5px 2px 5px;
}

td {
    vertical-align: top; 
    padding: 2px 5px 2px 5px;
    border-top: 1px solid #bbbbbb;  
}

div.section {
    padding-bottom: 12px;
} 

div.header {
    border: 1px solid #bbbbbb; 
    margin: 0px 0px -1px 0px;
    height: 2em;
    width: 95%; 
    font-weight: bold ;
    color: #ffffff;
    background-color: #337e94;
}

div.content { 
    border: 1px solid #bbbbbb; 
    margin: 0px 0px -1px 0px;
    width: 95%; 
    color: #000000; 
    background-color: #f9f9f9;
}

div.reportname {
    font-size: 16pt; 
    font-weight: bold;
}

div.footer {
    padding-right: 5em;
    text-align: right; 
}

table.fixed {
    table-layout: fixed; 
}

th.content { 
    border-top: 1px solid #bbbbbb; 
	width: 25%;
}

td.content { 
	width: 75%;
}

td.groupby {
	border-top: 3px double #bbbbbb;
}

.green {
	background-color: #a1cda4;
}

.yellow {
	background-color: #fffab1;
}

.red {
	background-color: #f5a085;
}

.odd {
	background-color: #D5D8DC;
}

.even {
	background-color: #F7F9F9;
}

.header {
	background-color: #616A6B; color: #F7F9F9;
}

</style>

</head>

<div class="section">
    <div class="reportname">$($TitleText)</div>
    <hr/>
    <br>  </br>
</div>
"@
	Return $Report
}

function Get-SummaryClose
{
$Report = @"
<div class="section">
    <hr />
    <div class="footer">$Footer</div>
</div>
    
</body>
</html>
"@
	Write-Output $Report
}
##
$Conn = New-Object System.Data.SqlClient.SQLConnection(Get-ConnectionString)
$Query = "SELECT MachineName, NAME AS ServiceName, DisplayName, Status FROM AXReportAOSServices WHERE REPORTID = '$FileDateTime'"
$Cmd = New-Object System.Data.SqlClient.SqlCommand($Query,$Conn)
$Adapter = New-Object System.Data.SqlClient.SqlDataAdapter
$Adapter.SelectCommand = $Cmd
$AxServices = New-Object System.Data.DataSet
$Adapter.Fill($AxServices)
$AxServicesReport = $AxServices.Tables[0] | Select MachineName, ServiceName, DisplayName, Status
##
$Query = "SELECT HISTORYCAPTION AS [History Caption],JOBCAPTION AS [Job Caption],Status,ServerID AS Server,STARTDATETIMECST AS [Start Time(CST)],ENDDATETIMECST AS [End Time(CST)],EXECUTEDBY AS [User], LOG AS Log
            FROM AXReportBatchJobs 
            WHERE REPORTID = '$FileDateTime'"
$Cmd = New-Object System.Data.SqlClient.SqlCommand($Query,$Conn)
$Adapter = New-Object System.Data.SqlClient.SqlDataAdapter
$Adapter.SelectCommand = $Cmd
$AxBatchJobs = New-Object System.Data.DataSet
$Adapter.Fill($AxBatchJobs)
$AxBatchJobsReport = $AxBatchJobs.Tables[0] | Select 'History Caption', 'Job Caption', 'Status', @{n='Server';e={($_.SERVER -replace '01@','').Trim()}}, 'Start Time(CST)', 'End Time(CST)', 'User', 'Log'
##
$Query = "SELECT Job, Count, Status, Duration, EXECUTEDBY AS [User], ServerID AS [Server]
            FROM AXReportLongBatchJobs 
            --WHERE REPORTID = '$FileDateTime'
            ORDER BY Duration DESC"
$Cmd = New-Object System.Data.SqlClient.SqlCommand($Query,$Conn)
$Adapter = New-Object System.Data.SqlClient.SqlDataAdapter
$Adapter.SelectCommand = $Cmd
$AxLongBatchJobs = New-Object System.Data.DataSet
$Adapter.Fill($AxLongBatchJobs)
$AxLongBatchJobsReport = $AxLongBatchJobs.Tables[0] | Select 'Job', 'Count', 'Status', 'Duration', 'User', 'Server'
##
$Query = "SELECT JobID, STATUSDOWNLOADSESSIONDATASTORE AS [Download Status], Message, DateRequested, DateDownloaded, DateApplied, ROWSAFFECTED as [Rows], DATAFILEOUTPUTPATH as [Path], STATUSDOWNLOADSESSION as [Session Status], DATABASE_ as [Database], Name
            FROM AXReportCDXJobs 
            WHERE REPORTID = '$FileDateTime'"
$Cmd = New-Object System.Data.SqlClient.SqlCommand($Query,$Conn)
$Adapter = New-Object System.Data.SqlClient.SqlDataAdapter
$Adapter.SelectCommand = $Cmd
$AxCDXJobs = New-Object System.Data.DataSet
$Adapter.Fill($AxCDXJobs)
$AxCDXJobsReport = $AxCDXJobs.Tables[0] | Select JobID, 'Download Status', Message, DateRequested, DateDownloaded, DateApplied, Rows, Path, 'Session Status', Database, Name
##
$Query = "SELECT ServerName, ServerType, EntryType as Type, EventID as ID, Source
            FROM AXReportEventLogs 
            WHERE REPORTID = '$FileDateTime' --AND (SOURCE LIKE '%Dynamics%' OR SOURCE LIKE '%MSSQLSERVER%' OR SOURCE LIKE 'Application%')"
$Cmd = New-Object System.Data.SqlClient.SqlCommand($Query,$Conn)
$Adapter = New-Object System.Data.SqlClient.SqlDataAdapter
$Adapter.SelectCommand = $Cmd
$AxEventLogs = New-Object System.Data.DataSet
$Adapter.Fill($AxEventLogs)
$AxEventLogsChart = $AxEventLogs.Tables[0] #| Select ServerName, TimeGenerated, LogName, Type, ID, Source, Message, Count
#
$Query = "SELECT ServerName, Servertype, LogName, EntryType as Type, EventID as ID, Source, Count(1) as Count
            FROM AXReportEventLogs 
            WHERE REPORTID = '$FileDateTime' --AND (SOURCE LIKE '%Dynamics%' OR SOURCE LIKE '%MSSQLSERVER%' OR SOURCE LIKE 'Application%')
            GROUP BY ServerName, Servertype, LogName, EntryType, EventID, Source"

$Cmd = New-Object System.Data.SqlClient.SqlCommand($Query,$Conn)
$Adapter = New-Object System.Data.SqlClient.SqlDataAdapter
$Adapter.SelectCommand = $Cmd
$AxEventLogs = New-Object System.Data.DataSet
$Adapter.Fill($AxEventLogs)
$AxEventLogsReport = $AxEventLogs.Tables[0] | Select ServerName, ServerType, LogName, Type, ID, Source, Count
##
$Query = "SELECT TOP 7 STARTDATETIME as [Start Time(CST)], ENDDATETIME as [End Time(CST)], ((TIMECOPY+TIMECOVERAGE+TIMEUPDATE)/60) AS [TotalTime], Cancelled, USEDTODAYSDATE as [Todays Date], NUMOFITEMS as Items, NUMOFINVENTONHAND as OnHand, NUMOFSALESLINE as SalesLines, NUMOFPURCHLINE as PurchLines, NUMOFTRANSFERPLANNEDORDER as Transfers, NUMOFITEMPLANNEDORDER as Orders, NUMOFINVENTJOURNAL as InventJournals, LOG as Log
            FROM AXReportMRP 
            WHERE REPORTID = '$FileDateTime' AND REQPLANID = 'MFIS'
            ORDER BY STARTDATETIME DESC"
$Cmd = New-Object System.Data.SqlClient.SqlCommand($Query,$Conn)
$Adapter = New-Object System.Data.SqlClient.SqlDataAdapter
$Adapter.SelectCommand = $Cmd
$AxMRPLogs = New-Object System.Data.DataSet
$Adapter.Fill($AxMRPLogs)  
$AxMRPLogsReport = $AxMRPLogs.Tables[0] | Select 'Start Time(CST)', 'End Time(CST)', 'TotalTime', Cancelled, Items, OnHand, SalesLines, PurchLines, Transfers, Orders, InventJournals, Log
##
$Query = "SELECT MAX(LOGDATE) as Date, MAX(PROCESSINFO) as Process, TEXT as Log, MAX(Server) as Server, MAX([Database]) as [Database], COUNT(TEXT) as Count
            FROM AXReportSQLServerLogs
            WHERE REPORTID = '$FileDateTime' AND
		            PROCESSINFO NOT LIKE 'Backup' AND PROCESSINFO NOT LIKE 'Logon' AND
		            TEXT NOT LIKE 'SQL Trace%'
			GROUP BY TEXT
			ORDER BY MAX(LOGDATE)"
$Cmd = New-Object System.Data.SqlClient.SqlCommand($Query,$Conn)
$Adapter = New-Object System.Data.SqlClient.SqlDataAdapter
$Adapter.SelectCommand = $Cmd
$SQLErrorLogs = New-Object System.Data.DataSet
$Adapter.Fill($SQLErrorLogs)
$SQLErrorLogsReport = $SQLErrorLogs.Tables[0] | Select  Date, Process, Log, Server, Database, Count
##
$Query = "SELECT INSTANCENAME as Instance, STATUS as Message, REPORTPATH as Report, COUNT(REPORTPATH) as Count
            FROM AXReportSSRSLogs
            WHERE REPORTID = '$FileDateTime'
            GROUP BY INSTANCENAME, STATUS, REPORTPATH
            ORDER BY COUNT DESC, INSTANCENAME"
$Cmd = New-Object System.Data.SqlClient.SqlCommand($Query,$Conn)
$Adapter = New-Object System.Data.SqlClient.SqlDataAdapter
$Adapter.SelectCommand = $Cmd
$SSRSErrorLogs = New-Object System.Data.DataSet
$Adapter.Fill($SSRSErrorLogs)
$SSRSErrorLogsReport = $SSRSErrorLogs.Tables[0] | Select Instance, Message, Report, Count
#
$Query = "SELECT UserName as [User], COUNT(1) as Count
            FROM AXReportSSRSLogs
            WHERE REPORTID = '$FileDateTime'
            GROUP BY USERNAME
            ORDER BY COUNT DESC"
$Cmd = New-Object System.Data.SqlClient.SqlCommand($Query,$Conn)
$Adapter = New-Object System.Data.SqlClient.SqlDataAdapter
$Adapter.SelectCommand = $Cmd
$SSRSUsers = New-Object System.Data.DataSet
$Adapter.Fill($SSRSUsers)
$SSRSUsersReport = $SSRSUsers.Tables[0]
#
$Query = "SELECT TOP 7 ReportID, CONVERT(date, MAX(TIMESTART)) as [Date], COUNT(1) as Count
            FROM AXReportSSRSLogs
            GROUP BY REPORTID
            ORDER BY REPORTID DESC"
$Cmd = New-Object System.Data.SqlClient.SqlCommand($Query,$Conn)
$Adapter = New-Object System.Data.SqlClient.SqlDataAdapter
$Adapter.SelectCommand = $Cmd
$SSRSWeek = New-Object System.Data.DataSet
$Adapter.Fill($SSRSWeek)
$SSRSWeekReport = $SSRSWeek.Tables[0] | Select @{n='Date';e={($_.Date | Get-Date -Format "MM/dd/yyyy")}}, Count
##
$Query = "SELECT ServerName, ServerType, Counter, CounterType, 
		            CASE  WHEN COUNTER like '%Private Bytes%' THEN SUM(ROUND((MAXIMUM/1073741824),2))
			              WHEN COUNTER like '%Bytes %' THEN SUM(ROUND((MAXIMUM/1024),2))
			              WHEN COUNTER like '%Virtual Bytes%' THEN SUM(ROUND((MAXIMUM/1073741824),2))
			              WHEN COUNTER like '%Working Set%' THEN SUM(ROUND((MAXIMUM/1073741824),2))
			              WHEN COUNTER like '%Available GBytes%' THEN SUM(ROUND((MAXIMUM/1024),2))
			              WHEN COUNTER like '%Total Server Memory%' THEN SUM(ROUND((MAXIMUM/1048576),2))
			              ELSE SUM(ROUND(MAXIMUM,2))
		            END AS Max,
		            CASE  WHEN COUNTER like '%Private Bytes%' THEN SUM(ROUND((MINIMUM/1073741824),2))
			              WHEN COUNTER like '%Bytes %' THEN SUM(ROUND((MINIMUM/1024),2))
			              WHEN COUNTER like '%Virtual Bytes%' THEN SUM(ROUND((MINIMUM/1073741824),2))
			              WHEN COUNTER like '%Working Set%' THEN SUM(ROUND((MINIMUM/1073741824),2))
			              WHEN COUNTER like '%Available GBytes%' THEN SUM(ROUND((MAXIMUM/1024),2))
			              WHEN COUNTER like '%Total Server Memory%' THEN SUM(ROUND((MAXIMUM/1048576),2))
			              ELSE SUM(ROUND(MINIMUM,2))
		            END AS Min,
		            CASE  WHEN COUNTER like '%Private Bytes%' THEN SUM(ROUND((AVERAGE/1073741824),2))
			              WHEN COUNTER like '%Bytes %' THEN SUM(ROUND((AVERAGE/1024),2))
			              WHEN COUNTER like '%Virtual Bytes%' THEN SUM(ROUND((AVERAGE/1073741824),2))
			              WHEN COUNTER like '%Working Set%' THEN SUM(ROUND((AVERAGE/1073741824),2))
			              WHEN COUNTER like '%Available GBytes%' THEN SUM(ROUND((AVERAGE/1024),2))
			              WHEN COUNTER like '%Total Server Memory%' THEN SUM(ROUND((AVERAGE/1048576),2))
			              ELSE SUM(ROUND(AVERAGE,2))
		            END AS Avg,
				COUNT(SERVERName) AS [Check]
            FROM AXReportPerfmonData
            WHERE REPORTID = '$FileDateTime' AND REPORTVIEW = 1
			GROUP BY SERVERName, SERVERTYPE, COUNTER, COUNTERTYPE
            ORDER BY SERVERName"
$Cmd = New-Object System.Data.SqlClient.SqlCommand($Query,$Conn)
$Adapter = New-Object System.Data.SqlClient.SqlDataAdapter
$Adapter.SelectCommand = $Cmd
$PermonDataLogs = New-Object System.Data.DataSet
$Adapter.Fill($PermonDataLogs)
$PermonDataLogsReport = $PermonDataLogs.Tables[0] | Select ServerName, ServerType, Counter, CounterType, Max, Min, Avg
##
$Conn.Close()
##
HTML-Create