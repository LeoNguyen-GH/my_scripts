function azureAD_connect {
    param(
        [bool]$silent = $false
    )
    
    while ($true) {
        try {
            if (get-azureADUser -Top 1) {
                if (!$silent) { write-host "Successfully connected to Entra ID" -ForegroundColor Green }
                break
            }
        } catch {
            try {
                if (!$silent) { Write-host "Connecting to Entra ID" -Foregroundcolor Cyan }
                Connect-AzureAD -ErrorAction SilentlyContinue
            } catch {
                if (!$silent) { Write-Host "Error occured while trying to connect to Entra ID, trying again." -ForegroundColor Red }
            }
        }
    }
}

function EXO_connect {
    param (
        [string]$UPN = "admin@company.com",
        [bool]$silent = $false
    )
    
    while ($true) {
        try {
            if (Get-AcceptedDomain) {
                if (!$silent) {Write-host "Successfully connected to EXO" -ForegroundColor Green}
                break
            }
        } catch {
            try {
                if (!$silent) {Write-host "Connecting to EXO" -Foregroundcolor Cyan}
                Connect-ExchangeOnline -UserPrincipalName $UPN *> $null
            } catch {
                if (!$silent) { Write-Host "Error occured and could not connect to ExchangeOnline, trying again." -ForegroundColor Red }
            }
        }
    }
}

function MSOL_connect {
    while ($true) {
        $ErrorActionPreference = "SilentlyContinue"
        if (Get-MsolUser -MaxResults 1) {
            write-host "Successfully connected to MsolService" -ForegroundColor Green
            $ErrorActionPreference = "Continue"
            break
        } else {
            Write-host "Connecting to MsolService" -Foregroundcolor Cyan
            connect-MsolService *>&1 | Out-Null
        }
    }
}

function print_dash_across_terminal {
    Write-Host ("-" * (Get-Host).UI.RawUI.WindowSize.Width)
}

function multi_user_input {
    param (
        [string]$prompt = "Enter data below (Newline for multiple, enter 'q' to continue):",
        [bool]$sort = $false
    )
    
    Write-Host $prompt -ForegroundColor Cyan
    
    $data = [System.Collections.Generic.List[string]]::new()
    
    do {
        while ($true) {
            $user_input = (Read-Host " ").Trim()
            
            if ($user_input -eq "q") {
                break
            } elseif ($user_input -and $user_input -notin $data) {
                $data.Add($user_input)
            }
        }
    } while (!$data)
    
    return $data = if ($sort) { $data | Sort-Object } else { $data }
}

function email_type {
    param (
        [parameter(mandatory)] [string]$email,
        [bool]$type_aduser = $false
    )
    
    if ($type_aduser) {
        return $result =  if (((Get-ADUser -Filter {UserPrincipalName -eq $email}))) { $true } else { $null }
    }

    if (![string]::IsNullOrEmpty((Get-AzureADUser -SearchString $email -All $true))) {
        return "cloud user"
    } elseif (![string]::IsNullOrEmpty((Get-DistributionGroup -Identity $email -ErrorAction SilentlyContinue))) {
        return "distribution list"
    } elseif (![string]::IsNullOrEmpty((Get-UnifiedGroup -Identity $email -ErrorAction SilentlyContinue))) {
        return "Microsoft 365 group"
    } else {
        try { $object = Get-AzureADContact -All $true -Filter "mail eq $email" } catch {} 
        if (![string]::IsNullOrEmpty($object)) {
            return "contact email"
        }
    }
    
    return $null
}

function prompt_for_valid_email {
    param (
        [parameter(mandatory)] [string]$email,
        [bool]$type_aduser = $false
    )
    
    while ([string]::IsNullOrEmpty((email_type -email $email -type_aduser $type_aduser)) -eq $true) {
        Write-Host "Email '$email' could not be found" -ForegroundColor Red
        
        do {
            $email = (Read-Host "Enter a valid email (Input 'skip' to skip)" ).trim()
        } while ([string]::IsNullOrEmpty($email))
        
        if ($email -eq "skip") {
            Write-host "Skipping email '$email''" -ForegroundColor Yellow
            return $null
        }
    }
    
    Write-Host "$email found" -ForegroundColor Cyan
    
    return $email
}

function validate_email {
    param (
        [parameter(mandatory)] [System.Collections.Generic.List[string]]$emails,
        [bool]$type_aduser = $false
    )
    
    Write-Host "Validating emails" -ForegroundColor Cyan
    
    for ($i = 0; $i -lt $emails.Count; $i++) {
        $emails[$i] = prompt_for_valid_email -email $emails[$i] -type_aduser $type_aduser
    }
    
   return $emails | Select-Object -Unique
}

function validate_entra_ID_user {
    [CmdletBinding()]
    param (
        [parameter(mandatory, ValueFromPipeline)] [string]$email
    )
    
    process {
        if (!($user_object = Get-AzureADUser -SearchString $email)) {
            write-host "User '$email' could not be found." -ForegroundColor Red
            return $null
        } elseif ($user_object.count -gt 1) {
            write-host "User '$email' is not unique. Multiple users has been found:" -ForegroundColor Red
            $user_object | Select-Object DisplayName, mail
            return $null
        } else {
            write-host "User '$email' found" -ForegroundColor Green
            return $user_object
        }
    }
}

function group_type {
    param (
        [parameter(mandatory)] [string]$email
    ) 
    
    if (![string]::IsNullOrEmpty((Get-DistributionGroup -Identity $email -ErrorAction SilentlyContinue))) {
        return "distribution list"
    } elseif (![string]::IsNullOrEmpty((Get-Recipient -Identity $email -RecipientTypeDetails DynamicDistributionGroup -ErrorAction SilentlyContinue))) {
        return "dynamic distribution list"
    } elseif (![string]::IsNullOrEmpty((Get-UnifiedGroup -Identity $email -ErrorAction SilentlyContinue))) {
        return "Microsoft 365 group"
    } elseif (![string]::IsNullOrEmpty((Get-AzureADGroup -SearchString $email -ErrorAction SilentlyContinue))) {
        return "security group"
    } elseif (![string]::IsNullOrEmpty(($group = Get-Mailbox -Identity $email -ErrorAction SilentlyContinue))) {
        if ($group.RecipientTypeDetails -eq "SharedMailbox") {
            return "shared mailbox"
        }
        elseif ($group.RecipientTypeDetails -eq "RoomMailbox") {
            return "RoomMailbox"
        }
        elseif ($group.RecipientTypeDetails -eq "UserMailbox") {
            return "user mailbox"
        }
    } else {
        return $null
    }
}

function closed_input {
    param (
        [string]$user_prompt = "Enter 'Y' or 'N'",
        [string]$y_msg = $null,
        [string]$n_msg = $null
    )
    
    while ($true) {
        $user_input = (read-host "$user_prompt").Trim()
        if ($user_input -eq "Y") {
            if ($y_msg) { write-host $y_msg -ForegroundColor Cyan }
            return $true
        } elseif ($user_input -eq "N") {
            if ($n_msg) { write-host $n_msg -ForegroundColor Cyan }
            return $false
        } else {
            write-host "Invalid input" -ForegroundColor Red
        }
    }
}

function export_csv {
    param (
        [parameter(mandatory)] $data,
        [parameter(mandatory)] [string]$csv_file_path
    )
    
    [void](New-Item -Path (Split-Path -Path $csv_file_path -Parent) -ItemType "directory" -erroraction silentlycontinue)
    $data | Export-Csv -Path $csv_file_path -NoTypeInformation
    write-host "Exported CSV -> $csv_file_path" -ForegroundColor Green
}
