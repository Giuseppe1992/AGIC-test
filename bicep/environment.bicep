@allowed(['Ubuntu', 'Mariner'])
param AKSHostImage string = 'Ubuntu'
@description('Check if this size is available for the region you choose')
param AKSSize string = 'Standard_DS2_v2'
param Location string = 'eastus'
param RandomPostfix string = 'x123'

var VirtualNetworkName = 'AKS-vnet-${AKSHostImage}-${RandomPostfix}'
resource VirtualNetwork 'Microsoft.Network/virtualNetworks@2020-11-01' = {
  name: VirtualNetworkName
  location: Location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '192.168.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'AzureClients'
        properties: {
          addressPrefix: '192.168.3.0/24'
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '192.168.0.0/24'
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'AKSSubnet'
        properties: {
          addressPrefix: '192.168.2.0/24'
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'AzureApplicationGatewaySubnet'
        properties: {
          addressPrefix: '192.168.1.0/24'
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
    virtualNetworkPeerings: []
    enableDdosProtection: false
  }
}


var AKSName = 'AKS-cluster-${AKSHostImage}-${RandomPostfix}'
resource AKS 'Microsoft.ContainerService/managedClusters@2022-07-02-preview' = {
  name: AKSName
  location: Location
  sku: {
    name: 'Basic'
    tier: 'Paid'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: '1.23.12'
    dnsPrefix: toLower('${AKSName}-${RandomPostfix}')
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: 2
        vmSize: AKSSize
        osDiskSizeGB: 128
        osDiskType: 'Managed'
        kubeletDiskType: 'OS'
        vnetSubnetID: '${VirtualNetwork.id}/subnets/AKSSubnet'
        maxPods: 30
        type: 'VirtualMachineScaleSets'
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
        enableAutoScaling: false
        orchestratorVersion: '1.23.12'
        mode: 'System'
        osType: 'Linux'
        osSKU: AKSHostImage
        enableFIPS: false
      }
    ]
    addonProfiles: {}
    enableRBAC: true
    networkProfile: {
      networkPlugin: 'azure'
      loadBalancerSku: 'Standard'
      podCidr: '10.244.0.0/16'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
      dockerBridgeCidr: '172.17.0.1/16'
      outboundType: 'loadBalancer'
      podCidrs: [
        '10.244.0.0/16'
      ]
      serviceCidrs: [
        '10.0.0.0/16'
      ]
      ipFamilies: [
        'IPv4'
      ]
    }
  }
}

var PublicIPName = 'aks-public-ip-${toLower(AKSHostImage)}-${RandomPostfix}'
resource PublicIP 'Microsoft.Network/publicIPAddresses@2020-11-01' = {
  name: PublicIPName
  location: Location
  sku: {
    name: 'Standard'
    tier: 'Regional'
}
  properties: {
      publicIPAddressVersion: 'IPv4'
      publicIPAllocationMethod: 'Dynamic'
      dnsSettings: {
        domainNameLabel: PublicIPName
      }
  }
}

var subscriptionId = subscription().id
var resourceGroupName = resourceGroup().name
var ApplicationGatewayName = 'AKS-AGW-${AKSHostImage}-${RandomPostfix}'
// /subscriptions/xxxxxxxxxxxxxxxxxxx/resourceGroups/rrrrrrrrr/providers/Microsoft.Network/applicationGateways/aaaaaaaaa
var applicationGatewayId = '${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/applicationGateways/${ApplicationGatewayName}'

resource ApplicationGateway 'Microsoft.Network/applicationGateways@2020-11-01' = {
  name: ApplicationGatewayName
  location: Location
  tags: {}
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
      capacity: 2
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: '${VirtualNetwork.id}/subnets/AzureApplicationGatewaySubnet'
          }
        }
      }
    ]
    sslCertificates: []
    trustedRootCertificates: []
    trustedClientCertificates: []
    sslProfiles: []
    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: {
          publicIPAddress: {
            id: PublicIP.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port_80'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'null-backend'
        properties: {
          backendAddresses: []
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'null-backend-setting'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 20
        }
      }
    ]
    httpListeners: [
      {
        name: 'null-listener'
        properties: {
          frontendIPConfiguration: {
            id: '${applicationGatewayId}/frontendIPConfigurations/appGwPublicFrontendIp'
          }
          frontendPort: {
            id: '${applicationGatewayId}/frontendPorts/port_80'
          }
          protocol: 'Http'
          sslCertificate: null
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'null-rule'
        properties: {
          ruleType: 'Basic'
          httpListener: {
            id: '${applicationGatewayId}/httpListeners/null-listener'
          }
          priority: 20000
          backendAddressPool: {
            id: '${applicationGatewayId}/backendAddressPools/null-backend'
          }
          backendHttpSettings: {
            id: '${applicationGatewayId}/backendHttpSettingsCollection/null-backend-setting'
          }
        }
      }
    ]
    rewriteRuleSets: []
    redirectConfigurations: []
    privateLinkConfigurations: []
    enableHttp2: false
  }
}

