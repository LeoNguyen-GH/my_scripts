. "$PSScriptRoot\common\functions.ps1"

function get_cloud_user {
    param (
        [string]$prompt = "Enter the email to get the user object from Entra ID"
    )

    do {
        do {
            $user_email = (Read-Host $prompt).trim()
        } while ([string]::IsNullOrEmpty($user_email))
    } while ([string]::IsNullOrEmpty(($cloud_email_object = validate_entra_ID_user -email $user_email)))

    return $cloud_email_object
}

function display_groups {
    param (
        [parameter(mandatory)] [PSCustomObject]$cloud_user_object,
        [parameter(mandatory)] [string]$email
    )
    
    Write-Host "Updated listed groups for '$email':"
    do {
        Get-AzureADUserMembership -ObjectId $cloud_user_object.ObjectId -All $true | Select-Object Displayname, Mail 
    } while ((Read-Host "Do you want to refresh '$email' groups? (Y/N)").trim() -eq "Y")
}

function add_group_member {
    param (
        [parameter(mandatory)] [PSCustomObject]$group_object,
        [parameter(mandatory)] [string]$email
    )
    
    if (!($group = $group_object.mail)) {
        $group = $group_object.Displayname
    }
    
    try {
        Add-AzureADGroupMember -ObjectId $group_object.ObjectId -RefObjectId $target_user_object.ObjectId
        write-host "Assigned member: '$email' -> '$group'" -ForegroundColor Cyan
    } catch {
        if (($error_msg = [regex]::Match($_, "Message: (.+)").Groups[1].Value) -match "Cannot Update a mail-enabled security groups and or distribution list.") {
            try {
                Add-DistributionGroupMember -Identity $group_object.mail -Member $email -BypassSecurityGroupManagerCheck -Confirm:$false -ErrorAction Stop
                write-host "Assigned member: '$email' -> '$group'" -ForegroundColor Cyan
            } catch [System.Object] {
                if (([regex]::Match($_, "((.*\|)(.*))").Groups[3].Value) -match "is already a member of the group") {
                    write-warning "The recipient '$email' is already a member of the group '$($group_object.mail)'"
                } else {
                    Write-Error "Error: $_"
                }
            } catch {
                Write-Error "Error: $_"
            }
        } elseif ($error_msg -match "One or more added object references already exist for the following modified properties") {
            Write-warning "The recipient '$email' is already a member of the group '$group"
        } else {
            Write-Error "Error: $error_msg"
        }
    }
}

function main {
    $source_user_object = get_cloud_user -prompt "Enter email of source user to copy email groups from" 
    $target_user_object = get_cloud_user -prompt "Enter email of target user to mirror email groups from source user"

    # Discontinue the process if source and target user is the same
    if (($source_user_UPN = $source_user_object.UserPrincipalName) -eq ($target_user_UPN = $target_user_object.UserPrincipalName)) {
        write-host "Source and target user can't be the same, cancelling current process" -ForegroundColor Red
        return
    }

    # Get source user groups
    if (!($source_user_groups = Get-AzureADUserMembership -ObjectId $source_user_object.ObjectId -All $true)) {
        write-host "No email groups was found for the source user '$source_user_UPN' to mirror from, cancelling current process" -ForegroundColor Yellow
        return
    }

    # Display source user groups
    Write-Host "Adding listed email groups: Source user '$source_user_UPN' -> Target user '$target_user_UPN'" -ForegroundColor Blue
    $source_user_groups | Select-Object Displayname, Mail

    # Confirmation prompt to continue
    if (!(closed_input -user_prompt "Do you want to continue? (Y/N)" -n_msg "Current process terminated.")) {
        return
    }
    
    # Copy source user groups to target user
    $filtered_groups = @("group1")
    $source_user_groups | Where-Object { $_.mail -notin $filtered_groups  } | ForEach-Object {
        add_group_member -group_object $_ -email $target_user_UPN
    }
    
    #  Display updated target user groups
    display_groups -cloud_user_object $target_user_object -email $target_user_UPN

    print_dash_across_terminal
}

EXO_connect
azureAD_connect

while ($true) {
    main
}
