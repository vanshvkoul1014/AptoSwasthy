# AptoSwasthy Profile API — Infrastructure

Serverless stack that stores the onboarding `UserProfile` (and the list of
connected health apps) in DynamoDB, fronted by an API Gateway HttpApi that
Cognito-authenticates every call.

## What it provisions

- `AptoSwasthyUserProfiles` DynamoDB table — partition key `userSub`
  (the Cognito `sub` claim). Point-in-time recovery enabled.
- `ProfileFunction` Lambda (Python 3.12) — routes `GET /profile` and
  `PUT /profile` against the table using the caller's sub.
- `ProfileApi` HttpApi with a JWT authorizer pinned to the existing
  Cognito pool `us-east-1_mctlUA1LV` and app client `69hg6pj3eb7ts829l21ogj7kjd`.

No client secret is required — identity comes from the JWT the app already
obtains at sign-in.

## Prerequisites

- AWS SAM CLI (`brew install aws-sam-cli`)
- A terminal with AWS credentials configured for an account that has
  permission to create DynamoDB tables, Lambda functions, and HttpApis
  in `us-east-1`.

## Deploy

From this directory:

```bash
sam build
sam deploy --guided
```

On first run, accept the defaults and answer:

- **Stack name**: `aptoswasthy-profile`
- **Region**: `us-east-1`
- **Confirm changes before deploy**: `y`
- **Allow SAM CLI IAM role creation**: `y`
- **Save arguments to samconfig.toml**: `y`

When the deploy finishes, the `ApiUrl` output is the base URL for the API,
e.g. `https://xxxxx.execute-api.us-east-1.amazonaws.com`.

## Wire it into the iOS app

Open `Sources/AptoSwasthy/Services/CognitoAuthService.swift` and set:

```swift
static let apiBaseURL: String? = "https://xxxxx.execute-api.us-east-1.amazonaws.com"
```

Rebuild and the app will start syncing profiles on sign-in / onboarding.

## Later updates

After editing `handler.py` or `template.yaml`:

```bash
sam build && sam deploy
```
