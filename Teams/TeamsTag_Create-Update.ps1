<#
.DESCRIPTION
  This script can be run standalone or setup as an Azure Automation Runbook. If you are setting this up as an automation runbook, 
    it is highly recommended to create an Entra App Registration then use the Client ID / Client Secret values as automation variables. 
    The Graph connection section of this script is setup to leverage this using saved Azure Automation variables.
  
  The creation/update process is designed to operate using an Entra security group as the source of truth for the tag membership. 
    When run, the script will import the group members to a variable, then compare that to the current membership of the tag. 
    Based on the results, the script will add or remove users from the tag so the tag's membership matches that of the security group.
  
  If you are running this script locally, it is recommended to:
	1. Insert sections for transcript logging (start/stop) so you have a record of changes made.
	2. Uncomment the Disconnect-MgGraph command at the very end of the script so you don't leave the connection open.
  
  How to use:
	1. (Line 56) Create the search query for the teams where you want to add/update the tag. You can build multiple search variables, 
        but the final variable that gets used in the rest of the script MUST be $Teams.
	2. (Lines 62-66) Enter the values for $tagName, $tagDescription, and $controlSG
	3. (Line 71) Enter the Object ID for a service account that will be used when creating the tag on a team for the first time. 
        New-MgTeamTag requires at least one user to be included when creating the tag, but this can be ANY user account - it will 
        be removed during the membership update stage if the user does not exist in the membership security group.
#>

#################################################################################################################################
## Graph Connection
#################################################################################################################################
$client_id     = Get-AutomationVariable -Name 'Graph_Client_ID' 
$client_secret = Get-AutomationVariable -Name 'Graph_Client_Secret'
$tenant_id     = Get-AutomationVariable -Name 'TenantID'
# Connect to API
$request   = @{
    Method = 'POST'
    URI    = "https://login.microsoftonline.com/$tenant_id/oauth2/v2.0/token"
    body   = @{
        grant_type    = "client_credentials"
        scope         = "https://graph.microsoft.com/.default"
        client_id     = $client_id
        client_secret = $client_secret
    }
}
# Get the access token
$token = ConvertTo-SecureString -String (Invoke-RestMethod @request).access_token -AsPlainText -Force
# Connect to Graph SDK
try {
    Connect-MgGraph -AccessToken $token -NoWelcome
}
catch {
    Write-Output "Graph Connection Error"
    Write-Output $_
}
# Start Time Measurement
$startTime = (Get-Date)

#################################################################################################################################
## Team Query Data
#################################################################################################################################
$Teams = Get-MgGroup -All | Where-Object {$_.Description -like "*/*"}  #Build your group query here - you can use multiple query vars, but the final one MUST be $Teams

#################################################################################################################################
## Variables and Functions
#################################################################################################################################
# Tag Name
$tagName        = "REPLACE ME WITH THE NAME OF YOUR TAG - FYI, SHORTER IS BETTER..."
# Tag Description
$tagDescription = "REPLACE ME WITH THE TAG DESCRIPTION YOU WANT TO USE"
# Entra security group containing updated membership list for tag
$controlSG      = "REPLACE ME WITH THE ID OF THE ENTRA SECURITY GROUP WHERE THE TAG MEMBERSHIP IS STORED"
# Retrieve new membership list for tag from Entra SG
$SGmembers      = Get-MgGroupMember -GroupId $controlSG | Select-Object Id
# Service account object ID - used as the initial member when creating the tag (must have at least one user on creation) 
# but will be removed during membership update
$SAUser         = "REPLACE ME WITH SERVICE ACCOUNT OBJECT ID"

# Create the tag if it does not exist for a team
Function New-Tag4Team {
    # Tag creation parameters
    $TagParams = @{
        DisplayName     = $tagName
        Description     = $tagDescription
        Members         = @(
            @{
                UserId  = $SAUser
            }
        )
    }
    # Notate tag creation in output log
    Write-Output "$($tagName) does not exist for team: $($teamdeets.DisplayName). Creating it now."
    # Create the tag
    New-MgTeamTag -TeamId $teamdeets.id -BodyParameter $TagParams
    # Record tag creation in output log
    Write-Output "$($tagName) tag created for team: $($teamdeets.DisplayName)"
    # Pause to allow tag creation to fully process
    Start-Sleep -Milliseconds 200
}

