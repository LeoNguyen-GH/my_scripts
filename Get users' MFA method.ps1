. "$PSScriptRoot\common\functions.ps1"

function get_users_data {
    param (
        [string[]]$OU_users = $null
    )
    
    $users_data = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    $users = if ($OU_users) { Get-MsolUser -All | where-object { ($_.UserType -eq "Member") -and ($_.UserPrincipalName -in $OU_users) } } else { Get-MsolUser -All | where-object { ($_.UserType -eq "Member") -and ($_.BlockCredential -eq $false) -and ($_.IsLicensed -eq $true) } }
    
    foreach ($user in $users) {
        $MFA_method = if ($user.StrongAuthenticationMethods) { $user.StrongAuthenticationMethods | Where-Object {$_.IsDefault -eq $true} | Select-Object -ExpandProperty MethodType } else { "Disabled" }
        
        $users_data.Add([PSCustomObject]@{
            "email" = $user.UserPrincipalName
            "display name" = $user.DisplayName
            "mfa method" = $MFA_method
            "department" = $user.Department
            "office" = $user.Office
            "state" = $user.State
            "city" = $user.City
            "is licensed" = $user.IsLicensed
            "created" = $user.WhenCreated
        })
    }
    
    return $users_data
}

function get_AD_users {
    multi_user_input -prompt "Enter OU distinguished name to parse AD users (Newline for multiple, enter 'q' to continue):" | ForEach-Object {
        $OU_users = Get-ADUser -SearchBase $_ -Filter * | Select-Object -ExpandProperty UserPrincipalName
        $users = get_users_data -OU_users $OU_users
        export_csv -csv_file_path "$PSScriptRoot\_logs\exported\MFA users status - $_ $(Get-Date -Format 'dd-MM-yyyy h.mmtt').csv" -data $users
    }
}

function get_entra_users {
    $users = get_users_data
    export_csv -csv_file_path "$PSScriptRoot\_logs\exported\MFA users status $(Get-Date -Format 'dd-MM-yyyy h.mmtt').csv" -data $users
}

function main {
    if (closed_input -user_prompt "Do you want to parse users in an AD OU? (Y/N to get all users in Entra ID tenent)") {
        get_AD_users
    }
    else {
        get_entra_users
    }
}

MSOL_connect

while ($true) {
    main
}
