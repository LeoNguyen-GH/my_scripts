. "$PSScriptRoot\common\functions.ps1"

function new_csv {
    param (
        [parameter(mandatory)] [string]$file_path,
        [parameter(mandatory)] [string]$headers
        )
        
        [void](New-Item -Path (Split-Path -Path $file_path -Parent) -ItemType "directory" -erroraction silentlycontinue)
        Set-Content $file_path -Value $headers
}

function add_log {
    param (
        [parameter(mandatory)] [string]$file_path,
        [parameter(mandatory)] [string]$UPN,
        [parameter(mandatory)] [string]$attribute,
        [string]$original = $null,
        [string]$modified = $null
        )
        
        if (!(Test-Path -Path $file_path)) {
            new_csv -file_path $file_path -headers "userPrincipleName, Attribute, Original value, Modified value, Date, Time"
        }
        
        [PSCustomObject]@{
            userPrincipleName = $UPN
            Attribute = $attribute
            "Original value" = $original
            "Modified value" = $modified
            Date = $(get-date -format dd-MM-yyyy)
            Time = $(get-date -format hh.mm.ss)
        } | Export-CSV $file_path -Append
}

function main {
    $csv_file_path = get_validated_input -prompt "Enter the csv file path to import to AD user attributes" -condition "!`$user_input -or !(Test-Path -Path `$user_input -PathType Leaf -Include *.csv)" -after_prompt "csv validated"
    $OU = get_validated_input -prompt "Enter OU distinguished name to modify AD users attributes" -condition "!`$user_input -or !(Get-ADOrganizationalUnit -Filter `"DistinguishedName `-eq `'`$user_input`'`")"
    $search_user_attribute = get_validated_input -prompt "Enter the displayed option to use for searching AD users" -before_prompt "1. displayName`n2. userPrincipalName`n3. mail" -condition "`$user_input -notin @('displayName', 'userPrincipalName', 'mail')"
    $set_user_attribute = get_validated_input -prompt "Enter the displayed option to use for modifying AD users attributes" -before_prompt "1. telephonenumber`n2. mobile`n3. title`n4. department`n5. description" -condition "`$user_input -notin @('telephonenumber', 'mobile', 'title', 'department', 'description')"
    
    $csv_data = Import-Csv -Path $csv_file_path
    $csv_headers = $csv_data[0].PSObject.Properties.Name
    
    $csv_search_user_attribute = get_validated_input -prompt "Enter the csv header you want to use to match the attribute '$search_user_attribute' on AD" -before_prompt "$($csv_headers -join ', ')" -condition "`$user_input -notin `$csv_headers"
    $csv_set_user_attribute = get_validated_input -prompt "Enter the csv header you want to use to replace the attribute '$set_user_attribute' on AD" -before_prompt "$($csv_headers -join ', ')" -condition "`$user_input -notin `$csv_headers"
    
    write-host "Using csv header '$csv_search_user_attribute' to search with AD attribute '$search_user_attribute'." -ForegroundColor Cyan 
    write-host "Using csv header '$csv_set_user_attribute' to set AD attribute '$set_user_attribute'." -ForegroundColor Cyan
    
    $clear_attribute = closed_input -user_prompt "When a matching user is found in both the CSV file and AD, but the CSV attribute is empty, would you like to clear the corresponding user attribute in AD? (Y/N)"
    
    read-host -prompt "Press enter to continue"
    
    foreach ($row in $csv_data) {
        if (($user = Get-ADUser -Filter $("$search_user_attribute -eq '$($row.$csv_search_user_attribute)'") -Properties *) -and ($user.DistinguishedName -match $OU)) {
            if ($row.$csv_set_user_attribute) {
                Set-ADUser -Identity $user -Replace @{$set_user_attribute = "$($row.$csv_set_user_attribute)"}
                add_log -file_path "$PSScriptRoot\_logs\Import CSV data to AD user attributes log.csv" -UPN $user.userPrincipalName -attribute $set_user_attribute -original $user.$set_user_attribute -modified $row.$csv_set_user_attribute
                write-host "Set '$($user.userPrincipalName)' $set_user_attribute $($user.$set_user_attribute) -> $($row.$csv_set_user_attribute)" -ForegroundColor Cyan
            } elseif ($clear_attribute) {
                Set-ADUser -Identity $user -clear $set_user_attribute
                add_log -file_path "$PSScriptRoot\_logs\Import CSV data to AD user attributes log.csv" -UPN $user.userPrincipalName -attribute $set_user_attribute -original $user.$set_user_attribute -modified $row.$csv_set_user_attribute
                write-host "Cleared '$($user.userPrincipalName)' $set_user_attribute $($user.$set_user_attribute)" -ForegroundColor Cyan
            }
        } else {
            Write-host "Could not find the user '$($row.$csv_search_user_attribute)' in the AD OU." -ForegroundColor Yellow
        }
    }
}

while ($true) { main }
