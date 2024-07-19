. "$PSScriptRoot\common\functions.ps1"

function required_modules {
    $required_module = Get-Module -ListAvailable -Name Selenium
    if (!($required_module.version -eq "3.0.1")) {
        Install-Module -Name Selenium -RequiredVersion 3.0.1
    }
    
    Import-Module Selenium
}

function form_to_hashtable {
    param (
        [parameter(mandatory)] [System.Object[]]$form
    )
    
    $data = @{}
    
    foreach ($line in $form) {
        $splitted_line = $line -split ":"
        $data[$splitted_line[0]] = $splitted_line[1].trim()
    }
    
    return $data
}

function data_validation {
    param ([parameter(mandatory)] [hashtable]$data)
    
    $required_data = @(
        "First Name", 
        "Last Name",
        "Job Title",
        "Line Manager",
        "Office",
        "City",
        "Country",
        "Department",
        "Rejoiner"
    )
        
    foreach ($property in $required_data) {
        if (!($data.ContainsKey($property) -and ![string]::IsNullOrEmpty($data[$property]))) {
            Write-Warning "Data is missing attribute '$property'."
        }
    }
}

function set_user_email {
    param([parameter(mandatory)] [hashtable]$data)
    
    $email = "$($data['First Name'].replace(' ', '')).$($data['Last Name'].replace(' ', ''))@company.com"
    
    if (!(closed_input -user_prompt "Setting email address '$email' for the new user, is this correct? (Y/N)")) {
        do {
            $email = read-host "Input the new user email address"
        } while (!$email -or $email -notmatch "@")
    }
    
    $data["Email"] = $email
}

function create_password {
    param([parameter(mandatory)] [hashtable]$data)
    
    add-type -AssemblyName System.Web
    $new_user_password = [System.Web.Security.Membership]::GeneratePassword(16,10)
    
    $data["Password"] = $new_user_password
    Write-Host "New user password: $new_user_password" -ForegroundColor Cyan
}

function get_login_details {
    param([parameter(mandatory)] [hashtable]$data)
    
    $login_data = @{}
    
    $login_data["Password"] = Get-Content "$PSScriptRoot\common\secrets.txt"
    $login_data["username"]  = "domain\admin"
    $login_data["login_url"] = "https://ipaddress/ecp/?exsvurl=1&p=Mailboxes"
    $login_data["form_url"] = "https://ipaddress/ecp/UsersGroups/NewRemoteMailbox.aspx?pwmcid=2&ReturnObjectType=1"
    
    return $login_data
}

