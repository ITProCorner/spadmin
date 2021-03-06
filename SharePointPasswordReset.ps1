<#  
.SYNOPSIS  
    Reset passwords for SP Managed Accounts and update farm configuration
	
.DESCRIPTION  
    Offers menu with granular control options for scope and actions.  Command line parameter "-user" can narrow scope to execute for just one user account.

.EXAMPLE

	Run manually for all service accounts:  
	.\SharePointPasswordReset.ps1
	
	Run manually for one service accounts:  
	.\SharePointPasswordReset.ps1 -user SPPOOL

	Run automated for all:  
	.\SharePointPasswordReset.ps1 -option 1

.NOTES  
	File Name:  SharePointPasswordReset.ps1
	Version  :  2.2
	Modified :  2019-01-11
	
	1) Reset passwords and push configuration
	Full execution will both changes the password and also pushes new configuration out to all servers in the current farm.
	Prompts for "YES" verification before changes.
	
	2) Push configuration only
	Will NOT change any passwords, but rather execute only the second step. Pushes new configuration out to all servers in the current farm.
	Prompts for "YES" verification before changes.
	
	3) Display managed account passwords
	Will retrieve current SharePoint known password from configuration database and display in table format.  Can be used with ZZAdmin account in a two step process to 1) connect to farm and 2) display credential for any managed account.
	Read-only safe function.
	https://gallery.technet.microsoft.com/office/Recover-SharePoint-Farm-3ddb6577
	
	4) Display Active Directory status
	Connect to current AD domain and retrieve account detail for all SharePoint managed accounts.  Details include LockedOut,PasswordExpired,CannotChangePassword ,PasswordLastSet,LastBadPasswordAttempt,LastLogonDate.
	Read-only safe function.
	
	5) Attempt AD login
	Connect to current AD domain and login to each account. Helps verify SharePoiint has current accurate passwords. Warning - This operation *could* result in lockout if invalid credentials are attempted repeatedly.
	Prompts for "YES" verification before changes.
#>

# Command line input parameters
Param(
    [string]$inputuser,
    [int]$option
)

# Load PowerShell cmdlet plugins
Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue | Out-Null
Import-Module WebAdministration -ErrorAction SilentlyContinue | Out-Null

# Password function
# TechNet Gallery - Generate a random and complex passwords (Simon Wahlin)
# https://gallery.technet.microsoft.com/scriptcenter/Generate-a-random-and-5c879ed5

Function Generate-Seed {
    # Generate a seed for randomization
    $RandomBytes = New-Object -TypeName 'System.Byte[]' 4
    $Random = New-Object -TypeName 'System.Security.Cryptography.RNGCryptoServiceProvider'
    $Random.GetBytes($RandomBytes)
    [BitConverter]::ToUInt32($RandomBytes, 0)
}

