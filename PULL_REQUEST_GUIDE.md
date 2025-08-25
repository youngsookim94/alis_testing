# Pull Request Management Guide

This guide explains how to delete and manage pull requests in GitHub repositories.

## How to Delete Pull Requests

### Important Note
**Pull requests cannot be permanently deleted in GitHub.** However, there are several ways to manage them:

### 1. Close a Pull Request

The most common way to "remove" a pull request is to close it:

#### Via GitHub Web Interface:
1. Navigate to the pull request you want to close
2. Scroll down to the bottom of the pull request
3. Click the **"Close pull request"** button
4. Optionally add a comment explaining why you're closing it

#### Via Command Line (using GitHub CLI):
```bash
# Close a specific pull request
gh pr close <pull-request-number>

# Close with a comment
gh pr close <pull-request-number> --comment "Reason for closing"
```

### 2. Convert to Draft

If you want to temporarily hide a pull request while keeping it open:

1. Go to the pull request page
2. Click **"Convert to draft"** in the sidebar
3. The PR will be marked as a draft and won't appear in standard PR lists

### 3. Delete the Source Branch

After closing or merging a pull request, you can delete its source branch:

#### Via GitHub Web Interface:
1. After closing/merging a PR, GitHub will show a "Delete branch" button
2. Click it to remove the branch

#### Via Command Line:
```bash
# Delete local branch
git branch -d branch-name

# Delete remote branch
git push origin --delete branch-name
```

### 4. Repository Admin Options

Repository administrators have additional options:

- **Hide from timeline**: Admins can hide pull request comments from the repository timeline
- **Lock conversations**: Prevent further comments on closed pull requests
- **Transfer ownership**: Move pull requests between repositories (in some cases)

## Best Practices

### Before Closing a Pull Request:
- ✅ Add a clear comment explaining why it's being closed
- ✅ Reference any related issues or alternative solutions
- ✅ Thank contributors for their effort
- ✅ Save any valuable code/discussion for future reference

### Example Closing Comment:
```
Closing this PR because:
- The feature request has been implemented differently in PR #123
- The approach needs significant changes (see discussion above)
- The changes are no longer needed due to [reason]

Thank you for your contribution!
```

## Alternative Actions

Instead of deleting/closing, consider:

1. **Merging**: If the changes are valuable
2. **Requesting changes**: Ask the author to modify the PR
3. **Converting to issue**: Save the discussion as an issue for future reference
4. **Cherry-picking**: Take specific commits and apply them elsewhere

## Common Scenarios

### Duplicate Pull Requests
```bash
# Close the duplicate
gh pr close <duplicate-pr-number> --comment "Duplicate of #<original-pr-number>"
```

### Outdated/Stale Pull Requests
```bash
# Close due to inactivity
gh pr close <pr-number> --comment "Closing due to inactivity. Please reopen if you'd like to continue working on this."
```

### Superseded Pull Requests
```bash
# Close when replaced by a better solution
gh pr close <old-pr-number> --comment "Superseded by #<new-pr-number> which provides a better implementation."
```

## Recovery

If you accidentally close a pull request:

1. Go to the closed pull request
2. Click **"Reopen pull request"** (if you have permissions)
3. The PR will be restored to its open state

## GitHub CLI Quick Reference

```bash
# List all pull requests
gh pr list

# List closed pull requests
gh pr list --state closed

# View a specific pull request
gh pr view <pr-number>

# Close a pull request
gh pr close <pr-number>

# Reopen a pull request
gh pr reopen <pr-number>
```

## Additional Resources

- [GitHub Documentation on Pull Requests](https://docs.github.com/en/pull-requests)
- [GitHub CLI Documentation](https://cli.github.com/manual/gh_pr)
- [Best Practices for Pull Request Reviews](https://github.com/features/code-review)

---

*Remember: Good communication is key when closing pull requests. Always explain your reasoning to maintain a positive collaborative environment.*