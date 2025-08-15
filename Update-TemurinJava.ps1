<#
.SYNOPSIS
    Manages Adoptium Eclipse Temurin OpenJDK/OpenJRE installations, checking for updates and installing new versions

.DESCRIPTION
    This script identifies installed Adoptium Eclipse Temurin OpenJDK and OpenJRE installations,
    checks GitHub releases for newer versions within the same major version, and performs silent updates.
    It can also install new versions when specified. The script self-installs to ProgramData and creates
    a scheduled task for daily update checks.

.PARAMETER Install
    Switch parameter to enable installation mode for new Java versions

.PARAMETER Versions
    Comma-separated list of major Java versions to install (e.g., "8,11,17,21")

.PARAMETER Arch
    Architecture to install: "x64" or "x86"

.PARAMETER Type
    Type of Java to install: "JRE" or "JDK" (defaults to "JRE")

.PARAMETER Force
    Forces the script to copy itself even if it already exists in the target location

.PARAMETER SkipScheduledTask
    Skips the creation of the scheduled task

.EXAMPLE
    .\Update-TemurinJava.ps1
    Checks for updates to existing Temurin installations

.EXAMPLE
    .\Update-TemurinJava.ps1 -Install -Versions "8,17" -Arch "x64" -Type "JRE"
    Installs JRE versions 8 and 17 for x64 architecture

.EXAMPLE
    .\Update-TemurinJava.ps1 -Force
    Forces reinstallation of the script and scheduled task

.NOTES
    Author: System Administrator
    Version: 1.0
    Created: 2025
#>

# ================================
# ===          PARAMS          ===
# ================================
#region Parameters
[CmdletBinding(DefaultParameterSetName = 'Update')]
Param(
    [Parameter(ParameterSetName = 'Install', Mandatory = $true)]
    [Switch]$Install,
    
    [Parameter(ParameterSetName = 'Install', Mandatory = $true)]
    [ValidatePattern('^(\d+,)*\d+$')]
    [String]$Versions,
    
    [Parameter(ParameterSetName = 'Install', Mandatory = $true)]
    [ValidateSet('x64', 'x86')]
    [String]$Arch,
    
    [Parameter(ParameterSetName = 'Install')]
    [ValidateSet('JRE', 'JDK')]
    [String]$Type = 'JRE',
    
    [Parameter(ParameterSetName = 'Update')]
    [Parameter(ParameterSetName = 'Install')]
    [Switch]$Force,
    
    [Parameter(ParameterSetName = 'Update')]
    [Parameter(ParameterSetName = 'Install')]
    [Switch]$SkipScheduledTask
)

#endregion

# ================================
# ===  CONFIG VARS (EDITABLE)  ===
# ================================
#region Configuration Variables (Editable)

# Paths and directories
$Script:InstallPath = 'C:\ProgramData\Update-TemurinJava'
$Script:ScriptName = 'Update-TemurinJava.ps1'
$Script:TempDownloadPath = Join-Path $Script:InstallPath 'Installers'
$Script:LogPath = 'C:\ProgramData\Update-TemurinJava\Logs'

# Scheduled task configuration
$Script:ScheduledTaskName = 'UpdateTemurinJava'
$Script:ScheduledTaskDescription = 'Daily check for Adoptium Eclipse Temurin Java updates'
$Script:ScheduledTaskTime = '08:00:00'

# Update check configuration
$Script:MaxRetryAttempts = 5
$Script:InitialRetryDelaySeconds = 5

#endregion

# ================================
# === CONFIG VARS (DONT EDIT)  ===
# ================================
#region Configuration Variables (Don't Edit)

# GitHub API endpoints for different Java versions
$Script:GitHubRepos = @{
    '8'  = 'https://api.github.com/repos/adoptium/temurin8-binaries/releases/latest'
    '11' = 'https://api.github.com/repos/adoptium/temurin11-binaries/releases/latest'
    '17' = 'https://api.github.com/repos/adoptium/temurin17-binaries/releases/latest'
    '21' = 'https://api.github.com/repos/adoptium/temurin21-binaries/releases/latest'
}

# Architecture mapping for GitHub downloads
$Script:ArchMapping = @{
    'x64' = 'x64_windows'
    'x86' = 'x86-32_windows'
}

# Type mapping for GitHub downloads
$Script:TypeMapping = @{
    'JRE' = 'jre'
    'JDK' = 'jdk'
}

# Script execution context
$Script:LogFileName = 'Update-TemurinJava'
$Script:DefaultLogger = $null
$Script:ConsoleLogger = $null
$Script:Debug = $false

# Temporary file tracking for cleanup
$Script:MSIInstallers = [System.Collections.Generic.List[String]]::new()

#endregion

# ================================
# ===    LOGGING FUNCTIONS     ===
# ================================
#region Logging Functions

