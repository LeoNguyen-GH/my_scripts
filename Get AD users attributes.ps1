. "$PSScriptRoot\common\functions.ps1"

function get_OU_users {
    param ([parameter(Mandatory)] [string]$ouDN)

    try {
        return Get-ADUser -SearchBase $ouDN -Filter * -Properties *
    } catch {
        write-host "Error: $_" -ForegroundColor Red
        return
    }
}

function format_user_data {
    [CmdletBinding()]
    param ([parameter(Mandatory, ValuefromPipeline)] [array]$user)
    
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
    multi_user_input -prompt "Enter OU distinguished name to parse AD users (Newline for multiple, enter 'q' to continue):" | ForEach-Object {
        if (!($users = get_OU_users -ouDN $_)) {
            return
        }
        
        $users_data = [System.Collections.Generic.List[PSCustomObject]]::new()

        $users | format_user_data | ForEach-Object {
            $users_data.Add($_)
        }
        
        export_csv -csv_file_path "$PSScriptRoot\_logs\exported\AD users - $_ $(Get-Date -Format "dd-MM-yyyy h.mmtt").csv" -data $users_data
    }
}

while ($true) {
    main
}
