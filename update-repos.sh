#!/bin/bash -eC

REPO_HOME="$HOME/arch-svntogit/repos"
REPOS=(packages community)
REMOTE=public
LOCKFILE="$0.lock"

update_pkg() {
	local pkg=$1

	if [[ -e $pkg ]]; then
		if ! git show-ref -q packages/$pkg; then
			# Added package; create package branch
			git branch packages/$pkg
			git filter-branch -f --subdirectory-filter $pkg packages/$pkg \
				>/dev/null
		else
			# Updated package; apply changes to package branch
			git checkout -q packages/$pkg
			git format-patch --stdout last-commit-processed..master -- $pkg |
				git am -p2 --whitespace=fix --committer-date-is-author-date \
					&>/dev/null
		fi
	else
		# Deleted package; destroy the branch and stop processing this package
		git branch -D packages/$pkg &>/dev/null || true
		git push -q --delete $REMOTE packages/$pkg &>/dev/null || true
		return 0
	fi
}

# Rather simple locking mechanism
echo $$ >"$LOCKFILE"

for repo in ${REPOS[@]}; do
	echo "==> Updating '$repo' Git repository on $(date -u)"

	pushd "$REPO_HOME/$repo" >/dev/null

	# Make sure we have a last-commit-processed tag to work from
	if ! git show-ref -q last-commit-processed; then
		echo "==> ERR: Couldn't update '$repo' Git repository;" \
			"missing last-commit-processed tag" >&2
		# Skip to the next repo
		continue
	fi

	# Make sure we're on the master branch
	git checkout -q master

	echo '  -> Fetching changes from SVN'
	git svn rebase &>/dev/null

	echo '  -> Updating package branches'
	pkgs=($(git diff --name-only last-commit-processed.. | cut -d'/' -f1 |
		uniq))
	pkg_count=${#pkgs[@]}

	if ((pkg_count)); then
		# Update each package branch
		for pkg in ${pkgs[@]}; do
			echo "    > Updating package branch for '$pkg'"
			update_pkg $pkg
		done

		# Return to the master branch
		git checkout -q master

		echo "  -> Updated $pkg_count package branches"

		echo '  -> Updating public Git repository'
		git push -q --all $REMOTE
	else
		echo '    > No updates found'
	fi

	echo '  -> Tagging last commit processed'
	git tag -f last-commit-processed >/dev/null

	popd >/dev/null

	echo "==> Finished updating '$repo' on $(date -u)"
	echo
done

# Remove lock
rm "$LOCKFILE"

# vim:set ts=4 sw=4 noet:
