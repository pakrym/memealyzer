@description('Failover location for Cosmos DB')
param failoverLocation string = 'eastus2'

resource storage 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
}

resource formrecognizer 'Microsoft.CognitiveServices/accounts@2017-04-18' = {
  kind: 'FormRecognizer'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: '${resourceGroup().name}fr'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource textanalytics 'Microsoft.CognitiveServices/accounts@2017-04-18' = {
  kind: 'TextAnalytics'
  sku: {
    name: 'S'
  }
  properties: {
    customSubDomainName: '${resourceGroup().name}ta'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource keyvault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
  }

  resource cosmoskeysecret 'secrets' = {
    name: 'CosmosKey'
    properties: {
      value: cosmosaccount.listKeys().primaryMasterKey
    }
  }

  resource signalrconnectionstringsecret 'secrets' = {
    name: 'SignalRConnectionString'
    properties: {
      value: signalr.listKeys().primaryConnectionString
    }
  }
}

resource cosmosaccount 'Microsoft.DocumentDB/databaseAccounts@2020-04-01' = {
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        failoverPriority: 1
        locationName: failoverLocation
      }
      {
        failoverPriority: 0
        locationName: resourceGroup().location
      }
    ]
  }

  resource cosmossqldb 'sqlDatabases' = {
    name: 'memealyzer'
    properties: {
      options: {
        throughput: 400
      }
      resource: {
        id: 'memealyzer'
      }
    }

    resource cosmossqldbcontainer 'containers' = {
      name: 'images'
      properties: {
        options: {
          throughput: 400
        }
        resource: {
          partitionKey: {
            paths: [
              '/partitionKey'
            ]
          }
          id: 'images'
          uniqueKeyPolicy: {
            uniqueKeys: [
              {
                paths: [
                  '/uid'
                ]
              }
            ]
          }
        }
      }
    }
  }
}

resource aks 'Microsoft.ContainerService/managedClusters@2020-09-01' = {
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: '1.21.1'
    nodeResourceGroup: '${resourceGroup().name}aksnodes'
    dnsPrefix: '${resourceGroup().name}aks'

    agentPoolProfiles: [
      {
        name: 'default'
        count: 1
        vmSize: 'Standard_A2_v2'
        mode: 'System'
      }
    ]
  }
}

resource logging 'Microsoft.Insights/components@2015-05-01' = {
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

resource appconfig 'Microsoft.AppConfiguration/configurationStores@2020-06-01' = {
  sku: {
    name: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }

  resource appconfigborderstyle 'keyValues@2020-07-01-preview' = {
    name: 'borderStyle'
    properties: {
      value: 'solid'
    }
  }
}

resource signalr 'Microsoft.SignalRService/signalR@2020-07-01-preview' = {
  sku: {
    name: 'Standard_S1'
    capacity: 1
  }
  properties: {
    cors: {
      allowedOrigins: [
        '*'
      ]
    }
    features: [
      {
        flag: 'ServiceMode'
        value: 'Serverless'
      }
    ]
  }
}

resource plan 'Microsoft.Web/serverfarms@2020-06-01' = {
  sku: {
    tier: 'Standard'
    size: 'S1'
    name: 'S1'
  }
}

resource function 'Microsoft.Web/sites@2020-06-01' = {
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    siteConfig: {
      alwaysOn: true
      cors: {
        allowedOrigins: [
          '*'
        ]
        supportCredentials: false
      }
      ftpsState: 'FtpsOnly'
    }
    httpsOnly: true
  }

  resource functionappsettings 'config@2018-11-01' = {
    name: 'appsettings'
    properties: {
      'AzureWebJobsStorage__accountName': storage.name
      'AzureSignalRConnectionString': '@Microsoft.KeyVault(VaultName=${keyvault.name};SecretName=${keyvault::signalrconnectionstringsecret.name})'
      'ServiceBusConnection__fullyQualifiedNamespace': '${servicebus.name}.servicebus.windows.net'
      'StorageConnection__queueServiceUri': storage.properties.primaryEndpoints.queue
      'APPINSIGHTS_INSTRUMENTATIONKEY': logging.properties.InstrumentationKey
      'FUNCTIONS_WORKER_RUNTIME': 'dotnet'
      'FUNCTIONS_EXTENSION_VERSION': '~3'
      'WEBSITES_ENABLE_APP_SERVICE_STORAGE': 'false'
      'WEBSITE_RUN_FROM_PACKAGE': ''
      'resourceGroup().name': resourceGroup().name
    }
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2019-12-01-preview' = {
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: true
  }
}

resource servicebus 'Microsoft.ServiceBus/namespaces@2017-04-01' = {
  sku: {
    name: 'Basic'
  }

  resource messages 'queues' = {
    name: 'messages'
    properties: {
      defaultMessageTimeToLive: 'PT30S'
    }
  }

  resource sync 'queues' = {
    name: 'sync'
    properties: {
      defaultMessageTimeToLive: 'PT30S'
    }
  }
}
