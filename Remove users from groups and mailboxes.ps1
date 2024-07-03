. "$PSScriptRoot\common\functions.ps1"

function remove_group_members {
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)] [string]$user,
        [parameter(Mandatory)] [string]$group,
        [parameter(Mandatory)] [string]$group_type
    )
    
    process {
        switch ($group_type) {
            "distribution list" { Remove-DistributionGroupMember -Identity $group -Member $user -BypassSecurityGroupManagerCheck -Confirm:$false }
            "Microsoft 365 group" { Remove-UnifiedGroupLinks -Identity $group -LinkType Members -Links $user -ErrorAction Stop }
            "security group" { Remove-AzureADGroupMember -ObjectId $(Get-AzureADGroup -SearchString $group).ObjectId -MemberId $(Get-AzureADUser -ObjectId $user).ObjectId }
            { $_ -in @("user mailbox", "RoomMailbox", "shared mailbox") } {
                Remove-MailboxPermission -Identity $group -User $user -AccessRights FullAccess -InheritanceType All
                Remove-RecipientPermission -Identity $group -Trustee $user -AccessRights SendAs -Confirm:$false }
            "dynamic distribution list" {
                write-host "Can't remove members from a dynamic distribution list '$group'" -ForegroundColor -Red
                return }
            default {
                write-host "Group '$group' could not be found." -foregroundcolor Red
                return }
        }
        
        Write-Host "Removed '$user' -> $group_type '$group'" -ForegroundColor Green
    }
}

function main {
    $users = multi_user_input -prompt "Enter the users email to remove from the group/mailbox (Newline for multiple, enter 'q' 'to continue):"
    if (!($users = validate_email -emails $users)) {
        return
    }
    
    multi_user_input -prompt "Enter the group/mailbox email to remove users from (Newline for multiple, enter 'q' to continue):" | ForEach-Object {
        $group_type = group_type -email $_
        $users | remove_group_members -group $_ -group_type $group_type
    }
    
    print_dash_across_terminal
}

EXO_connect
azureAD_connect

while ($true) {
    main
}