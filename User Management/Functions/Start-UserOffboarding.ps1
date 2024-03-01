Function Start-UserOffboard {
    <#
    .SYNOPSIS
        Performs an offboarding for a user account
    .PARAMETER User
        The UPN of the user account to offboard
    .PARAMETER SkipMailbox
        Boolean value. Only needed if the user account does not have an associated mailbox. 
        Default is: $false
    .PARAMETER SkipDelete
        Boolean value. Only needed if you DO NOT WANT the user account deleted at the end of the process.
        Default is: $false
    .EXAMPLE
        Start-UserOffboard -User john.smith@example.com
        Performs full offboarding of user John Smith
    .EXAMPLE
        Start-UserOffboard -User app1234@example.com -SkipMailbox $true
        Performs offboarding of service account app1234, skipping the mailbox components as it doesn't have a mailbox
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [String]$User,
        [Parameter(Mandatory = $false)]
        [Boolean]$SkipMailbox = $false,
        [Parameter(Mandatory = $false)]
        [Boolean]$SkipDelete = $false
    )

    #############################################################
    ## Define Script Requirements
    #############################################################
    #Requires -Version 7.0
    #Requires -Modules @{ ModuleName="Microsoft.Graph.Authentication"; ModuleVersion="2.10.0"}
    #Requires -Modules @{ ModuleName="Microsoft.Graph.Users"; ModuleVersion="2.10.0"}
    #Requires -Modules @{ ModuleName="Microsoft.Graph.Groups"; ModuleVersion="2.10.0"}
    #Requires -Modules @{ ModuleName="Microsoft.Graph.DeviceManagement"; ModuleVersion="2.10.0"}
    #Requires -Modules @{ ModuleName="ExchangeOnlineManagement"; ModuleVersion="3.1.0"}
    #Requires -RunAsAdministrator

    #############################################################
    ## Initialize/Start Transcript
    #############################################################
    $transcriptFile = (Get-Date -UFormat "%Y%m%d-%H%M")+' - UserOffboard.txt'
    $transcriptDir = "PUT THE DIRECTORY WHERE YOU WANT THE TRANSCRIPT SAVED HERE"
    $transcriptPath = $transcriptDir+$transcriptFile
    Start-Transcript -Path $transcriptPath -IncludeInvocationHeader

    #############################################################
    ## Graph and Exchange Online Connections
    #############################################################
    # Connect to Graph
    Try {
        Write-Output "Connecting to Microsoft Graph API..."
        Connect-GraphUserChanges
    }
    Catch {
        Write-Error - "Unable to connect to Graph via the 'GraphUserChanges' CBA connector. Please verify the function is loaded to your PS Profile and your certificate is valid."
        Write-Error $_
        Exit
    }
    # Connect to Exchange online
    Try {
        Write-Output "Connecting to Exchange Online PowerShell..."
        Connect-ExchangeOnline
    }
    Catch {
        Write-Error - "Unable to connect to Exchange Online PowerShell."
        Write-Error $_
        Exit
    }

    #############################################################
    ## Collect User Info
    #############################################################
    $userDeets = Get-MgUser -UserId $User
    Write-Output "Beginning offboarding for user $($userDeets.DisplayName)"

    #############################################################
    ## Block User Access
    #############################################################
    # Revoke AAD user refresh token
    Write-Output "Revoking session tokens for $($userDeets.DisplayName)"
    Revoke-MgUserSignInSession -UserId $userDeets.Id
    Write-Output "$($userDeets.DisplayName) has been logged out of all devices, apps, and services."
    Write-Output ""
    Write-Output "--------------------------------------------------------------------------------------------------------------"
    Write-Output ""
    # Find and remove any configured MFA methods
    $mfa = Get-MgUserAuthenticationMethod -UserId $userDeets.Id
    Write-Output "Retrieving all configured MFA methods for $($userDeets.DisplayName). All identified methods will be deleted."
    Write-Output ""
    Foreach ($method in $mfa) {
        Switch ($method.AdditionalProperties["@odata.type"]) {
            "#Microsoft.Graph.emailAuthenticationMethod" {
                $emailData = Get-MgUserAuthenticationEmailMethod -UserId $userDeets.Id -EmailAuthenticationMethodId $method.Id
                Write-Output "Removing Email MFA methods" 
                Write-Output "--------------------------" 
                Remove-MgUserAuthenticationEmailMethod -UserId $userDeets.Id -EmailAuthenticationMethodId $method.Id
                Write-Output "Email logged to MFA was $($emailData.EmailAddress)" 
                Write-Output " "
            }
            "#microsoft.graph.fido2AuthenticationMethod" {
                $fidoData = Get-MgUserAuthenticationFido2Method -UserId $userDeets.Id -Fido2AuthenticationMethodId $method.Id
                Write-Output "Removing FIDO2 MFA methods" 
                Write-Output "--------------------------" 
                Remove-MgUserAuthenticationFido2Method -UserId $userDeets.Id -Fido2AuthenticationMethodId $method.Id
                Write-Output "FIDO2 Device Name: $($fidoData.DisplayName)" 
                Write-Output "FIDO2 Device Model: $($fidoData.Model)" 
                Write-Output " "
            }
            "#microsoft.graph.microsoftAuthenticatorAuthenticationMethod" {
                $msftAuthData = Get-MgUserAuthenticationMicrosoftAuthenticatorMethod -UserId $userDeets.Id -MicrosoftAuthenticatorAuthenticationMethodId $method.Id
                Write-Output "Removing Microsoft Authenticator MFA methods" 
                Write-Output "--------------------------------------------" 
                Remove-MgUserAuthenticationMicrosoftAuthenticatorMethod -UserId $userDeets.Id -MicrosoftAuthenticatorAuthenticationMethodId $method.Id
                Write-Output "Device name $($msftAuthData.DisplayName)" 
                Write-Output " "
            }
            "#microsoft.graph.phoneAuthenticationMethod" {
                $phoneData = Get-MgUserAuthenticationPhoneMethod -UserId $userDeets.Id -PhoneAuthenticationMethodId $method.Id
                Write-Output "Removing Phone MFA methods" 
                Write-Output "--------------------------" 
                Remove-MgUserAuthenticationPhoneMethod -UserId $userDeets.Id -PhoneAuthenticationMethodId $method.Id
                Write-Output "Phone type $($phoneData.PhoneType)" 
                Write-Output "Phone number $($phoneData.PhoneNumber)" 
                Write-Output " "
            }
            "#microsoft.graph.softwareOathAuthenticationMethod" {
                # No device/app details to display for transcript record
                Write-Output "Removing Software Oath MFA methods" 
                Write-Output "------------------------------" 
                Write-Output " "
                Remove-MgUserAuthenticationSoftwareOathMethod -UserId $userDeets.Id -SoftwareOathAuthenticationMethodId $method.Id
            }
            "#microsoft.graph.temporaryAccessPassAuthenticationMethod" {
                # No users have TAP enabled, unable to collect requisite data for detail display
                Write-Output "Removing Temporary Access Pass (TAP) MFA methods" 
                Write-Output "------------------------------------------------" 
                Write-Output " "
                Remove-MgUserAuthenticationTemporaryAccessPassMethod -UserId $userDeets.Id -TemporaryAccessPassAuthenticationMethodId $method.Id
            }
            "#microsoft.graph.windowsHelloForBusinessAuthenticationMethod" {
                $whfbData = Get-MgUserAuthenticationWindowsHelloForBusinessMethod -UserId $userDeets.Id -WindowsHelloForBusinessAuthenticationMethodId $method.Id
                Write-Output "Removing Windows Hello for Business MFA methods" 
                Write-Output "-----------------------------------------------" 
                Remove-MgUserAuthenticationWindowsHelloForBusinessMethod -UserId $userDeets.Id -WindowsHelloForBusinessAuthenticationMethodId $method.Id
                Write-Output "Device Name $($whfbData.DisplayName)" 
                Write-Output " "
            }
        }
    }
    Write-Output ""
    Write-Output "--------------------------------------------------------------------------------------------------------------"
    Write-Output ""

    #############################################################
    ## Collect and log user groups before disabling account
    #############################################################
    Write-Output "These are the groups $($userDeets.DisplayName) is a member of:"
    Write-Output ""
    Write-Output "Direct group memberships:"
    Write-Output "---------------------------"
    Get-MgUserMemberOf -UserId $userDeets.Id | Select-Object * -ExpandProperty additionalProperties | Select-Object Id,{$_.AdditionalProperties["displayName"]},{$_.AdditionalProperties["groupTypes"]} | Format-Table
    Write-Output ""
    Write-Output "Transitive group memberships (there may be some overlap with direct group memberships):"
    Write-Output "-----------------------------------------------------------------------------------------"
    Get-MgUserTransitiveMemberOf -UserId $userDeets.Id | Select-Object * -ExpandProperty additionalProperties | Select-Object Id,{$_.AdditionalProperties["displayName"]},{$_.AdditionalProperties["groupTypes"]} | Format-Table
    
    Write-Output ""
    Write-Output "--------------------------------------------------------------------------------------------------------------"
    Write-Output ""

    #############################################################
    ## Remove mailbox features (unless $SkipMailbox = $true)
    #############################################################
    if ($SkipMailbox -eq $false) {
        # Collect mailbox info
        Write-Output "Disabling mailbox features for user $($userDeets.DisplayName)"
        $mailboxDeets = Get-Mailbox -Identity $User
        Write-Output ""
        # Disable all existing user mailbox rules
        Get-InboxRule -Mailbox $mailboxDeets.Guid | Where-Object {($_.Enabled -eq $true)} | Disable-InboxRule
        Write-Output "User-side mailbox rules for $($mailboxDeets.DisplayName) have been disabled"
        Write-Output ""
        # Remove calendar publishing 
        # NOTE: Check if calendar is published FIRST - will cause a watson dump exception if command is run when calendar publishing is not enabled
        if((Get-MailboxCalendarFolder -Identity "$($mailboxDeets.Identity):\Calendar").PublishEnabled -eq $true) {
            Set-MailboxCalendarFolder -Identity "$($mailboxDeets.Identity):\Calendar" -PublishEnabled:$false -Confirm:$false
            Write-Output "User calendar publishing for $($mailboxDeets.DisplayName) has been disabled"
        }
        else {
            Write-Output "$($mailboxDeets.DisplayName) did not have any published calendars"
        }
        Write-Output ""
        # Cancel all existing meetings scheduled up to 2 years after termination date
        Remove-CalendarEvents -Identity $mailboxDeets.Guid -CancelOrganizedMeetings -QueryWindowInDays 730
        Write-Output "All future events scheduled by user $($mailboxDeets.DisplayName) have been canceled"
        Write-Output ""
        # Remove mailbox delegates
        $mailboxDelegates = Get-MailboxPermission -Identity $mailboxDeets.Guid | Where-Object {($_.IsInherited -ne "True") -and ($_.User -notlike "*SELF*")}
        foreach ($delegate in $mailboxDelegates) {
            Remove-MailboxPermission -Identity $mailboxDeets.Guid -User $delegate.User -AccessRights $delegate.AccessRights -InheritanceType All -Confirm:$false
        }
        Write-Output "All delegates on user mailbox $($mailboxDeets.Identity) have been removed"
        Write-Output ""
        # Disable any existing mailbox forwarding
        Set-Mailbox -Identity $mailboxDeets.Guid -DeliverToMailboxAndForward $false -ForwardingSmtpAddress $null -WarningAction:SilentlyContinue
        Write-Output "All forwarding rules for user mailbox $($mailboxDeets.Identity) have been disabled"
    }
    Write-Output ""
    Write-Output "--------------------------------------------------------------------------------------------------------------"
    Write-Output ""

    #############################################################
    ## Disable user account
    #############################################################
    # Disable user
    Write-Output "Disabling user acccount for $($userDeets.DisplayName)"
    Update-MgUser -UserId $userDeets.Id -AccountEnabled:$false
    Write-Output "$($userDeets.DisplayName) can no longer access the tenant."
    Write-Output "Dynamic license/group/application assignments will begin removing automatically."

    Write-Output ""
    Write-Output "--------------------------------------------------------------------------------------------------------------"
    Write-Output ""

    #############################################################
    ## List all user devices - remove personal ones
    #############################################################
    # Collect all devices associated with the user
    $userDevices = Get-MgUserOwnedDeviceAsDevice -UserId $userDeets.Id | Select-Object Id,DeviceId,DeviceOwnership,DisplayName,OperatingSystem,OperatingSystemVersion
    # Collect non-corporate devices associated with the user
    $personalDevices = Get-MgUserOwnedDeviceAsDevice -UserId $userDeets.Id | Where-Object {$_.DeviceOwnership -ne "Company" -and $_.OperatingSystem -ne "Windows"} | Select-Object Id,DeviceId,DeviceOwnership,DisplayName,OperatingSystem,OperatingSystemVersion
    # Display devices for output log
    Write-Output "These are the corporate-owned devices associated with $($userDeets.DisplayName):"
    Write-Output "---------------------------------------------------------------------------------"
    $userDevices | Format-Table
    Write-Output ""
    Write-Output "These are the personal devices associated with $($userDeets.DisplayName):"
    Write-Output "--------------------------------------------------------------------------"
    $personalDevices | Format-Table
    Write-Output "Removing all personal devices from $($userDeets.DisplayName)'s Entra account"
    # Iterate through each device, display the name/OS of each device, then remove it
    foreach ($device in $personalDevices) {
        Write-Output "Removing personal device $($device.DisplayName)"
        Write-Output "Device OS is $($device.OperatingSystem)"
        Remove-MgDevice -DeviceId $device.Id
    }
    Write-Output "Issuing Fresh Start wipe command to all corporate-owned devices"
    Write-Output "-----------------------------------------------------------------"
    foreach ($device in $userDevices) {
        $managedDeviceId = Get-MgDeviceManagementManagedDevice | Where-Object {$_.AzureAdDeviceId -eq "$($device.DeviceId)"}
        if (!$managedDeviceId) {
            Write-Output "Failed to issue Fresh Start wipe command to $($device.DisplayName). Manual intervention required"
        }
        else {
            $params = @{
                keepUserData = $false
            }
            Invoke-MgCleanDeviceManagementManagedDeviceWindowsDevice -ManagedDeviceId $managedDeviceId.Id -BodyParameter $params
            Write-Output "Fresh Start wipe command sent to $($device.DisplayName)"
        }
    }
    Write-Output ""
    Write-Output "--------------------------------------------------------------------------------------------------------------"
    Write-Output ""

    #############################################################
    ## Remove user from membership in non-dynamic groups
    #############################################################
    Write-Output "Removing user $($userDeets.DisplayName) from all directly-assigned group memberships."
    Write-Output "NOTE: This does not include membership in dynamic groups - those will be removed when the user is disabled"
    $directGroups = Get-MgUserMemberOfAsGroup -UserId $userDeets.Id -Filter "NOT(groupTypes/any(s:s eq 'DynamicMembership'))" -CountVariable CountVar -ConsistencyLevel Eventual
    Foreach ($group in $directGroups) {
        try {
            Remove-MgGroupMemberByRef -GroupId $group.Id -DirectoryObjectId $userDeets.Id
        }
        catch {
            Write-Output "Failed to remove $($userDeets.DisplayName) from $($group.DisplayName). Manual intervention required."
        }
    }

    Write-Output ""
    Write-Output "--------------------------------------------------------------------------------------------------------------"
    Write-Output ""

    #############################################################
    ## Delete user account (unless $SkipDelete = $true)
    #############################################################
    if ($SkipDelete -eq $false) {
        # Wait 5 seconds for processing
        Start-Sleep -Seconds 5
        # Soft-delete user account
        Write-Output "Deleting user account for $($userDeets.DisplayName)"
        Remove-MgUser -UserId $userDeets.Id
        Write-Output "User can be recovered from deleted users menu in the tenant admin portal if needed within the next 30 days."
    }
        
    Write-Output ""
    Write-Output "--------------------------------------------------------------------------------------------------------------"
    Write-Output ""

    #############################################################
    ## Stop transcript logging and complete script
    #############################################################
    Write-Output "User offboard process is complete"
    Write-Output "Transcript log for this process can be found here: $($transcriptPath)"
    Stop-Transcript
    Disconnect-MgGraph
}
