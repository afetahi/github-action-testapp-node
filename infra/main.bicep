// ──────────────────────────────────────────────────────────────
// main.bicep — hosting for github-action-testapp-node (SRE Agent lab workload)
//
// Creates, in one resource group:
//   - Log Analytics workspace + Application Insights (telemetry)
//   - Linux App Service plan (Basic B1 by default, see skuName) + web app (Node.js)
//   - Diagnostic settings: console/HTTP/platform logs and metrics -> workspace
//   - A user-assigned managed identity that GitHub Actions uses to deploy,
//     through OIDC (federated credential, no stored secret), with
//     Website Contributor on this web app only
//
// Deploy:
//   az group create -n rg-testapp-node -l northeurope
//   az deployment group create -g rg-testapp-node -f infra/main.bicep
// ──────────────────────────────────────────────────────────────

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Base name; a short unique suffix is added because web app names are global')
param baseName string = 'testapp-node'

@description('App Service Linux runtime (list options with: az webapp list-runtimes --os linux)')
param linuxFxVersion string = 'NODE|24-lts'

@description('App Service plan SKU. F1 (Free) needs no VM quota but has no Always On or health check.')
@allowed([
  'F1'
  'B1'
  'S1'
  'P0v3'
  'P1v3'
])
param skuName string = 'B1'

@description('GitHub repository allowed to deploy, as owner/name')
param githubRepo string = 'afetahi/github-action-testapp-node'

@description('Branch allowed to deploy')
param githubBranch string = 'master'

var suffix = take(uniqueString(resourceGroup().id), 6)
var webAppName = '${baseName}-${suffix}'
var websiteContributorRoleId = 'de139f84-1756-47ae-9be6-808fbbe84772'
var isFree = skuName == 'F1'

// ─── Telemetry ────────────────────────────────────────────────
resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${baseName}-law'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${baseName}-ai'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: law.id
    IngestionMode: 'LogAnalytics'
  }
}

// ─── Hosting ──────────────────────────────────────────────────
resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${baseName}-plan'
  location: location
  kind: 'linux'
  sku: {
    name: skuName
  }
  properties: {
    reserved: true // required for Linux plans
  }
}

resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: webAppName
  location: location
  kind: 'app,linux'
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      alwaysOn: !isFree // not available on the Free tier
      healthCheckPath: isFree ? null : '/api/health'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          // Fault-injection endpoints stay off until a lab scenario turns them on.
          name: 'CHAOS_ENABLED'
          value: 'false'
        }
      ]
    }
  }
}

// Deployments use Entra ID (OIDC) only, so basic-auth publishing is turned off.
resource scmBasicAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2023-12-01' = {
  parent: webApp
  name: 'scm'
  properties: {
    allow: false
  }
}

resource ftpBasicAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2023-12-01' = {
  parent: webApp
  name: 'ftp'
  properties: {
    allow: false
  }
}

resource webAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-log-analytics'
  scope: webApp
  properties: {
    workspaceId: law.id
    logs: [
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServicePlatformLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ─── GitHub Actions deployment identity (OIDC) ────────────────
resource deployIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-github-${baseName}'
  location: location
}

resource githubFederation 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: deployIdentity
  name: 'github-${githubBranch}'
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${githubRepo}:ref:refs/heads/${githubBranch}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

resource deployRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(webApp.id, deployIdentity.id, websiteContributorRoleId)
  scope: webApp
  properties: {
    principalId: deployIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', websiteContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

// ─── Outputs (identifiers only, no secrets) ───────────────────
output webAppName string = webApp.name
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output azureClientId string = deployIdentity.properties.clientId
output azureTenantId string = tenant().tenantId
output azureSubscriptionId string = subscription().subscriptionId
