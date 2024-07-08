. "$PSScriptRoot\common\functions.ps1"

function display_user {
    param ([parameter(mandatory)] [Microsoft.Open.AzureAD.Model.DirectoryObject[]]$user)

    if ($user.Count -gt 1) { $user | Select-Object UserPrincipalName, DisplayName | format-table } else { write-host $user.UserPrincipalName }
}

function main {
    $names = multi_user_input -prompt "Enter user displayname to get email address (Newline for multiple, enter 'q' to continue):"

    foreach ($name in $names) {
        $first_name = $name -replace '^(\w+).*', '$1'
        
        if ($user = Get-AzureADUser -SearchString $name) {
            display_user -user $user
        } elseif ($user = Get-AzureADUser -SearchString $first_name) {
            write-warning "$name not found, found search query with just first name '$first_name'."
            display_user -user $user
        } else {
            write-warning "No match found for '$name'."
        }
    }
}

azureAD_connect

while ($true) { main }