Class Logger {
    <#
    .DESCRIPTION
    Class that handles logging operations with multiple options including file rotation, encoding options, and console output

    .EXAMPLE
    # Create a new logger with default settings
    $Logger = [Logger]::new("MyLog")
    $Logger.Write("Hello World!")

    # Create a logger with custom settings
    $Logger = [Logger]::new("ApplicationLog", "C:\Logs", "WARNING")
    $Logger.Write("This is a warning message")
    
    # Create a logger with log rotation settings
    $Logger = [Logger]::new()
    $Logger.LogName = "RotatingLog"
    $Logger.LogRotateOpt = "10M"
    $Logger.LogZip = $True
    $Logger.Write("This message will be in a log that rotates at 10MB")
    #>

    # Required properties
    [string]$LogName
    [string]$LogPath
    [string]$LogLevel
    
    # Optional configuration properties
    [string]$DateTimeFormat
    [bool]$NoLogInfo
    [string]$Encoding
    [bool]$LogRoll
    [int]$LogRetry
    [bool]$WriteConsole
    [bool]$ConsoleOnly
    [bool]$ConsoleInfo
    [string]$LogRotateOpt
    [bool]$LogZip
    [int]$LogCountMax

    # Hidden properties
    hidden [string]$LogFile

    # Default constructor
    Logger() {
        $This.InitializeDefaults()
    }

    # Constructor with basic parameters
    Logger([string]$LogName) {
        $This.InitializeDefaults()
        $This.LogName = $LogName
    }

    # Constructor with extended parameters
    Logger([string]$LogName, [string]$LogPath) {
        $This.InitializeDefaults()
        $This.LogName = $LogName
        $This.LogPath = $LogPath
    }

    # Constructor with most common parameters
    Logger([string]$LogName, [string]$LogPath, [string]$LogLevel) {
        $This.InitializeDefaults()
        $This.LogName = $LogName
        $This.LogPath = $LogPath
        $This.LogLevel = $LogLevel
    }

    # Initialize default values for all properties
    hidden [void] InitializeDefaults() {
        $This.LogName = "Debug"
        $This.LogPath = "C:\Temp"
        $This.LogLevel = "INFO"
        $This.DateTimeFormat = 'yyyy-MM-dd HH:mm:ss'
        $This.NoLogInfo = $False
        $This.Encoding = 'Unicode'
        $This.LogRoll = $False
        $This.LogRetry = 2
        $This.WriteConsole = $False
        $This.ConsoleOnly = $False
        $This.ConsoleInfo = $False
        $This.LogRotateOpt = "1M"
        $This.LogZip = $True
        $This.LogCountMax = 5
        
        # Set the log file path
        $This.LogFile = "$($This.LogPath)\$($This.LogName).log"
    }

    # Update LogFile property when LogName or LogPath changes
    [void] UpdateLogFile() {
        $This.LogFile = "$($This.LogPath)\$($This.LogName).log"
    }

    # Main method to write to the log
    [void] Write([string]$LogMsg) {
        $This.Write($LogMsg, $This.LogLevel)
    }

    # Overload to specify log level
    [void] Write([string]$LogMsg, [string]$LogLevel) {
        # Update log file path if needed
        $This.UpdateLogFile()
        
        # If the Log directory doesn't exist, create it
        If (!(Test-Path -Path $This.LogPath)) {
            New-Item -ItemType "Directory" -Path $This.LogPath > $Null
        }

        # If the log file doesn't exist, create it
        If (!(Test-Path -Path $This.LogFile)) {
            Write-Output "[$([datetime]::Now.ToString($This.DateTimeFormat))][$LogLevel] Logging started" | 
                Out-File -FilePath $This.LogFile -Append -Encoding $This.Encoding
        # Else check if the log needs to be rotated. If rotated, create a new log file.
        } Else {
            If ($This.LogRoll -and ($This.ConfirmLogRotation() -eq $True)) {
                Write-Output "[$([datetime]::Now.ToString($This.DateTimeFormat))][$LogLevel] Log rotated... Logging started" | 
                    Out-File -FilePath $This.LogFile -Append -Encoding $This.Encoding
            }
        }

        # Write to the console
        If ($This.WriteConsole) {
            # Write timestamp and log level to the console
            If ($This.ConsoleInfo) {
                Write-Host "[$([datetime]::Now.ToString($This.DateTimeFormat))][$LogLevel] $LogMsg"
            # Write just the log message to the console
            } Else {
                Write-Host "$LogMsg"
            }

            # Write to the console only and return to stop the function from writing to the log
            If ($This.ConsoleOnly) {
                Return
            }
        }

        # Initialize variables for retrying if writing to log fails
        $Saved = $False
        $Retry = 0
        
        # Retry writing to the log until we have success or have hit the maximum number of retries
        Do {
            # Increment retry by 1
            $Retry++
            
            # Try to write to the log file
            Try {
                # Write to the log without log info (timestamp and log level)
                If ($This.NoLogInfo) {
                    Write-Output "$LogMsg" | Out-File -FilePath $This.LogFile -Append -Encoding $This.Encoding -ErrorAction Stop
                # Write to the log with log info (timestamp and log level)
                } Else {
                    Write-Output "[$([datetime]::Now.ToString($This.DateTimeFormat))][$LogLevel] $LogMsg" | 
                        Out-File -FilePath $This.LogFile -Append -Encoding $This.Encoding -ErrorAction Stop
                }
                
                # Set saved variable to true. We successfully wrote to the log file.
                $Saved = $True
            } Catch {
                If ($Saved -eq $False -and $Retry -eq $This.LogRetry) {
                    # Write the final error to the console. We were not able to write to the log file.
                    Write-Error "Logger couldn't write to the log File $($_.Exception.Message). Tried ($Retry/$($This.LogRetry)))"
                    Write-Error "Err Line: $($_.InvocationInfo.ScriptLineNumber) Err Name: $($_.Exception.GetType().FullName) Err Msg: $($_.Exception.Message)"
                } Else {
                    # Write warning to the console and try again until we hit the maximum configured number of retries
                    Write-Warning "Logger couldn't write to the log File $($_.Exception.Message). Retrying... ($Retry/$($This.LogRetry))"
                    # Sleep for half a second
                    Start-Sleep -Milliseconds 500
                }
            }
        } Until ($Saved -eq $True -or $Retry -ge $This.LogRetry)
    }

    # Convenience methods for different log levels
    [void] WriteInfo([string]$LogMsg) {
        $This.Write($LogMsg, "INFO")
    }

    [void] WriteWarning([string]$LogMsg) {
        $This.Write($LogMsg, "WARNING")
    }

    [void] WriteError([string]$LogMsg) {
        $This.Write($LogMsg, "ERROR")
    }

    [void] WriteDebug([string]$LogMsg) {
        $This.Write($LogMsg, "DEBUG")
    }

    # Method to check if log rotation is needed
    [bool] ConfirmLogRotation() {
        <#
        .DESCRIPTION
        Determines if the log needs to be rotated per the parameters values. It supports rotating log files on disk and stored in a zip archive.
        
        .EXAMPLE
        $Logger = [Logger]::new("MyLog")
        $Logger.LogRotateOpt = "10M"
        $Logger.ConfirmLogRotation()
        #>
        
        # Initialize default return variable. If returned $True, will write a log rotate line to a new log file.
        $LogRolled = $False

        # Get the log name without the file extension
        $This.LogName = "$([System.IO.Path]::GetFileNameWithoutExtension($This.LogFile))"

        # Get the base path to the log file
        $This.LogPath = Split-Path -Path $This.LogFile

        # Initialize the zip archive path
        $ZipPath = "$($This.LogPath)\$($This.LogName)-archive.zip"

        # Initialize the TempLogPath variable to null.
        $TempLogPath = $Null

        # If the zip already exists, we set TempLogPath to a generated user temp folder path
        # This will be used to extract the zip archive before rotating logs
        If (Test-Path $ZipPath) {
            $TempLogPath = "$([System.IO.Path]::GetTempPath())$($This.LogName).archive"
        } 

        # Check If the LogRotateOpt matches the size pattern (e.g., 10M, 5G, 500K)
        If ($This.LogRotateOpt -match '(\d+)([GMK])') {
            $Unit = $matches[2]

            # Calculate the log size and compare it to the LogRotateOpt size
            If ($Unit -eq 'G') {
                # Calculate size with GB
                $RotateSize = [int]$matches[1] * 1GB 
            } ElseIf ($Unit -eq 'M') {
                # Calculate size with MB
                $RotateSize = [int]$matches[1] * 1MB 
            } ElseIf ($Unit -eq 'K') {
                # Calculate size with KB
                $RotateSize = [int]$matches[1] * 1KB 
            } Else {
                Write-Warning "Incorrect log rotation parameter provided. Using default of 1MB."
                $RotateSize = 1 * 1MB
            }

            $LogSize = ((Get-Item -Path $This.LogFile).Length)

            If ($LogSize -gt $RotateSize) {
                If ($This.LogZip) {
                    # Zip archive does not exist yet. Rotate existing logs and put them all inside of a zip archive
                    If (!(Test-Path $ZipPath)) {
                        # Get the list of current log files
                        $LogFiles = Get-ChildItem -Path $This.LogPath -File -Filter "*.log" | 
                            Where-Object { ($_.Name -like "$($This.LogName)*") } | 
                            Sort-Object BaseName
                            
                        # Roll the log files
                        $LogRolled = $This.StartLogRoll($This.LogName, $This.LogPath, $LogFiles)
                        
                        # Update the list of current log files after rotating
                        $LogFiles = Get-ChildItem -Path $This.LogPath -File -Filter "*.log" | 
                            Where-Object { ($_.Name -like "$($This.LogName)*") -and ($_.Name -match '\.\d+') } | 
                            Sort-Object BaseName
                            
                        # Iterate over each log file and compress it into the archive and then delete it off the disk
                        ForEach ($File in $LogFiles) {
                            Compress-Archive -Path "$($This.LogPath)\$($File.Name)" -DestinationPath $ZipPath -Update
                            Remove-Item -Path "$($This.LogPath)\$($File.Name)"
                        }
                        Return $True
                    # Zip archive already exists. Lets extract and rotate some logs
                    } Else {
                        # Ensure the temp folder exists
                        If (-Not (Test-Path -Path $TempLogPath)) {
                            New-Item -Path $TempLogPath -ItemType Directory
                        }

                        # Unzip the File to the temp folder
                        Expand-Archive -Path $ZipPath -DestinationPath $TempLogPath -Force

                        # Get the LogFiles from the temp folder
                        $LogFiles = Get-ChildItem -Path $TempLogPath -File -Filter "*.log" | 
                            Where-Object { ($_.Name -like "$($This.LogName)*") -and ($_.Name -match '\.\d+') } | 
                            Sort-Object BaseName
                        
                        # Roll the log files
                        $LogRolled = $This.StartLogRoll($This.LogName, $This.LogPath, $LogFiles)

                        Write-Host $TempLogPath

                        # Compress and overwrite the old log files inside the existing archive
                        Compress-Archive -Path "$TempLogPath\*" -DestinationPath $ZipPath -Update

                        # Remove the Files we extracted, we no longer need them
                        If (Test-Path $TempLogPath) {
                            Remove-Item -Path $TempLogPath -Recurse -Force
                        }

                        # Return True or False
                        Return $LogRolled
                    }
                # Logs are not zipped, just roll em over
                } Else {
                    $LogFiles = Get-ChildItem -Path $This.LogPath -File -Filter "*.log" | 
                        Where-Object { ($_.Name -like "$($This.LogName)*") } | 
                        Sort-Object BaseName
                    Write-Host $LogFiles
                    $LogRolled = $This.StartLogRoll($This.LogName, $This.LogPath, $LogFiles)
                    Return $LogRolled
                }
            }
        # Check if LogRotateOpt matches the days pattern (e.g., 7, 30, 365)
        } ElseIf ($This.LogRotateOpt -match '^\d+$') {
            # Convert the string digit into an integer
            $RotateDays = [int]$This.LogRotateOpt

            # Get the file's last write time
            $CreationTime = (Get-Item $This.LogFile).CreationTime

            # Calculate the age of the file in days
            $Age = ((Get-Date) - $CreationTime).Days

            # If the age of the file is older than the configured number of days to rotate the log
            If ($Age -gt $RotateDays) {
                If ($This.LogZip) {
                    # Zip archive does not exist yet. Rotate existing logs and put them all inside of a zip archive
                    If (!(Test-Path $ZipPath)) {
                        # Get the list of current log files
                        $LogFiles = Get-ChildItem -Path $This.LogPath -File -Filter "*.log" | 
                            Where-Object { ($_.Name -like "$($This.LogName)*") } | 
                            Sort-Object BaseName
                            
                        # Roll the log files
                        $LogRolled = $This.StartLogRoll($This.LogName, $This.LogPath, $LogFiles)
                        
                        # Update the list of current log files after rotating
                        $LogFiles = Get-ChildItem -Path $This.LogPath -File -Filter "*.log" | 
                            Where-Object { ($_.Name -like "$($This.LogName)*") -and ($_.Name -match '\.\d+') } | 
                            Sort-Object BaseName
                            
                        # Iterate over each log file and compress it into the archive and then delete it off the disk
                        ForEach ($File in $LogFiles) {
                            Compress-Archive -Path "$($This.LogPath)\$($File.Name)" -DestinationPath $ZipPath -Update
                            Remove-Item -Path "$($This.LogPath)\$($File.Name)"
                        }
                        Return $True
                    # Zip archive already exists. Lets extract and rotate some logs
                    } Else {
                        # Ensure the temp folder exists
                        If (-Not (Test-Path -Path $TempLogPath)) {
                            New-Item -Path $TempLogPath -ItemType Directory
                        }

                        # Unzip the File to the temp folder
                        Expand-Archive -Path $ZipPath -DestinationPath $TempLogPath -Force

                        # Get the LogFiles from the temp folder
                        $LogFiles = Get-ChildItem -Path $TempLogPath -File -Filter "*.log" | 
                            Where-Object { ($_.Name -like "$($This.LogName)*") } | 
                            Sort-Object BaseName
                        
                        # Roll the log files
                        $LogRolled = $This.StartLogRoll($This.LogName, $This.LogPath, $LogFiles)

                        # Compress and overwrite the old log files inside the existing archive
                        Compress-Archive -Path "$TempLogPath\*" -DestinationPath $ZipPath -Update -Force

                        # Remove the Files we extracted, we no longer need them
                        If (Test-Path $TempLogPath) {
                            Remove-Item -Path $TempLogPath -Recurse -Force
                        }

                        # Return True or False
                        Return $LogRolled
                    }
                # No zip archiving. Just roll us some logs on the disk.
                } Else {
                    $LogFiles = Get-ChildItem -Path $This.LogPath -File -Filter "*.log" | 
                        Where-Object { ($_.Name -like "$($This.LogName)*") } | 
                        Sort-Object BaseName
                    $LogRolled = $This.StartLogRoll($This.LogName, $This.LogPath, $LogFiles)
                    Return $LogRolled
                }
            }
        } Else {
            Write-Error "Incorrect log rotation parameter provided. Logs will not be rotated!"
        }
        
        # Return false by default if no rotation was triggered
        Return $False
    }

    # Method to perform log rotation
    [bool] StartLogRoll([string]$LogName, [string]$LogPath, [object]$LogFiles) {
        <#
        .DESCRIPTION
        Rolls the logs incrementing the number by 1 and deleting any older logs over the allowed maximum count of log files
        
        .EXAMPLE
        $Logger = [Logger]::new("MyLog")
        $LogFiles = Get-ChildItem -Path $Logger.LogPath -File -Filter "*.log" | Where-Object { ($_.Name -like "$($Logger.LogName)*") -and ($_.Name -match '\.\d+') }
        $Logger.StartLogRoll($Logger.LogName, $Logger.LogPath, $LogFiles)
        #>

        # Get the working log path from the $LogFiles object that was passed to the function. 
        # This may be a temp folder for zip archived logs.
        $WorkingLogPath = $LogFiles[0].Directory

        $LogFiles = Get-ChildItem -Path $WorkingLogPath -File -Filter "*.log" | 
                        Where-Object { ($_.Name -like "$($This.LogName)*") -and ($_.Name -match '\.\d+') } | 
                        Sort-Object BaseName

        # Rotate multiple log files if 1 or more already exists
        If ($LogFiles.Count -gt 0) {
            # Iterate over the log files starting at the highest number and decrement down to 1
            For ($i = $LogFiles.Count; $i -ge 0; $i--) {
                # Get rotating log file that we are working on
                $OperatingFile = $LogFiles | Where-Object {$_.Name -eq "$LogName.$i.log"}
                
                # Check if we are over the maximum allowed rotating log files
                If ($i -ge $This.LogCountMax) {
                    # Remove rotating logs that are over the maximum allowed
                    Remove-Item "$WorkingLogPath\$($OperatingFile.Name)" -Force -ErrorAction Stop
                # If we have iterated down to zero, we are working with the base log file
                } ElseIf ($i -eq 0) {
                    # Set the rotating log number
                    $OperatingNumber = 1
                    # Set the name of the new rotated log name
                    $NewFileName = "$LogName.$OperatingNumber.log" 
                    If ($WorkingLogPath -eq $This.LogPath) {
                        # Rotate the base log
                        Rename-Item -Path "$WorkingLogPath\$LogName.log" -NewName $NewFileName 
                    } Else {
                        Move-Item -Path "$LogPath\$LogName.log" -Destination "$WorkingLogPath\$LogName.1.log"
                    }
                    # Return true since all logs have been rotated
                    Return $True
                # We are iterating through the rotated logs and renaming them as needed
                } Else { 
                    # Set the operating number to be +1 of the current increment
                    $OperatingNumber = $i + 1
                    # Set the name of the new rotated log name
                    $NewFileName = "$LogName.$OperatingNumber.log" 
                    # Rotate the base log
                    Rename-Item -Path "$WorkingLogPath\$LogName.$i.log" -NewName $NewFileName -Force
                } 
            } 
        # Rotate the base log file into its first rotating log file
        } Else {
            Move-Item -Path "$LogPath\$LogName.log" -Destination "$WorkingLogPath\$LogName.1.log"
            # Return true since base log has been rotated
            Return $True
        }

        # Return false since we didn't rotate any logs
        Return $False
    }
}

