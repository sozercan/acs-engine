# Open Service Broker for Azure Extension

The `open-service-broker-azure` extension installs Kubernetes Service Catalog and Open Service Broker for Azure.

```
{
  "apiVersion": "vlabs",
  "properties": {
    "orchestratorProfile": {
      "orchestratorType": "Kubernetes"
    },
    "masterProfile": {
      "count": 1,
      "dnsPrefix": "",
      "vmSize": "Standard_DS2_v2"
    },
    "agentPoolProfiles": [
      {
        "name": "agentpool1",
        "count": 3,
        "vmSize": "Standard_DS2_v2",
        "availabilityProfile": "AvailabilitySet",
        "extensions": [
          {
            "name": "open-service-broker-azure"
          }
        ]
      }
    ],
    "linuxProfile": {
      "adminUsername": "azureuser",
      "ssh": {
        "publicKeys": [
          {
            "keyData": ""
          }
        ]
      }
    },
    "extensionProfiles": [
      {
        "name": "open-service-broker-azure",
        "version": "v1",
        "rootURL": "https://raw.githubusercontent.com/sozercan/acs-engine/open-service-broker-azure/",
        "extensionParameters": ""
      }
    ],
    "servicePrincipalProfile": {
      "clientId": "",
      "secret": ""
    }
  }
}
```

## Configuration

|Name|Required|Acceptable Value|
|---|---|---|
|name|yes|open-service-broker-azure|
|version|yes|v1|
|extensionParameters|yes|The base64 encoded json representation of your Client ID, Client Secret, Subscription ID and Tenant ID values.|
|rootURL|no||

## Extension Parameters

Open Service Broker for Azure k8s extension requires your Client ID, Client Secret, Subscription ID and Tenant ID to be placed in extensionParameters.  You can find this in your

The parameters for this extension must be provided in the following json format.

``` javascript
{
  "clientId": "<client id>",
  "clientSecret": "<client secret>",
  "subscriptionId": "<subscription id>",
  "tenantId": "<tenant id>"
}

```
The json must then be base64 encoded before being passed into the `extensionParameters` value.

Here is an example in bash.
``` bash
$ printf '{   "clientId": "<client id>", "clientSecret": "<client secret>", "subscriptionId": "<subscription id>","tenantId": "<tenant id>" }' | base64 -w0
<base64-coded-string>
```

Here is an example in PowerShell.
``` powershell
PS> $json = '{   "clientId": "<client id>", "clientSecret": "<client secret>", "subscriptionId": "<subscription id>", "tenantId": "<tenant id>" }'
PS> [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))
<base64-coded-string>
```

## Example
``` javascript
{
  "name": "open-service-broker-azure",
  "version": "v1"
  "extensionsParameters": "<base64-coded-string>"
}
```

## Supported Orchestrators
Kubernetes
