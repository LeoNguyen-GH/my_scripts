. "$PSScriptRoot\common\functions.ps1"

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

function main {
    multi_user_input -prompt "Enter the groups and mailboxes email to parse (Newline for multiple, enter 'q' to continue):" | ForEach-Object {
        if (!($members = get_members -group $_)) {
            write-host "Could not find '$group'." -foregroundcolor Red
            return
        }

        export_csv -csv_file_path "$PSScriptRoot\_logs\exported\$_ - list of members $(Get-Date -Format 'dd-MM-yyyy h.mmtt').csv" -data $members
    }
}

EXO_connect
azureAD_connect

while ($true) {
    main
}