Function Initialize-Log {
    <#
    .DESCRIPTION
    Initializes the logger class to be used by the write-log function. The class can be saved in a script variable as a default log
    or it will be returned by the function which can be passed to Write-Log function to log into a specific log.

    .PARAMETER LogName
    Name of the log File that will be written to. It will have .log automatically appended as the File extension.

    .PARAMETER LogPath
    Path to the log File. Defaults to a Logs subfolder wherever the script is ran from.

    .PARAMETER LogLevel
    The default log level to be used if a log level is not defined

    .PARAMETER DateTimeFormat
    Format of the timestamp to be displayed in the log File or in optional console output

    .PARAMETER NoLogInfo
    Disable logging time and level in the log File or in optional console output

    .PARAMETER Encoding
    Text encoding to write to the log File with

    .PARAMETER LogRoll
    Enables automatic rolling of the log if set to True.

    .PARAMETER LogRetry
    Number of times to retry writing to the log File. Will wait half a second before trying again. Defaults to 2.

    .PARAMETER WriteConsole
    Switch to write the output to the console

    .PARAMETER ConsoleOnly
    Switch to write the output to the console only without logging to the log file

    .PARAMETER ConsoleInfo
    Switch to write the timestamp and log level during WriteConsole

    .PARAMETER LogRotateOpt
    Size of the log file with unit indicator letter or integer of the number of days to rotate the log file (e.g. 10M = 10 Megabytes or 7 = 7 days)

    .PARAMETER LogZip
    Keeping rotated logs inside of a compressed zip archive

    .PARAMETER LogCountMax
    Maximum number of rotated log files to keep

    .OUTPUTS
    Intialized log class that can be passed to the Write-Log function

    .EXAMPLE
    # Initialize a default log with default settings
    Initialize-Log -Default
    Write-Log "This message will go to the default log (Debug.log)"
    
    .EXAMPLE
    # Initialize a custom named log
    $AppLog = Initialize-Log -LogName "Application"
    Write-Log "This message goes to Application.log" -Logger $AppLog
    
    .EXAMPLE
    # Initialize a log with custom name and path
    $CustomPathLog = Initialize-Log -LogName "Process" -LogPath "D:\Logs\System"
    Write-Log "This message goes to D:\Logs\System\Process.log" -Logger $CustomPathLog
    
    .EXAMPLE
    # Initialize a log with a custom name and a different default log level
    $ErrorLog = Initialize-Log -LogName "Errors" -LogLevel "ERROR"
    Write-Log "This will be logged as an ERROR" -Logger $ErrorLog
    
    .EXAMPLE
    # Initialize a log with a custom name and a custom date/time format
    $CustomTimeLog = Initialize-Log -LogName "TimeLog" -DateTimeFormat "MM/dd/yyyy HH:mm:ss"
    Write-Log "This will have a custom timestamp format" -Logger $CustomTimeLog
    
    .EXAMPLE
    # Initialize a log a custom name and without timestamp and level in log entries
    $CleanLog = Initialize-Log -LogName "Clean" -NoLogInfo
    Write-Log "This message will appear without timestamp or level prefix" -Logger $CleanLog
    
    .EXAMPLE
    # Initialize a log with console output
    $ConsoleLog = Initialize-Log -LogName "Console" -WriteConsole
    Write-Log "This appears in both the log file and console" -Logger $ConsoleLog
    
    .EXAMPLE
    # Initialize a log with console-only output (no file writing)
    $ConsoleOnlyLog = Initialize-Log -LogName "ConsoleOnly" -WriteConsole -ConsoleOnly
    Write-Log "This only appears in the console, not in any log file" -Logger $ConsoleOnlyLog
    
    .EXAMPLE
    # Initialize a log with console output including timestamp and level
    $VerboseConsoleLog = Initialize-Log -LogName "VerboseConsole" -WriteConsole -ConsoleInfo
    Write-Log "This shows in console with timestamp and level" -Logger $VerboseConsoleLog
    
    .EXAMPLE
    # Initialize a log with log rotation by size
    $RotatingLog = Initialize-Log -LogName "Rotating" -LogRoll $True -LogRotateOpt "10M"
    Write-Log "This log will rotate when it reaches 10MB" -Logger $RotatingLog
    
    .EXAMPLE
    # Initialize a log with rotation by days
    $DailyLog = Initialize-Log -LogName "Daily" -LogRoll $True -LogRotateOpt "1"
    Write-Log "This log will rotate daily" -Logger $DailyLog
    
    .EXAMPLE
    # Initialize a log with rotation and zip archiving
    $ZipLog = Initialize-Log -LogName "ZippedLogs" -LogRoll $True -LogRotateOpt "5M" -LogZip $True
    Write-Log "Rotated logs will be stored in a zip archive" -Logger $ZipLog
    
    .EXAMPLE
    # Initialize a log with custom retry count
    $RetryLog = Initialize-Log -LogName "Retry" -LogRetry 5
    Write-Log "Will try 5 times if writing to log fails" -Logger $RetryLog
    
    .EXAMPLE
    # Initialize a log with custom encoding
    $Utf8Log = Initialize-Log -LogName "UTF8Log" -Encoding "utf8"
    Write-Log "This will be written with UTF-8 encoding" -Logger $Utf8Log
    
    .EXAMPLE
    # Initialize a log with a limit on the number of rotated files
    $LimitedLog = Initialize-Log -LogName "Limited" -LogRoll $True -LogCountMax 3
    Write-Log "Only 3 rotated log files will be kept" -Logger $LimitedLog
    
    .EXAMPLE
    # Initialize a default log and access it from anywhere in the script
    Initialize-Log -Default -LogName "GlobalLog" -WriteConsole
    # Later in the script, without passing a Logger object:
    Write-Log "This uses the default log configuration"

    #>

    Param(
        [alias ('D')][switch] $Default,
        [alias ('LN')][string] $LogName = "Debug",
        [alias ('LP')][string] $LogPath = "C:\Temp",
        [alias ('LL', 'LogLvl')][string] $LogLevel = "INFO",
        [Alias('TF', 'DF', 'DateFormat', 'TimeFormat')][string] $DateTimeFormat = 'yyyy-MM-dd HH:mm:ss',
        [alias ('NLI')][switch] $NoLogInfo,
        [ValidateSet('unknown', 'string', 'unicode', 'bigendianunicode', 'utf8', 'utf7', 'utf32', 'ascii', 'default', 'oem')][string]$Encoding = 'Unicode',
        [alias ('Retry')][int] $LogRetry = 2,
        [alias('WC', 'Console')][switch] $WriteConsole,
        [alias('CO')][switch] $ConsoleOnly,
        [alias('CI')][switch] $ConsoleInfo,
        [alias ('LR', 'Roll')][switch] $LogRoll,
        [alias ('RotateOpt')][string] $LogRotateOpt = "1M",
        [alias('Zip')][switch] $LogZip,
        [alias('LF', 'LogFiles')][int]$LogCountMax = 5
    )

    # Create a new logger instance
    $Logger = [Logger]::new()

    # Set all properties from parameters
    $Logger.LogName = $LogName
    $Logger.LogPath = $LogPath
    $Logger.LogLevel = $LogLevel
    $Logger.DateTimeFormat = $DateTimeFormat
    $Logger.NoLogInfo = $NoLogInfo
    $Logger.Encoding = $Encoding
    $Logger.LogRoll = $LogRoll
    $Logger.LogRetry = $LogRetry
    $Logger.WriteConsole = $WriteConsole
    $Logger.ConsoleOnly = $ConsoleOnly
    $Logger.ConsoleInfo = $ConsoleInfo
    $Logger.LogRotateOpt = $LogRotateOpt
    $Logger.LogZip = $LogZip
    $Logger.LogCountMax = $LogCountMax

    If ($Default) {
        $Script:DefaultLog = $Logger
        Return
    }

    Return $Logger
}

Function Write-Log {
    <#
    .DESCRIPTION
    Writes output to a log File provided by the logger class. The logger needs to be intialized with Intialize-Logger function first
    and either be configured as the default log file or the logger class that is returned has to be passed to this function to specify
    the log to write to.

    .PARAMETER LogMsg
    Message to be written to the log

    .PARAMETER LogLevel
    Name of a label to indicate the severity of the log

    .PARAMETER Logger
    Log class to be used to write to a log file. If a default log class was not initialized, this is a require parameter.

    .EXAMPLE
    # Writing to the default log class if one was initialized
    Write-Log "This will write a INFO level message to the default log called debug.log"
    Write-Log "This will write a WARNING level message to the default log called debug.log" -LogLevel "WARNING"

    .EXAMPLE
    # Writing to a non-default log class
    $DebugLog = Initialize-Log -LogName "Debug"
    Write-Log "This will write a WARNING level message to a log called Debug.log" -LogLevel "WARNING" -Logger $DebugLog
    #>
    Param(
        [alias ('LM', 'Msg', 'Message')][Parameter(Mandatory=$True)][String] $LogMsg,
        [alias ('LL', 'LogLvl', 'Level')][string] $LogLevel = "INFO",
        [alias ('L', 'Log')] $Logger = $Script:DefaultLog
    )

    If (-not $Logger) {
        Write-Error "No log class has been initialized. Initialize a default log class or provide an initialized log class."
    } Else {
        # Write the log entry
        $Logger.Write($LogMsg, $LogLevel)
    }
}

#endregion

# ================================
# ===    HELPER FUNCTIONS      ===
# ================================
#region Helper Functions

Function Get-MsiExitCodeDescription {
    <#
    .SYNOPSIS
    Returns a description for MSI installer exit codes
    
    .DESCRIPTION
    Provides human-readable descriptions for Windows Installer (msiexec) exit codes
    based on Microsoft documentation
    
    .PARAMETER ExitCode
    The exit code returned by msiexec
    
    .EXAMPLE
    Get-MsiExitCodeDescription -ExitCode 1619
    Returns: "This installation package could not be opened. Verify that the package exists and is accessible."
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [Int32]$ExitCode
    )
    
    $ExitCodes = @{
        0 = 'Success. The action completed successfully.'
        13 = 'The data is invalid.'
        87 = 'One of the parameters was invalid.'
        120 = 'This value is returned when a custom action attempts to call a function that cannot be called from custom actions. The function returns the value ERROR_CALL_NOT_IMPLEMENTED.'
        1259 = 'If Windows Installer determines a product may be incompatible with the current operating system, it displays a dialog box informing the user and asking whether to try to install anyway. This error code is returned if the user chooses not to try the installation.'
        1601 = 'The Windows Installer service could not be accessed. Contact your support personnel to verify that the Windows Installer service is properly registered.'
        1602 = 'User cancelled installation.'
        1603 = 'A fatal error occurred during installation.'
        1604 = 'Installation suspended, incomplete.'
        1605 = 'This action is only valid for products that are currently installed.'
        1606 = 'Feature ID not registered.'
        1607 = 'Component ID not registered.'
        1608 = 'Unknown property.'
        1609 = 'Handle is in an invalid state.'
        1610 = 'The configuration data for this product is corrupt. Contact your support personnel.'
        1611 = 'Component qualifier not present.'
        1612 = 'The installation source for this product is not available. Verify that the source exists and that you can access it.'
        1613 = 'This installation package cannot be installed by the Windows Installer service. You must install a Windows service pack that contains a newer version of the Windows Installer service.'
        1614 = 'Product is uninstalled.'
        1615 = 'SQL query syntax invalid or unsupported.'
        1616 = 'Record field does not exist.'
        1618 = 'Another installation is already in progress. Complete that installation before proceeding with this install.'
        1619 = 'This installation package could not be opened. Verify that the package exists and is accessible, or contact the application vendor to verify that this is a valid Windows Installer package.'
        1620 = 'This installation package could not be opened. Contact the application vendor to verify that this is a valid Windows Installer package.'
        1621 = 'There was an error starting the Windows Installer service user interface. Contact your support personnel.'
        1622 = 'There was an error opening installation log file. Verify that the specified log file location exists and is writable.'
        1623 = 'This language of this installation package is not supported by your system.'
        1624 = 'There was an error applying transforms. Verify that the specified transform paths are valid.'
        1625 = 'This installation is forbidden by system policy. Contact your system administrator.'
        1626 = 'Function could not be executed.'
        1627 = 'Function failed during execution.'
        1628 = 'Invalid or unknown table specified.'
        1629 = 'Data supplied is of wrong type.'
        1630 = 'Data of this type is not supported.'
        1631 = 'The Windows Installer service failed to start. Contact your support personnel.'
        1632 = 'The Temp folder is either full or inaccessible. Verify that the Temp folder exists and that you can write to it.'
        1633 = 'This installation package is not supported on this platform. Contact your application vendor.'
        1634 = 'Component is not used on this machine.'
        1635 = 'This patch package could not be opened. Verify that the patch package exists and is accessible, or contact the application vendor to verify that this is a valid Windows Installer patch package.'
        1636 = 'This patch package could not be opened. Contact the application vendor to verify that this is a valid Windows Installer patch package.'
        1637 = 'This patch package cannot be processed by the Windows Installer service. You must install a Windows service pack that contains a newer version of the Windows Installer service.'
        1638 = 'Another version of this product is already installed. Installation of this version cannot continue. To configure or remove the existing version of this product, use Add/Remove Programs in Control Panel.'
        1639 = 'Invalid command line argument. Consult the Windows Installer SDK for detailed command-line help.'
        1640 = 'The current user is not permitted to perform installations from a client session of a server running the Terminal Server role service.'
        1641 = 'The installer has initiated a restart. This message is indicative of a success.'
        1642 = 'The installer cannot install the upgrade patch because the program being upgraded may be missing or the upgrade patch updates a different version of the program. Verify that the program to be upgraded exists on your computer and that you have the correct upgrade patch.'
        1643 = 'The patch package is not permitted by system policy.'
        1644 = 'One or more customizations are not permitted by system policy.'
        1645 = 'Windows Installer does not permit installation from a Remote Desktop Connection.'
        1646 = 'The patch package is not a removable patch package. Available beginning with Windows Installer version 3.0.'
        1647 = 'The patch is not applied to this product. Available beginning with Windows Installer version 3.0.'
        1648 = 'No valid sequence could be found for the set of patches. Available beginning with Windows Installer version 3.0.'
        1649 = 'Patch removal was disallowed by policy. Available beginning with Windows Installer version 3.0.'
        1650 = 'The XML patch data is invalid. Available beginning with Windows Installer version 3.0.'
        1651 = 'Administrative user failed to apply patch for a per-user managed or a per-machine application that is in advertise state. Available beginning with Windows Installer version 3.0.'
        1652 = 'Windows Installer is not accessible when the computer is in Safe Mode. Exit Safe Mode and try again or try using System Restore to return your computer to a previous state. Available beginning with Windows Installer version 4.0.'
        1653 = 'Could not perform a multiple-package transaction because rollback has been disabled. Multiple-Package Installations cannot run if rollback is disabled. Available beginning with Windows Installer version 4.5.'
        1654 = 'The app that you are trying to run is not supported on this version of Windows. A Windows Installer package, patch, or transform that has not been signed by Microsoft cannot be installed on an ARM computer.'
        3010 = 'A restart is required to complete the install. This message is indicative of a success. This does not include installs where the ForceReboot action is run.'
        3011 = 'The requested operation is successful. Changes will not be effective until the system is rebooted.'
    }
    
    If ($ExitCodes.ContainsKey($ExitCode)) {
        Return $ExitCodes[$ExitCode]
    } Else {
        Return "Unknown exit code. Please refer to Windows Installer documentation for exit code: $ExitCode"
    }
}

