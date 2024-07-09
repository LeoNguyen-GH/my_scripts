. "$PSScriptRoot\common\functions.ps1"
get_functions -file_path "$PSScriptRoot\Add users to groups and mailboxes.ps1" | Invoke-Expression

function display_groups {
    param ([parameter(mandatory)] [Microsoft.Open.AzureAD.Model.DirectoryObject]$user)
    
    Write-Host "Updated groups for '$($user.UserPrincipalName)':"
    do { Get-AzureADUserMembership -ObjectId $user.ObjectId -All $true | Select-Object Displayname, Mail | format-table
    } while ((Read-Host "Do you want to refresh '$($user.UserPrincipalName)' groups? (Y/N)").trim() -eq "Y")
}

function main {
    $source_user = get_validated_input -prompt "Enter email of source user to copy email groups from" -condition "!(`$user_input = get_valid_entra_ID_user -email `$user_input)"
    $target_user = get_validated_input -prompt "Enter email of target user to mirror email groups from source user" -condition "!(`$user_input = get_valid_entra_ID_user -email `$user_input)"

    # Discontinue the process if source and target user is the same
    if (($source_user_UPN = $source_user.UserPrincipalName) -eq ($target_user_UPN = $target_user.UserPrincipalName)) {
        write-host "Source and target user can't be the same, cancelling current process" -ForegroundColor Red
        return
    }

    # Get source user groups
    if (!($source_user_groups = Get-AzureADUserMembership -ObjectId $source_user.ObjectId -All $true)) {
        write-warning "No email groups was found for the source user '$source_user_UPN' to mirror from, cancelling current process" -ForegroundColor Yellow
        return
    }

    # Display source user groups
    Write-Host "Adding listed email groups: Source user '$source_user_UPN' -> Target user '$target_user_UPN'" -ForegroundColor Blue
    $source_user_groups | Select-Object Displayname, Mail | format-table

    # Confirmation prompt to continue
    if (!(closed_input -user_prompt "Do you want to continue? (Y/N)" -n_msg "Current process terminated.")) { return }
    
    # Copy source user groups to target user
    $filtered_groups = @("group@company.com")
    foreach ($group in $source_user_groups) {
        $group_ref = if ($group.mail) {$group.mail} else {$group.Displayname}
        if ($group_ref -in $filtered_groups) { continue }

        add_group_member -user $target_user_UPN -group $group_ref
    }
    
    display_groups -user $target_user
}

EXO_connect
azureAD_connect

while ($true) { main }
