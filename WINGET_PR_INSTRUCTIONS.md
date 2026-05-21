# Winget PR Instructions for Alochi.Monitoring

Since this is the first submission of Alochi.Monitoring to the Microsoft Winget repository, it must be done manually.

## Manifest Files
The following files have been generated in manifests/a/Alochi/Monitoring/1.0.19/:
1. Alochi.Monitoring.installer.yaml
2. Alochi.Monitoring.locale.uz-UZ.yaml
3. Alochi.Monitoring.yaml

## Steps to submit:
1. Fork the microsoft/winget-pkgs repository (https://github.com/microsoft/winget-pkgs).
2. Clone your fork locally.
3. Copy the manifests/a/Alochi/Monitoring/1.0.19/ directory from this project to the manifests/a/Alochi/Monitoring/ directory in your winget-pkgs clone.
4. (Optional) Validate the manifests if you have the winget CLI:
   winget validate --manifest manifests/a/Alochi/Monitoring/1.0.19/
5. Commit the changes:
   git add manifests/a/Alochi/Monitoring/1.0.19/
   git commit -m "New package: Alochi.Monitoring version 1.0.19"
6. Push to your fork and open a Pull Request to microsoft/winget-pkgs with the title:
   "New package: Alochi.Monitoring version 1.0.19"

Once this PR is merged, subsequent updates will be handled automatically by the GitHub Action.
