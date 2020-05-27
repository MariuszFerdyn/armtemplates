Param(
    [Parameter(Mandatory)]
    [string]$ProjectName,

    [Parameter(Mandatory)]
    [string]$WebGatewayFqdn,

    [Parameter(Mandatory)]
    [string]$BrokerFqdn,

    [Parameter(Mandatory)]
    [string]$WebGatewayServer,

    [Parameter(Mandatory)]
    [string]$Passwd
)

New-Item -ItemType Directory -Path "C:\temp" -Force
Start-Transcript -Path "C:\temp\RequestCertificate.log"

$ServerObj = Get-WmiObject -Namespace "root\cimv2" -Class "Win32_ComputerSystem"

$DomainName = $ServerObj.Domain
$CertPasswd = ConvertTo-SecureString -String $Passwd -Force -AsPlainText
[System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($ProjectName)", $CertPasswd)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name Posh-ACME -Scope AllUsers -Force
Import-Module Posh-ACME
Import-Module RemoteDesktop

Function RequestCert([string]$Fqdn) {
    Set-PAServer LE_PROD
    New-PAAccount -AcceptTOS -Contact "$($ProjectName)@$($Fqdn)" -Force
    New-PAOrder $Fqdn
    $auth = Get-PAOrder | Get-PAAuthorizations | Where-Object { $_.HTTP01Status -eq "Pending" }
    $AcmeBody = Get-KeyAuthorization $auth.HTTP01Token (Get-PAAccount)

    Invoke-Command -ComputerName $WebGatewayServer -Credential $DomainCreds -ScriptBlock {
        Param($auth, $AcmeBody)
        $AcmePath = "C:\Inetpub\wwwroot\.well-known\acme-challenge"
        New-Item -ItemType Directory -Path $AcmePath -Force
        New-Item -Path $AcmePath -Name $auth.HTTP01Token -ItemType File -Value $AcmeBody
    } -ArgumentList $auth, $AcmeBody

    $auth.HTTP01Url | Send-ChallengeAck

    Do {
        Write-Host "Waiting for validation. Sleeping 30 seconds..."
        Start-Sleep -Seconds 30
    } While ((Get-PAOrder | Get-PAAuthorizations).HTTP01Status -ne "valid")

    New-PACertificate $Fqdn -Install
    $Thumbprint = (Get-PACertificate $Fqdn).Thumbprint
    
    $CertFullPath = (Join-path "C:\temp" $($Fqdn + ".pfx"))
    Export-PfxCertificate -Cert Cert:\LocalMachine\My\$Thumbprint -FilePath $CertFullPath -Password $CertPasswd -Force
}

$ServerName = $ServerObj.DNSHostName + "." + $DomainName
$CertWebGatewayPath = (Join-path "C:\temp" $($WebGatewayFqdn + ".pfx"))
$CertBrokerPath = (Join-path "C:\temp" $($BrokerFqdn + ".pfx"))

If (-Not (Get-RDCertificate -Role RDGateway).IssuedTo) {
    RequestCert $WebGatewayFqdn
    RequestCert $BrokerFqdn
    Set-RDCertificate -Role RDWebAccess -ImportPath $CertWebGatewayPath -Password $CertPasswd -ConnectionBroker $ServerName -Force
    Set-RDCertificate -Role RDGateway -ImportPath $CertWebGatewayPath -Password $CertPasswd -ConnectionBroker $ServerName -Force
    Set-RDCertificate -Role RDRedirector -ImportPath $CertBrokerPath -Password $CertPasswd -ConnectionBroker $ServerName -Force
    Set-RDCertificate -Role RDPublishing -ImportPath $CertBrokerPath -Password $CertPasswd -ConnectionBroker $ServerName -Force
}

Stop-Transcript