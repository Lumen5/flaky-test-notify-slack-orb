#!/bin/bash
# This example uses envsubst to support variable substitution in the string parameter type.
# https://circleci.com/docs/orbs-best-practices/#accepting-parameters-as-strings-or-environment-variables
TO=$(circleci env subst "${PARAM_TO}")
# If for any reason the TO variable is not set, default to "World"
echo "Hello ${TO:-World}!"

echo "Running the Python script..."
python - <<EOF
# Your Python script here
import sys

print("Hello, CircleCI!")
sys.exit(0)
EOF
