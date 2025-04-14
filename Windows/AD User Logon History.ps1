<#
.SYNOPSIS
    Retrieves recent logon events for a specified user from the Security Event Log on all domain controllers.

.DESCRIPTION
    This script retrieves logon history (Event ID 4624) from the Security event logs of all domain controllers
    for a specified user (SamAccountName). It does so by:
      1. Prompting the user for the target username and the maximum number of events to retrieve.
      2. Querying all domain controllers in the current domain using Get-ADDomainController.
      3. For each domain controller, querying the Security log via Get-WinEvent using an XPath filter that looks 
         for logon events where the TargetUserName matches the given username.
      4. Displaying each event’s timestamp, a specific data field (using Data index 8, which may represent the workstation
         name or another value depending on the event schema), and the computer on which the event was logged.
    
    **Note:** The script assumes that the ActiveDirectory module is available and that you have permissions to query
    domain controllers and their event logs.

.PARAMETER None
    The script is interactive and prompts for:
      - The username (SamAccountName) whose logon events should be retrieved.
      - The number of events to retrieve (default is set to 100).

.EXAMPLE
    PS C:\> .\Get-LogonHistory.ps1
    Enter the username (SamAccountName): jdoe
    Logon events for user 'jdoe':
    2025-04-14 08:30:45 - <DataFieldValue> - DC1.domain.com
    ...

.NOTES
    Author:         Dewain Smith #TheBeardedEngineer
    Updated:        2025-04-14
    Version:        1.0
#>

#----------------------------------------------
# Global Logging Function
#----------------------------------------------
function Write-Log {
    <#
    .SYNOPSIS
        Outputs a log message with a timestamp and severity level.
    
    .PARAMETER Message
        The text of the log message.
    
    .PARAMETER Level
        The severity level (e.g., "INFO" or "ERROR"). Default is "INFO".
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timeStamp [$Level] $Message"
}

#----------------------------------------------
# 1. Retrieve Input Parameters
#----------------------------------------------
# Prompt for the username (SamAccountName) whose logon history will be retrieved.
$userName = Read-Host "Enter the username (SamAccountName)"

# Specify the maximum number of logon events to retrieve per domain controller.
$logonEventsCount = 100

#----------------------------------------------
# 2. Retrieve Domain Controllers
#----------------------------------------------
Write-Log -Message "Querying all domain controllers in the current domain..."
try {
    # Retrieve all domain controllers using Get-ADDomainController.
    $domainControllers = Get-ADDomainController -Filter * -ErrorAction Stop
    if (-not $domainControllers) {
        Write-Log -Message "No domain controllers found." -Level "ERROR"
        exit
    }
    Write-Log -Message "Found $($domainControllers.Count) domain controller(s)."
} catch {
    Write-Log -Message "Error retrieving domain controllers: $_" -Level "ERROR"
    exit
}

#----------------------------------------------
# 3. Retrieve Logon Events from Each Domain Controller
#----------------------------------------------
Write-Log -Message "Querying logon events (Event ID 4624) for user '$userName' from the Security logs..."

# Initialize an empty array to collect logon events.
$logonEvents = @()

foreach ($dc in $domainControllers) {
    Write-Log -Message "Querying domain controller: $($dc.HostName)..."
    try {
        # Construct the XPath query that selects Security events where:
        # - The event ID is 4624 (successful logon).
        # - The TargetUserName in the event data matches the specified user.
        $xpathQuery = "<QueryList>
                           <Query Id='0' Path='Security'>
                               <Select Path='Security'>
                                   *[System[(EventID=4624) and (EventRecordID > 0)]]
                                   [EventData[Data[@Name='TargetUserName']='$userName']]
                               </Select>
                           </Query>
                       </QueryList>"
        # Retrieve logon events from the current domain controller.
        $events = Get-WinEvent -ComputerName $dc.HostName -LogName Security -FilterXPath $xpathQuery -MaxEvents $logonEventsCount
        $logonEvents += $events
        Write-Log -Message "Retrieved $($events.Count) event(s) from $($dc.HostName)."
    } catch {
        Write-Log -Message "Error querying $($dc.HostName): $_" -Level "ERROR"
        continue
    }
}

#----------------------------------------------
# 4. Display Retrieved Logon Events
#----------------------------------------------
if ($logonEvents.Count -eq 0) {
    Write-Log -Message "No logon events found for user '$userName'." -Level "INFO"
} else {
    Write-Log -Message "Logon events for user '$userName':"
    foreach ($event in $logonEvents) {
        try {
            # Convert the event to XML for detailed data extraction.
            $eventXML = [xml]$event.ToXml()
            # Extract the event's creation time.
            $eventTime = Get-Date $event.TimeCreated
            # Extract a specific data field from the event's EventData section.
            # In this example, Data index 8 is used; this may vary depending on the event schema.
            $dataField = $eventXML.Event.EventData.Data[8].'#text'
            # Extract the computer name from the event's System section.
            $computer = $eventXML.Event.System.Computer
            # Output the event details in a formatted manner.
            Write-Log -Message ("{0} - {1} - {2}" -f $eventTime.ToString('yyyy-MM-dd HH:mm:ss'), $dataField, $computer)
        } catch {
            Write-Log -Message "Error processing event: $_" -Level "ERROR"
        }
    }
}

Write-Log -Message "Logon events retrieval process completed." -Level "INFO"