Function Generate-Password {

    # Specifies a fixed password length
    [int]$PasswordLength = 24
	
    # Specifies an array of strings containing charactergroups from which the password will be generated.
    # At least one char from each group (string) will be used.
    [String[]]$InputStrings = @('abcdefghijkmnpqrstuvwxyz', 'ABCEFGHJKLMNPQRSTUVWXYZ', '1234567890', '~!@#%^&*()')

    # Specifies a string containing a character group from which the first character in the password will be generated.
    # Useful for systems which requires first char in password to be alphabetic.
    [String] $FirstChar
	
    # Specifies number of passwords to generate.
    [int]$Count = 1

    For ($iteration = 1; $iteration -le $Count; $iteration++) {
        $Password = @{}
        # Create char arrays containing groups of possible chars
        [char[][]]$CharGroups = $InputStrings

        # Create char array containing all chars
        $AllChars = $CharGroups | ForEach-Object {[Char[]]$_}

        # Set password length
        if ($PSCmdlet.ParameterSetName -eq 'RandomLength') {
            if ($MinPasswordLength -eq $MaxPasswordLength) {
                # If password length is set, use set length
                $PasswordLength = $MinPasswordLength
            }
            else {
                # Otherwise randomize password length
                $PasswordLength = ((Generate-Seed) % ($MaxPasswordLength + 1 - $MinPasswordLength)) + $MinPasswordLength
            }
        }

        # If FirstChar is defined, randomize first char in password from that string.
        if ($PSBoundParameters.ContainsKey('FirstChar')) {
            $Password.Add(0, $FirstChar[((Generate-Seed) % $FirstChar.Length)])
        }
        # Randomize one char from each group
        Foreach ($Group in $CharGroups) {
            if ($Password.Count -lt $PasswordLength) {
                $Index = Generate-Seed
                While ($Password.ContainsKey($Index)) {
                    $Index = Generate-Seed                        
                }
                $Password.Add($Index, $Group[((Generate-Seed) % $Group.Count)])
            }
        }

        # Fill out with chars from $AllChars
        for ($i = $Password.Count; $i -lt $PasswordLength; $i++) {
            $Index = Generate-Seed
            While ($Password.ContainsKey($Index)) {
                $Index = Generate-Seed                        
            }
            $Password.Add($Index, $AllChars[((Generate-Seed) % $AllChars.Count)])
        }
		
        return ($( -join ($Password.GetEnumerator() | Sort-Object -Property Name | Select-Object -ExpandProperty Value)));
    }
}


