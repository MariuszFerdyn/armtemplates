#$Subscription = ""

#Connect-AzAccount
#Select-AzSubscription -Subscription $Subscription -Scope CurrentUser -Force -Tenant 
#Set-AzContext -Subscription $Subscription

$RG = "rds2019"
$Location = "East US"

If (-Not (Get-AzResourceGroup -Name $RG -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $RG -Location $Location
}

$templateFile = "C:\Marcus\ARMTemplates\RDSRemoteApp2019\azuredeploy.json"
$parameterFile = "C:\Marcus\ARMTemplates\RDSRemoteApp2019\azuredeploy.parameters.lab.json"

Write-host "[$(Get-Date)] Deployment started..."

New-AzResourceGroupDeployment -Name "RDS2019Deployment" `
    -ResourceGroupName $RG `
    -TemplateFile $templateFile `
    -TemplateParameterFile $parameterFile `
    -Mode Complete `
    -Verbose `
    -Force

If ($?) {
    $Result = "Successful."
}
Else {
    $Result = "Failed."
}

Write-host "[$(Get-Date)] Deployment finished. Result: $($Result)"