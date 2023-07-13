#!/bin/bash
# This example uses envsubst to support variable substitution in the string parameter type.
# https://circleci.com/docs/orbs-best-practices/#accepting-parameters-as-strings-or-environment-variables
#TO=$(circleci env subst "${PARAM_TO}")
# If for any reason the TO variable is not set, default to "World"
#echo "Hello ${TO:-World}!"

# If $PROJECT_SLUG is not specified, extract from current project's $CIRCLE_BUILD_URL
if [ "${PROJECT_SLUG}" = '' ]; then
  PROJECT_SLUG=$(echo "$CIRCLE_BUILD_URL" | sed -e "s|https://circleci.com/||g" -e "s|/[0-9]*$||g")
fi
echo "Project slug: ${PROJECT_SLUG}"

CIRCLE_TOKEN=$(circleci env subst "${PARAM_CIRCLE_TOKEN}")

echo "Running the Python script..."
CIRCLE_TOKEN=$CIRCLE_TOKEN PROJECT_SLUG=$PROJECT_SLUG python - <<EOF
import json
import os
import sys
import urllib.request

token = os.environ.get('CIRCLE_TOKEN', '')
project_slug = os.environ.get('PROJECT_SLUG', '')
notify_threshold = os.environ.get('NOTIFY_THRESHOLD', 1)

# Create a GET request
url = "https://circleci.com/api/v2/insights/{}/flaky-tests".format(project_slug)
req = urllib.request.Request(url, headers={"circle-token": token})

try:
    with urllib.request.urlopen(req) as response:
        res = response.read().decode('utf-8')
except Exception as e:
    print("Request failed with status code:", e.code)
    print("Response:", e.read().decode('utf-8'))
    sys.exit(1)

print("Request successful")
data = json.loads(res)

filtered_tests = [test for test in data["flaky_tests"] if test["times_flaked"] >= notify_threshold]

if len(filtered_tests) == 0:
    print("No flaky tests found")
    sys.exit(0)

blocks = [
    {
        "type": "section",
        "text": {
            "type": "mrkdwn",
            "text": f":warning: Flaky tests detected in *{os.environ.get('CIRCLE_PROJECT_REPONAME', 'unknown')}* repo."
        }
    }
]

for test in filtered_tests:
    blocks.append(
        {
            "type": "divider"
        },
    )
    blocks.append(
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*{test['test_name']}*"
            }
        },
    )
    blocks.append(
        {
            "type": "section",
            "fields": [
                {
                    "type": "mrkdwn",
                    "text": f"*Job:* {test['job_name']}"
                },
                {
                    "type": "mrkdwn",
                    "text": f"*Classname:* {test['classname']}"
                },
                {
                    "type": "mrkdwn",
                    "text": f"*Times flaked:* {test['times_flaked']}"
                }
            ],
            "accessory": {
                "type": "button",
                "text": {
                    "type": "plain_text",
                    "text": "See last run",
                },
                "url": f"https://app.circleci.com/pipelines/{project_slug}/{test['pipeline_number']}/workflows/{test['workflow_id']}/jobs/{test['job_number']}/tests"
            }
        }
    )

blocks.append(
    {
        "type": "divider"
    }
)
blocks.append(
    {
        "type": "actions",
        "elements": [
            {
                "type": "button",
                "text": {
                    "type": "plain_text",
                    "text": "Open insights dashboard",
                },
                "url": f"https://app.circleci.com/insights/{project_slug}"
            }
        ]
    }
)

with open("/tmp/flaky_tests_slack_template.json", "w") as outfile:
    json.dump({"blocks": blocks}, outfile)
EOF

if [ ! -s "tmp/flaky_tests_slack_template.json" ]; then
    echo "Nothing to send to slack."
    circleci-agent step halt
fi

# Export the template as an environment variable so the Slack orb can use it
# shellcheck disable=SC2016
echo 'export FLAKY_TESTS_SLACK_TEMPLATE=$(cat /tmp/flaky_tests_slack_template.json)' >> "$BASH_ENV"
