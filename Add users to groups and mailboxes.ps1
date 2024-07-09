. "$PSScriptRoot\common\functions.ps1"

function add_group_member {
    param (
        [parameter(Mandatory, ValueFromPipeline)] [string]$user,
        [parameter(Mandatory)] [string]$group,
        [bool]$display_total = $false
    )
    
    begin {
        $users_added = 0
        $group_type = get_group_type -email $group

        if (!$group_type) { throw "Couldn't find group '$group'." }
        elseif ($group_type -eq "dynamic distribution list") { throw "Cannot assign members to a dynamic distribution list: '$group'" }
        if ($group_type -in @("security group", "Microsoft 365 group")) { $group_ID = $(Get-AzureADGroup -SearchString $group).ObjectId }
    }
    
    process {
        try {
            switch ($group_type) {
                "distribution list" { Add-DistributionGroupMember -Identity $group -Member $user -BypassSecurityGroupManagerCheck -Confirm:$false -ErrorAction stop }
                { $_ -in @("security group", "Microsoft 365 group") } { Add-AzureADGroupMember -ObjectId $group_ID -RefObjectId $(Get-AzureADUser -ObjectId $user).ObjectId }
                { $_ -in @("user mailbox", "RoomMailbox", "shared mailbox") } {
                    Add-MailboxPermission -Identity $group -User $user -AccessRights FullAccess -InheritanceType All -AutoMapping $true
                    Add-RecipientPermission -Identity $group -Trustee $user -AccessRights SendAs -Confirm:$false }
            }
        
            $users_added++
            Write-Host "Added '$user' -> $group_type '$group'" -ForegroundColor Green
        } catch { write-warning $_ }
    }

    end { if ($display_total) {Write-Host "Total users added - $group`: $users_added"} }
}

function main {
    $users = get_multi_user_input -prompt "Enter the users email to add to the group/mailbox (Newline for multiple, enter 'q' 'to continue):"
    if (!($users = get_valid_email -emails $users)) { return }
    
    $groups = get_multi_user_input -prompt "Enter the group/mailbox email to add users to (Newline for multiple, enter 'q' to continue):"

    foreach ($group in $groups) {
        try { $users | add_group_member -group $group -display_total $true } catch { write-warning $_ }
    }
}

EXO_connect
azureAD_connect

while ($true) { main }