Function Get-MsiLogPath {
    <#
    .SYNOPSIS
    Generates a unique MSI log file path for debugging installations
    
    .DESCRIPTION
    Creates a timestamped log file path for MSI installations to help with debugging
    
    .PARAMETER MsiFileName
    The name of the MSI file being installed
    
    .PARAMETER Operation
    The operation type (Install, Uninstall, Update)
    
    .EXAMPLE
    Get-MsiLogPath -MsiFileName "OpenJDK8U-jre_x64.msi" -Operation "Install"
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [String]$MsiFileName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('Install', 'Uninstall', 'Update')]
        [String]$Operation
    )
    
    # Ensure log directory exists
    If (-not (Test-Path $Script:LogPath)) {
        New-Item -Path $Script:LogPath -ItemType Directory -Force | Out-Null
    }
    
    # Create MSI logs subdirectory
    $MsiLogDir = Join-Path $Script:LogPath 'MSI_Logs'
    If (-not (Test-Path $MsiLogDir)) {
        New-Item -Path $MsiLogDir -ItemType Directory -Force | Out-Null
    }
    
    # Generate unique log filename with timestamp
    $Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $SafeMsiName = [System.IO.Path]::GetFileNameWithoutExtension($MsiFileName)
    $LogFileName = "${SafeMsiName}_${Operation}_${Timestamp}.log"
    
    Return Join-Path $MsiLogDir $LogFileName
}

Function Get-HttpClientDownload {
    <#
    .SYNOPSIS
        Downloads a file using System.Net.Http.HttpClient
    
    .DESCRIPTION
        A simple, efficient file download function using the modern System.Net.Http.HttpClient
        class. Compatible with PowerShell 5.1+ and .NET Framework 4.5+. Provides better
        performance and connection management compared to deprecated WebClient or Invoke-WebRequest.
    
    .PARAMETER Url
        The URL of the file to download
    
    .PARAMETER OutputPath
        The full path where the file will be saved
    
    .PARAMETER TimeoutSeconds
        Request timeout in seconds (default: 300)
    
    .PARAMETER BufferSize
        Buffer size for reading response stream in bytes (default: 65536)
    
    .PARAMETER ProgressBar
        Switch parameter to show download progress bar (default: false)
    
    .PARAMETER UserAgent
        Custom user agent string (default: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.3)
    
    .PARAMETER Headers
        Additional headers to include in the request as a hashtable
    
    .PARAMETER OverwriteExisting
        Overwrite existing file without prompting (default: false)
    
    .EXAMPLE
        Get-HttpClientDownload -Url 'https://example.com/file.zip' -OutputPath 'C:\Downloads\file.zip'
        
    .EXAMPLE
        Get-HttpClientDownload -Url 'https://example.com/largefile.iso' -OutputPath 'C:\largefile.iso' -ProgressBar
        
    .EXAMPLE
        Get-HttpClientDownload -Url 'https://api.example.com/file' -OutputPath 'C:\file.dat' -Headers @{'Authorization' = 'Bearer token123'}
        
    .EXAMPLE
        Get-HttpClientDownload -Url 'https://example.com/file.pdf' -OutputPath 'C:\file.pdf' -ProgressBar -TimeoutSeconds 600
    #>
    
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]$Url,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]$OutputPath,
        
        [Parameter()]
        [ValidateRange(30, 3600)]
        [Int32]$TimeoutSeconds = 300,
        
        [Parameter()]
        [ValidateRange(8192, 1048576)]
        [Int32]$BufferSize = 65536,
        
        [Parameter()]
        [Switch]$ProgressBar,
        
        [Parameter()]
        [String]$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.3',
        
        [Parameter()]
        [Hashtable]$Headers = @{},
        
        [Parameter()]
        [Switch]$OverwriteExisting
    )
    
    # Load System.Net.Http assembly (required for PowerShell 5.1)
    Try {
        Add-Type -AssemblyName 'System.Net.Http'
    } Catch {
        Throw "Failed to load System.Net.Http assembly. Ensure .NET Framework 4.5+ is installed: $($_.Exception.Message)"
        Exit 1
    }
    
    # Validate and create output directory
    $OutputDir = [System.IO.Path]::GetDirectoryName($OutputPath)
    If (-not (Test-Path -Path $OutputDir -PathType Container)) {
        Try {
            Write-Log "Creating output directory: $OutputDir"
            New-Item -Path $OutputDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        } Catch {
            Throw "Cannot create output directory '$OutputDir': $($_.Exception.Message)"
            Exit 1
        }
    }
    
    # Check if file exists and handle accordingly
    If ((Test-Path -Path $OutputPath) -and -not $OverwriteExisting) {
        Write-Log 'File already exists. Use OverwriteExisting parameter to overwrite the file.' -LogLevel 'INFO'
        Return
    }
    
    # Validate URL format
    Try {
        $Uri = [System.Uri]::new($Url)
        If ($Uri.Scheme -notin @('http', 'https')) {
            Throw "Unsupported URL scheme: $($Uri.Scheme). Only HTTP and HTTPS are supported."
            Exit 1
        }
    } Catch {
        Throw "Invalid URL format: $($_.Exception.Message)"
        Exit 1
    }
    
    Write-Log "Starting download..."
    Write-Log "Source: $Url" -LogLevel 'DEBUG'
    Write-Log "Destination: $OutputPath" -LogLevel 'DEBUG'
    Write-Log "Using System.Net.Http.HttpClient with .NET Framework" -LogLevel 'DEBUG'
    Write-Log "Timeout: $TimeoutSeconds seconds" -LogLevel 'DEBUG'
    Write-Log "Buffer size: $BufferSize bytes" -LogLevel 'DEBUG'
    
    $HttpClient = $null
    $Response = $null
    $ResponseStream = $null
    $FileStream = $null
    $StartTime = Get-Date
    
    Try {
        # Create and configure HttpClient
        $HttpClient = New-Object System.Net.Http.HttpClient
        $HttpClient.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
        
        # Set default headers
        $HttpClient.DefaultRequestHeaders.Add('User-Agent', $UserAgent)
        
        # Add custom headers if provided
        ForEach ($Header in $Headers.GetEnumerator()) {
            Try {
                $HttpClient.DefaultRequestHeaders.Add($Header.Key, $Header.Value)
                Write-Log "Added header: $($Header.Key) = $($Header.Value)" -LogLevel 'DEBUG'
            } Catch {
                Write-Log "Failed to add header '$($Header.Key)': $($_.Exception.Message)" -LogLevel 'WARNING'
            }
        }
        
        Write-Log "Sending HTTP GET request..." -LogLevel 'DEBUG'
        
        # Send the request and get response
        $Response = $HttpClient.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
        
        # Check if request was successful
        If (-not $Response.IsSuccessStatusCode) {
            Throw "HTTP request failed with status: $($Response.StatusCode) ($([Int32]$Response.StatusCode)) - $($Response.ReasonPhrase)"
        }
        
        Write-Log "Response received successfully" -LogLevel 'DEBUG'
        Write-Log "Status: $($Response.StatusCode) - $($Response.ReasonPhrase)" -LogLevel 'DEBUG'
        Write-Log "Content-Type: $($Response.Content.Headers.ContentType)" -LogLevel 'DEBUG'
        
        # Get content length for progress tracking
        $ContentLength = $Response.Content.Headers.ContentLength
        If ($ContentLength) {
            Write-Log "File size: $([Math]::Round($ContentLength / 1MB, 2)) MB ($ContentLength bytes)" -LogLevel 'DEBUG'
        } Else {
            Write-Log "Content-Length header not provided by server. Progress tracking will be limited." -LogLevel 'WARNING'
        }
        
        # Get response stream
        $ResponseStream = $Response.Content.ReadAsStreamAsync().Result
        
        # Create output file stream
        $FileStream = [System.IO.FileStream]::new($OutputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        
        # Download file with progress tracking
        $Buffer = New-Object Byte[] $BufferSize
        $TotalBytesRead = 0
        $BytesRead = 0
        $LastProgressUpdate = Get-Date
        $ProgressUpdateInterval = [TimeSpan]::FromMilliseconds(250) # Update progress every 250ms
        
        Write-Log "Starting file transfer..."
        
        Do {
            $BytesRead = $ResponseStream.ReadAsync($Buffer, 0, $Buffer.Length).Result
            
            If ($BytesRead -gt 0) {
                $FileStream.Write($Buffer, 0, $BytesRead)
                $TotalBytesRead += $BytesRead
                
                # Update progress bar if enabled and content length is known
                If ($ProgressBar -and $ContentLength -and ((Get-Date) - $LastProgressUpdate) -ge $ProgressUpdateInterval) {
                    $PercentComplete = [Math]::Round(($TotalBytesRead / $ContentLength) * 100, 1)
                    $CurrentSpeed = ($TotalBytesRead / 1MB) / ((Get-Date) - $StartTime).TotalSeconds
                    
                    $ProgressStatus = "Downloaded: $([Math]::Round($TotalBytesRead / 1MB, 2)) MB"
                    If ($ContentLength) {
                        $ProgressStatus += " of $([Math]::Round($ContentLength / 1MB, 2)) MB"
                    }
                    $ProgressStatus += " @ $([Math]::Round($CurrentSpeed, 2)) MB/s"
                    
                    Write-Progress -Activity 'HttpClient File Download' -Status $ProgressStatus -PercentComplete $PercentComplete
                    $LastProgressUpdate = Get-Date
                }
            }
            
        } While ($BytesRead -gt 0)
        
        # Close streams
        $FileStream.Close()
        $ResponseStream.Close()
        
        # Clear progress bar if it was shown
        If ($ProgressBar) {
            Write-Progress -Activity 'HttpClient File Download' -Completed
        }
        
        # Verify file was created and has content
        If (Test-Path -Path $OutputPath) {
            $DownloadedFile = Get-Item -Path $OutputPath
            $EndTime = Get-Date
            $Duration = ($EndTime - $StartTime).TotalSeconds
            $AverageSpeed = ($DownloadedFile.Length / 1MB) / $Duration
            
            # Verify file size matches if Content-Length was provided
            If ($ContentLength -and ($DownloadedFile.Length -ne $ContentLength)) {
                Write-Log "File size mismatch: Expected $ContentLength bytes, got $($DownloadedFile.Length) bytes" -LogLevel 'WARNING'
            }
            
           
            # Return file information object
            Return @{
                Success = $true
                FilePath = $OutputPath
                FileSize = $DownloadedFile.Length
                FileSizeMB = [Math]::Round($DownloadedFile.Length / 1MB, 2)
                Duration = $Duration
                AverageSpeed = $AverageSpeed
                Url = $Url
                HttpStatusCode = $Response.StatusCode
                ContentType = $Response.Content.Headers.ContentType
            }
            
        } Else {
            Throw "OutputPath does not exist, file was not downloaded."
        }
        
    } Catch {
        # Clean up partial file on error
        If (Test-Path -Path $OutputPath) {
            Try {
                Remove-Item -Path $OutputPath -Force -ErrorAction SilentlyContinue
                Write-Log "Cleaned up partial file due to error"
            } Catch {
                Write-Log "Could not clean up partial file: $($_.Exception.Message)" -LogLevel 'WARNING'
            }
        }
        
        # Clear progress bar if it was shown
        If ($ProgressBar) {
            Write-Progress -Activity 'HttpClient File Download' -Completed
        }
        
        Write-Log "Download failed: $($_.Exception.Message)" -LogLevel 'ERROR'
        Throw
        
    } Finally {
        # Dispose of all resources
        If ($FileStream) {
            Try { $FileStream.Dispose() } Catch { }
        }
        If ($ResponseStream) {
            Try { $ResponseStream.Dispose() } Catch { }
        }
        If ($Response) {
            Try { $Response.Dispose() } Catch { }
        }
        If ($HttpClient) {
            Try { $HttpClient.Dispose() } Catch { }
        }
        
        Write-Log "Resources cleaned up successfully"
    }
}

