"""Select checks without skipping the PR's stable CI job; deploy only merged PRs."""
import json
import os
from pathlib import Path
import subprocess
import time
import urllib.request


def changed_checks(files):
    shared = any(p in ('pubspec.yaml', 'pubspec.lock') or p.startswith(('lib/', 'assets/')) for p in files)
    workflow = any(p in ('.github/workflows/ci.yml', 'tool/ci_plan.py', 'tool/web_release.py') for p in files)
    web = shared or workflow or any(p.startswith('web/') for p in files)
    flutter = shared or web or any(p.startswith(('test/', 'android/', 'ios/'))
                                  or p == 'analysis_options.yaml' or (p.startswith('tool/') and p.endswith('.dart')) for p in files)
    tools = web or any(p.startswith('tool/') or p == '.github/workflows/android-release.yml' for p in files)
    return {'flutter': flutter, 'tools': tools, 'web': web}


def merged_pr(pulls, repository, sha):
    return any(p.get('merged_at') and p.get('merge_commit_sha') == sha
               and p['base']['ref'] == 'main' and p['base']['repo']['full_name'] == repository for p in pulls)


def main():
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    kind, sha = os.environ['GITHUB_EVENT_NAME'], os.environ['GITHUB_SHA']
    base = event.get('pull_request', {}).get('base', {}).get('sha') if kind == 'pull_request' else event.get('before')
    args = ['git', 'diff', '--name-only', '-z', base, sha] if base and set(base) != {'0'} else ['git', 'ls-files', '-z']
    files = subprocess.check_output(args).decode().split('\0')
    plan = changed_checks(files)
    eligible = False
    if kind == 'push' and os.environ['GITHUB_REF'] == 'refs/heads/main' and plan['web']:
        repo = os.environ['GITHUB_REPOSITORY']
        request = urllib.request.Request(f'https://api.github.com/repos/{repo}/commits/{sha}/pulls', headers={
            'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'Accept': 'application/vnd.github+json',
            'User-Agent': 'BusReminder-CI'})
        for attempt in range(3):
            with urllib.request.urlopen(request, timeout=20) as response:
                eligible = merged_pr(json.load(response), repo, sha)
            if eligible:
                break
            if attempt < 2:
                time.sleep(3)
        if not eligible:
            print('::warning::This main commit is not a merged PR. CI runs, but production deployment is blocked.')
    # Every production candidate gets a complete build and regression checks once.
    if eligible:
        plan = dict.fromkeys(plan, True)
    plan['deploy'] = eligible
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        for key, value in plan.items():
            output.write(f'{key}={str(value).lower()}\n')
    print(json.dumps(plan))


if __name__ == '__main__':
    main()