# Main function
Function Main() {
    # Display menu and gather user input options
    Write-Host "-------------------------------"
    Write-Host "   SharePoint Password Reset"
    if ($inputuser) {
        # Display if "-user" parameter was input
        Write-Host "   Scope reduce to one user only : $inputuser" -ForegroundColor Yellow
    }
    if (!$option) {
        # Display standard menu
        Write-Host ""
        Write-Host "   [Choose Option]"
        Write-Host "   1) Reset passwords and push configuration"
        Write-Host "   2) Push configuration only"
        Write-Host "   3) Display managed account passwords"
        Write-Host "   4) Display Active Directory status"
        Write-Host "   5) Attempt AD login"
        Write-Host "   6) Repair-SPManagedAccountDeployment"
        Write-Host ""
        Write-Host " - Please type 1-6 and press enter to continue" -ForegroundColor Yellow
		
        # Wait for valid input
        while (!$option) {
            $option = Read-Host
        }
		
        # Verify choices with end user before continuing
        if ($option -eq 1 -or $option -eq 2 -or $option -eq 5) {
            Write-Host ""
            Write-Host "   [Verification]"
            Write-Host "   Option=$option"
            if ($inputuser) {
                Write-Host "   User=$inputuser"
            }
            Write-Host " - Please type ""YES"" to continue" -ForegroundColor Yellow
            $confirm = Read-Host
            $confirm = $confirm.ToUpper()
            if ($confirm -ne "YES") {break; }
        }
		
    }

    # Logging to transcript with custom filename based on current time
    $logpath = ".\$(Get-Date -f "yyyyMMdd_HHmm")-$($MyInvocation.MyCommand).txt"
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null} catch {}
    Start-Transcript $logpath -ErrorAction SilentlyContinue | Out-Null
    $domain = $env:USERDOMAIN
    $start = Get-Date
	
    # Header
    Write-Host "File Name     : SharePointPasswordReset.ps1"
    Write-Host "Version       : 2.1"
    Write-Host "Last Modified : 06-28-2017"
	
    # Menu options
    if ($option -eq 5) {
        #load module dependency for AD query
        if ($inputuser) {
            $spma = Get-SPManagedAccount |? {$_.UserName -like '*$inputuser'}
        }
        else {
            $spma = Get-SPManagedAccount
        }
        $spma | % {$login = ($_.UserName); $pass = (ReadSPMAPassword $login); $result = (TestADAuthentication $login $pass); $_} | Select UserName, @{n = 'Password'; e = {$pass}}, @{n = 'AD Login Successful'; e = {$result}} | Sort UserName | ft -a
		
        #exit
        break
    }
	
    if ($option -eq 4) {
        #load module dependency for AD query
        Import-Module ActiveDirectory -ErrorAction SilentlyContinue | Out-Null
		
        #Active Directory status check for all Managed Accounts
        Get-SPManagedAccount | % {$login = ($_.UserName.Split('\')[1]); $u = Get-ADUser $login -Properties *; $_} | Select @{n = 'Login'; e = {$login}}, @{n = 'LockedOut'; e = {$u.LockedOut}}, @{n = 'PasswordExpired'; e = {$u.PasswordExpired}}, @{n = 'CannotChangePassword'; e = {$u.CannotChangePassword}}, @{n = 'PasswordExpireDate'; e = {$u.PasswordLastSet.AddDays(90)}}, @{n = 'PasswordLastSet'; e = {$u.PasswordLastSet}}, @{n = 'LastBadPasswordAttempt'; e = {$u.LastBadPasswordAttempt}}, @{n = 'LastLogonDate'; e = {$u.LastLogonDate}} | Sort Login | ft -a
		
        #exit
        break
    }
	
    if ($option -eq 6) {
        # repair 
        # mitigate any ConfigDB/AD out of sync issues.http://blogs.technet.com/b/sbs/archive/2011/08/19/two-commands-you-should-always-run-first-when-troubleshooting-companyweb.aspx
        Write-Host "Starting ... Repair-SPManagedAccountDeployment"
        Repair-SPManagedAccountDeployment -ErrorAction Continue
        Write-Host "OK"
        Sleep 15
		
        #exit
        break
    }
	
    if ($option -eq 3) {
        # Option 3 display passwords
        DisplayAllPasswords
    }
    else {
        # Option 1 and 2 modification
		
        # Loop SP managed accounts
        $managedaccounts = Get-SPManagedAccount
        $i = 0
        $foundinputuser = $false
        foreach ($account in $managedaccounts) {
            # Managed account
            $username = $account.Username
            $user = $username.Split("\")[1]
			
            # Progress bar
            $i++
            $total = $managedaccounts.Count
            $prct = ($i / $total) * 100.0
            Write-Progress -PercentComplete $prct -Status $username -Activity "$i out of $total"

            # -user command line
            if ($inputuser.length -gt 0) {
                # single user option
                if ($user -eq $inputuser) {
                    UpdateManagedAccount $account $user $option $i
                    $foundinputuser = $true
                }
            }
            else {
                # all users
                UpdateManagedAccount $account $user $option $i
            }
        }
		
        # If username was not found in Config DB, prompt again
        if (!$foundinputuser) {
            Write-Host " - User ""$inputuser"" not found, please verify and run again." -ForegroundColor Yellow
        }
    }
	
    # Summary of elapsed time
    $elapsed = (Get-Date) - $start
    Write-Host "Elapsed Min: "$elapsed.TotalMinutes
}
Function UpdateManagedAccount($account, $user, $option, $i) {
    # Clean input array
    $domain = $env:USERDOMAIN
    if ($user -is [system.array]) {
        $user = $user[0]
    }
		
    # Display account we are processing
    Write-Host "`nManaged Account - $domain\$user" -ForegroundColor Green

    # Option 1 - Reset and push
    if ($option -eq 1) {
        # Generate Password
        # MS TechNet - AutoGeneratePassword will create a fully random new 31 character length password
        # http://technet.microsoft.com/en-us/library/ff607617(v=office.15).aspx
        Write-Host " - Changing password for $user to " -ForegroundColor Yellow -NoNewline
		
        # Randomly generate
        $pw = Generate-Password
        if ($pw -is [system.array]) {
            $pw = $pw[$pw.length - 1]
        }
        #VERBOSE PW DISPLAY
        Write-Host $pw
		
        $loop = $i
        do {
            # Apply change to AD and SP
            $account | Set-SPManagedAccount -NewPassword (ConvertTo-Securestring $pw -AsPlainText -Force) -SetNewPassword -ConfirmPassword (ConvertTo-Securestring $pw -AsPlainText -Force) -Confirm:$false
			
            # Monitor background timer job
            Start-Sleep 5
            do {
                Start-Sleep 2
                Write-Host "." -ForegroundColor Yellow -NoNewline
            } while (Get-SPTimerJob | Where {$_.DisplayName.Contains($user) -and 
                    $_.DisplayName.Contains("Password")}
            )
			
            # Repeat twice for first user account
            $loop--
            if ($loop -eq 0) {Write-Host "Repeat twice for first user account. Sleep 20 sec ..."; Start-Sleep 20}
        } while ($loop -eq 0)
		
        # Apply farm configuration updates for this user and password
        ApplySpecialRole $user $pw
    }
	
    # Option 2 - Push only
    if ($option -eq 2) {
        # Apply farm configuration updates for this user and password
        $pw = ReadSPMAPassword "$domain\$user"
        ApplySpecialRole $user $pw
    }
}
Function DisplayAllPasswords() {
    # Display all managed accounts with password
    $disp = Get-SPManagedAccount | select UserName, @{Name = 'Password'; Expression = {ConvertTo-UnsecureString (GetFieldValue $_ 'm_Password').SecureStringValue}} | Sort UserName
	
    # Add  row number
    $row = 1
    $disp = $disp | % {$row++; $_} | select @{n = 'Row'; e = {$row}}, UserName, Password
    $disp | ft -a
	
    # Clipboard
    Write-Host " - (optional) Type number to copy Password to clipboard.  Or enter to continue:" -ForegroundColor Yellow
    $sel = Read-Host
    if ($sel) {
        $match = $disp |? {$_.Row -eq $sel}
        $match.Password | clip.exe
        Write-Host " - Clipboard set OK" -ForegroundColor Green
    }
	
}
Function ApplySpecialRole($user, $pw) {
    # Match role based on user name syntax
    $user = $user.toLower()
    $domain = $env:USERDOMAIN
    $role = "default"
    if ($user -like '*farm*') {$role = "farm"}
    if ($user -like '*search*') {$role = "search"}
    if ($user -like '*content*') {$role = "content"}
    if ($user -like '*profile*') {$role = "profile"}
    if ($user -like '*workflow*') {$role = "workflow"}
    if ($user -like '*visio*') {$role = "visio"}
    if ($user -like '*excel*') {$role = "excel"}
    if ($user -like '*service*') {$role = "service"}
    Write-Host "Role: $role"
	
    # Special roles
    # Area beyond traditional SPManagedAccount where we want to apply direct configuration updates.
    if ($role -eq "profile") {
        # FARM Role
        # User Profile Service (UPS)
        Write-Host " - Role User Profile Synchronization "  -ForegroundColor Yellow
		
        # Detect servers in farm
        $syncMachine = $null
        $online = Get-SPServiceInstance |? {$_.TypeName -eq "User Profile Synchronization Service" -and $_.Status -eq "Online"}
        if ($online) {
            $syncMachine = $online.Parent
        }
		
        # First from array
        if ($syncMachine -is [system.array]) {
            $syncMachine = $syncMachine[0]
        }
		
        if ($syncMachine) {
            $syncMachine | fl
            $profApp = Get-SPServiceApplication |? {$_.TypeName -eq "User Profile Service Application"}
            $syncSvc = Get-SPServiceInstance -Server $syncMachine | where-object {$_.TypeName -eq "User Profile Synchronization Service"}
            if ($syncSvc) {
                $syncSvc.Status = [Microsoft.SharePoint.Administration.SPObjectStatus]::Provisioning
                $syncSvc.IsProvisioned = $false
                $syncSvc.UserProfileApplicationGuid = $profApp.Id
                $syncSvc.Update()
            }

            # Apply new password and provision (Starting...)
            $profApp.SetSynchronizationMachine($syncMachine.Address, $syncSvc.Id, "$domain\$user", $pw)
			
            # Start User Profile Service
            StartUPS
            Write-host "   "$syncSvc.Status
        }
    }
    if ($role -eq "search") {
        # SEARCH ROLE
        # Update service application for Enterprise Search
        Write-Host "`n - Role Search Service ... " -ForegroundColor Yellow
        $secpwd = ConvertTo-SecureString -AsPlainText -String $pw -Force
        Set-SPEnterpriseSearchService -ServiceAccount $user -ServicePassword $secpwd
    }
    if ($role -eq "content") {
        # CRAWL ROLE
        # Update content crawl used with Enterprise Search
        Write-Host "`n - Role Content Crawl ... " -ForegroundColor Yellow
        $secpwd = ConvertTo-SecureString -AsPlainText -String $pw -Force
        $sa = Get-SPEnterpriseSearchServiceApplication
        $sa | Set-SPEnterpriseSearchServiceApplication -DefaultContentAccessAccountName "$domain\$user" -DefaultContentAccessAccountPassword $secpwd
    }
    if ($role -eq "profile") {
        # PROFILE ROLE
        # Update AD profile import role with RDC.  Replicating Directory Changes.
        Write-Host "`n - Role AD Profile Import ... " -ForegroundColor Yellow
		
        # Start User Profile Service
        StartUPS
		
        # Apply password to AD connection
        Write-Host "   Add-SPProfileSyncConnection()"
        $profileServiceApp = Get-SPServiceApplication |? {$_.TypeName -eq "User Profile Service Application"}
        $connectionSyncOU = (Get-ADDomain).DistinguishedName
        $secpwd = ConvertTo-SecureString -AsPlainText -String $pw -Force
        Add-SPProfileSyncConnection -ProfileServiceApplication $profileServiceApp -ConnectionForestName $env:USERDNSDOMAIN -ConnectionDomain $env:USERDOMAIN -ConnectionUserName $user -ConnectionSynchronizationOU $connectionSyncOU -ConnectionPassword $secpwd
    }

    # ALWAYS CHECK WINDOWS SERVICE
    # Managed Accounts
		
    $spma = Get-SPManagedAccount | % {$login = ($_.UserName.Split('\')[1]);
        $u = Get-ADUser $login -Properties *;
        $_} | Select UserName, @{Name = 'Password';
        Expression = {ConvertTo-UnsecureString (GetFieldValue $_ 'm_Password').SecureStringValue}
    }, @{n = 'AccountExpirationDate';
        e = {$u.AccountExpirationDate}
    }, @{n = 'LockedOut';
        e = {$u.LockedOut}
    }, @{n = 'PasswordExpired';
        e = {$u.PasswordExpired}
    }, @{n = 'PasswordNeverExpires';
        e = {$u.PasswordNeverExpires}
    }, @{n = 'PasswordLastSet';
        e = {$u.PasswordLastSet}
    }, @{n = 'LastBadPasswordAttempt';
        e = {$u.LastBadPasswordAttempt}
    }, @{n = 'LastLogonDate';
        e = {$u.LastLogonDate}
    };
		
    # Double check that Trace is running with new account credential
    Write-Host "`n -  Windows Service ... " -ForegroundColor Yellow
    foreach ($srv in (Get-SPServer |? {$_.Role -ne "Invalid"})) {
        $addr = $srv.Address
        Write-Host "   [$addr]"
        $services = Get-WmiObject win32_service -computer $addr | select Name, StartName, Status, StartMode
        foreach ($s in $services) {
            foreach ($ma in $spma) {
                # single user scope
                if ($inputuser) {
                    if ($s.StartName -eq "$domain\$user") {
                        $match = $true
                    } else {
                        $match = $false
                    }
                } else {
                    $match = $true
                }

                # match fitler - then match user names
                if ($match) {
                    if ($s.StartName -eq $ma.UserName) {
                        # Microsoft TechNet Reference for $null parameters http://msdn.microsoft.com/en-us/library/aa384901(v=vs.85).aspx
                        # Most parameters are NULL because we are not apply change in that area
                        $sn = $s.Name
                        $startname = $s.StartName
                        $startmode = $s.StartMode
                        Write-Host " -  Updated Windows Service - $sn - $startname - $startmode - $($ma.UserName)" -ForegroundColor Yellow
                        $service = Get-WmiObject win32_service -computer $addr -filter "name='$sn'" 
                        #REM $service.change($null, $null, $null, $null, $null, $null, $ma.UserName, $ma.Password) | Out-Null
                    }
                }
            }
        }
    }
	
    if ($role -eq "workflow") {
        # Workflow Manager ROLE
        Write-Host "`n - Workflow Manager Service ... " -ForegroundColor Yellow
		
        # Apply password to Service Bus
        $secpwd = ConvertTo-SecureString -AsPlainText -String $pw -Force
        Update-SBHost -RunAsPassword $secpwd | Out-Null
        Write-Host "   Updated SBHost"
		
        # Apply password to Workflow Manager
        Update-WFHost -RunAsPassword $secpwd | Out-Null
        Write-Host "   Updated WFHost"
    }
    if ($role -eq "excel") {
        # Excel Service Application
        # Unattend account and Secure Store target ID
        Write-Host "`n - Excel Unattend ... " -ForegroundColor Yellow
        UpdateVisioExcelSSA "$domain\$user" $pw "Excel Services Application Web Service Application" "Excel"
    }
    if ($role -eq "visio") {
        # Visio Service Application
        # Unattend account and Secure Store target ID
        Write-Host "`n - Visio Unattend ... " -ForegroundColor Yellow
        UpdateVisioExcelSSA "$domain\$user" $pw "Visio Graphics Service Application" "Visio"
    }
    if ($role -eq "perform") {
        # PerformancePoint Service Application
        # Unattend account and Secure Store target ID
        Write-Host "`n - PerformancePoint Unattend ... " -ForegroundColor Yellow
        $secpwd = ConvertTo-SecureString -AsPlainText -String $pw -Force
        $performancePointCredential = New-Object System.Management.Automation.PsCredential "$domain\$user", $secpwd
        $application = Get-SPPerformancePointServiceApplication
        if ($application) {
            $application | Set-SPPerformancePointSecureDataValues -DataSourceUnattendedServiceAccount $performancePointCredential
        }
    }
	
    # ALWAYS - Task Scheduler Jobs
    Write-Host " - Checking Scheduled Tasks in farm ... " -ForegroundColor Yellow
    foreach ($srv in (Get-SPServer |? {$_.Role -ne "Invalid"})) {
        $addr = $srv.Address
        Write-Host "   [$addr]"
		
        # Locate and apply to Scheduled Tasks
        $schtask = schtasks.exe /query /s "$addr" /V /FO CSV | ConvertFrom-Csv
        $task = $schtask |? {$_."Run As User" -eq "$domain\$user"}
        if ($task) {
            if ($task -is [system.array]) {
                # Loop multiple
                foreach ($s in $task) {
                    $out = schtasks.exe /change /s $addr /tn $s.TaskName /rp $pw
                    Write-Host "   $out"
                }
            }
            else {
                # Single
                $out = schtasks.exe /change /s $addr /tn $task.TaskName /rp $pw
                Write-Host "   $out"
            }
        }
    }
	
    # ALWAYS - IIS Application Pools
    Write-Host " - Checking IIS pools in farm ... " -ForegroundColor Yellow
    foreach ($srv in (Get-SPServer |? {$_.Role -ne "Invalid"})) {
        $addr = $srv.Address
        Write-Host "   [$addr]"
		
        # Locate and apply to IIS Pools
        [Reflection.Assembly]::LoadWithPartialName("Microsoft.Web.Administration") | Out-Null
        $sm = [Microsoft.Web.Administration.ServerManager]::OpenRemote($addr)
        foreach ($pool in $sm.ApplicationPools) {
            $currname = $pool.Name
            $curruser = $pool.processModel.userName
            $currpw = $pool.processModel.password
			
            # If different PW then update PW
            #REM Write-Host "VERBOSE // curruser $curruser - currpw $currpw - pw $pw"
            if ($curruser -eq "$domain\$user" -and $currpw -ne $pw -and $pw) {
                #Server Manager for changes.  New object here to apply changes and commit.   Keeps higher level context "$sm" static to manage looping.
                $csm = [Microsoft.Web.Administration.ServerManager]::OpenRemote($addr)
                foreach ($p in $csm.ApplicationPools) {
                    if ($p.Name -eq $pool.Name) {
                        $p.processModel.userName = "$domain\$user"
                        $p.processModel.password = $pw
                        $p.processModel.identityType = 3
                        $csm.CommitChanges()
                        Write-Host "   Updated Pool ""$currname"""
                    }
                }
				
                # Attempt recycle to apply changes and flush any old W3WP process
                try {
                    $pool.Start() | Out-Null
                    $pool.Recycle() | Out-Null
                } catch {}
            }
        }
    }
}
function Bindings() {
    return [System.Reflection.BindingFlags]::CreateInstance -bor [System.Reflection.BindingFlags]::GetField -bor [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic;
};
function GetFieldValue([object]$o, [string]$fieldName) {
    $bindings = Bindings;
    return $o.GetType().GetField($fieldName, $bindings).GetValue($o);
};
function ConvertTo-UnsecureString([System.Security.SecureString]$string) {
    $intptr = [System.IntPtr]::Zero;
    $unmanagedString = [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($string);
    $unsecureString = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($unmanagedString);
    [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($unmanagedString);
    return $unsecureString;
};
Function TestADAuthentication ($username, $password) {
    return ((new-object directoryservices.directoryentry "", $username, $password).psbase.name -ne $null)
}
Function ReadSPMAPassword($user) {
    # Read SP Managed Account credential
    $account = Get-SPManagedAccount |? {$_.Username -eq $user} | Select UserName, @{Name = 'Password'; Expression = {ConvertTo-UnsecureString (GetFieldValue $_ 'm_Password').SecureStringValue}}
    return $account.Password
}
function Bindings() { 
    # Support method for ReadSPMAPassword()
    return [System.Reflection.BindingFlags]::CreateInstance -bor 
    [System.Reflection.BindingFlags]::GetField -bor 
    [System.Reflection.BindingFlags]::Instance -bor 
    [System.Reflection.BindingFlags]::NonPublic 
} 
function GetFieldValue([object]$o, [string]$fieldName) { 
    # Support method for ReadSPMAPassword()
    $bindings = Bindings 
    return $o.GetType().GetField($fieldName, $bindings).GetValue($o) 
} 
function ConvertTo-UnsecureString([System.Security.SecureString]$string) {  
    # Support method for ReadSPMAPassword()
    $intptr = [System.IntPtr]::Zero 
    $unmanagedString = [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($string) 
    $unsecureString = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($unmanagedString) 
    [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($unmanagedString) 
    return $unsecureString 
} 
function UpdateVisioExcelSSA($user, $pw, $typeName, $shortType) {

    if ($pw) {

        # Apply unattended data access account updated for Secure Store target application ID
        $secPassword = ConvertTo-SecureString "$pw" -AsPlaintext -Force
        $unattendedAccount = New-Object System.Management.Automation.PsCredential $user, $secPassword
        $serviceApplication = Get-SPServiceApplication |? {$_.TypeName -eq $typeName}

        # Set the group claim and admin principals
        $groupClaim = New-SPClaimsPrincipal -Identity "nt authority\authenticated users" -IdentityType WindowsSamAccountName
        $adminPrincipal = New-SPClaimsPrincipal -Identity "$($env:userdomain)\$($env:username)" -IdentityType WindowsSamAccountName

        # Set the field values
        $secureUserName = ConvertTo-SecureString $unattendedAccount.UserName -AsPlainText -Force
        $securePassword = $unattendedAccount.Password
        $credentialValues = $secureUserName, $securePassword

        # Set the Target App Name and create the Target App
        $name = "$($serviceApplication.ID)-$($shortType)UnattendedAccount"
        Write-Host -ForegroundColor White " - Creating Target Application $name..."
        $secureStoreTargetApp = New-SPSecureStoreTargetApplication -Name $name `
            -FriendlyName "$shortType Services Unattended Account Target App" `
            -ApplicationType Group `
            -TimeoutInMinutes 3

        # Set the account fields
        $usernameField = New-SPSecureStoreApplicationField -Name "User Name" -Type WindowsUserName -Masked:$false
        $passwordField = New-SPSecureStoreApplicationField -Name "Password" -Type WindowsPassword -Masked:$false
        $fields = $usernameField, $passwordField

        # Get the service context
        $subId = [Microsoft.SharePoint.SPSiteSubscriptionIdentifier]::Default
        $context = [Microsoft.SharePoint.SPServiceContext]::GetContext($serviceApplication.ServiceApplicationProxyGroup, $subId)

        # Check to see if the Secure Store App already exists
        $secureStoreApp = Get-SPSecureStoreApplication -ServiceContext $context -Name $name -ErrorAction SilentlyContinue
        If (!($secureStoreApp)) {
            # Doesn't exist so create.
            Write-Host -ForegroundColor White " - Creating Secure Store Application..."
            $secureStoreApp = New-SPSecureStoreApplication -ServiceContext $context `
                -TargetApplication $secureStoreTargetApp `
                -Administrator $adminPrincipal `
                -CredentialsOwnerGroup $groupClaim `
                -Fields $fields
        }
        # Update the field values
        Write-Host -ForegroundColor White " - Updating Secure Store Group Credential Mapping..."
        if ($secureStoreApp) {
            Update-SPSecureStoreGroupCredentialMapping -Identity $secureStoreApp -Values $credentialValues
        }

        # Set the unattended service account application ID
        Write-Host -ForegroundColor White " - Setting Application ID for $shortType Service..."
        if ($typeName -like '*visio*') {
            $serviceApplication | Set-SPVisioExternalData -UnattendedServiceAccountApplicationID $name
        }
        elseif ($typeName -like '*excel*') {
            Set-SPExcelServiceApplication -Identity $serviceApplication -UnattendedAccountApplicationId $name
        }
    }
}
function StartUPS() {
    # Start User Profile Service (UPS)
    $start = Get-Date
    $syncSvc = Get-SPServiceInstance |? {$_.TypeName -eq "User Profile Synchronization Service"}
    $online = Get-SPServiceInstance |? {$_.TypeName -eq "User Profile Synchronization Service" -and $_.Status -eq "Online"}
    if ($syncSvc) {
        # Not Online and will need start
        $syncMachine = $syncSvc.Parent
        if (!$online) {
            if ($syncSvc -is [array]) {
                $syncSvc = $syncSvc[0]
            }

            # Start UPS
            if ($syncSvc.Status -ne "Online") {
                Write-Host " - Not Online, Starting ... " -ForegroundColor Yellow
                Start-SPServiceInstance $syncSvc | Out-Null
            }

            # Monitor background timer job
            if ($syncMachine) {
                Start-Sleep 5
                do {
                    Start-Sleep 2
                    Write-Host "." -NoNewline
                } while (
                    (Get-SPServiceInstance -Server $syncMachine | where-object {$_.TypeName -eq "User Profile Synchronization Service"}).Status -ne "Online" -and 
                    ((Get-Date) - $start).TotalMinutes -lt 15
                )
            }
        }
    }
}

# Execute main function (including command line parameters)
Main