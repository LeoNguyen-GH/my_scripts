. "$PSScriptRoot\common\functions.ps1"

function get_OU_users {
    param ([parameter(Mandatory)] [string]$ouDN)

    try { return Get-ADUser -SearchBase $ouDN -Filter * -Properties * } catch { write-host "Error: $_" -ForegroundColor Red }
}

function get_formatted_ADuser_data {
    [CmdletBinding()]
    param ([parameter(Mandatory, ValuefromPipeline)] [Microsoft.ActiveDirectory.Management.ADAccount]$user)
    
    process {
        return [PSCustomObject]@{
            Name            = $user.Name
            SamAccountName  = $user.SamAccountName
            UPN             = $user.UserPrincipalName
            Email           = $user.EmailAddress
            MobileNumber    = $user.mobile
            TelephoneNumber = $user.telephonenumber
            Office          = $user.office
            Department      = $user.department
            Manager         = $user.Manager
            Company         = $user.Company
            JobTitle        = $user.title
        }
    }
}

function main {
    $ouDNs = multi_user_input -prompt "Enter OU distinguished name to parse AD users (Newline for multiple, enter 'q' to continue):"

    foreach ($ouDN in $ouDNs) {
        if (!($users = get_OU_users -ouDN $ouDN)) { continue }
        
        $users_data = [System.Collections.Generic.List[PSCustomObject]]::new()
        $users | get_formatted_ADuser_data | ForEach-Object { $users_data.Add($_) }
        
        export_csv -csv_file_path "$PSScriptRoot\_logs\exported\AD users - $ouDN $(Get-Date -Format "dd-MM-yyyy h.mmtt").csv" -data $users_data
    }
}

while ($true) {
    main
}
