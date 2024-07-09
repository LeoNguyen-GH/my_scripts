. "$PSScriptRoot\common\functions.ps1"

$cache_path = "$PSScriptRoot\_logs\cache\all mailboxes.csv"

function export_all_mailboxes {
    $mailboxes = Get-Mailbox -ResultSize Unlimited | Select-Object UserPrincipalName, DisplayName, RecipientTypeDetails, ForwardingAddress, @{Name='ForwardingSmtpAddress'; Expression={$_.ForwardingSmtpAddress}}

    $mailboxes_data = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    foreach ($mailbox in $mailboxes) {
        $mailboxes_data.Add([PSCustomObject]@{
            UserPrincipalName = $mailbox.UserPrincipalName
            DisplayName = $mailbox.DisplayName
            RecipientTypeDetails = $mailbox.RecipientTypeDetails
            ForwardingAddress = $mailbox.ForwardingAddress
            ForwardingSmtpAddress = ($mailbox.ForwardingSmtpAddress -split ":")[1]
        })
    }

    return $mailboxes_data
}

function search_csv {
    param(
        [parameter(Mandatory)] [string]$user,
        [parameter(Mandatory)] [PSCustomObject]$csv_data
    )

    $forwarded_emails = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($row in $csv_data) {
        if ($row.ForwardingSmtpAddress -eq $user) {
            $forwarded_emails.Add([PSCustomObject]@{
                UserPrincipalName = $row.UserPrincipalName
                DisplayName = $row.DisplayName
                RecipientTypeDetails = $row.RecipientTypeDetails
                ForwardingAddress = $row.ForwardingAddress
                ForwardingSmtpAddress = $row.ForwardingSmtpAddress
            })
        }
    }

    return $forwarded_emails
}

function main {
    $users = get_multi_user_input -prompt "Enter the user's email to find which mailboxes are being forwarded to it. (Newline for multiple, enter 'q' to continue):"
    
    if (closed_input -user_prompt "Do you want to refresh the cache 'all mailboxes' csv file with all the mailboxes and respective fowarded emails? (Y/N)" -y_msg "Refreshing cache.") {
        $mailboxes_data = export_all_mailboxes
        export_csv -csv_file_path $cache_path -data $mailboxes_data
    }
    
    $csv_data = Import-Csv -Path $cache_path
    
    foreach ($user in $users) {
        $data = search_csv -user $user -csv_data $csv_data
        export_csv -csv_file_path "$PSScriptRoot\_logs\exported\$user - Forwarded emails $(Get-Date -Format 'dd-MM-yyyy h.mmtt').csv" -data $data
    }
}

EXO_connect

while ($true) { main }
