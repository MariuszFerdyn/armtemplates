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

$CertPasswd = ConvertTo-SecureString -String $Passwd -Force -AsPlainText

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name Posh-ACME -Scope AllUsers -Force
Import-Module Posh-ACME
Import-Module RemoteDesktop
New-Item -ItemType Directory -Path "C:\temp" -Force

Function RequestCert([string]$Fqdn) {
    New-PAAccount -AcceptTOS -Contact "$($ProjectName)@$($Fqdn)" -Force
    New-PAOrder $Fqdn
    $auth = Get-PAOrder | Get-PAAuthorizations | Where-Object { $_.HTTP01Status -eq "Pending" }
    $AcmeBody = Get-KeyAuthorization $auth.HTTP01Token (Get-PAAccount)

    Invoke-Command -ComputerName $WebGatewayServer -ScriptBlock {
        Param($auth, $AcmeBody)
        $AcmePath = "C:\Inetpub\wwwroot\.well-known\acme-challenge"
        New-Item -ItemType Directory -Path $AcmePath -Force
        New-Item -Path $AcmePath -Name $auth.HTTP01Token -ItemType File -Value $AcmeBody
        If (-Not (Get-WebConfiguration //staticcontent -PSPath "IIS:\sites\Default Web Site").collection | Where-Object { $_.FileExtension -eq "." }) {
            Add-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter "system.webServer/staticContent" -Name "." -Value @{ fileExtension = '.'; mimeType = 'text/plain' }
        }
    } -ArgumentList $auth, $AcmeBody

    Start-Sleep -Seconds 5
    $auth.HTTP01Url | Send-ChallengeAck
    New-PACertificate $Fqdn -Install
    $Thumbprint = (Get-PACertificate $Fqdn).Thumbprint
    
    $CertFullPath = (Join-path "C:\temp" $($Fqdn + ".pfx"))
    Export-PfxCertificate -Cert Cert:\LocalMachine\My\$Thumbprint -FilePath $CertFullPath -Password $CertPasswd -Force
}

$ServerObj = Get-WmiObject -Namespace "root\cimv2" -Class "Win32_ComputerSystem"
$ServerName = $ServerObj.DNSHostName + "." + $ServerObj.Domain
$CertWebGatewayPath = (Join-path "C:\temp" $($WebGatewayFqdn + ".pfx"))
$CertBrokerPath = (Join-path "C:\temp" $($BrokerFqdn + ".pfx"))
RequestCert $WebGatewayFqdn
RequestCert $BrokerFqdn
Set-RDCertificate -Role RDWebAccess -ImportPath $CertWebGatewayPath -Password $CertPasswd -ConnectionBroker $ServerName
Set-RDCertificate -Role RDGateway -ImportPath $CertWebGatewayPath -Password $CertPasswd -ConnectionBroker $ServerName
Set-RDCertificate -Role RDRedirector -ImportPath $CertBrokerPath -Password $CertPasswd -ConnectionBroker $ServerName
Set-RDCertificate -Role RDPublishing-ImportPath $CertBrokerPath -Password $CertPasswd -ConnectionBroker $ServerName