function Initalize_web_browser {
    param (
        [parameter(mandatory)] [hashtable] $data,
        [parameter(mandatory)] [hashtable] $login_data
    )
    
    $chromeDriverPath = "$PSScriptRoot\common\"
    $chromeExecutablePath = "$PSScriptRoot\common\GoogleChromePortable\App\Chrome-bin\chrome.exe"
    
    # Initalize the Chrome browser with set options
    $chromeOptions = [OpenQA.Selenium.Chrome.ChromeOptions]::new()
    $chromeOptions.BinaryLocation = $chromeExecutablePath
    $chromeOptions.AddArguments("start-maximized")
    $chromeOptions.AddArguments("--allow-running-insecure-content")
    $chromeOptions.AddArguments("--ignore-certificate-errors")
    $chromeOptions.AddArguments("--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0")

    $chromeDriver = [OpenQA.Selenium.Chrome.ChromeDriver]::new($chromeDriverPath, $chromeOptions)

    $chromeDriver.Navigate().GoToUrl($login_data["login_url"])

    # Enter credentials
    $chromeDriver.FindElementById("username").sendKeys($login_data["username"])
    $chromeDriver.FindElementById("password").sendKeys($login_data["Password"])

    # select sign in button
    $chromeDriver.FindElementByClassName("signinbutton").Click()

    # Navigate to Office 365 mailbox form
    $chromeDriver.Navigate().GoToUrl($login_data["form_url"])

    # first name
    $form_first_name = $data["First Name"]
    $chromeDriver.FindElementById("ResultPanePlaceHolder_NewRemoteMailboxWizard_NameAccountSection_contentContainer_ctl00_tbxFirstName").sendKeys($form_first_name)
    
    # last name
    $form_last_name = $data["Last Name"]
    $chromeDriver.FindElementById("ResultPanePlaceHolder_NewRemoteMailboxWizard_NameAccountSection_contentContainer_ctl00_tbxLastName").sendKeys($form_last_name)
    
    # user logon name
    $form_user_email = $data["Email"] -replace '@.*$'
    $chromeDriver.FindElementById("ResultPanePlaceHolder_NewRemoteMailboxWizard_NameAccountSection_contentContainer_tbxUserPrincipalName").sendKeys($form_user_email)
    
    # new password
    $form_user_password = $data["Password"]
    $chromeDriver.FindElementById("ResultPanePlaceHolder_NewRemoteMailboxWizard_NameAccountSection_contentContainer_tbxPassword").sendKeys($form_user_password)
    
    # confirm new password
    $form_confirm_user_password = $data["Password"]
    $chromeDriver.FindElementById("ResultPanePlaceHolder_NewRemoteMailboxWizard_NameAccountSection_contentContainer_tbxConfirmPassword").sendKeys($form_confirm_user_password) 
    
    # select option from combo box
    $comboBox_userLogonName = $chromeDriver.FindElementById("ResultPanePlaceHolder_NewRemoteMailboxWizard_NameAccountSection_contentContainer_listDomain")
    $comboBox_userLogonName_valueToSelect = $data["domain name"]
    
    $comboBox_userLogonName_selectElement = [OpenQA.Selenium.Support.UI.SelectElement]::new($comboBox_userLogonName)
    $comboBox_userLogonName_selectElement.SelectByValue($comboBox_userLogonName_valueToSelect)

    # click OU browse in form
    $chromeDriver.FindElementById("ResultPanePlaceHolder_NewRemoteMailboxWizard_NameAccountSection_contentContainer_pickerOU_ctl00_browseButton").click()
    
    start-sleep 1
    
    # expand all OU
    $chromeDriver.FindElementById("dlgModalError_Toggle").click()
}

function new_user {
    param([parameter(Mandatory)] [hashtable]$data)

    $new_user_data = @{
        Name = "$($data["First Name"]) $($data["Last Name"])"
        DisplayName = "$($data["First Name"]) $($data["Last Name"])"
        GivenName = $data["First Name"]
        Surname = $data["Last Name"]
        SamAccountName = "$($data["First Name"]).$($data["Last Name"])"
        UserPrincipalName = $data["Email"]
        EmailAddress = $data["Email"]
        AccountPassword = (ConvertTo-SecureString $data["Password"] -AsPlainText -Force)
        ChangePasswordAtLogon = $false
        Enabled = $true
        Path = read-host "Enter the Enter OU distinguished name for the new user to be created in"
    }

    $new_user_data
    read-host "Creating new user in AD with the following data, press enter to continue"

    New-ADUser @new_user_data
}

function get_AD_user {
    param([parameter(mandatory)] [hashtable]$data)

    $UPN = $data["Email"]
    $data["User Object"] = if ($user = Get-ADUser -Filter {UserPrincipalName -eq $UPN}) { $user } else { $null }
}

function get_manager {
    param ([parameter(mandatory)] [hashtable]$data)
    
    $manager_email = $data["Line Manager"]
    
    while ($true) {
        if ($manager = get-ADUser -Filter {userPrincipalName -eq $manager_email}) {
            $data["Manager Object"] = $manager
            return
        } else {
            $manager_email = get_validated_input -condition "!`$user_input" -prompt "Manager '$manager_email' could not be found, enter a valid email."
        }
    }
}

