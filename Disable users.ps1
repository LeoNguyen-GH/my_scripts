if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit } 
. "$PSScriptRoot\common\functions.ps1"

function set_auto_reply {
    if (closed_input -user_prompt "Do you want to enable automatic replies for this mailbox? (Y/N)") {
        return get_validated_input -prompt "Enter the Out of Office message" -condition "!`$user_input"
    }
}

function get_user_data {
    param ([parameter(mandatory)] [string]$email)
    
    return $user = if ($user = Get-ADUser -Filter { userPrincipalName -eq $email }) { $user } else { Get-ADUser -Filter { EmailAddress -eq $email } }
}

function check_user_enabled_state {
    param ([parameter(mandatory)] [Microsoft.ActiveDirectory.Management.ADAccount]$user)
    
    if ($user.Enabled -eq $false -and !(closed_input -user_prompt "User '$($user.SamAccountName)' is already disabled. Do you want to continue? (Y/N)" -n_msg "User disable process terminated.")) {
        return $true
    } else {
        return $null
    }
}

function remove_attributes {
    param ([parameter(mandatory)] [Microsoft.ActiveDirectory.Management.ADAccount]$user)
    
    try { $manager = (Get-ADUser $($user.manager)).name } catch { $manager = $null }
    write-host "Removing user attributes Company ($($user.company)), Department ($($user.department)), Manager ($manager)"
    Set-ADUser -Identity $user -Clear Company, Department, Manager
}

function move_ADUser {
    param (
        [parameter(mandatory)] [string]$OU_name,
        [parameter(mandatory)] [Microsoft.ActiveDirectory.Management.ADAccount]$user
    )
    
    $OU = Get-ADOrganizationalUnit -Filter { Name -eq $OU_name }
    write-host "Moving user to OU: $($OU.DistinguishedName)"
    Move-ADObject -Identity $user.DistinguishedName -TargetPath $OU.DistinguishedName
    start-sleep 2
    
    # Check if the user is in the OU and is disabled
    $disabled_users = Get-ADUser -SearchBase $OU.DistinguishedName -Filter { Enabled -eq $false }
    if ($user.SamAccountName -in $disabled_users.SamAccountName) {
        write-host "User '$($user.SamAccountName)' is in the '$OU_name' OU and is disabled." -ForegroundColor Green
    } else {
        Write-Warning "User '$($user.SamAccountName)' is not in the '$OU_name' OU or is not disabled."
    }
}

function remove_user_group {
    param (
        [parameter(mandatory)] [string]$user_objectID,
        [parameter(mandatory)] [string]$email
    )
    
    $groups = Get-AzureADUserMembership -ObjectId $user_objectID | Where-Object { ($_.ObjectType -eq "Group") -and ($_.DirSyncEnabled -ne "True") }
    
    foreach ($group in $groups) {
        if ($group_ref = Get-DistributionGroup -Identity $group.ObjectId -ErrorAction SilentlyContinue) {
            Remove-DistributionGroupMember -Identity $group_ref.PrimarySmtpAddress -Member $email -BypassSecurityGroupManagerCheck -Confirm:$false
            write-host "Removed '$email' from distribution/mail enabled group: $($group_ref.PrimarySmtpAddress)" -ForegroundColor Cyan
        } else {
            remove-AzureADGroupMember -ObjectId $group.ObjectId -MemberId $user_objectID
            write-host "Removed '$email' from Microsoft 365 team/Security group: $($group.DisplayName)" -ForegroundColor Cyan
        }
    }

    write-host "User '$email' has been removed from all cloud based groups." -ForegroundColor Green
}

function remove_all_user_licenses {
    param ([parameter(mandatory)] [Microsoft.Open.AzureAD.Model.DirectoryObject]$user)

    $Skus = ($user | Select-Object -ExpandProperty AssignedLicenses).SkuID

    if (!$Skus) {
        Write-Host "No licenses found for '$($user.UserPrincipalName)'" -ForegroundColor Magenta
        return
    }
    
    $licenses = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicenses
    
    foreach ($sku in $Skus) {
        $licenses.RemoveLicenses += $sku
    }
    
    Set-AzureADUserLicense -ObjectId $user.UserPrincipalName -AssignedLicenses $licenses
    Write-Host "Removed $($Skus.count) licenses from $($user.UserPrincipalName)`: `n$($licenses.RemoveLicenses)" -ForegroundColor Magenta
}