Function Get-InstalledApplication {
    <#
    .SYNOPSIS
    Retrieves installed applications from the local computer with enhanced performance and comprehensive property collection.

    .DESCRIPTION
    This function queries the Windows Registry to retrieve information about installed applications
    on the local computer. It searches both 32-bit and 64-bit application registries and
    returns detailed information about each installed application.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String[]]$Properties,

        [Parameter(Position = 1)]
        [ValidatePattern('^(\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}|[A-Za-z0-9\-\.\_]+)$')]
        [String]$IdentifyingNumber,

        [Parameter(Position = 2)]
        [ValidateNotNullOrEmpty()]
        [String]$Name,

        [Parameter(Position = 3)]
        [ValidateNotNullOrEmpty()]
        [String]$Publisher
    )

    Begin {
        # Internal helper function to determine if CPU architecture is x86
        Function Test-CPUx86 {
            [CmdletBinding()]
            [OutputType([Boolean])]
            Param(
                [Parameter(Mandatory = $true)]
                [ValidateNotNull()]
                [Microsoft.Win32.RegistryKey]$HklmHive
            )
            
            Try {
                $RegPath = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
                $Key = $HklmHive.OpenSubKey($RegPath)

                If ($null -eq $Key) {
                    Write-Warning "Unable to access registry key: $($RegPath)"
                    Return $false
                }

                $CpuArch = $Key.GetValue('PROCESSOR_ARCHITECTURE')
                $IsX86 = $CpuArch -eq 'x86'
                
                Write-Verbose "Detected CPU architecture: $($CpuArch) (x86: $($IsX86))"
                Return $IsX86
                
            } Catch {
                Write-Warning "Error determining CPU architecture: $($_.Exception.Message)"
                Return $false
            } Finally {
                If ($null -ne $Key) {
                    $Key.Dispose()
                }
            }
        }

        Write-Verbose "Starting Get-InstalledApplication at $(Get-Date)"
        
        $RegPaths = [System.Collections.Generic.List[String]]::new()
        $RegPaths.Add('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
        $RegPaths.Add('SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
        
        $StandardProperties = [System.Collections.Generic.List[String]]::new()
        $StandardPropertiesArray = [String[]]@(
            'DisplayName', 'DisplayVersion', 'EstimatedSize', 'InstallDate',
            'InstallLocation', 'InstallSource', 'UninstallString', 'Publisher',
            'ProductCode', 'VersionMajor', 'VersionMinor', 'Language', 'SystemComponent',
            'WindowsInstaller', 'ParentKeyName', 'ParentDisplayName'
        )
        $StandardProperties.AddRange($StandardPropertiesArray)
    }

    Process {
        Try {
            Write-Verbose "Processing local computer: $($ENV:COMPUTERNAME)"
            
            $Hive = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                [Microsoft.Win32.RegistryHive]::LocalMachine, 
                [Microsoft.Win32.RegistryView]::Default
            )
            
            If ($null -eq $Hive) {
                Write-Error "Failed to connect to local registry"
                Return
            }
            
            If (Test-CPUx86 -HklmHive $Hive) {
                Write-Verbose "Detected x86 architecture, using single registry path"
                $RegPaths = [System.Collections.Generic.List[String]]::new()
                $RegPaths.Add('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
            }

            $Results = [System.Collections.Generic.List[PSObject]]::new()

            ForEach ($Path in $RegPaths) {
                Try {
                    $Key = $Hive.OpenSubKey($Path)
                    
                    If ($null -eq $Key) {
                        Write-Verbose "Registry path not found: $($Path)"
                        Continue
                    }
                    
                    $SubKeyNames = $Key.GetSubKeyNames()
                    Write-Verbose "Found $($SubKeyNames.Count) entries in $($Path)"
                    
                    ForEach ($SubKey in $SubKeyNames) {
                        Try {
                            If ($PSBoundParameters.ContainsKey('IdentifyingNumber')) {
                                $NormalizedSubKey = $SubKey.TrimStart('{').TrimEnd('}')
                                $NormalizedIdentifyingNumber = $IdentifyingNumber.TrimStart('{').TrimEnd('}')
                            
                                If ($NormalizedSubKey -ne $NormalizedIdentifyingNumber -and $SubKey -ne $IdentifyingNumber) {
                                    Continue
                                }
                            }
                            
                            $SubKeyObj = $Key.OpenSubKey($SubKey)
                            If ($null -eq $SubKeyObj) {
                                Write-Verbose "Unable to open subkey: $($SubKey)"
                                Continue
                            }
                            
                            $AppName = $SubKeyObj.GetValue('DisplayName')
                            
                            If ([String]::IsNullOrWhiteSpace($AppName)) {
                                Continue
                            }
                            
                            If ($PSBoundParameters.ContainsKey('Name')) {
                                If ($AppName -notlike $Name) {
                                    Continue
                                }
                            }
                            
                            $AppPublisher = $SubKeyObj.GetValue('Publisher')
                            
                            If ($PSBoundParameters.ContainsKey('Publisher')) {
                                If ($AppPublisher -notlike $Publisher) {
                                    Continue
                                }
                            }
                            
                            $RegistryProperties = [System.Collections.Hashtable]::new()
                            
                            $ValueNames = $SubKeyObj.GetValueNames()
                            
                            ForEach ($ValueName in $ValueNames) {
                                Try {
                                    $Value = $SubKeyObj.GetValue($ValueName)
                                    If ($null -ne $Value) {
                                        Switch ($SubKeyObj.GetValueKind($ValueName)) {
                                            'DWord' { 
                                                $RegistryProperties[$ValueName] = [Int32]$Value 
                                            }
                                            'QWord' { 
                                                $RegistryProperties[$ValueName] = [Int64]$Value 
                                            }
                                            'MultiString' { 
                                                $RegistryProperties[$ValueName] = [String[]]$Value 
                                            }
                                            'Binary' { 
                                                $RegistryProperties[$ValueName] = [Byte[]]$Value 
                                            }
                                            Default { 
                                                $RegistryProperties[$ValueName] = [String]$Value 
                                            }
                                        }
                                    }
                                } Catch {
                                    Write-Warning "Error retrieving registry value '$($ValueName)' for application '$($AppName)': $($_.Exception.Message)"
                                }
                            }
                            
                            $AppVersion = $RegistryProperties['DisplayVersion']
                            $AppEstimatedSize = $RegistryProperties['EstimatedSize']
                            $AppInstallDate = $RegistryProperties['InstallDate']
                            $AppInstallLocation = $RegistryProperties['InstallLocation']
                            $AppInstallSource = $RegistryProperties['InstallSource']
                            $AppUninstallString = $RegistryProperties['UninstallString']
                            
                            $OutputObject = [PSCustomObject][Ordered]@{
                                Name = $AppName
                                Version = $AppVersion
                                Publisher = $AppPublisher
                                EstimatedSize = $AppEstimatedSize
                                InstallDate = $AppInstallDate
                                InstallLocation = $AppInstallLocation
                                InstallSource = $AppInstallSource
                                UninstallString = $AppUninstallString
                                IdentifyingNumber = $SubKey
                                ComputerName = $ENV:COMPUTERNAME
                                RegistryPath = "$($Path)\$($SubKey)"
                                RegistryProperties = $RegistryProperties
                            }
                            
                            If ($PSBoundParameters.ContainsKey('Properties')) {
                                If ($Properties -contains '*') {
                                    ForEach ($PropName in $RegistryProperties.Keys) {
                                        If (-not ($OutputObject.PSObject.Properties.Name -contains $PropName)) {
                                            $OutputObject | Add-Member -MemberType NoteProperty -Name $PropName -Value $RegistryProperties[$PropName] -Force
                                        }
                                    }
                                } Else {
                                    ForEach ($Prop in $Properties) {
                                        If ($RegistryProperties.ContainsKey($Prop)) {
                                            If (-not ($OutputObject.PSObject.Properties.Name -contains $Prop)) {
                                                $OutputObject | Add-Member -MemberType NoteProperty -Name $Prop -Value $RegistryProperties[$Prop] -Force
                                            }
                                        }
                                    }
                                }
                            }
                            
                            $Results.Add($OutputObject)
                            
                        } Catch {
                            Write-Warning "Error processing application subkey '$($SubKey)': $($_.Exception.Message)"
                        } Finally {
                            If ($null -ne $SubKeyObj) {
                                $SubKeyObj.Dispose()
                            }
                        }
                    }
                } Catch {
                    Write-Warning "Error accessing registry path '$($Path)': $($_.Exception.Message)"
                } Finally {
                    If ($null -ne $Key) {
                        $Key.Dispose()
                    }
                }
            }
            
            Return $Results
            
            Write-Verbose "Completed processing $($Results.Count) applications on local computer"
            
        } Catch {
            $ErrorMsg = "Critical error processing local computer: $($_.Exception.Message)"
            Write-Error $ErrorMsg
        } Finally {
            If ($null -ne $Hive) {
                $Hive.Dispose()
            }
        }
    }

    End {
        Write-Verbose "Completed Get-InstalledApplication at $(Get-Date)"
    }
}

Function Remove-TemporaryInstallers {
    <#
    .SYNOPSIS
    Removes all temporary installer files tracked during script execution
    
    .DESCRIPTION
    Cleans up all MSI and SHA256 files that were downloaded during the script execution.
    This ensures no temporary files are left behind regardless of script success or failure.
    #>
    [CmdletBinding()]
    Param()
    
    If ($Script:MSIInstallers.Count -eq 0) {
        Write-Log -Message 'No temporary installer files to clean up' -LogLevel 'DEBUG'
        Return
    }
    
    Write-Log -Message "Cleaning up $($Script:MSIInstallers.Count) temporary installer file(s)" -LogLevel 'INFO'
    
    $CleanedCount = 0
    $FailedCount = 0
    
    ForEach ($File in $Script:MSIInstallers) {
        Try {
            If (Test-Path $File) {
                Remove-Item -Path $File -Force -ErrorAction Stop
                Write-Log -Message "Removed temporary file: $(Split-Path $File -Leaf)" -LogLevel 'DEBUG'
                $CleanedCount++
            } Else {
                Write-Log -Message "File already removed or doesn't exist: $(Split-Path $File -Leaf)" -LogLevel 'DEBUG'
            }
        } Catch {
            Write-Log -Message "Failed to remove temporary file: $File - $($_.Exception.Message)" -LogLevel 'WARNING'
            $FailedCount++
        }
    }
    
    If ($CleanedCount -gt 0) {
        Write-Log -Message "Successfully cleaned up $CleanedCount temporary file(s)" -LogLevel 'SUCCESS'
    }
    
    If ($FailedCount -gt 0) {
        Write-Log -Message "Failed to clean up $FailedCount temporary file(s)" -LogLevel 'WARNING'
    }
    
    # Clear the list
    $Script:MSIInstallers.Clear()
    
    # Try to remove the temp download directory if it's empty
    Try {
        If (Test-Path $Script:TempDownloadPath) {
            $RemainingFiles = Get-ChildItem -Path $Script:TempDownloadPath -File -ErrorAction SilentlyContinue
            If ($null -eq $RemainingFiles -or $RemainingFiles.Count -eq 0) {
                Remove-Item -Path $Script:TempDownloadPath -Force -ErrorAction Stop
                Write-Log -Message 'Removed empty temporary download directory' -LogLevel 'DEBUG'
            } Else {
                Write-Log -Message "Temporary download directory not empty, keeping it: $($RemainingFiles.Count) file(s) remaining" -LogLevel 'DEBUG'
            }
        }
    } Catch {
        Write-Log -Message "Could not remove temporary download directory: $($_.Exception.Message)" -LogLevel 'DEBUG'
    }
}

#endregion

# ================================
# ===   DETECTION FUNCTIONS    ===
# ================================
#region Detection Functions

Function Get-TemurinInstallations {
    <#
    .SYNOPSIS
    Detects all installed Adoptium Eclipse Temurin Java installations
    
    .DESCRIPTION
    Uses Get-InstalledApplication to find all Temurin JDK and JRE installations
    and returns structured information about each installation
    #>
    [CmdletBinding()]
    Param()
    
    Try {
        Write-Log -Message 'Detecting installed Temurin Java installations' -LogLevel 'INFO'
        
        # Get all installed applications from Eclipse Adoptium publisher
        $TemurinApps = Get-InstalledApplication -Publisher 'Eclipse Adoptium'
        
        If (-not $TemurinApps) {
            Write-Log -Message 'No Temurin Java installations found' -LogLevel 'INFO'
            Return @()
        }
        
        $Installations = [System.Collections.Generic.List[PSObject]]::new()
        
        ForEach ($App in $TemurinApps) {
            # Parse the display name to extract version and architecture info
            # Example: "Eclipse Temurin JRE with Hotspot 8u432-b06 (x64)"
            If ($App.Name -match 'Eclipse Temurin (JRE|JDK) .* (\d+)u(\d+)-b(\d+) \((x64|x86)\)') {
                $Type = $Matches[1]
                $MajorVersion = $Matches[2]
                $UpdateVersion = $Matches[3]
                $BuildNumber = $Matches[4]
                $Architecture = $Matches[5]
                
                $InstallInfo = [PSCustomObject]@{
                    Name = $App.Name
                    Type = $Type
                    MajorVersion = $MajorVersion
                    UpdateVersion = $UpdateVersion
                    BuildNumber = $BuildNumber
                    Architecture = $Architecture
                    InstalledVersion = $App.Version
                    GitHubVersion = "${MajorVersion}u${UpdateVersion}b${BuildNumber}"
                    InstallLocation = $App.InstallLocation
                    UninstallString = $App.UninstallString
                    IdentifyingNumber = $App.IdentifyingNumber
                }
                
                $Installations.Add($InstallInfo)
                Write-Log -Message "Found: $($App.Name) - Version: $($InstallInfo.GitHubVersion)" -LogLevel 'INFO'
            }
            ElseIf ($App.Name -match 'Eclipse Temurin (JRE|JDK) .* (\d+)\.(\d+)\.(\d+)[_+](\d+) \((x64|x86)\)') {
                # Handle newer version format (11+)
                # Example: "Eclipse Temurin JDK with Hotspot 17.0.9+9 (x64)"
                $Type = $Matches[1]
                $MajorVersion = $Matches[2]
                $MinorVersion = $Matches[3]
                $PatchVersion = $Matches[4]
                $BuildNumber = $Matches[5]
                $Architecture = $Matches[6]
                
                $InstallInfo = [PSCustomObject]@{
                    Name = $App.Name
                    Type = $Type
                    MajorVersion = $MajorVersion
                    MinorVersion = $MinorVersion
                    PatchVersion = $PatchVersion
                    BuildNumber = $BuildNumber
                    Architecture = $Architecture
                    InstalledVersion = $App.Version
                    GitHubVersion = "${MajorVersion}.${MinorVersion}.${PatchVersion}_${BuildNumber}"
                    InstallLocation = $App.InstallLocation
                    UninstallString = $App.UninstallString
                    IdentifyingNumber = $App.IdentifyingNumber
                }
                
                $Installations.Add($InstallInfo)
                Write-Log -Message "Found: $($App.Name) - Version: $($InstallInfo.GitHubVersion)" -LogLevel 'INFO'
            }
        }
        
        Return $Installations
        
    } Catch {
        Write-Log -Message "Error detecting Temurin installations: $($_.Exception.Message)" -LogLevel 'ERROR'
        Return @()
    }
}

Function Convert-ArchitectureToGitHub {
    <#
    .SYNOPSIS
    Converts architecture naming from registry format to GitHub format
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [String]$Architecture
    )
    
    Switch ($Architecture) {
        'x64' { Return 'x64_windows' }
        'x86' { Return 'x86-32_windows' }
        Default { Return 'x64_windows' }
    }
}

