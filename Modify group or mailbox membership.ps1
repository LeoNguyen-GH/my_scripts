. "$PSScriptRoot\common\functions.ps1"

function modify_group_membership {
    param (
        [parameter(Mandatory)][ValidateSet("Add", "Remove")] [string]$action,
        [parameter(Mandatory, ValueFromPipeline)] [string]$user,
        [parameter(Mandatory)] [string]$group,
        [bool]$display_total = $false
    )
    
    begin {
        $group_updates = 0
        $group_type = get_group_type -email $group
        
        if (!$group_type) { throw "Couldn't find group '$group'." }
        elseif ($group_type -eq "dynamic distribution list") { throw "Cannot manually modify members in a dynamic distribution list: '$group'" }
        if ($group_type -in @("security group", "Microsoft 365 group")) { $group_ID = $(Get-AzureADGroup -SearchString $group).ObjectId }
        
        $i = if ($action -eq "add") { 0 } else { 1 }
        
        $commands = @{
            distribution = @("Add-DistributionGroupMember" ,"Remove-DistributionGroupMember")
            azure = @("Add-AzureADGroupMember" ,"Remove-AzureADGroupMember")
            azure_id = @("-RefObjectId" ,"-MemberId")
            mailbox_access = @("Add-MailboxPermission" ,"Remove-MailboxPermission")
            mailbox_send_as = @("Add-RecipientPermission" ,"Remove-RecipientPermission")
        }
    }
    
    process {
        try {
            switch ($group_type) {
                "distribution list" { & $commands["distribution"][$i] -Identity $group -Member $user -BypassSecurityGroupManagerCheck -Confirm:$false -ErrorAction stop }
                { $_ -in @("security group", "Microsoft 365 group") } { $command = "$($commands['azure'][$i]) -ObjectId $group_ID $($commands['azure_id'][$i]) `$(Get-AzureADUser -ObjectId $user).ObjectId"; invoke-expression $command }
                { $_ -match "Mailbox" } {
                    [void](& $commands["mailbox_access"][$i] -Identity $group -User $user -AccessRights FullAccess -InheritanceType All -Confirm:$false)
                    [void](& $commands["mailbox_send_as"][$i] -Identity $group -Trustee $user -AccessRights SendAs -Confirm:$false) }
            }
        
            $group_updates++
            Write-Host "$action`: '$user' -> $group_type '$group'" -ForegroundColor Green
        } catch { write-warning $_ }
    }

    end { if ($display_total) {Write-Host "Total users $action - $group`: $group_updates"} }
}

function main {
    $group_membership_action = get_validated_input -condition "`$user_input -notin @('add', 'remove')" -prompt "Enter in the type of user modification to the group's membership (Add/Remove)"
    
    $users = get_multi_user_input -prompt "Enter the user emails to $group_membership_action from/to the group or mailbox (Newline for multiple, enter 'q' 'to continue):"
    if (!($users = get_valid_email -emails $users)) { return }
    
    $groups = get_multi_user_input -prompt "Enter the group or mailbox email to $group_membership_action users from/to (Newline for multiple, enter 'q' to continue):"

    foreach ($group in $groups) {
        try { $users | modify_group_membership -group $group -action $group_membership_action -display_total $true } catch { write-error $_.Exception.Message }
    }
}

EXO_connect
azureAD_connect

while ($true) { main }
