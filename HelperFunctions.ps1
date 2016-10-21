function Dump-InstalledPackages {
	param($InstalledPackages)
	$InstalledPackages | ConvertTo-Json |
	Out-File $script:InstalledPackagesPath -Force
}

function Dump-RegisteredPackageSources {
	$script:RegisteredPackageSources | Select * -ExcludeProperty Headers | ConvertTo-Json |
	Out-File $script:RegisteredPackageSourcesPath -Force
}

function Get-PackageSources {
	param(
		[Parameter(Mandatory)]
		$request
	)
	$Sources = if ($request.PackageSources) {
		$script:RegisteredPackageSources | ? Name -in $request.PackageSources
	} else { $script:RegisteredPackageSources }
	
	$Sources | ? {-not $_.Headers} | % {
		if ($request.Credential) {
			Set-PackageSourcePrivateToken -Source $_.Name -Credential $request.Credential
		} else {
			$msg = "Credentials are required for source $($_.Name)"
			Write-Error -Message $msg -ErrorId CredentialsNotSpecified -Category InvalidOperation -TargetObject $_.Name
		}
	}
	$Sources
}

function Set-PackageSourcePrivateToken {
	param(
		[Parameter(Mandatory)]
		[string[]] $Source,
		[Parameter(Mandatory)]
		[pscredential] $Credential
	)
	$Source | % {
		$PackageSource = $script:RegisteredPackageSources | ? Name -eq $_
		if (-not $PackageSource.Headers) {
			$Auth = @{
				login = $Credential.UserName
				password = $Credential.GetNetworkCredential().Password
			}
			$Location = $PackageSource.Location.TrimEnd('/')
			$PrivateToken = (Invoke-RestMethod -Uri ($Location + '/session') -Method Post -Body $Auth).'private_token'
			$Headers = @{
				'PRIVATE-TOKEN' = $PrivateToken
				#'SUDO' = 'root'
			}
			$PackageSource | Add-Member -MemberType NoteProperty -Name Headers -Value $Headers -TypeName hashtable
		}
	}
}

function ConvertTo-Hashtable {
    param(
        [Parameter(Mandatory,ValueFromPipeline)]
        $Object,
        [int] $Depth = 5
    )
    Process {
        if (!$Depth) { return $Object }
        $ht = [ordered]@{}
        if ($Object -as [hashtable]) {
            ($Object -as [hashtable]).GetEnumerator() | % {
                if ($_.Value -is [PSCustomObject]) {
                    $ht[$_.Key] = ConvertTo-Hashtable ($_.Value) ($Depth - 1)
                } else {
                    $ht[$_.Key] = $_.Value
                }
            }
            return $ht
        } elseif ($Object.GetType().Name -eq 'PSCustomObject') {
            $Object | Get-Member -MemberType Properties | % {
                $ht[$_.Name] = ConvertTo-Hashtable $Object.($_.Name) ($Depth - 1)
            }
            return $ht
        } else {
            return $Object
        }
    }
}

function Get-GitSubmodules {
	param(
		[Parameter(Mandatory)]
		[ValidateScript({Test-Path $_})]
		$Path
	)
	(Get-Content $Path -Raw).Split('[]') -ne '' | % -Begin { $i = 0 } {
		if ($i++ % 2) { [PSCustomObject](ConvertFrom-StringData $_) }
	}
}