#################################################################################################################################
## Process Tag Updates
#################################################################################################################################
# Iterate through teams - create tag if needed and update membership
ForEach ($Team in $Teams) {    
    # Collect info on the team
    $teamdeets = Get-MgTeam -TeamId $Team.id
    # Variable to check if tag exists
    $tagcheck  = Get-MgTeamTag -TeamId $teamdeets.id -Filter "displayname eq '$($tagName)'"    
    # If tag does not exist, create it. Otherwise, report to output log and continue
    If (!$tagcheck) {
        New-Tag4Team
    }
    Else {
        # Record tag's existence in output log
        Write-Host "$($tagName) tag already exists for team: $($teamdeets.DisplayName)"
    }    
    # Get tag details
    $tagId = Get-MgTeamTag -TeamId $teamdeets.id -Filter "displayname eq '$($tagName)'"    
    # Get tag membership from team - if [NotFound] error appears for one of the users, delete tag and recreate it then pull again
    <#
    NOTE: This is a workaround for a known potential issue - if a user is offboarded and the account deleted BEFORE they are removed
      from a tag, the script will throw a terminating break for that particular team/tag update as the system cannot identify the user
      to either keep or remove them. This probably isn't the ideal solution, but it works reliably and does not add a significant amount
      of processing time to the overall script.
    #>
    $tagmembers = Get-MgTeamTagMember -TeamId $teamdeets.id -TeamworkTagId $tagId.Id
    if (!$tagmembers) {
        # Write to output log that tag needs to be removed and rebuilt
        Write-Output "Tag member found that cannot be removed. Deleting tag and re-creating."
        # Delete the tag
        Remove-MgTeamTag -TeamId $teamdeets.Id -TeamworkTagId $tagId.Id
        Write-Output "$($tagName) tag deleted"
        # Pause for 5 seconds to allow tag to fully delete
        Start-Sleep -Seconds 5
        # Create team fresh
        New-Tag4Team
        # Pull new tag membership
        $tagId = Get-MgTeamTag -TeamId $teamdeets.id -Filter "displayname eq '$($tagName)'"
        # Rerun tag member query
        $tagmembers = Get-MgTeamTagMember -TeamId $teamdeets.id -TeamworkTagId $tagId.Id
        Write-Output "Tag members retrieved"
    }
    else {
        Write-Output "Tag members retrieved"
    }
    # Create delta between SG and tag memberships
    $delta         = Compare-Object -ReferenceObject $SGmembers.Id -DifferenceObject $tagmembers.UserId
    # Define additions and removals
    $addMembers    = $delta | Where-Object {$_.SideIndicator -eq "<="}
	$removeMembers = $delta | Where-Object {$_.SideIndicator -eq "=>"}    
	# Process additions to tag
	If ($addMembers.InputObject.Count -gt "0") {
		# Iterate through members, adding each to tag
        ForEach ($member in $addMembers) {
			# Get user info (for display purposes)
            $memberDeets = Get-MgUser -UserId $member.InputObject
			# Add member to tag
            New-MgTeamTagMember -TeamId $teamdeets.id -TeamworkTagId $tagId.Id -UserId $member.InputObject
			# Record the addition in output logs
            Write-Output "Adding $($memberDeets.DisplayName) to $($tagName) tag for team: $($teamdeets.DisplayName)"
		}
	}
	Else {
        # Record in output log no members need to be added
		Write-Output "No members added to $($tagName) tag for team: $($teamdeets.DisplayName)"
	}	
	# Process removals from tag
	If ($removeMembers.InputObject.Count -gt "0") {
		# Iterate through members, removing each from tag
        ForEach ($member in $removeMembers) {
            # Get user info (for display purposes)
			$memberDeets = Get-MgUser -UserId $member.InputObject
            # Obtain user's tag membership ID
			$tagMemberDeets = Get-MgTeamTagMember -TeamId $teamdeets.id -TeamworkTagId $tagId.Id | Where-Object {$_.UserId -eq $($memberDeets.Id)}
            # Remove user from tag
			Remove-MgTeamTagMember -TeamId $teamdeets.id -TeamworkTagId $tagId.Id -TeamworkTagMemberId $tagMemberDeets.Id
            # Record the removal in output logs
			Write-Output "Removing $($memberDeets.DisplayName) from $($tagName) tag in team: $($teamdeets.DisplayName)"
		}
	}
	Else {
        # Record in output log no members need to be removed
		Write-Output "No members removed from $($tagName) tag for team: $($teamdeets.DisplayName)"
	}
}

#################################################################################################################################
## Stop time measurement, display total script time
#################################################################################################################################
$endTime = (Get-Date)
$elapsedTime = (($endTime-$startTime).TotalSeconds)
Write-Output "Total execution time in seconds:" $elapsedTime
# If running this script locally (NOT A RUNBOOK), uncomment the next line to disconnect from Graph
# Disconnect-MgGraph