#endregion

# ================================
# ===    UPDATE FUNCTIONS      ===
# ================================
#region Update Functions

Function Get-LatestTemurinVersion {
    <#
    .SYNOPSIS
    Gets the latest version information from GitHub releases API
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [String]$MajorVersion,
        
        [Parameter(Mandatory = $true)]
        [String]$Type,
        
        [Parameter(Mandatory = $true)]
        [String]$Architecture
    )
    
    Try {
        $ApiUrl = $Script:GitHubRepos[$MajorVersion]
        If (-not $ApiUrl) {
            Write-Log -Message "Unsupported major version: $MajorVersion" -LogLevel 'WARNING'
            Return $null
        }
        
        Write-Log -Message "Checking GitHub for latest version of Java $MajorVersion $Type ($Architecture)" -LogLevel 'DEBUG'
        
        # Call GitHub API
        $Response = Invoke-RestMethod -Uri $ApiUrl -Method Get -ErrorAction Stop
        
        # Convert architecture to GitHub format
        $GitHubArch = Convert-ArchitectureToGitHub -Architecture $Architecture
        $TypeLower = $Type.ToLower()
        
        # Find the MSI asset for the specified type and architecture
        $MsiPattern = "OpenJDK${MajorVersion}U-${TypeLower}_${GitHubArch}_hotspot_.*\.msi$"
        $MsiAsset = $Response.assets | Where-Object { $_.name -match $MsiPattern }
        
        If (-not $MsiAsset) {
            Write-Log -Message "No MSI found for Java $MajorVersion $Type ($Architecture)" -LogLevel 'WARNING'
            Return $null
        }
        
        # Extract version from filename
        # Example: OpenJDK8U-jre_x64_windows_hotspot_8u462b08.msi
        If ($MajorVersion -eq '8') {
            # Java 8 format: 8u462b08 (note: build can have leading zeros)
            If ($MsiAsset.name -match "_(\d+u\d+b\d+)\.msi$") {
                $GitHubVersion = $Matches[1]
            } Else {
                Write-Log -Message "Could not parse Java 8 version from filename: $($MsiAsset.name)" -LogLevel 'WARNING'
                Return $null
            }
        } Else {
            # Java 11+ format: 17.0.9_9 or 17.0.9+9
            If ($MsiAsset.name -match "_(\d+\.\d+\.\d+[_+]\d+)\.msi$") {
                $GitHubVersion = $Matches[1]
            } Else {
                Write-Log -Message "Could not parse version from filename: $($MsiAsset.name)" -LogLevel 'WARNING'
                Return $null
            }
        }
        
        # Find SHA256 file
        $ShaAsset = $Response.assets | Where-Object { $_.name -eq "$($MsiAsset.name).sha256.txt" }

        Write-Log -Message "Latest version found on GitHub: $GitHubVersion (from file: $($MsiAsset.name))" -LogLevel 'DEBUG'
        
        Return [PSCustomObject]@{
            Version = $GitHubVersion
            MsiUrl = $MsiAsset.browser_download_url
            MsiName = $MsiAsset.name
            ShaUrl = $ShaAsset.browser_download_url
            ReleaseTag = $Response.tag_name
        }
        
    } Catch {
        Write-Log -Message "Error getting latest version from GitHub: $($_.Exception.Message)" -LogLevel 'ERROR'
        Return $null
    }
}

Function Compare-TemurinVersions {
    <#
    .SYNOPSIS
    Compares two Temurin version strings to determine if an update is available
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [String]$InstalledVersion,
        
        [Parameter(Mandatory = $true)]
        [String]$AvailableVersion,
        
        [Parameter(Mandatory = $true)]
        [String]$MajorVersion
    )
    
    Try {
        If ($MajorVersion -eq '8') {
            # Format: 8u432b06 or 8u462b08 (build numbers can have leading zeros)
            Write-Log -Message "Comparing versions - Installed: $InstalledVersion vs Available: $AvailableVersion" -LogLevel 'DEBUG'
            
            If ($InstalledVersion -match '^(\d+)u(\d+)b(\d+)$' -and $AvailableVersion -match '^(\d+)u(\d+)b(\d+)$') {
                $null = $InstalledVersion -match '^(\d+)u(\d+)b(\d+)$'
                # Store installed version parts
                $InstMajor = [Int]$Matches[1]
                $InstUpdate = [Int]$Matches[2]
                $InstBuild = [Int]$Matches[3]
                
                # Re-match for available version
                $null = $AvailableVersion -match '^(\d+)u(\d+)b(\d+)$'
                $AvailMajor = [Int]$Matches[1]
                $AvailUpdate = [Int]$Matches[2]
                $AvailBuild = [Int]$Matches[3]
                
                Write-Log -Message "Version comparison - Installed: ${InstMajor}u${InstUpdate}b${InstBuild} vs Available: ${AvailMajor}u${AvailUpdate}b${AvailBuild}" -LogLevel 'DEBUG'
                
                If ($AvailUpdate -gt $InstUpdate) {
                    Write-Log -Message "Update available: Update version $AvailUpdate > $InstUpdate" -LogLevel 'DEBUG'
                    Return $true
                } ElseIf ($AvailUpdate -eq $InstUpdate -and $AvailBuild -gt $InstBuild) {
                    Write-Log -Message "Update available: Build version $AvailBuild > $InstBuild" -LogLevel 'DEBUG'
                    Return $true
                }
                
                Write-Log -Message "No update needed: Current version is up to date or newer" -LogLevel 'DEBUG'
            } Else {
                Write-Log -Message "Version format mismatch - Installed: $InstalledVersion, Available: $AvailableVersion" -LogLevel 'WARNING'
            }
        } Else {
            # Format: 17.0.9_9 or 17.0.9+9
            $InstalledNorm = $InstalledVersion -replace '[_+]', '.'
            $AvailableNorm = $AvailableVersion -replace '[_+]', '.'
            
            $InstParts = $InstalledNorm.Split('.')
            $AvailParts = $AvailableNorm.Split('.')
            
            For ($i = 0; $i -lt [Math]::Min($InstParts.Count, $AvailParts.Count); $i++) {
                $InstNum = [Int]$InstParts[$i]
                $AvailNum = [Int]$AvailParts[$i]
                
                If ($AvailNum -gt $InstNum) {
                    Return $true
                } ElseIf ($AvailNum -lt $InstNum) {
                    Return $false
                }
            }
            
            # If all compared parts are equal, check if available has more parts
            Return $AvailParts.Count -gt $InstParts.Count
        }
        
        Return $false
        
    } Catch {
        Write-Log -Message "Error comparing versions: $($_.Exception.Message)" -LogLevel 'ERROR'
        Return $false
    }
}

Function Get-TemurinInstaller {
    <#
    .SYNOPSIS
    Downloads Temurin MSI installer and validates SHA256 hash
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [String]$MsiUrl,
        
        [Parameter(Mandatory = $true)]
        [String]$ShaUrl,
        
        [Parameter(Mandatory = $true)]
        [String]$FileName
    )
    
    Try {
        # Ensure temp directory exists
        If (-not (Test-Path $Script:TempDownloadPath)) {
            New-Item -Path $Script:TempDownloadPath -ItemType Directory -Force | Out-Null
        }
        
        $MsiPath = Join-Path $Script:TempDownloadPath $FileName
        $ShaPath = Join-Path $Script:TempDownloadPath "$FileName.sha256.txt"
        
        # Download with retry logic
        $RetryCount = 0
        $Downloaded = $false
        
        While (-not $Downloaded -and $RetryCount -lt $Script:MaxRetryAttempts) {
            Try {
                $RetryCount++
                Write-Log -Message "Downloading MSI (Attempt $RetryCount/$Script:MaxRetryAttempts): $FileName" -LogLevel 'INFO'
                
                # Clean up any existing files from previous attempts
                If (Test-Path $MsiPath) {
                    Write-Log -Message "Removing existing MSI file from previous attempt" -LogLevel 'DEBUG'
                    Remove-Item -Path $MsiPath -Force -ErrorAction SilentlyContinue
                }
                If (Test-Path $ShaPath) {
                    Write-Log -Message "Removing existing SHA file from previous attempt" -LogLevel 'DEBUG'
                    Remove-Item -Path $ShaPath -Force -ErrorAction SilentlyContinue
                }
                
                # Download MSI with overwrite
                $MsiDownloadStart = Get-Date
                $MsiResult = Get-HttpClientDownload -Url $MsiUrl -OutputPath $MsiPath -TimeoutSeconds 600 -ProgressBar -OverwriteExisting
                $MsiDownloadTime = ((Get-Date) - $MsiDownloadStart).TotalSeconds
                
                Write-Log -Message "MSI download completed in $([Math]::Round($MsiDownloadTime, 2)) seconds" -LogLevel 'DEBUG'
                Write-Log -Message "Downloaded file size: $($MsiResult.FileSizeMB) MB ($($MsiResult.FileSize) bytes)" -LogLevel 'DEBUG'
                
                # Download SHA256
                $ShaDownloadStart = Get-Date
                $ShaResult = Get-HttpClientDownload -Url $ShaUrl -OutputPath $ShaPath -TimeoutSeconds 60 -OverwriteExisting
                $ShaDownloadTime = ((Get-Date) - $ShaDownloadStart).TotalSeconds
                
                Write-Log -Message "MSI download completed in $([Math]::Round($ShaDownloadTime, 2)) seconds" -LogLevel 'DEBUG'
                Write-Log -Message "Downloaded file size: $($ShaResult.FileSizeMB) MB ($($ShaResult.FileSize) bytes)" -LogLevel 'DEBUG'
                
                # Verify SHA256
                Write-Log -Message "Starting SHA256 hash verification" -LogLevel 'DEBUG'
                $HashCalcStart = Get-Date
                
                # Read expected hash from file
                $ShaContent = Get-Content $ShaPath -Raw
                $ExpectedHash = ($ShaContent.Trim().Split(' ')[0]).ToUpper()
                
                # Calculate actual hash
                $ActualHash = (Get-FileHash -Path $MsiPath -Algorithm SHA256).Hash.ToUpper()
                $HashCalcTime = ((Get-Date) - $HashCalcStart).TotalSeconds
                
                Write-Log -Message "Hash calculation completed in $([Math]::Round($HashCalcTime, 2)) seconds" -LogLevel 'DEBUG'
                Write-Log -Message "Expected SHA256: $ExpectedHash" -LogLevel 'DEBUG'
                Write-Log -Message "Actual SHA256:   $ActualHash" -LogLevel 'DEBUG'
                Write-Log -Message "File size verified: $($MsiResult.FileSize) bytes" -LogLevel 'DEBUG'
                
                If ($ExpectedHash -eq $ActualHash) {
                    Write-Log -Message 'SHA256 verification successful - hashes match' -LogLevel 'SUCCESS'
                    $Downloaded = $true
                } Else {
                    Write-Log -Message 'SHA256 verification failed - hash mismatch detected' -LogLevel 'ERROR'
                    Write-Log -Message "Expected: $ExpectedHash" -LogLevel 'ERROR'
                    Write-Log -Message "Actual:   $ActualHash" -LogLevel 'ERROR'
                    Write-Log -Message "File may be corrupted or incomplete. Will retry download." -LogLevel 'WARNING'
                    
                    # Remove corrupted files
                    Remove-Item -Path $MsiPath -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path $ShaPath -Force -ErrorAction SilentlyContinue
                    
                    If ($RetryCount -lt $Script:MaxRetryAttempts) {
                        $Delay = $Script:InitialRetryDelaySeconds * [Math]::Pow(2, $RetryCount - 1)
                        Write-Log -Message "Waiting $Delay seconds before retry..." -LogLevel 'DEBUG'
                        Start-Sleep -Seconds $Delay
                    }
                }
                
            } Catch {
                Write-Log -Message "Download attempt $RetryCount failed: $($_.Exception.Message)" -LogLevel 'WARNING'
                
                # Clean up any partial files
                If (Test-Path $MsiPath) {
                    Remove-Item -Path $MsiPath -Force -ErrorAction SilentlyContinue
                }
                If (Test-Path $ShaPath) {
                    Remove-Item -Path $ShaPath -Force -ErrorAction SilentlyContinue
                }
                
                If ($RetryCount -lt $Script:MaxRetryAttempts) {
                    $Delay = $Script:InitialRetryDelaySeconds * [Math]::Pow(2, $RetryCount - 1)
                    Write-Log -Message "Waiting $Delay seconds before retry..." -LogLevel 'DEBUG'
                    Start-Sleep -Seconds $Delay
                }
            }
        }
        
        If (-not $Downloaded) {
            Throw "Failed to download and verify MSI after $Script:MaxRetryAttempts attempts"
        }
        
        # Final validation - ensure file exists and has content
        If (Test-Path $MsiPath) {
            $FinalFileInfo = Get-Item $MsiPath
            Write-Log -Message "Final MSI validation - File exists: Yes, Size: $($FinalFileInfo.Length) bytes" -LogLevel 'DEBUG'
            
            If ($FinalFileInfo.Length -eq 0) {
                Write-Log -Message "MSI file is empty (0 bytes) - download failed" -LogLevel 'ERROR'
                Remove-Item -Path $MsiPath -Force -ErrorAction SilentlyContinue
                Remove-Item -Path $ShaPath -Force -ErrorAction SilentlyContinue
                Throw "Downloaded MSI file is empty"
            }
            
            # Add to tracking list for cleanup
            $Script:MSIInstallers.Add($MsiPath)
            $Script:MSIInstallers.Add($ShaPath)
            Write-Log -Message "Added files to cleanup tracking: $FileName and SHA256 file" -LogLevel 'DEBUG'
        } Else {
            Throw "MSI file does not exist after download completion"
        }
        
        Return $MsiPath
        
    } Catch {
        Write-Log -Message "Critical error downloading installer: $($_.Exception.Message)" -LogLevel 'CRITICAL'
        Return $null
    }
}

