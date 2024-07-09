. "$PSScriptRoot\common\functions.ps1"

function get_group_members {
    param ([parameter(Mandatory)] [string]$group)

    try {
        return $members = switch (get_group_type -email $group) {
            "distribution list" {Get-DistributionGroupMember -Identity $group -ResultSize unlimited | Select-Object @{Name='Name'; Expression={$_.DisplayName}}, @{Name='Email'; Expression={$_.PrimarySmtpAddress}}}
            "Microsoft 365 group" {Get-UnifiedGroupLinks -Identity $group -LinkType Members -ResultSize Unlimited -ErrorAction SilentlyContinue | Select-Object @{Name='Name'; Expression={$_.DisplayName}}, @{Name='Email'; Expression={$_.PrimarySmtpAddress}}}
            "security group" {Get-AzureADGroupMember -ObjectId (Get-AzureADGroup -SearchString $group).ObjectId -All:$true -ErrorAction SilentlyContinue | Select-Object @{Name='Name'; Expression={$_.DisplayName}}, @{Name='Email'; Expression={$_.UserPrincipalName}}}
            "dynamic distribution list" { Get-Recipient -RecipientPreviewFilter (Get-DynamicDistributionGroup -Identity $group -ErrorAction SilentlyContinue).RecipientFilter | Select-Object @{Name='Name'; Expression={$_.DisplayName}}, @{Name='Email'; Expression={$_.PrimarySmtpAddress}} }
            { $_ -in @("RoomMailbox", "shared mailbox", "user mailbox") } { Get-MailboxPermission -Identity (Get-Mailbox -Identity $group) | Where-object { $_.User -notlike "*SELF*" } | Select-Object @{Name='Name'; Expression={$_.User}},AccessRights }
            default { throw "Could not find the group '$group'." }
        }
    } catch { write-warning $_ }
}

function main {
    $groups = get_multi_user_input -prompt "Enter the groups and mailboxes email to parse (Newline for multiple, enter 'q' to continue):"
    
    foreach ($group in $groups) {
        if ($members = get_group_members -group $group) {
            export_csv -csv_file_path "$PSScriptRoot\_logs\exported\$group - list of members $(Get-Date -Format 'dd-MM-yyyy h.mmtt').csv" -data $members
        } else {
            write-output "No members found for '$group'."
        }
    }
}

EXO_connect
azureAD_connect

while ($true) { main }
