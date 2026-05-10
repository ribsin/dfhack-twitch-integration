# Pushing this repo to GitHub

`git init` has already been run locally. To publish:

1. Go to https://github.com/new and create an **empty** repo (no README, no
   `.gitignore`, no LICENSE — those exist here already). Suggested name:
   `dfhack-twitch-integration`. Owner: your account.

2. Copy the new repo's HTTPS URL — looks like
   `https://github.com/<you>/dfhack-twitch-integration.git`.

3. From a terminal in this folder run:

   ```bash
   git remote add origin https://github.com/<you>/dfhack-twitch-integration.git
   git branch -M main
   git push -u origin main
   ```

That's it.

## Subsequent commits

```bash
git add -A
git commit -m "what changed"
git push
```

## When the native plugin lands

The plugin source will live in `dev/`. Compiled DLLs are gitignored — they go
on GitHub Releases, not in the repo.
