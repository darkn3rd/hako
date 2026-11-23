# check-config.sh

Unmodified copy of Moby's kernel checker for Docker:

- Source: https://github.com/moby/moby/blob/01573380f945924cd2b4d99330fb233bc5117bb8/contrib/check-config.sh
- License: Apache License 2.0 (https://github.com/moby/moby/blob/master/LICENSE)

`scripts/test-box.sh` (in each distro directory) runs it inside every test VM
and fails the test if a feature Docker requires is missing. Moby's copy is used
rather than the older `coreos/docker` fork, which only understands cgroup v1
and reports "cgroup hierarchy nonexistent" on cgroup v2 systems like these.

To update it:

    curl -fsSLo check-config.sh https://raw.githubusercontent.com/moby/moby/master/contrib/check-config.sh
