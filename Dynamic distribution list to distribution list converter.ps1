. "$PSScriptRoot\common\functions.ps1"
get_functions -file_path "$PSScriptRoot\Get group or mailbox members.ps1" | Invoke-Expression
get_functions -file_path "$PSScriptRoot\Get groups an email is member of.ps1" | Invoke-Expression

function search_member_of_csv {
    param ([parameter(Mandatory)] [string]$dir_path)
    
    $csv_files = Get-ChildItem -Path $dir_path -Filter *.csv
    $csv_data = @{}
    
    foreach ($file in $csv_files) {
        $members_of = (Import-Csv -Path $file.FullName).groups
        $csv_data[$file.BaseName] = if ($members_of) { $members_of } else { $null }
    }
    
    return $csv_data
}

function add_distribution_group_members {
    param (
        [parameter(ValueFromPipeline)] [string]$member,
        [parameter(Mandatory)] [string]$group,
        [bool]$switch = $false
    )

    process {
        if (!$member) { throw "No members found to add." }
            
        $source = if ($switch) { $group } else { $member }
        $destination = if ($switch) {  $member } else { $group }
        
        write-host "Adding email '$source' -> '$destination'" -ForegroundColor Green
        Add-DistributionGroupMember -Identity $destination -Member $source -BypassSecurityGroupManagerCheck -Confirm:$false
    }
}

function convert_dynamic_group {
    param (
        [parameter(Mandatory)] [hashtable]$dynamic_groups,
        [parameter(Mandatory)] [string]$group_owner
    )
    
    foreach ($dynamic_group in $dynamic_groups.GetEnumerator()) {
        if (!($group = Get-DynamicDistributionGroup -Identity $dynamic_group.key -ErrorAction SilentlyContinue)) { continue }

        if ($members = get_group_members -group $dynamic_group.key) {
            # Backup dynamic group members to a csv file
            export_csv -csv_file_path "$PSScriptRoot\_logs\exported\Backup dynamic group data - $($group.PrimarySmtpAddress) $($group.DisplayName) $(Get-Date -Format 'dd-MM-yyyy h.mmtt').csv" -data $members
        }

        Remove-DynamicDistributionGroup -Identity $group.PrimarySmtpAddress -Confirm:$false
        
        do {
            [void](New-DistributionGroup -Name $group.DisplayName -Type "Distribution" -PrimarySmtpAddress $group.PrimarySmtpAddress -ManagedBy $group_owner -Confirm:$false)
        } while (!(Get-DistributionGroup -Identity $group.PrimarySmtpAddress -ErrorAction silentlycontinue))
        
        # Add members to new distribution group
        try { $members.email | add_distribution_group_members -group $group.PrimarySmtpAddress } catch { Write-Warning $_ }
        # Add new distribution group to prior groups it was a member of
        try { $dynamic_group.value | add_distribution_group_members -group $group.PrimarySmtpAddress -switch $true } catch { Write-Warning $_ }
    }
}

function main {
    $emails = get_multi_user_input -prompt "Enter the dynamic distribution lists to convert to distribution lists (Newline for multiple, enter 'q' to continue):"
    
    $default_dir = "$PSScriptRoot\_logs\cache\all groups"
    
    if (closed_input -user_prompt "Do you want to refresh the cache 'all groups' folder with all email groups and its respective members? (Y/N)" -y_msg "Refreshing cache.") {
        export_all_groups -dir_path $default_dir
    }
    
    # Generate the CSV files with the emails the inputs are a member of
    if ($members_of = find_members_of -members $emails -dir_path $default_dir) {
        $csv_dir_path = generate_csv_member_of -members_of $members_of -csv_dir_path "$PSScriptRoot\_logs\exported\members of $(Get-Date -Format 'dd-MM-yyyy h.mmtt')" -return_csv_dir_path $true
        
        $dynamic_groups = search_member_of_csv -dir_path $csv_dir_path
        
        convert_dynamic_group -dynamic_groups $dynamic_groups -group_owner "owner@company.com"
    }
}

EXO_connect
azureAD_connect

while ($true) { main }
