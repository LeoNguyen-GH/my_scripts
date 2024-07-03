. "$PSScriptRoot\common\functions.ps1"

function main {
    $users = multi_user_input -prompt "Enter user email to parse membership (Newline for multiple, enter 'q' to continue):"
    if (!($users = validate_email -emails $users)) {
        return
    }
    
    foreach ($user in $users) {
        if ($user_groups = Get-AzureADUserMembership -ObjectId (Get-AzureADUser -SearchString $user).ObjectId | Select-Object DisplayName, Mail) {
            export_csv -data $user_groups -csv_file_path "$PSScriptRoot\_logs\exported\$user - list of groups $(Get-Date -Format 'dd-MM-yyyy h.mmtt').csv"
        } else {
            Write-Host "Could not find any groups for user '$($user_object.DisplayName)'." -ForegroundColor Yellow
        }
    }
}

azureAD_connect

while ($true) {
    main
}
