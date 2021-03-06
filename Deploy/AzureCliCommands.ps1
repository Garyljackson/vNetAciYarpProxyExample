$Location = 'australiaeast'
$ResourceGroupName = 'MyExampleResourceGroup'

$VNetName = 'MyExampleVNet'
$VNetCIDR = '10.0.0.0/16'

$DefaultSubnetName = 'Default'
$DefaultSubnetCIDR = '10.0.1.0/24'

$AciSubnetName = 'ExampleAciSubnet'
$AciSubnetCIDR = '10.0.2.0/24'

$WebAppIntegrationSubnetName = 'vNetIntegrationSubnet'
$WebAppIntegrationSubnet = '10.0.3.0/24'

$AppServicePlanName = 'ExampleAsp'
$ProxyWebAppName = 'ExampleAciProxy12345'

az group create --name $ResourceGroupName --location $Location

# Create the virtual network
az network vnet create `
    --name $VNetName `
    --resource-group $ResourceGroupName `
    --location $Location `
    --address-prefix $VNetCIDR `
    --subnet-name $DefaultSubnetName `
    --subnet-prefix $DefaultSubnetCIDR

# Create 2 subnets
# You can't mix resource types in a single resource group due to the delegations on each subnet
az network vnet subnet create `
    --name $AciSubnetName `
    --resource-group $ResourceGroupName `
    --vnet-name $VNetName   `
    --address-prefix $AciSubnetCIDR

az network vnet subnet create `
    --resource-group $ResourceGroupName `
    --vnet-name $vNetName `
    --name $WebAppIntegrationSubnetName `
    --address-prefixes $WebAppIntegrationSubnet `
    --delegations 'Microsoft.Web/serverFarms'

# Deploy the ACI instance to the virtual network
az container create `
    --name appcontainer `
    --resource-group $ResourceGroupName `
    --image mcr.microsoft.com/azuredocs/aci-helloworld `
    --vnet $VNetName `
    --subnet $AciSubnetName

# Create the proxy web app resources
# Needs to be S1 to support vNet integration
az appservice plan create `
    --resource-group $ResourceGroupName `
    --name $AppServicePlanName `
    --is-linux `
    --sku S1 

az webapp create `
    --name $ProxyWebAppName `
    --resource-group $ResourceGroupName `
    --plan $AppServicePlanName `
    --runtime '"DOTNET|6.0"'

# Get the ip address for the ACI instance we deployed - this is used in the proxy web app settings
$AciIp = $(az container show `
        --name appcontainer `
        --resource-group $ResourceGroupName `
        --query ipAddress.ip --output tsv)

## Double underscores are needed for nested json settings in Azure
az webapp config appsettings set `
    --resource-group $ResourceGroupName `
    --name $ProxyWebAppName `
    --settings ReverseProxy__Clusters__MinimumCluster__Destinations__MyBackend__Address="http://$AciIp"

# Setup the vNet integration for the web app to its subnet
az webapp vnet-integration add `
    --resource-group $ResourceGroupName `
    --name $ProxyWebAppName `
    --vnet $VNetName `
    --subnet $WebAppIntegrationSubnetName

# Link the YARP proxy application from the GitHub repo
az webapp deployment source config `
    --branch master `
    --manual-integration `
    --name $ProxyWebAppName `
    --repo-url https://github.com/Garyljackson/vNetAciYarpProxyExample/ `
    --resource-group $ResourceGroupName

# Deploy the source code to the web app
az webapp deployment source sync `
    --name $ProxyWebAppName `
    --resource-group $ResourceGroupName

# Display the details to access the proxy application
az webapp config hostname list `
    --resource-group $ResourceGroupName `
    --webapp-name $ProxyWebAppName