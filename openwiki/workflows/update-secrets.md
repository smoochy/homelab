---
type: workflow
title: Updating Secrets with SOPS/Age
description: Explains the process for rotating or updating encrypted secrets using SOPS, age, and the Komodo periphery workflow.
tags: ["komodo", "secrets", "sops", "age", "workflow"]
verified:
  - by: openwiki/0.5.0
    at: 2026-09-06T09:58:25.192Z
sources:
  - id: openwiki-source-5ef0409c965921b60d6187d5
    resource: repo://stacks/komodo/compose.yaml
  - id: openwiki-source-71fa1bbc4a715e98914f8046
    resource: repo://stacks/komodo/README.md
  - id: openwiki-source-bb59ae5ba473dc43d4ca3202
    resource: repo://stacks/traefik/scripts/cloudflare_trusted_ips/README.md
generated: { by: "openwiki/0.5.0", at: "2026-09-06T09:58:25.192Z" }
---

# Updating Secrets with SOPS/Age

Komodo uses SOPS with age encryption to manage secrets in Git repositories. Updating a secret involves modifying the encrypted file in the repository and triggering a redeployment so that Periphery can decrypt the updated secret using the host's age private key.

## Prerequisites

- Access to the host where the age private key is stored (typically `/mnt/user/appdata/komodo/config/keys`).
- The age public key used for encryption must be known (it is embedded in the SOPS file or defined in `.sops.yaml`).
- SOPS and age must be installed on the host used for editing (or use the Komodo periphery container which includes both).

## Update Procedure

1. **Locate the encrypted secret file** in the Git repository (e.g., `secrets.yaml.enc`, `.env.enc`).

2. **Decrypt the file** using the age private key:
   ```bash
   sops --decrypt --age <private-key-file> <encrypted-file> > <decrypted-file>
   ```
   Alternatively, if the age private key is mounted at `/config/keys` and SOPS is configured to use it:
   ```bash
   sops --decrypt <encrypted-file> > <decrypted-file>
   ```

3. **Edit the decrypted file** to update the secret value(s).

4. **Re-encrypt the file** using the age public key:
   ```bash
   sops --encrypt --age <public-key> <decrypted-file> > <encrypted-file>
   ```
   If a `.sops.yaml` file exists in the repository that specifies the age key, you can simply run:
   ```bash
   sops --encrypt <decrypted-file> > <encrypted-file>
   ```

5. **Commit and push** the changes to the Git repository:
   ```bash
   git add <encrypted-file>
   git commit -m "Update secret: <description>"
   git push
   ```

6. **Trigger a redeployment** of the affected stack in Komodo:
   - Via the Komodo UI: Navigate to the stack and click "Redeploy".
   - Via the Komodo API: Trigger the stack's deployment endpoint.
   - Alternatively, wait for the next scheduled deployment if the stack is set to auto-update.

## How Komodo Uses the Updated Secret

During redeployment:
1. Periphery pulls the latest commit from the stack's Git repository.
2. For any SOPS-encrypted files, Periphery uses the age private key (mounted at `/config/keys`) to decrypt the file in memory.
3. Decrypted values are injected into the stack's containers as environment variables or file mounts.
4. The stack is deployed with the updated secret.

## Security Notes

- The age private key must be kept secure and accessible only to trusted administrators.
- Decrypted secrets never touch disk in Periphery; they are kept in memory only.
- Always verify that the encrypted file (not the decrypted version) is committed to the repository.
- Rotate the age key pair periodically if there is a risk of key compromise, which requires re-encrypting all secrets with the new public key.

## Related Workflows

<!-- openwiki: broken internal link [../workflows/deploy-stack.md] file "../workflows/deploy-stack.md" does not exist. Fix the href or restore the target, then delete this comment. -->
- [Deploy Stack Workflow](../workflows/deploy-stack.md): Describes how secrets are used during deployment.
- [Backup Procedures](../operations/backups.md): Shows how Komodo-managed secrets are encrypted in backups.