Function Update-TemurinInstallation {
    <#
    .SYNOPSIS
    Updates a single Temurin installation
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Installation,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$LatestVersion
    )
    
    Try {
        Write-Log -Message "Updating $($Installation.Name) from $($Installation.GitHubVersion) to $($LatestVersion.Version)" -LogLevel 'INFO'
        
        # Check for running Java processes
        $JavaProcesses = Get-Process -Name 'java', 'javaw' -ErrorAction SilentlyContinue
        If ($JavaProcesses) {
            Write-Log -Message 'Java processes detected. Waiting for them to close...' -LogLevel 'WARNING'
            
            # Wait for processes to close
            $WaitTime = 0
            While ($JavaProcesses) {
                Start-Sleep -Seconds 10
                $WaitTime += 10
                
                If ($WaitTime % 60 -eq 0) {
                    Write-Log -Message "Still waiting for Java processes to close ($($WaitTime / 60) minutes)..." -LogLevel 'INFO'
                }
                
                $JavaProcesses = Get-Process -Name 'java', 'javaw' -ErrorAction SilentlyContinue
            }
            
            Write-Log -Message 'All Java processes closed' -LogLevel 'INFO'
        }
        
        # Download installer
        $MsiPath = Get-TemurinInstaller -MsiUrl $LatestVersion.MsiUrl -ShaUrl $LatestVersion.ShaUrl -FileName $LatestVersion.MsiName
        
        If (-not $MsiPath) {
            Throw 'Failed to download installer'
        }
        
        # Determine if we need to uninstall first (for revision updates)
        $NeedsUninstall = $false
        If ($Installation.MajorVersion -eq '8') {
            # For Java 8, check if only build number changed
            If ($Installation.UpdateVersion -eq ($LatestVersion.Version -replace '.*u(\d+)b.*', '$1')) {
                $NeedsUninstall = $true
            }
        }
        
        If ($NeedsUninstall) {
            Write-Log -Message 'Revision update detected, uninstalling current version first' -LogLevel 'INFO'

            # Generate MSI log path for uninstall
            $UninstallLogPath = Get-MsiLogPath -MsiFileName $Installation.Name -Operation 'Uninstall'
            Write-Log -Message "MSI uninstall log will be written to: $UninstallLogPath" -LogLevel 'DEBUG'
            
            # Uninstall current version with verbose logging
            # IMPORTANT: ArgumentList must be an array, not a string, to avoid argument parsing issues
            $UninstallArgs = @(
                "/x$($Installation.IdentifyingNumber)"
                '/quiet'
                '/norestart'
                '/l*v'
                "`"$UninstallLogPath`""
            )

            Write-Log -Message "Uninstall command: msiexec.exe $($UninstallArgs -join ' ')" -LogLevel 'DEBUG'

            $UninstallResult = Start-Process -FilePath 'msiexec.exe' -ArgumentList $UninstallArgs -Wait -PassThru -NoNewWindow
            
            If ($UninstallResult.ExitCode -eq 0) {
                Write-Log -Message 'Uninstall completed successfully' -LogLevel 'SUCCESS'
            } ElseIf ($UninstallResult.ExitCode -eq 3010 -or $UninstallResult.ExitCode -eq 1641 -or $UninstallResult.ExitCode -eq 3011) {
                Write-Log -Message 'Uninstall completed successfully (restart required)' -LogLevel 'SUCCESS'
            } Else {
                $ExitDescription = Get-MsiExitCodeDescription -ExitCode $UninstallResult.ExitCode
                Write-Log -Message "MSI Exit Code: $($UninstallResult.ExitCode) - $ExitDescription" -LogLevel 'ERROR'
                Throw "Uninstall failed with exit code $($UninstallResult.ExitCode): $ExitDescription"
            }
            
            Write-Log -Message 'Uninstall completed successfully' -LogLevel 'SUCCESS'
        }
        
        # Install new version
        Write-Log -Message 'Installing new version' -LogLevel 'INFO'

        # Validate MSI file accessibility before installation
        Try {
            $MsiFileInfo = Get-Item -Path $MsiPath -ErrorAction Stop
            Write-Log -Message "MSI file details - Path: $MsiPath" -LogLevel 'DEBUG'
            Write-Log -Message "MSI file details - Size: $($MsiFileInfo.Length) bytes" -LogLevel 'DEBUG'
            Write-Log -Message "MSI file details - Exists: $($MsiFileInfo.Exists)" -LogLevel 'DEBUG'
            Write-Log -Message "MSI file details - FullName: $($MsiFileInfo.FullName)" -LogLevel 'DEBUG'
            
            # Test if file can be opened
            $TestStream = [System.IO.File]::OpenRead($MsiPath)
            $TestStream.Close()
            Write-Log -Message "MSI file accessibility test: PASSED" -LogLevel 'DEBUG'
        } Catch {
            Write-Log -Message "MSI file accessibility test: FAILED - $($_.Exception.Message)" -LogLevel 'ERROR'
        }

        # Generate MSI log path
        $InstallLogPath = Get-MsiLogPath -MsiFileName $LatestVersion.MsiName -Operation 'Update'
        Write-Log -Message "MSI install log will be written to: $InstallLogPath" -LogLevel 'INFO'

        # Build MSI arguments with verbose logging
        $InstallArgs = @(
            '/i'
            "`"$MsiPath`""
            '/quiet'
            '/l*v'
            "`"$InstallLogPath`""
        )
        Write-Log -Message "Install command: msiexec.exe $($InstallArgs -join ' ')" -LogLevel 'DEBUG'

        $InstallResult = Start-Process -FilePath 'msiexec.exe' -ArgumentList $InstallArgs -Wait -PassThru -NoNewWindow
        
        $ExitDescription = Get-MsiExitCodeDescription -ExitCode $InstallResult.ExitCode

        If ($InstallResult.ExitCode -eq 0) {
            Write-Log -Message "Successfully updated $($Installation.Name) to version $($LatestVersion.Version)" -LogLevel 'SUCCESS'
            Write-Log -Message "MSI Exit Code: 0 - $ExitDescription" -LogLevel 'DEBUG'
        } ElseIf ($InstallResult.ExitCode -eq 3010 -or $InstallResult.ExitCode -eq 1641 -or $InstallResult.ExitCode -eq 3011) {
            Write-Log -Message "Successfully updated $($Installation.Name) to version $($LatestVersion.Version) (restart required)" -LogLevel 'SUCCESS'
            Write-Log -Message "MSI Exit Code: $($InstallResult.ExitCode) - $ExitDescription" -LogLevel 'INFO'
        } Else {
            If (Test-Path $InstallLogPath) {
                Write-Log -Message "Analyzing MSI log for error details..." -LogLevel 'DEBUG'
                Try {
                    # Get last 50 lines of the log file for immediate context
                    $LogContent = Get-Content -Path $InstallLogPath -Tail 50 -ErrorAction Stop
                    
                    # Look for specific error patterns
                    $ErrorLines = $LogContent | Where-Object { 
                        $_ -match 'Error \d+:' -or 
                        $_ -match 'MSI \([A-Z]\)' -or 
                        $_ -match 'MainEngineThread is returning' -or
                        $_ -match 'Note:' -or
                        $_ -match 'Failed to' -or
                        $_ -match 'Cannot'
                    }
                    
                    If ($ErrorLines) {
                        Write-Log -Message "Key MSI log entries:" -LogLevel 'ERROR'
                        $ErrorLines | ForEach-Object {
                            Write-Log -Message "  MSI Log: $_" -LogLevel 'ERROR'
                        }
                    }
                    
                    Write-Log -Message "Full MSI log available at: $InstallLogPath" -LogLevel 'INFO'
                } Catch {
                    Write-Log -Message "Could not analyze MSI log: $($_.Exception.Message)" -LogLevel 'WARNING'
                }
            }
        }
        
        Return $true
        
    } Catch {
        Write-Log -Message "Failed to update $($Installation.Name): $($_.Exception.Message)" -LogLevel 'CRITICAL'
        Return $false
    }
}

#endregion

# ================================
# ===   INSTALL FUNCTIONS      ===
# ================================
#region Install Functions

Function Install-TemurinVersion {
    <#
    .SYNOPSIS
    Installs a new Temurin Java version
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [String]$MajorVersion,
        
        [Parameter(Mandatory = $true)]
        [String]$Architecture,
        
        [Parameter(Mandatory = $true)]
        [String]$Type
    )
    
    Try {
        Write-Log -Message "Installing Temurin Java $MajorVersion $Type ($Architecture)" -LogLevel 'INFO'
        
        # Get latest version information
        $LatestVersion = Get-LatestTemurinVersion -MajorVersion $MajorVersion -Type $Type -Architecture $Architecture
        
        If (-not $LatestVersion) {
            Throw "Could not find latest version for Java $MajorVersion $Type ($Architecture)"
        }
        
        Write-Log -Message "Latest version available: $($LatestVersion.Version)" -LogLevel 'INFO'
        
        # Download installer
        $MsiPath = Get-TemurinInstaller -MsiUrl $LatestVersion.MsiUrl -ShaUrl $LatestVersion.ShaUrl -FileName $LatestVersion.MsiName
        
        If (-not $MsiPath) {
            Throw 'Failed to download installer'
        }
        
        # Install
        Write-Log -Message 'Starting installation' -LogLevel 'INFO'

        # Validate MSI file accessibility before installation
        Try {
            $MsiFileInfo = Get-Item -Path $MsiPath -ErrorAction Stop
            Write-Log -Message "MSI file details - Path: $MsiPath" -LogLevel 'DEBUG'
            Write-Log -Message "MSI file details - Size: $($MsiFileInfo.Length) bytes" -LogLevel 'DEBUG'
            Write-Log -Message "MSI file details - Exists: $($MsiFileInfo.Exists)" -LogLevel 'DEBUG'
            Write-Log -Message "MSI file details - FullName: $($MsiFileInfo.FullName)" -LogLevel 'DEBUG'
            
            # Test if file can be opened
            $TestStream = [System.IO.File]::OpenRead($MsiPath)
            $TestStream.Close()
            Write-Log -Message "MSI file accessibility test: PASSED" -LogLevel 'DEBUG'
        } Catch {
            Write-Log -Message "MSI file accessibility test: FAILED - $($_.Exception.Message)" -LogLevel 'ERROR'
        }

        # Generate MSI log path
        $InstallLogPath = Get-MsiLogPath -MsiFileName $LatestVersion.MsiName -Operation 'Install'
        Write-Log -Message "MSI install log will be written to: $InstallLogPath" -LogLevel 'INFO'

        # Build install arguments with verbose logging
        # IMPORTANT: ArgumentList must be an array, not a string, to avoid argument parsing issues
        $Features = 'FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome'
        If ($Type -eq 'JDK') {
            $Features += ',FeatureOracleJavaSoft'
        }

        $InstallArgs = @(
            '/i'
            "`"$MsiPath`""
            "INSTALLDIR=`"C:\Program Files\Temurin\`""
            "ADDLOCAL=$Features"
            '/quiet'
            '/l*v'
            "`"$InstallLogPath`""
        )

        Write-Log -Message "Install command: msiexec.exe $($InstallArgs -join ' ')" -LogLevel 'DEBUG'

        $InstallResult = Start-Process -FilePath 'msiexec.exe' -ArgumentList $InstallArgs -Wait -PassThru -NoNewWindow
        
        $ExitDescription = Get-MsiExitCodeDescription -ExitCode $InstallResult.ExitCode

        If ($InstallResult.ExitCode -eq 0) {
            Write-Log -Message "Successfully installed Java $MajorVersion $Type version $($LatestVersion.Version)" -LogLevel 'SUCCESS'
            Write-Log -Message "MSI Exit Code: 0 - $ExitDescription" -LogLevel 'DEBUG'
        } ElseIf ($InstallResult.ExitCode -eq 3010 -or $InstallResult.ExitCode -eq 1641 -or $InstallResult.ExitCode -eq 3011) {
            Write-Log -Message "Successfully installed Java $MajorVersion $Type version $($LatestVersion.Version) (restart required)" -LogLevel 'SUCCESS'
            Write-Log -Message "MSI Exit Code: $($InstallResult.ExitCode) - $ExitDescription" -LogLevel 'INFO'
        } Else {
            If (Test-Path $InstallLogPath) {
                Write-Log -Message "Analyzing MSI log for error details..." -LogLevel 'DEBUG'
                Try {
                    # Get last 50 lines of the log file for immediate context
                    $LogContent = Get-Content -Path $InstallLogPath -Tail 50 -ErrorAction Stop
                    
                    # Look for specific error patterns
                    $ErrorLines = $LogContent | Where-Object { 
                        $_ -match 'Error \d+:' -or 
                        $_ -match 'MSI \([A-Z]\)' -or 
                        $_ -match 'MainEngineThread is returning' -or
                        $_ -match 'Note:' -or
                        $_ -match 'Failed to' -or
                        $_ -match 'Cannot'
                    }
                    
                    If ($ErrorLines) {
                        Write-Log -Message "Key MSI log entries:" -LogLevel 'ERROR'
                        $ErrorLines | ForEach-Object {
                            Write-Log -Message "  MSI Log: $_" -LogLevel 'ERROR'
                        }
                    }
                    
                    Write-Log -Message "Full MSI log available at: $InstallLogPath" -LogLevel 'INFO'
                } Catch {
                    Write-Log -Message "Could not analyze MSI log: $($_.Exception.Message)" -LogLevel 'WARNING'
                }
            }
        }
        
        Return $true
        
    } Catch {
        Write-Log -Message "Failed to install Java $MajorVersion $($Type): $($_.Exception.Message)" -LogLevel 'CRITICAL'
        Return $false
    }
}

