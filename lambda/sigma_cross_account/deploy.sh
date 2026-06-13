#!/bin/bash
set -euo pipefail

FUNCTION_NAME="sigma_cross_account"
ZIP_FILE="sigma_cross_account.zip"
LAMBDA_FILE="lambda_function.py"
REGION="us-east-2"
CONTROL_ACCOUNT_ID="380093117861"
ALLOWED_ACCOUNT_IDS="932708079800,074642417664,366985590058"

if [ ! -f "$LAMBDA_FILE" ]; then
  echo "Error: $LAMBDA_FILE not found"
  exit 1
fi

zip -j "$ZIP_FILE" "$LAMBDA_FILE"

FUNCTION_EXISTS=$(aws lambda list-functions --region "$REGION" --query "Functions[?FunctionName=='$FUNCTION_NAME'].FunctionName" --output text)

if [ "$FUNCTION_EXISTS" == "$FUNCTION_NAME" ]; then
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://$ZIP_FILE" \
    --region "$REGION"
  echo "Updated existing function: $FUNCTION_NAME"
else
  ROLE_ARN="arn:aws:iam::${CONTROL_ACCOUNT_ID}:role/SigmaExecutionRole"
  aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime "python3.12" \
    --role "$ROLE_ARN" \
    --handler "lambda_function.lambda_handler" \
    --zip-file "fileb://$ZIP_FILE" \
    --region "$REGION" \
    --environment "Variables={ALLOWED_ACCOUNT_IDS=$ALLOWED_ACCOUNT_IDS}" \
    --timeout 30
  echo "Created new function: $FUNCTION_NAME"
fi

rm "$ZIP_FILE"
