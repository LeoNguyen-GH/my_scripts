. "$PSScriptRoot\common\functions.ps1"

function add_group_members {
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)] [string]$user,
        [parameter(Mandatory)] [string]$group,
        [parameter(Mandatory)] [string]$group_type
    )
    
    process {
        switch ($group_type) {
            "distribution list" { Add-DistributionGroupMember -Identity $group -Member $user -BypassSecurityGroupManagerCheck -Confirm:$false }
            "Microsoft 365 group" { Add-UnifiedGroupLinks -Identity $group -LinkType Members -Links $user -ErrorAction Stop }
            "security group" { Add-AzureADGroupMember -ObjectId $(Get-AzureADGroup -SearchString $group).ObjectId -RefObjectId $(Get-AzureADUser -ObjectId $user).ObjectId }
            { $_ -in @("user mailbox", "RoomMailbox", "shared mailbox") } {
                Add-MailboxPermission -Identity $group -User $user -AccessRights FullAccess -InheritanceType All -AutoMapping $true
                Add-RecipientPermission -Identity $group -Trustee $user -AccessRights SendAs -Confirm:$false }
            "dynamic distribution list" {
                write-host "Can't assign members to a dynamic distribution list '$group'" -ForegroundColor -Red
                return }
            default {
                write-host "Group '$group' could not be found." -foregroundcolor Red
                return }
        }
        
        Write-Host "Added '$user' -> $group_type '$group'" -ForegroundColor Green
    }
}

function main {
    $users = multi_user_input -prompt "Enter the users email to add to the group/mailbox (Newline for multiple, enter 'q' 'to continue):"
    if (!($users = validate_email -emails $users)) {
        return
    }
    
    multi_user_input -prompt "Enter the group/mailbox email to add users to (Newline for multiple, enter 'q' to continue):" | ForEach-Object {
        $group_type = group_type -email $_
        $users | add_group_members -group $_ -group_type $group_type
    }
    
    print_dash_across_terminal
}

EXO_connect
azureAD_connect

while ($true) {
    main
}