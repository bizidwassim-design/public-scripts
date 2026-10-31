<#
.SYNOPSIS
    Template to register a weekly scheduled task that runs a PowerShell script under a service account.
.DESCRIPTION
    Builds the action (PowerShell.exe -File), a weekly trigger, a service-account principal with
    highest privileges and battery-friendly settings, then calls Register-ScheduledTask.
    Adjust the EDIT ME block (script path, schedule, account, task name) before running.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin | ScheduledTasks module (built-in)
    Impact      : Modifies the local machine (creates a scheduled task)
    License     : MIT
.EXAMPLE
    .\New-ScheduledTaskTemplate.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$ScriptPath      = "C:\Scripts\My-Script.ps1"
$TaskName        = "My-Task-Name"
$TaskDescription = "What this task does"
$RunAsAccount    = "CONTOSO\svc-scheduler"      # service account (LogonType ServiceAccount)
$DayOfWeek       = "Sunday"
$StartTime       = "03:30"
# -------------------------------------------------------------------------

# Définir l'action (ce qui sera exécuté)
$Action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

# Définir le déclencheur (quand sera exécuté)
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $StartTime

# Définir le principal (sous quel compte)
$Principal = New-ScheduledTaskPrincipal `
    -UserId $RunAsAccount `
    -LogonType ServiceAccount `
    -RunLevel Highest

# Paramètres avancés
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable

# Créer la tâche
Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Settings $Settings `
    -Description $TaskDescription
