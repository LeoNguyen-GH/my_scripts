function get_functions {
    # usage: get_functions -file_path "$PSScriptRoot\script.ps1" | Invoke-Expression
    param ([parameter(Mandatory)] $file_path)

    $script = Get-Command $file_path
    return $script.ScriptBlock.AST.FindAll({ $args[0] -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)
}

function connect_services {
    param(
        [bool]$silent = $false,
        [parameter(Mandatory)] [string]$service_name,
        [parameter(Mandatory)] [string]$test_expression,
        [parameter(Mandatory)] [string]$connect_expression
    )
    
    while ($true) {
        try {
            Invoke-Expression $test_expression
            if (!$silent) { write-host "Successfully connected to $service_name" -ForegroundColor Green }
            return
        } catch {
            if (!$silent) { Write-host "Connecting to $service_name" -Foregroundcolor Cyan }
            Invoke-Expression $connect_expression
        }
    }
}

function azureAD_connect {
    connect_services -service_name "Entra ID" -test_expression "[void](get-azureADUser -Top 1)" -connect_expression "Connect-AzureAD -ErrorAction SilentlyContinue"
}

function EXO_connect {
    param ([string]$UPN = "admin@company.com")
    connect_services -service_name "ExchangeOnline" -test_expression "[void](Get-AcceptedDomain)" -connect_expression "Connect-ExchangeOnline -UserPrincipalName $UPN *> `$null"
}

function MSOL_connect {
    connect_services -service_name "MsolService" -test_expression "[void](Get-MsolUser -MaxResults 1)" -connect_expression "connect-MsolService *>&1 | Out-Null"
}

function print_dash_across_terminal {
    Write-Host ("-" * (Get-Host).UI.RawUI.WindowSize.Width)
}

function get_multi_user_input {
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

function get_email_type {
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

function get_valid_email_input {
    param (
        [parameter(mandatory)] [string]$email,
        [bool]$type_aduser = $false
    )
    
    while (!(get_email_type -email $email -type_aduser $type_aduser)) {
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

function get_valid_email {
    param (
        [parameter(mandatory)] [System.Collections.Generic.List[string]]$emails,
        [bool]$type_aduser = $false
    )
    
    Write-Host "Validating emails" -ForegroundColor Cyan
    
    for ($i = 0; $i -lt $emails.Count; $i++) {
        $emails[$i] = get_valid_email_input -email $emails[$i] -type_aduser $type_aduser
    }
    
   return $emails | Select-Object -Unique
}

function get_valid_entra_ID_user {
    param ([parameter(mandatory=$false)] [string]$email)
    
    if (!($user = Get-AzureADUser -SearchString $email)) {
        write-host "User '$email' could not be found." -ForegroundColor Red
        return $null
    } elseif ($user.count -gt 1) {
        write-host "User '$email' is not unique, multiple users has been found." -ForegroundColor Red
        return $null
    } else {
        write-host "User '$email' found" -ForegroundColor Green
        return $user
    }
}

function get_validated_input {
    param (
        [parameter(mandatory)] [string]$condition,
        [parameter(mandatory)] [string]$prompt,
        [string]$before_prompt = $null,
        [string]$after_prompt = $null
    )
    
    if ($before_prompt) {write-host $before_prompt}
    
    do {
        $user_input = (read-host $prompt).trim().trim('"')
    } while ((Invoke-Expression $condition))
    
    if ($after_prompt) {write-host $after_prompt -ForegroundColor Green}
    
    return $user_input
}

function get_group_type {
    param ([parameter(mandatory)] [string]$email) 
    
    if (Get-DistributionGroup -Identity $email -ErrorAction SilentlyContinue) {
        return "distribution list"
    } elseif (Get-Recipient -Identity $email -RecipientTypeDetails DynamicDistributionGroup -ErrorAction SilentlyContinue) {
        return "dynamic distribution list"
    } elseif (Get-UnifiedGroup -Identity $email -ErrorAction SilentlyContinue) {
        return "Microsoft 365 group"
    } elseif (Get-AzureADGroup -SearchString $email -ErrorAction SilentlyContinue) {
        return "security group"
    } elseif ($group = Get-Mailbox -Identity $email -ErrorAction SilentlyContinue) {
        if ($group.RecipientTypeDetails -eq "SharedMailbox") {
            return "shared mailbox"
        } elseif ($group.RecipientTypeDetails -eq "RoomMailbox") {
            return "RoomMailbox"
        } elseif ($group.RecipientTypeDetails -eq "UserMailbox") {
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
        [parameter(mandatory)] [string]$csv_file_path,
        [bool]$silent = $false
    )
    
    [void](New-Item -Path (Split-Path -Path $csv_file_path -Parent) -ItemType "directory" -erroraction silentlycontinue)
    $data | Export-Csv -Path $csv_file_path -NoTypeInformation
    if (!$silent) {write-host "Exported CSV -> $csv_file_path" -ForegroundColor Green}
}
