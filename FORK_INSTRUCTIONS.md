# Manual Fork Step Required

Before pushing changes, you need to fork the repository on GitHub:

1. Go to: https://github.com/collegevine/purescript-whine
2. Click "Fork" button
3. Fork to: `Cambridge-Vision-Technology` organization
4. Repository name: `purescript-whine`

Then update the remote:

```bash
cd /Volumes/Git/purescript-whine
git remote add cvt git@github.com:Cambridge-Vision-Technology/purescript-whine.git
git remote set-url origin git@github.com:Cambridge-Vision-Technology/purescript-whine.git
```

This allows us to push our `feat/nix-friendly-prebundle` branch.
