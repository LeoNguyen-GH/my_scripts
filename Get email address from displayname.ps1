. "$PSScriptRoot\common\functions.ps1"

function display_user {
    param (
        [parameter(mandatory)] [PSCustomObject]$user_object
    )
    
    write-host "$name not found, searching with only first name" -ForegroundColor Yellow
    
    if ($user_object.Count -gt 1) {
        $user_object | Select-Object UserPrincipalName, DisplayName
    } else {
        write-host $user_object.UserPrincipalName
    }
}

function main {
    $display_names = multi_user_input -prompt "Enter user displayname to get email address (Newline for multiple, enter 'q' to continue):"

    foreach ($name in $display_names) {
        $first_name = $name -replace '^(\w+).*', '$1'
        
        if ($user_object = Get-AzureADUser -SearchString $name) {
            display_user -user_object $user_object
        } elseif ($user_object = Get-AzureADUser -SearchString $first_name) {
                display_user -user_object $user_object
        } else {
            write-host "No match found for '$name" -Foregroundcolor Red
        }
    }
}

azureAD_connect

while ($true) {
    main
}