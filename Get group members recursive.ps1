. "$PSScriptRoot\common\functions.ps1"

function get_members {
    param (
        [parameter(mandatory)] [string]$group_email,
        [parameter(mandatory)] [string]$output_file_parent_path,
        [parameter(mandatory)] [string]$group_type
    )

    $members = switch ($group_type) {
        "distribution list" {Get-DistributionGroupMember -Identity $group_email -ResultSize unlimited | Select-Object @{Name='Name'; Expression={$_.DisplayName}}, @{Name='Email'; Expression={$_.PrimarySmtpAddress}}}
        "Microsoft 365 group" {Get-UnifiedGroupLinks -Identity $group_email -LinkType Members -ResultSize Unlimited -ErrorAction SilentlyContinue | Select-Object @{Name='Name'; Expression={$_.DisplayName}}, @{Name='Email'; Expression={$_.PrimarySmtpAddress}}}
        "security group" {Get-AzureADGroupMember -ObjectId (Get-AzureADGroup -SearchString $group_email).ObjectId -All:$true -ErrorAction SilentlyContinue | Select-Object @{Name='Name'; Expression={$_.DisplayName}}, @{Name='Email'; Expression={$_.UserPrincipalName}}}
        "dynamic distribution list" {Get-Recipient -RecipientPreviewFilter (Get-DynamicDistributionGroup -Identity $group_email -ErrorAction SilentlyContinue).RecipientFilter | Select-Object @{Name='Name'; Expression={$_.DisplayName}}, @{Name='Email'; Expression={$_.PrimarySmtpAddress}}}
    }
    
    $members | Export-Csv -Path "$output_file_parent_path\$group_email.csv" -NoTypeInformation

    get_members_type -members $members -parent_dir_path $output_file_parent_path
}

function get_members_type {
    param (
        [parameter(mandatory)] [array]$members,
        [parameter(mandatory)] [string]$parent_dir_path
    )

    # Check if each member is a type group
    foreach ($member in $members) {
        if (($group_type = group_type -email $member.email) -in @("security group", "Microsoft 365 group", "dynamic distribution list", "distribution list")) {
            $exported_folder_path = New-Item -Path "$parent_dir_path\$($member.email)" -ItemType "directory"
            get_members -group_email $member.email -output_file_parent_path $exported_folder_path.FullName -group_type $group_type
        }
    }
}

function main {
    multi_user_input -prompt "Enter the groups and mailboxes email to parse recursively (Newline for multiple, enter 'q' to continue):" | ForEach-Object {
        if (($group_type = group_type -email $_) -notin @("security group", "Microsoft 365 group", "dynamic distribution list", "distribution list")) {
            Write-Host "Group '$_' does not exist." -ForegroundColor Red
            return
        }
        
        $exported_folder_path = New-Item -Path "$PSScriptRoot\_logs\exported\$_" -ItemType "directory"
        
        get_members -group_email $_ -output_file_parent_path $exported_folder_path.FullName -group_type $group_type
    }
}

EXO_connect
azureAD_connect

while ($true) {
    main
}