Function Install-ScriptAndTask {
    <#
    .SYNOPSIS
    Copies script to ProgramData and creates scheduled task
    #>
    [CmdletBinding()]
    Param(
        [Parameter()]
        [Switch]$Force
    )
    
    Try {
        # Create installation directory if it doesn't exist
        If (-not (Test-Path $Script:InstallPath)) {
            Write-Log -Message "Creating installation directory: $Script:InstallPath" -LogLevel 'INFO'
            New-Item -Path $Script:InstallPath -ItemType Directory -Force | Out-Null
        }
        
        # Check if script already exists
        $TargetScript = Join-Path $Script:InstallPath $Script:ScriptName
        $CurrentScript = $PSCommandPath
        
        If ((Test-Path $TargetScript) -and -not $Force) {
            Write-Log -Message 'Script already installed. Use -Force to overwrite' -LogLevel 'INFO'
        } Else {
            Write-Log -Message "Copying script to $TargetScript" -LogLevel 'INFO'
            Copy-Item -Path $CurrentScript -Destination $TargetScript -Force
            Write-Log -Message 'Script copied successfully' -LogLevel 'SUCCESS'
        }
        
        # Create or update scheduled task
        If (-not $SkipScheduledTask) {
            Write-Log -Message 'Creating scheduled task' -LogLevel 'INFO'
            
            # Remove existing task if present
            $ExistingTask = Get-ScheduledTask -TaskName $Script:ScheduledTaskName -ErrorAction SilentlyContinue
            If ($ExistingTask) {
                Write-Log -Message 'Removing existing scheduled task' -LogLevel 'INFO'
                Unregister-ScheduledTask -TaskName $Script:ScheduledTaskName -Confirm:$false
            }
            
            # Create task actions
            $Action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$TargetScript`""
            
            # Create task triggers
            $Triggers = @(
                New-ScheduledTaskTrigger -Daily -At $Script:ScheduledTaskTime
                New-ScheduledTaskTrigger -AtStartup
            )
            
            # Create task principal (run as SYSTEM)
            $Principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
            
            # Create task settings
            $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
            
            # Register the task
            Register-ScheduledTask -TaskName $Script:ScheduledTaskName -Description $Script:ScheduledTaskDescription `
                -Action $Action -Trigger $Triggers -Principal $Principal -Settings $Settings | Out-Null
            
            Write-Log -Message 'Scheduled task created successfully' -LogLevel 'SUCCESS'
        }
        
        Return $true
        
    } Catch {
        Write-Log -Message "Failed to install script and task: $($_.Exception.Message)" -LogLevel 'ERROR'
        Return $false
    }
}

#endregion

# ================================
# ===    MAIN EXECUTION        ===
# ================================
#region Main Execution

Try {
    # Initialize log
    Initialize-Log -Default -LogName $Script:LogFileName -LogPath $Script:LogPath -LogRoll -LogRotateOpt '1M'

    Write-Log -Message 'Starting Temurin Java Update Script' -LogLevel 'INFO'
    Write-Log -Message "Script version: 1.0" -LogLevel 'INFO'
    Write-Log -Message "Execution mode: $($PSCmdlet.ParameterSetName)" -LogLevel 'INFO'
    
    # Install script and scheduled task if not running from installed location
    If ($PSCommandPath -ne (Join-Path $Script:InstallPath $Script:ScriptName)) {
        Write-Log -Message 'Script not running from installation directory' -LogLevel 'INFO'
        $null = Install-ScriptAndTask -Force:$Force
    }
    
    # Handle installation mode
    If ($Install) {
        Write-Log -Message 'Installation mode activated' -LogLevel 'INFO'
        
        $VersionList = $Versions -split ','
        $SuccessCount = 0
        $FailCount = 0
        
        ForEach ($Version in $VersionList) {
            Try {
                $Version = $Version.Trim()
                
                If ($Script:GitHubRepos.ContainsKey($Version)) {
                    Write-Log -Message "Processing installation request for Java $Version" -LogLevel 'INFO'
                    
                    $Result = Install-TemurinVersion -MajorVersion $Version -Architecture $Arch -Type $Type
                    
                    If ($Result) {
                        $SuccessCount++
                    } Else {
                        $FailCount++
                    }
                } Else {
                    Write-Log -Message "Unsupported Java version: $Version" -LogLevel 'WARNING'
                    $FailCount++
                }
            } Catch {
                Write-Log -Message "Error installing Java $($Version): $($_.Exception.Message)" -LogLevel 'ERROR'
                $FailCount++
            }
        }
        
        Write-Log -Message "Installation complete. Success: $SuccessCount, Failed: $FailCount" -LogLevel 'INFO'
        
    } Else {
        # Update mode - check for updates to existing installations
        Write-Log -Message 'Update mode - checking existing installations' -LogLevel 'INFO'
        
        $Installations = Get-TemurinInstallations
        
        If ($Installations.Count -eq 0) {
            Write-Log -Message 'No Temurin Java installations found. Exiting.' -LogLevel 'INFO'
            Exit 0
        }
        
        Write-Log -Message "Found $($Installations.Count) Temurin installation(s)" -LogLevel 'INFO'
        
        $UpdateCount = 0
        $FailCount = 0
        
        ForEach ($Installation in $Installations) {
            Try {
                Write-Log -Message "Checking for updates: $($Installation.Name)" -LogLevel 'INFO'
                
                # Get latest version from GitHub
                $LatestVersion = Get-LatestTemurinVersion -MajorVersion $Installation.MajorVersion `
                    -Type $Installation.Type -Architecture $Installation.Architecture
                
                If (-not $LatestVersion) {
                    Write-Log -Message "Could not retrieve latest version information" -LogLevel 'WARNING'
                    Continue
                }
                
                # Compare versions
                $UpdateAvailable = Compare-TemurinVersions -InstalledVersion $Installation.GitHubVersion `
                    -AvailableVersion $LatestVersion.Version -MajorVersion $Installation.MajorVersion
                
                If ($UpdateAvailable) {
                    Write-Log -Message "Update available: $($Installation.GitHubVersion) -> $($LatestVersion.Version)" -LogLevel 'INFO'
                    
                    $Result = Update-TemurinInstallation -Installation $Installation -LatestVersion $LatestVersion
                    
                    If ($Result) {
                        $UpdateCount++
                    } Else {
                        $FailCount++
                    }
                } Else {
                    Write-Log -Message "Already up to date: $($Installation.GitHubVersion)" -LogLevel 'INFO'
                }
                
            } Catch {
                Write-Log -Message "Error processing $($Installation.Name): $($_.Exception.Message)" -LogLevel 'CRITICAL'
                $FailCount++
            }
        }
        
        Write-Log -Message "Update check complete. Updated: $UpdateCount, Failed: $FailCount" -LogLevel 'INFO'
    }
    
    Write-Log -Message 'Script execution completed' -LogLevel 'SUCCESS'
    
} Catch {
    # Comprehensive error handling for any unhandled exceptions
    Write-Log "==================== ERROR DETAILS ====================" -Level 'ERROR' -Logger $Script:ConsoleLogger
    Write-Log "Timestamp    : $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'))" -Level 'ERROR' -Logger $Script:ConsoleLogger
    Write-Log "Error Type   : $($_.Exception.GetType().FullName)" -Level 'ERROR' -Logger $Script:ConsoleLogger
    Write-Log "Message      : $($_.Exception.Message)" -Level 'ERROR' -Logger $Script:ConsoleLogger
    Write-Log "FQID         : $($_.FullyQualifiedErrorId)" -Level 'ERROR' -Logger $Script:ConsoleLogger
    Write-Log "Category     : $($_.CategoryInfo.Category) ($($_.CategoryInfo.Reason))" -Level 'ERROR' -Logger $Script:ConsoleLogger
    
    if ($_.InvocationInfo.ScriptName) {
        Write-Log "Script       : $($_.InvocationInfo.ScriptName)" -Level 'ERROR' -Logger $Script:ConsoleLogger
    }
    if ($_.InvocationInfo.MyCommand) {
        Write-Log "Command      : $($_.InvocationInfo.MyCommand)" -Level 'ERROR' -Logger $Script:ConsoleLogger
    }
    Write-Log "Line Number  : $($_.InvocationInfo.ScriptLineNumber)" -Level 'ERROR' -Logger $Script:ConsoleLogger
    Write-Log "Column       : $($_.InvocationInfo.OffsetInLine)" -Level 'ERROR' -Logger $Script:ConsoleLogger
    
    if ($_.InvocationInfo.Line) {
        Write-Log "Code Line    : $($_.InvocationInfo.Line.Trim())" -Level 'ERROR'
    }
    
    if ($_.TargetObject) {
        Write-Log "Target       : $($_.TargetObject)" -Level 'ERROR'
    }
    
    if ($_.Exception.HResult -ne 0) {
        Write-Log "HResult      : 0x$($_.Exception.HResult.ToString('X8')) ($($_.Exception.HResult))" -Level 'ERROR'
    }
    
    if ($_.Exception.InnerException) {
        Write-Log "Inner Error  : $($_.Exception.InnerException.GetType().Name) - $($_.Exception.InnerException.Message)" -Level 'ERROR'
    }
    
    if ($_.ScriptStackTrace) {
        Write-Log "Stack Trace  :" -Level 'ERROR'
        $_.ScriptStackTrace -split "`n" | ForEach-Object {
            Write-Log "  $_" -Level 'ERROR'
        }
    }
    Write-Log "=======================================================" -Level 'ERROR'
    Exit 1
} Finally {
    # Always clean up temporary files
    Try {
        #Remove-TemporaryInstallers
    } Catch {
        Write-Log -Message "Error during cleanup: $($_.Exception.Message)" -LogLevel 'WARNING'
    }
    
    Write-Log -Message 'Script cleanup completed' -LogLevel 'DEBUG'
}

Exit 0


#endregion
