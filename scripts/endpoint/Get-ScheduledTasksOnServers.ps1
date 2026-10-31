<#
.SYNOPSIS
    Inventory enabled, non-SYSTEM scheduled tasks on a list of remote servers.
.DESCRIPTION
    For each reachable host in a text file, queries schtasks.exe remotely, keeps enabled tasks that do
    not run as SYSTEM and are not Microsoft/LAPS/msfeedssync built-ins, and appends Server / TaskName /
    RunAs / Task To Run / State / Last Result to ScheduledTasksExport.csv. Unreachable hosts go to
    FailureReport.txt. Useful to find tasks running under personal or service accounts.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : admin rights on the target servers | schtasks.exe
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-ScheduledTasksOnServers.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$ServerListPath = "C:\Scripts\ScheduleTask\Server_List.txt"   # one hostname per line
$ExportFolder   = "C:\Scripts\ScheduleTask"
# -------------------------------------------------------------------------

<#
.SYNOPSIS
This script checks scheduled tasks that use the specified "Run As" account or accounts on a list of devices specified in a text file.

.DESCRIPTION
The script searches for these scheduled tasks by calling schtasks.exe.

.EXAMPLE
ListscheduledTasks -CompList "C:\Scripts\Task_Scheduler\Complist.txt" -RunAsAccount "test1" -ExportLocation "C:\Scripts\Task_Scheduler\"

.EXAMPLE
ListscheduledTasks -CompList "C:\Scripts\Task_Scheduler\Complist.txt" -RunAsAccount "test1","test2" -ExportLocation "C:\Scripts\Task_Scheduler\"
#>

Function ListscheduledTasks {
# Set script parameters
param (
    [parameter(Mandatory = $true)]
    [String]$CompList,

    [parameter(Mandatory = $false)]
    [String[]]$RunAsAccount,

    [parameter(Mandatory = $true)]
    [String]$ExportLocation
)

# Get list of devices to check
$comps = Get-Content $CompList

# Loop through each device
foreach ($comp in $comps) {
    Write-Host "Testing connection to $($comp)" -ForegroundColor DarkGreen
    $TC = Test-Connection $comp -Count 1 -ErrorAction SilentlyContinue

    if ($TC) {
        Write-Host "Checking $($comp)" -ForegroundColor Green

        # Check scheduled tasks for specified "Run As" accounts
        $scheduledTasks = schtasks.exe /query /V /S $comp /FO CSV | ConvertFrom-Csv | Where-Object {$_.'Run As User' -notlike "SYSTEM" -and $_.'Scheduled Task State' -like "Enabled" -and $_.taskname -notlike "*Microsoft*" -and $_.taskname -notlike "*LAPS*" -and $_.'Task To Run' -notlike "*msfeedssync.exe*"}|select *
		#select HostName,'Run As User',taskname,'Task To Run','Last Result'
        foreach ($scheduledTask in $scheduledTasks){

        $taskInfo = [PSCustomObject]@{
        'Server'         = $comp
        'TaskName'       = $scheduledTask.TaskName
        'RunAs'          = $scheduledTask.'Run As User'
        'Task To Run'       = $scheduledTask.'Task To Run'
        'State'          = $scheduledTask.'Scheduled Task State'
        'Last Result'  = $scheduledTask.'Last Result'
         }



        if ($scheduledTask) {
            # Export results
            Write-Host "Tasks found. Exporting results to $($ExportLocation)"
            $taskInfo | Export-Csv "$ExportLocation\ScheduledTasksExport.csv" -NoTypeInformation -Append
        }
        else { Write-Host "No tasks found with specified 'Run As' accounts" -ForegroundColor Yellow}


    }


    }

    else {
        Write-Host "$($comp) not responding. Exporting failures to log file located in $($ExportLocation)" -ForegroundColor Yellow
        $comp | Out-File -FilePath "$ExportLocation\FailureReport.txt"  -Append
         }
    }
}


ListscheduledTasks -CompList $ServerListPath -ExportLocation $ExportFolder
