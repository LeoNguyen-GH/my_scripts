. "$PSScriptRoot\common\functions.ps1"
get_functions -file_path "$PSScriptRoot\Get group or mailbox members.ps1" | Invoke-Expression

function export_all_groups {
    # Removes the all groups folder then gets all the groups in the tenent and exports it to a csv file
    param ([parameter(Mandatory)] [string]$dir_path)

    Remove-Item -Path $dir_path -Force -Recurse -ErrorAction SilentlyContinue

    $groups = Get-AzureADGroup -All:$true | select-object DisplayName, Mail, ObjectId, @{Name='ProxyAddresses'; Expression={($_.ProxyAddresses -join ';')}}, MailEnabled, SecurityEnabled
    
    $total_groups = $groups.Count
    for ($i=0; $i -lt $total_groups; $i++) {
        $percent_complete = ($i / $total_groups) * 100
        Write-Progress -Activity "Exporting in progress" -Status "$percent_complete% Complete" -PercentComplete $percent_complete

        $group_ref = if ($groups[$i].Mail) { $groups[$i].Mail } else { $groups[$i].DisplayName }
        $members = if ($members = get_group_members -group $group_ref) { $members } else { [PSCustomObject]@{ name = ""; email = "" } }
        
        export_csv -data $members -csv_file_path "$dir_path\$group_ref.csv"
    }
}

function find_members_of {
    param (
        [array]$members,
        [parameter(Mandatory)] [string]$dir_path
    )
    
    $members_of = @{}
    
    $csv_files = get-childitem -Path $dir_path -Filter *.csv
    foreach ($file in $csv_files) {
        $filename_without_extension = $file.BaseName
        
        # Add to the hashtable with the matched members in the csv file being the key and the key value being the csv group filename, the key value is a array to sort multiple groups the member key is a member of e.g. {"user@email.com" = @("group1", "group2")}
        $csv_data = Import-Csv -Path $file.FullName
            
        foreach ($row in $csv_data) {
            if ($row.email -in $members) {
                $members_of[$row.email] += @($filename_without_extension)
            }
        }
    }
    
    return $members_of
}

function generate_csv_member_of {
    param ([hashtable]$members_of)
    
    $csv_dir_path =  "$PSScriptRoot\_logs\exported\members of $(Get-Date -Format 'dd-MM-yyyy h.mmtt')"
    [void](New-Item -Path $csv_dir_path -ItemType "directory")
    
    foreach ($key in $members_of.Keys) {
        # Create an array of custom objects with a property
        $values = $members_of[$key] | ForEach-Object { [PSCustomObject]@{ groups = $_  } }
        
        # Export the array of objects to a CSV file named after the key
        $values | Export-Csv -Path "$csv_dir_path\$key.csv" -NoTypeInformation
    }
}

function main {
    $emails = get_multi_user_input -prompt "Enter the groups/users email to find which group they are a member of (Newline for multiple, enter 'q' to continue):"

    if (closed_input -user_prompt "Do you want to refresh the cache 'all groups' folder with all email groups and its respective members? (Y/N)" -y_msg "Refreshing cache.") {
        export_all_groups -dir_path "$PSScriptRoot\_logs\cache\all groups"
    }
    
    # Generate the CSV files with the emails the inputs are a member of
    if ($members_of = find_members_of -members $emails -dir_path "$PSScriptRoot\_logs\cache\all groups") {
        generate_csv_member_of -members_of $members_of
        $members_of
    }
}

EXO_connect
azureAD_connect

while ($true) { main }
