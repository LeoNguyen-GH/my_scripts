. "$PSScriptRoot\common\functions.ps1"

$dir_path = "$PSScriptRoot\_logs\exported\all groups"

function get_members {
    param ([parameter(Mandatory)] [string]$group)
    
    return $members = switch ($group_type = group_type -email $group) {
        "distribution list" { Get-DistributionGroupMember -Identity $group -ResultSize unlimited | Select-Object @{Name='Name'; Expression={$_.DisplayName}}, @{Name='Email'; Expression={$_.PrimarySmtpAddress}} }
        "Microsoft 365 group" { Get-UnifiedGroupLinks -Identity $group -LinkType Members -ResultSize Unlimited -ErrorAction SilentlyContinue | Select-Object @{Name='Name'; Expression={$_.DisplayName}}, @{Name='Email'; Expression={$_.PrimarySmtpAddress}} }
        "security group" { Get-AzureADGroupMember -ObjectId (Get-AzureADGroup -SearchString $group).ObjectId -All:$true | Select-Object @{Name='Name'; Expression={$_.DisplayName}}, @{Name='Email'; Expression={$_.UserPrincipalName}} }
        "dynamic distribution list" { Get-Recipient -RecipientPreviewFilter (Get-DynamicDistributionGroup -Identity $group -ErrorAction SilentlyContinue).RecipientFilter | Select-Object @{Name='Name'; Expression={$_.DisplayName}}, @{Name='Email'; Expression={$_.PrimarySmtpAddress}} }
        { $group_type -in @("RoomMailbox", "shared mailbox", "user mailbox") } { Get-MailboxPermission -Identity (Get-Mailbox -Identity $group) | Where-object { $_.User -notlike "*SELF*" } | Select-Object @{Name='Name'; Expression={$_.User}},AccessRights }
        default { return $null }
    }
}

function populate_groups {
    Remove-Item -Path $dir_path -Force -Recurse -ErrorAction SilentlyContinue

    # Loop through each group
    Get-AzureADGroup -All:$true | select-object DisplayName, Mail, ObjectId, @{Name='ProxyAddresses'; Expression={($_.ProxyAddresses -join ';')}}, MailEnabled, SecurityEnabled | ForEach-Object {
        if (!($group = $_.Mail)) {
            $group = $_.DisplayName
        }
        
        # Get members of each group
        if(!($members = get_members -group $group)) {
            $members = [PSCustomObject]@{
                name = "" 
                email = ""
            }
        }

        # Export members of each group to a CSV file
        export_csv -data $members -csv_file_path "$dir_path\$group.csv"
    }
}

function find_members_of {
    param (
        [array]$members
    )
    
    $members_of = @{}
    
    get-childitem -Path $dir_path -Filter *.csv | ForEach-Object {
        $filename_without_extension = $_.BaseName
        
        # Add to the hashtable with the matched members in the csv file being the key and the key value being the csv group filename, the key value is a array to sort multiple groups the member key is a member of e.g. {"user@email.com" = @("group1", "group2")}
        $csv_data = Import-Csv -Path $_.FullName

        foreach ($row in $csv_data) {
            if ($row.email -in $members) {
                $members_of[$row.email] += @($filename_without_extension)
            }
        }
    }
    
    return $members_of
}

function generate_csv_member_of {
    param (
        [hashtable]$members_of
    )
    
    $csv_dir_path =  "$PSScriptRoot\_logs\exported\members of $(Get-Date -Format 'dd-MM-yyyy h.mmtt')"
    [void](New-Item -Path $csv_dir_path -ItemType "directory")
    
    foreach ($key in $members_of.Keys) {
        # Create an array of custom objects with a property
        $values = $members_of[$key] | ForEach-Object {
            [PSCustomObject]@{
                groups = $_ 
            }
        }
        
        # Export the array of objects to a CSV file named after the key
        $values | Export-Csv -Path "$csv_dir_path\$key.csv" -NoTypeInformation
    }
}

function main {
    $emails = multi_user_input -prompt "Enter the groups/users email to find which group they are a member of (Newline for multiple, enter 'q' to continue):"

    if (closed_input -user_prompt "Do you want to repopulate the 'all groups' folder with all email groups and its respective members? (Y/N)" -y_msg "Repopulating 'all groups' folder.") {
        populate_groups
    }
    
    # Generate the CSV files with the emails the inputs are a member of
    if ($members_of = find_members_of -members $emails) {
        generate_csv_member_of -members_of $members_of
        $members_of
    }
}

EXO_connect
azureAD_connect

while ($true) {
    main
}
