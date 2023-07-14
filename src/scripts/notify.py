import json
import os
import re
import subprocess
import sys
import urllib.request

param_circle_token = os.environ.get('PARAM_CIRCLE_TOKEN', '')
token = os.environ.get(param_circle_token, '')
project_slug = os.environ.get('PROJECT_SLUG', '')
notify_threshold = int(os.environ.get('NOTIFY_THRESHOLD', 1))

# extract the project slug from the CIRCLE_BUILD_URL if not provided
if not project_slug:
    circle_build_url = os.environ.get('CIRCLE_BUILD_URL', '')
    pattern = r"https://circleci.com/|/[0-9]*$"
    project_slug = re.sub(pattern, "", circle_build_url)

print(f"Using project slug: {project_slug}")

pattern = r"/([^/]+)$"
match = re.search(pattern, project_slug)
if match:
    repo_name = match.group(1)
else:
    repo_name = os.environ.get('CIRCLE_PROJECT_REPONAME', 'unknown')

# Create a GET request to https://circleci.com/docs/api/v2/index.html#operation/getFlakyTests
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

tests_above_threshold = [test for test in data["flaky_tests"] if test["times_flaked"] >= notify_threshold]

# filter out any tests that we've already notified about
notify_record_path = "/tmp/notify_record.json"
notified_tests = {}
if os.path.exists(notify_record_path):
    print("Found existing notify record")
    with open(notify_record_path, "r") as f:
        notified_tests = json.load(f)

filtered_tests = [test for test in tests_above_threshold if test["test_name"] not in notified_tests]

if len(filtered_tests) == 0:
    print(f"No flaky tests to notify about.")
    if len(tests_above_threshold) > 0:
        print(f"However, there are {len(tests_above_threshold)} flaky tests that are below the threshold ({notify_threshold}).")
    subprocess.run(["circleci-agent", "step", "halt"])
    sys.exit(0)

# record the tests above threshold, so we don't notify about them again
for test in tests_above_threshold:
    notified_tests[test["test_name"]] = True
with open(notify_record_path, "w") as f:
    json.dump(notified_tests, f, ensure_ascii=False, indent=4)

blocks = [
    {
        "type": "header",
        "text": {
            "type": "plain_text",
            "text": f":warning: Flaky tests detected in the {repo_name} repo",
            "emoji": True
        }
    },
]

for test in filtered_tests:
    blocks.append(
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*<https://app.circleci.com/pipelines/{project_slug}/{test['pipeline_number']}/workflows/{test['workflow_id']}/jobs/{test['job_number']}/tests|{test['test_name']}>*"
            },
        },
    )
    blocks.append(
        {
            "type": "context",
            "elements": [
                {
                    "type": "mrkdwn",
                    "text": f"*Job:* {test['job_name']}"
                },
                {
                    "type": "mrkdwn",
                    "text": f"*File:* {test['file']}"
                },
                {
                    "type": "mrkdwn",
                    "text": f"*Times flaked:* {test['times_flaked']}"
                }
            ],
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

template_path = '/tmp/flaky_tests_slack_template.json'
with open(template_path, "w") as outfile:
    json.dump({"blocks": blocks}, outfile, ensure_ascii=False, indent=4)

# Export the template as an environment variable so the Slack orb can use it
bash_env_file = os.environ.get('BASH_ENV')
if bash_env_file:
    with open(bash_env_file, 'a') as env_file:
        env_file.write(f'export FLAKY_TESTS_SLACK_TEMPLATE=$(cat {template_path})\n')
