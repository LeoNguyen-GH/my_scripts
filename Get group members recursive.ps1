. "$PSScriptRoot\common\functions.ps1"
get_functions -file_path "$PSScriptRoot\Get group or mailbox members.ps1" | Invoke-Expression

function get_group_members_recursive {
    # Get the members from the group and export it then pass it to the function that finds the member's group type
    param (
        [parameter(mandatory)] [string]$group_email,
        [parameter(mandatory)] [string]$output_file_parent_path
    )

    $members = get_group_members -group $group_email
    
    $members | Export-Csv -Path "$output_file_parent_path\$group_email.csv" -NoTypeInformation

    get_group_type_recursive -members $members -parent_dir_path $output_file_parent_path
}

function get_group_type_recursive {
    # Send each member that is a group type to the function that gets its members and exports it
    param (
        [parameter(mandatory)] [PSCustomObject[]]$members,
        [parameter(mandatory)] [string]$parent_dir_path
    )

    foreach ($member in $members) {
        if ((get_group_type -email $member.email) -in @("security group", "Microsoft 365 group", "dynamic distribution list", "distribution list")) {
            write-host "Searching for members with type group in group '$($member.email)'"
            
            $exported_folder_path = New-Item -Path "$parent_dir_path\$($member.email)" -ItemType "directory"
            
            get_group_members_recursive -group_email $member.email -output_file_parent_path $exported_folder_path.FullName
        }
    }
}

function main {
    $groups = get_multi_user_input -prompt "Enter the groups and mailboxes email to parse recursively (Newline for multiple, enter 'q' to continue):"

    foreach ($group in $groups) {
        if ((get_group_type -email $group) -in @("security group", "Microsoft 365 group", "dynamic distribution list", "distribution list")) {     
            $exported_folder_path = New-Item -Path "$PSScriptRoot\_logs\exported\$group" -ItemType "directory"
            
            get_group_members_recursive -group_email $group -output_file_parent_path $exported_folder_path.FullName
        } else {
            write-warning "Group '$group' could not be found."
        }
    }
}

EXO_connect
azureAD_connect

while ($true) { main }