function get_company {
    param([parameter(mandatory)] [hashtable]$data)
    
    $OU_office_map = @{
        "OU=London" = "UK"
        "OU=Dubai" = "DBX"
        "OU=Milan" = "ITA"
        "OU=Argentina" = "AR"
        "OU=Australia" = "AU"
        "OU=Brazil" = "US-CA"
        "OU=California" = "US-CA"
    }
    
    foreach ($dn_component in $data["User Object"].DistinguishedName -split ",") {
        if ($OU_office_map.ContainsKey($dn_component)) {
            $data["Company"] = $OU_office_map[$dn_component]
            return
        }
    }
}

function set_user_attribute {
    param([parameter(mandatory)] [hashtable]$data)
    
    Write-host "Setting '$($data["Email"])' attributes Description, Title, Department, Office, City, Manager, Telephone Number, Employee Type and Company."
    
    Set-ADUser -Identity $data["User Object"] -Replace @{
        Description = $data["Job Title"];
        Title = $data["Job Title"];
        Department = $data["Department"];
        physicalDeliveryOfficeName = $data["Office"];
        l = $data["City"];
        Manager = $data["Manager Object"].distinguishedname;
        employeeType = $data["Position Type"];
        Company = $data["Company"]
    }
    
    if ($data["Telephone"]) {
        Set-ADUser -Identity $data["User Object"] -Replace @{telephoneNumber = $data["Telephone"]}
    }
}

function validate_user_attribute {
    param([parameter(Mandatory)] [hashtable]$data)
    
    $attributes_mapping = @{
        "description" = "Job Title"
        "title" = "Job Title"
        "department" = "Department"
        "physicalDeliveryOfficeName" = "Office"
        "l" = "City"
        "company" = "Company"
        "manager" = "Manager Object"
        "employeeType" = "Position Type"
        "telephoneNumber" = "Telephone"
    }
    
    Write-host "Validating '$($data["Email"])' attributes Description, Title, Department, Office, City, Manager, Telephone Number, Employee Type and Company."
    
    $UPN = $data["Email"]
    $user = Get-ADUser -Filter {UserPrincipalName -eq $UPN} -Properties *
    
    foreach ($attribute in $attributes_mapping.GetEnumerator()) {
        $attribute_key = $attribute.Key
        $data_value = if ($attribute.Value -eq "Manager Object") { $data[$attribute.Value].DistinguishedName } else { $data[$attribute.Value] }
        if (!$data_value) {continue}
        
        for ($i=0; $i -lt 3; $i++) {
            if ($user.$attribute_key -eq $data_value) {
                Write-Host "Valid: $attribute_key = $data_value" -ForegroundColor Green
                break
            } else {
                Write-Warning "Invalid: $attribute_key should be '$data_value' but is '$($user.$attribute_key)'"
                Start-Sleep 3
                $user = Get-ADUser -Filter {UserPrincipalName -eq $UPN} -Properties *
            }
        }
    }
}

function get_EntraID_user {
    param([parameter(Mandatory)] [hashtable]$data)
    
    while ($true) {
        if ($user = get-azureaduser -ObjectId $data["Email"]) {
            write-host "New user found in Entra ID '$($user.UserPrincipalName)'." -ForegroundColor Green
            $data["EntraID User Object"] = $user
            return
        } else {
            Write-Warning "Could not find the new user, checking again in 1 minute."
            start-sleep 60
        }
    }
}

function set_user_location {
    param([parameter(Mandatory)] [hashtable]$data)
    
    Set-AzureADUser -ObjectId $data["EntraID User Object"].ObjectId -UsageLocation "GB"
    
    while ($true) {
        if (($user = get-azureaduser -ObjectId $data["Email"]).UsageLocation -eq "GB") {
            write-host "Usage location '$($user.usagelocation)' has been set for the user." -foregroundcolor green
            return
        } else {
            Write-Warning "Could not find the user's usage location, checking again." 
            start-sleep 3
        }
    }
}