function check_mailbox_type {
    param ([parameter(mandatory)] [string]$email)

    if (($mailbox_type = (Get-Mailbox -Identity $email).RecipientTypeDetails) -eq "SharedMailbox") {
        Write-Host "$email has a $mailbox_type." -ForegroundColor Green
        
    } else {
        Write-Warning "$email has a $mailbox_type."
        $global:retry = $true
    }
}

function check_license {
    param ([parameter(mandatory)] [Microsoft.Open.AzureAD.Model.DirectoryObject]$user)

    $Skus = ($user | Select-Object -ExpandProperty AssignedLicenses).SkuID

    if (!$Skus) {
        Write-Host "$($user.UserPrincipalName) has no licenses" -ForegroundColor Green
    } else {
        Write-Warning "$($user.UserPrincipalName) still has license found:`n$Skus"
        $global:retry = $true
    }
}

function check_groups {
    param ([parameter(mandatory)] [Microsoft.Open.AzureAD.Model.DirectoryObject]$user)
    
    if (Get-AzureADUserMembership -ObjectId $user.ObjectId | Where-Object { ($_.ObjectType -eq "Group") -and ($_.DirSyncEnabled -ne "True") }) {
        Write-Warning "$($user.UserPrincipalName) is a member of an email group"
        $global:retry = $true   
    } else {
        write-host "$($user.UserPrincipalName) is not a member of any email group." -ForegroundColor Green
    }
}

function disable_user_checks {
    param ([parameter(mandatory)] [Microsoft.Open.AzureAD.Model.DirectoryObject]$user)

    for ($i=0; $i -lt 3; $i++) {
        $global:retry = $false
        
        check_mailbox_type -email $user.UserPrincipalName
        check_license -user $user
        check_groups -user $user

        if (!$global:retry) { return }
        
        start-sleep 20
    }
}

function address_book_status {
    param ([parameter(mandatory)] [string]$email)

    if ((get-mailbox $email).HiddenFromAddressListsEnabled -eq $false) {
        Write-Warning "'$email' is not hidden in the Global Address List."
    } else {
        Write-Host "'$email' is hidden in the Global Address List." -ForegroundColor Green
    }
}

function main {
    $users_email = get_multi_user_input -prompt "Enter user email to disable (Newline for multiple, enter 'q' to continue):"
    if (!($users_email = get_valid_email -emails $users_email -type_aduser $true)) { return }
    
    [void](New-Item -Path "$PSScriptRoot\_logs\disabled_users" -ItemType "directory" -erroraction silentlycontinue)
    
    foreach ($user_email in $users_email) { 
        [void](Start-Transcript -Path "$PSScriptRoot\_logs\disabled_users\$user_email - $(Get-Date -Format 'dd-MM-yyyy h.mmtt').txt")
        
        write-host "Disabling user: $user_email"
        
        $user = get_user_data -email $user_email
        $UPN = $user.UserPrincipalName
        $entra_id_user = Get-AzureADUser -Filter "userPrincipalName eq '$UPN'"
        try { 
            if (!$user -or !$UPN -or !$entra_id_user) { throw "Unable to get sufficent user data for user '$user_email' to continue the user disable process." } 
        } catch { 
            write-error "$($_.Exception.Message)"  
            continue
        }
        
        $auto_reply_msg = set_auto_reply
        
        if (check_user_enabled_state -user $user) { continue }
        
        Set-ADUser -Identity $user -Enabled $false
        
        remove_attributes -user $user
        
        move_ADUser -OU_name "Disabled Users" -user $user
        
        write-host "Converting '$UPN' to Shared mailbox"
        Set-Mailbox -Identity $UPN -Type Shared

        remove_user_group -user_objectID $entra_id_user.ObjectId -email $UPN

        remove_all_user_licenses -user $entra_id_user
        
        if ($auto_reply_msg) {
            Set-MailboxAutoReplyConfiguration -Identity $UPN -AutoReplyState enabled -InternalMessage $auto_reply_msg -ExternalMessage $auto_reply_msg
            Write-Host "Automatic reply set: '$auto_reply_msg'" -ForegroundColor Yellow
        }
        
        Start-Sleep 20
        
        disable_user_checks -user $entra_id_user
        
        address_book_status -email $UPN
        
        [void](Stop-Transcript)
    }
}

EXO_connect
azureAD_connect

while ($true) { main }
