# The bump App

The Bump workflow (`.github/workflows/bump.yml`) opens its pull requests as a GitHub App, so they start CI, which a pull request opened with a workflow's own token doesn't. Only an owner of the Dockwell organization can make the App. These are the steps, once.

## 1. Make the App

1. Open <https://github.com/organizations/Dockwell/settings/apps/new>.
2. **GitHub App name:** `dockwell-catalog-bump`, exactly. The workflow keeps only this App's own pull requests as bumps, by this name, so a fork's pull request from a branch named `bump/` is never read or edited as one.
3. **Homepage URL:** `https://github.com/Dockwell/catalog`.
4. **Webhook:** clear **Active**. The App receives no events.
5. **Repository permissions:**
   - **Contents:** Read and write.
   - **Pull requests:** Read and write.
   - **Metadata:** Read-only, which GitHub sets by itself.
   - Every other permission, and every organization and account permission, stays **No access**.
6. **Where can this GitHub App be installed?** Only on this account.
7. Press **Create GitHub App**.
8. On the App's page, note its **Client ID**.
9. Under **Private keys**, press **Generate a private key**. Your browser downloads a `.pem` file.

## 2. Install it on Dockwell/catalog alone

1. On the App's page, open **Install App** in the left sidebar, and press **Install** beside Dockwell.
2. Choose **Only select repositories**, pick **Dockwell/catalog**, and press **Install**.

## 3. Give its key to the workflow, on main alone

1. Open <https://github.com/Dockwell/catalog/settings/environments> and press **New environment**. Name it `bump`.
2. Under **Deployment branches and tags**, choose **Selected branches and tags**, press **Add deployment branch or tag rule**, and add the branch `main`. So only a run on main can read what the environment holds.
3. Under **Environment secrets**, press **Add environment secret**. Name it `BUMP_APP_PRIVATE_KEY`, and paste the whole of the `.pem` file, its first and last lines included.
4. Under **Environment variables**, press **Add environment variable**. Name it `BUMP_APP_CLIENT_ID`, and give it the App's Client ID.
5. Delete the `.pem` file from your computer. A new key can be generated on the App's page whenever one is needed.

Nothing else changes: no ruleset, and no setting under Actions. In this slice nothing the App opens merges by itself; a person reviews and merges each bump.