function set_user_license {
    param([parameter(Mandatory)] [hashtable]$data)
    
    # Sets an E3 or E1 license
    Write-Host "Assigning a license to the user '$($data["Email"])'."
    
    $data["skuID"] = if ($data["Company"] -in @("UK", "NY")) { "6fd2c87f-b296-42f0-b197-1e91e994b900" } else { "18181a46-0d4e-45cd-891e-60aabd171b4e" }
    
    $license = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicense
    $license.SkuId = $data["skuID"]
    
    $license_to_assign = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicenses
    $license_to_assign.AddLicenses = $license
    
    Set-AzureADUserLicense -ObjectId $data["EntraID User Object"].ObjectId -AssignedLicenses $license_to_assign
}

function validate_user_license {
    param([parameter(Mandatory)] [hashtable]$data)
    
    while ($true) {
        if (($user_license = $(Get-AzureADUser -ObjectId $data["EntraID User Object"].ObjectId | Select-Object -ExpandProperty AssignedLicenses).SkuId) -eq $data["skuID"]) {
            write-host "The user '$($data["Email"])' has been assigned the license '$user_license'." -ForegroundColor Magenta
            return
        } else {
            Write-Warning "Could not find the assigned license for the user '$($data["Email"])', checking again." 
            Start-Sleep 3
        }
    }
}

function add_group_member {
    param(
        [parameter(Mandatory)] [string]$email,
        [parameter(Mandatory)] [string]$group
    )
    
    write-host "Adding $email to group '$group'."
    
    while ($true) {
        Add-DistributionGroupMember -Identity $group -Member $email -BypassSecurityGroupManagerCheck -ErrorAction SilentlyContinue
        
        if ($email -in (Get-DistributionGroupMember -Identity $group -ResultSize unlimited).PrimarySMTPAddress) {
            write-host "User '$email' has been successfully been added to email group '$email'" -ForegroundColor Green
            return
        } else {
            Write-Warning "User '$email' was not found in group '$group', retrying."
        }
    }
}

function main {
    $form_input = get_multi_user_input -prompt "Paste in the new user form (Enter 'q' to continue):"

    $user_data = form_to_hashtable -form $form_input
    $user_data
    
    if ($user_data["Rejoiner"] -ne "false") {
        Write-Warning "User rejoiner status is not false."
        if (!(closed_input -user_prompt "Do you want to continue? (Y/N):" -n_msg "New user process terminated.")) { return }
    }
    
    data_validation -data $user_data
    
    if (!(closed_input -user_prompt "Is this information correct? (Y/N)" -n_msg "New user process terminated.")) { return }
    
    set_user_email -data $user_data
    
    create_password -data $user_data
    
    if (closed_input -user_prompt "Create new user in exchange? (Y/N to create user within AD)") {
        # Create new user in exchange using automated web browser due to restrictions
        required_modules
        
        $login_data = get_login_details -data $user_data
        
        Initalize_web_browser -data $user_data -login_data $login_data
    } else {
        new_user -data $user_data
    }
    
    if (closed_input -user_prompt "Do you want to initiate Delta Sync from AD to Entra ID? (Y/N)") { & "$PSScriptRoot\common\ADSync Delta.ps1" }
    
    get_AD_user -data $user_data
    if (!$user_data["User Object"]) {
        write-warning "User with UPN $($user_data["Email"])' was not found in AD, new user process terminated."
        return
    }
    
    get_manager -data $user_data
    
    get_company -data $user_data
    
    set_user_attribute -data $user_data
    
    validate_user_attribute -data $user_data
    
    # Check if the AD user object has finished syncing to Entra ID
    get_EntraID_user -data $user_data
    
    set_user_location -data $user_data
    
    set_user_license -data $user_data
    
    validate_user_license -data $user_data
    
    @("group1@company.com", "group2@company.com") | ForEach-Object { add_group_member -group $_ -email $user_data["Email"] }
}

EXO_connect
azureAD_connect

while ($true) { main }
